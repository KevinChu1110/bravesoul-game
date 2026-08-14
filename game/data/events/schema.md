# 活動資料 Schema（EventCatalog）

路徑：`res://data/events/*.json`（檔名任意，內容為一個活動物件）。

## 必要欄位

| 欄位 | 型別 | 說明 |
|------|------|------|
| `id` | string | 唯一 id，建議 `YYYY_MM_slug` |
| `name` | string | 顯示名 |
| `start` | string | `YYYY-MM-DD`（含當日 00:00 本機） |
| `end` | string | `YYYY-MM-DD`（含當日） |

## 可選

| 欄位 | 型別 | 預設 | 說明 |
|------|------|------|------|
| `tagline` | string | "" | 一句話 |
| `force_active` | bool | false | true 時忽略日期（開發） |
| `recurring_month` | int | — | 1–12，每年同月自動開（優先於 start/end） |
| `challenge_enemy` | string | scar_wisp | 有獎挑戰敵人 mode |
| `token_to_gold` | int | 2 | 收攤 1 幣換幾金 |
| `title_flag` / `title_name` / `title_desc` | string | — | 活動稱號 |
| `daily_reward_cap` | int | 3 | 每日有獎次數 |
| `entry_map` | string | "" | 點「前往」開啟的 map id |
| `entry_need_flag` | string | "" | 需此 flag 才能進圖（否則只逛商店） |
| `entry_deny` | string | "" | 未解鎖提示 |
| `currency_name` | string | "活動幣" | |
| `story` | string[] | [] | 行商／活動石台詞 |
| `shop` | object[] | [] | `{id, cost, count?, name?}` 道具 id 見 InventorySystem |
| `missions` | object[] | [] | 見下 |
| `run_token` | int | 2 | 每次有獎挑戰獲得幣 |
| `run_gold` | int | 15 | 每次有獎挑戰金幣 |

## missions[]

| 欄位 | 說明 |
|------|------|
| `id` | 任務 id（存 `event.<event_id>.claim.<id>`） |
| `name` | 顯示名 |
| `desc` | 說明 |
| `need_runs` | 累計有獎挑戰次數 |
| `need_flag` | 需已立此 flag |
| `token` / `gold` / `dust` | 獎勵 |

## 執行期狀態（GameState.flags）

- `event.<id>.daily` — 今日日期字串  
- `event.<id>.runs_today` — 今日有獎次數  
- `event.<id>.runs_total` — 累計有獎次數  
- `event.<id>.token` — 活動幣  
- `event.<id>.claim.<mission_id>` — 任務已領  
