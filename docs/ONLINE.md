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
| 輕排行、公會週貢獻 | 拍賣行、語音內建 |
| 主線完全離線可通 | 必須上線才能玩 |

---

## 2. 分層路線圖

### L0 · 本機（已有）

本地存檔、匯出匯入、裂縫／公會（離線）。

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

### L2 · 可選共鬥 —— **2026-08-16 砍掉**

裂縫房／狩獵房整套移除。727 行在沒有後端時一行都不會執行，
等於只有設定過 Supabase 的人看得到。伺服器上 `rooms` / `room_members` /
`room_events` / `room_inputs` 那幾張表還在，但客戶端已經不再呼叫。
理由見 [DECISIONS.md](DECISIONS.md)。

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
| 排行分數 | **伺服器** |
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

### 4.7 leaderboard

```
POST /rest/v1/rpc/leaderboard_submit  { p_board, p_score }
GET  leaderboard?board=eq.rift_weekly&limit=50
```

只進不退（低分不覆蓋高分），分數上限 1e8。直接寫表已擋掉。

---

## 5. 房間協議 —— 已移除

房間、同屏觀戰、雙星連招在 2026-08-16 隨裂縫房一起砍掉。
`RealtimeBridge`（WebSocket）也一併移除 —— 它只有房間在用。

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
- [x] 影子帳與經濟守門（`player_econ` · `economy.sql`）  
- [x] ~~市集／裂縫房／狩獵房／助戰~~ —— 2026-08-16 全部砍掉，見 [DECISIONS.md](DECISIONS.md)

接線步驟見 `docs/ONLINE_SETUP.md`。  
循環內容見 `docs/HUNTING_GROUNDS.md`。
