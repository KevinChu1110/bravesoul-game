# ONLINE · 翠嶺多人線上設計（完整）

> 產品句：敘事優先的像素 RPG；線上是「星途旅人偶爾交會」，不是第二份工作。  
> 實作入口：`OnlineGate` autoload · SQL：`supabase/schema.sql`

---

## 0. 總原則（不可破）

```
主線敘事  ⊂  單機完整
連線內容  ⊂  可選加厚
連線故障  ⇏  卡劇情
```

1. **零連線可通關**（飛航模式打完 C0–C6）。  
2. 連線獎**不可**成為主線唯一最強裝備來源。  
3. 其他玩家＝**星途旅人／運命殘影**，不是帳號列表。  
4. 設定永遠有 **純單機模式**（`OnlineGate.offline_only`）。  
5. 先非同步＋弱即時，不做大世界 MMO。

---

## 1. 產品形態（已定）

| 做 | 不做 |
|----|------|
| 雲存檔、殘影、留言石、通關蠟燭 | 同圖強制組隊主線 |
| 裂縫／歲旅 **可選** 2～4 人房 | 開放世界即時 PvP |
| 輕排行、公會週貢獻 | 拍賣行、語音內建 |
| 活動進度可同步 | 必須上線才能打活動 |

---

## 2. 分層路線圖

### L0 · 本機（已有）

本地存檔、匯出匯入、歲旅／裂縫／公會（離線）。

### L0.5 · 雲存檔 + 帳號

| 項 | 規格 |
|----|------|
| 帳號 | 訪客（anonymous）或 OAuth（後期） |
| 存檔 | `saves` 表 JSON blob + `updated_at` + `schema_version` |
| 衝突 | 雲較新／本機較新 → 玩家選「用雲／用本機／另存」 |
| 失敗 | 安靜回落本機，toast 一句 |

### L1 · 存在感（非同步）

| 功能 | API 概念 | 敘事 |
|------|----------|------|
| 旅人殘影 | `presence` upsert / list | 足迹交疊 |
| 留言石 | `messages` insert / list | 塔下、城門 |
| 通關蠟燭 | `candles` count++ | 終章余韻 |
| 上傳頻率 | presence ≥ 5 min；留言 CD 60s | 防刷 |

**不需要 WebSocket。**

### L2 · 可選共鬥（0.10.0 輪詢版）

| 功能 | 規格 |
|------|------|
| 裂縫房 | 2～4 人；房主權威戰鬥 |
| 同步 | HTTP 輪詢 2.5s（非 Realtime 按鍵） |
| 權威 | **房主跑 BattleSim**；結果寫 `rooms.result` |
| 獎勵 | 客戶端共鬥金＋人數加成；成員手動領獎 |
| 掉線 | 房主可單人續；離線改用助戰 |
| 市集 | 非同步掛單 `market_listings` + `market_buy` RPC |

### L3 · 以後

即時同圖劇情、跨服工具、軍事級反外掛。

---

## 3. 系統架構

```
[Godot 客戶端]
  GameState / EventRuntime / BattleSim   ← 單機權威
  OnlineGate                             ← 可關；無 URL ＝永遠離線
       │
       │ HTTPS (Supabase REST / Edge)
       ▼
  Auth · saves · presence · messages · candles
  event_progress · leaderboard · (rooms 後期)
```

### 權威矩陣

| 內容 | 權威 |
|------|------|
| 主線 flag、對話、單人戰鬥 | 客戶端 + 雲備份 |
| **可交易的金幣與物品** | **伺服器影子帳 `player_econ`** |
| 市集上架／購買／下架 | **伺服器**（`market_*` RPC） |
| 活動有獎次數／排行／共鬥掉落 | **伺服器** |
| 共鬥血量同步 | 房主（L2） |
| 外觀展示 | 伺服器認可的 unlock 列表 |

單機模擬驗不出玩家的金幣怎麼來的，所以不驗來源，改驗**成長速率**：影子帳往下
精確跟隨存檔，往上只能按真實時間長。跟別人交易時看的是影子帳，不是存檔裡的數字。
細節見 `supabase/economy.sql` 與 ONLINE_SETUP 的 4.1。

---

## 4. API 契約（L0.5～L1）

Base：`SUPABASE_URL` + `apikey`（anon key，RLS 保護）。

### 4.1 Auth

- `signInAnonymously` → `user_id` + session  
- 本地快取 refresh token 於 `user://online_session.json`（勿進 git）

### 4.2 saves

```
POST /rest/v1/rpc/save_push  { p_payload, p_schema_version }
GET  /rest/v1/saves?user_id=eq.<id>&select=*
```

`p_payload` = `GameState.to_dict()` JSON。直接寫 `saves` 已被 RLS 擋掉——
推送必須走 `save_push`，因為同一筆交易還要更新影子帳。

回應 `{ ok, ledger_gold, seeded }`；`ledger_gold` 是伺服器認的可交易餘額。

### 4.3 presence

```
POST presence { user_id, display_name, map_id, chapter, cosmetic, updated_at }
GET  presence?map_id=eq.town&order=updated_at.desc&limit=20
```

客戶端：進城鎮時拉；每隔 ≥5 分鐘或換圖時推。

### 4.4 messages

```
POST messages { user_id, place, body, created_at }
GET  messages?place=eq.tower_camp&order=created_at.desc&limit=30
```

限制：body ≤ 80 字；每用戶 60s 一則（RLS / Edge）。

### 4.5 candles

```
POST candles_rpc_increment()  -- 通關一次
GET  candles_total
```

### 4.6 event_progress（可選同步）

```
UPSERT event_progress { user_id, event_id, runs_total, token, updated_at }
```

離線可玩；上線 merge（取 max runs、token 以伺服器為準若衝突）。

### 4.7 leaderboard

```
POST /rest/v1/rpc/leaderboard_submit  { p_board, p_score }
GET  leaderboard?board=eq.rift_weekly&limit=50
```

只進不退（低分不覆蓋高分），分數上限 1e8。直接寫表已擋掉。

### 4.8 市集與影子帳

```
POST /rest/v1/rpc/market_list_item      { p_item_id, p_qty, p_price }
POST /rest/v1/rpc/market_buy            { p_listing_id }
POST /rest/v1/rpc/market_cancel_listing { p_listing_id }
POST /rest/v1/rpc/market_claim_credit   {}
POST /rest/v1/rpc/econ_state            {}
GET  market_listings?status=eq.active&order=created_at.desc&limit=40
```

全部在伺服器單一交易內完成，所以下架不會退兩次貨、掛單不會被買兩次。
上架會檢查影子帳有沒有這些貨、訂價有沒有超過「基準價 × 數量 × 20」。
`econ_state` 給客戶端顯示「連線可用金幣」用。

### 4.9 共鬥結算

```
POST /rest/v1/rpc/room_report_result  { p_room_id, p_result }
POST /rest/v1/rpc/room_claim_reward   { p_room_id }
```

`reward_claimed` 由觸發器保護，客戶端改不動，所以獎勵一人一次。

---

## 5. 房間協議（L2 · 0.10.2 同屏觀戰）

```
ClientA (host) ──create_room──► rooms
ClientB ──join──► room_members
Host BattleSim → room_events (battle_start / snap / action / end)
  ├─ RealtimeBridge WebSocket (postgres_changes)
  └─ fallback: HTTP poll 0.4s
ClientB ──同屏觀戰──► BattleView.setup_spectator
```

| kind | 內容 |
|------|------|
| `battle_start` | mode、房主名、人數 |
| `snap` | 雙方 HP、敵名 |
| `action` | hit／skill／parry／mp 文字 |
| `mp_sync_window` | 雙星連招窗開／關 |
| `end` | won |

### 成員操作（0.10.3）

| 鍵 | 輸入 kind | 房主套用 |
|----|-----------|----------|
| J | `sync`／`parry` | 格擋 + 連招同步 |
| K | `skill` | 怒氣 +35 |
| L | `assist` | 攻↑4 秒 |

- 表：`room_inputs`（成員寫、房主 0.25s 拉）  
- **雙星連招**：可格擋窗內雙方都按 J → 強化格擋 + 追加傷害 + 怒氣滿  
- 權威仍在房主；**非**雙端完整幀重算（BattleSim 含隨機／浮點，改為輸入鎖步權威）  
SQL：`room_events` + `room_inputs`；Realtime 可訂閱 `room_events`。

---

## 6. 客戶端 `OnlineGate` 行為

| 狀態 | 行為 |
|------|------|
| `offline_only=true` | 所有網路 no-op；UI 顯示「純單機」 |
| `offline_only=false` 且無 URL | 等同離線；狀態「未設定後端」 |
| 有 URL 未登入 | 可「訪客上線」 |
| 已登入 | 可推／拉存檔、殘影、留言 |

設定檔：`user://online_settings.json`

```json
{
  "offline_only": true,
  "display_name": "小白",
  "supabase_url": "",
  "supabase_anon_key": ""
}
```

專案範例（不進密鑰）：`game/data/online/config.example.json`  
真 key 用環境或本機覆蓋，**禁止 commit**。

---

## 7. 失敗與隱私

- 任何 HTTP 失敗 → toast 短句 + 本機繼續  
- 顯示名可改；不強制實名  
- 留言長度／頻率；後期舉報  
- 未成年人：暴力維持像素戰鬥尺度  

---

## 8. 成功標準

| 玩家 | 成功 |
|------|------|
| 故事粉 | 全程純單機覺得完整 |
| 輕社交 | 殘影／蠟燭有溫度 |
| 共鬥粉 | 偶開裂縫房，掉線不毀體驗 |
| 開發 | 後端掛一週，主線仍可出包 |

---

## 9. 實作檢查清單

- [x] 設計文件（本檔）  
- [x] `OnlineGate` 骨架 + 純單機開關  
- [x] `supabase/schema.sql`  
- [x] 標題／Esc「連線設定」面板  
- [x] 殘影可視化（ExploreView · 連線拉 presence／離線假足迹）  
- [x] 留言石（城門告示／塔下）  
- [x] 通關蠟燭（塔下祭壇 · 通關可點）  
- [ ] 接上真實 Supabase 專案（需你方 URL/anon key）  
- [x] 組隊助戰離線原型（`PartySystem`）  
- [x] 真市集（`MarketSystem` · listings RPC）  
- [x] 真裂縫房輪詢（`RoomSystem` · 房主權威）  
- [x] `rooms` / `room_members` / `market_*` / `room_events` SQL  
- [x] Realtime 同屏觀戰（`RealtimeBridge` · WS＋輪詢）  
- [x] 成員可操作／雙星連招（`room_inputs` · 0.10.3）  
- [x] 延遲容錯 + 代碼加入（0.10.4）

接線步驟見 `docs/ONLINE_SETUP.md`。  
循環內容見 `docs/MULTIPLAYER_LOOPS.md`。  
**重跑** `supabase/schema.sql` 以啟用市集／房間表。
