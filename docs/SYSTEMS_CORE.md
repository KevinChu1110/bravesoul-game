# 核心系統設計 · 帳號／官網／數值表／裝備／Log／爆擊

> 版本：**0.11.0**  
> 原則：主線離線可玩；連線加厚；資料表 JSON 與程式欄位對齊。

---

## 1. 帳號密碼

| 模式 | 行為 |
|------|------|
| 純單機 | 可選「本地帳號」綁定存檔顯示名（不上雲） |
| 連線 | Supabase Auth：Email + Password 註冊／登入 |
| 訪客 | 既有 Anonymous 保留 |

- 密碼**永不**寫入存檔或聊天  
- Session：`user://online_session.json`  
- UI：連線面板 → 註冊／登入欄位  

---

## 2. 官方網頁

靜態站：`web/index.html`  
內容：願景、操作、連線說明、版本、下載連結（itch 占位）。

---

## 3. 資料格式化 · 對齊資料表

| 表檔 | 用途 |
|------|------|
| `game/data/tables/combat.json` | 傷害浮動、爆擊、命中基線 |
| `game/data/tables/equipment.json` | 裝備基底＋浮動區間 |
| `game/data/tables/items_meta.json` | 道具規則 |

程式：`DataTables` autoload 載入；`Formulas` / `EquipmentSystem` 只讀表。

---

## 4. 裝備素質浮動

掉落／鍛造／開箱時 **roll 一次** 鎖定實例：

```
{ uid, base_id, quality, rolled: {atk, def, hp, crit, crit_dmg}, bound }
```

quality：common / uncommon / rare / epic  
區間見 `equipment.json`。

---

## 5. 背包

- **堆疊物**：`inventory`（item_id → 數量）  
- **裝備實例**：未裝備的在 `equip_bag`，已穿的在 `equip_worn` + `equip_slots`  

容量：24 顯示格。**沒有倉庫** —— 全遊戲只有 11 種可交易物，
背包永遠裝得下，多一層存取只是多一次點擊（2026-08-16 砍掉，見
[DECISIONS.md](DECISIONS.md)）。

---

## 6. 遊戲紀錄 Log

`GameLog` → `user://game_log.jsonl`（最多保留 2000 行）  
類別：`combat` `economy` `equip` `account` `system` `quest`  
UI：暫停 → 冒險日誌。

---

## 7. 傷害素質浮動 + 爆擊

| 項 | 規則 |
|----|------|
| 浮動 | 最終傷害 × (1 ± variance)，預設 ±8% |
| 爆擊率 | crit% − 抗性，下限 0、上限 75 |
| 爆擊傷 | × (1 + crit_dmg/100)，預設 +50% |
| 來源 | 角色基底 + 裝備 rolled + 戰魂 |

`Formulas.roll_hit_damage(...)` 統一出口。
