# 體驗回報（遙測）

上線之後最貴的東西不是伺服器，是「不知道玩家卡在哪」。沒有這份資料，
調平衡只能靠猜，猜錯了還會以為是內容不夠。

這份設計的原則只有一條：**每一種事件都要說得出它會讓誰去改哪一段。**
說不出來的就不收。目前總共五種。

---

## 1. 收哪五種，各自回答什麼

| 事件 | 什麼時候送 | 帶什麼 | 回答的問題 | 看到數字之後會做什麼 |
|---|---|---|---|---|
| `session_start` | 開遊戲、或當場按下同意 | `chapter` `level` `ng` | 有多少人在玩、回來時卡在第幾章 | 當所有其他比例的分母 |
| `session_tick` | 每 5 分鐘一次 | `sec` `chapter` | 一次坐下來玩多久、第幾分鐘離開 | 節奏太長就切段落；某章的時長異常短就是勸退點 |
| `chapter_enter` | 章節切換 | `chapter` `level` `sec` | 每章有多少人抵達 → 流失漏斗 | 掉最多的那一章優先重做開頭 |
| `battle_end` | 每場戰鬥結束（含逃跑） | `mode` `boss` `won` `dur` `level` `place` `chapter` | Boss 勸退率、首勝前打幾次、死在哪張圖 | 勸退率高的 Boss 調數值或補提示；死亡熱點補補給／改路線 |
| `tutorial_step` | 每則引導第一次看到 | `step` `chapter` | 教學完成率、哪一步之後就沒下文 | 沒人走到的引導代表入口藏太深 |

遊玩時長不另外開事件：每個 `session_id` 取 `max(session_sec)` 就是這次玩了多久，
`session_tick` 只是讓中途離開的那一段也有下界。

### 刻意不收的

- **通用事件系統**。有了它就會收三十種、一種都不看。要加第六種之前，先在上表補一列。
- **battle_start**。中途關遊戲的那場會漏掉，但那是少數；為了它多一倍事件量不划算。
- **每一次按鍵、每一次開面板**。這些會讓資料量翻十倍，而我們不做 UI A/B 測試。
- **金幣／掉寶流水**。經濟已經有 `econ_audit`（見 `supabase/economy.sql`），不重複收。
- **失敗重送**。送不出去就丟掉。少幾筆不影響結論，重送會在伺服器出事時把佇列變成炸彈。

---

## 2. 隱私

這不是靠自律，是靠型別。

- **預設關閉。** `user://telemetry.json` 裡沒有 `consent: true` 之前，佇列永遠是空的。
- **身分只有一顆本機亂數 `install_id`。** 跟帳號、Email、存檔都沒有關聯，
  `telemetry_events` 也刻意沒有任何外鍵——接得起來就變成個資，測試會擋下這件事。
- **字串只准 `a-z0-9_`。** 客戶端 `_clean_props()` 洗一次，伺服器
  `telemetry_clean_props()` 再洗一次。玩家取的名字、留言、檔案路徑在型別上就寫不進來。
  客戶端是玩家的、改得動，所以能不能寫進資料庫由伺服器決定。
- **白名單外的欄位直接丟掉**，不是截斷、不是雜湊。
- **連線關掉時一個字都不送。** 玩家關連線就是不想跟伺服器講話，同意過也一樣。
- **撤回就當場清空。**「我不要了」指的是還沒送的那些也別送，不是從下一筆開始。
- **保留 120 天**，過期由 `telemetry_prune()` 刪掉。留著只為了改遊戲，改完就沒有留的理由。

---

## 3. 客戶端

`game/scripts/autoload/telemetry.gd`（autoload 名稱 `Telemetry`）

- 自己的 `HTTPRequest`，跟 `OnlineGate` 分開——回報再慢也不可以拖到存檔。
- 批次送：滿 20 筆或每 60 秒送一次，一次一個 HTTP。
- 佇列上限 200 筆（滿了丟最舊的）、單場總量上限 400 筆。記憶體必須有上界。
- 連續失敗 5 次就整場閉嘴並倒掉佇列。
- 關視窗時盡量把最後一批送掉；送不完就算了，不擋玩家關視窗
  （代價：最後不到 5 分鐘的時長可能少算）。

### 已經接好的掛鉤（不需要動 main.gd）

| 來源 | 位置 |
|---|---|
| 章節進度 | 直接接 `GameState.chapter_changed` |
| 教學步驟 | `scripts/systems/tutorial_system.gd` 的 `mark()` |
| 目前在哪張圖 | `scripts/world/explore_view.gd` 的 `setup()` |
| 戰鬥開始／結果 | `scripts/battle/battle_view.gd` 的 `setup()` 與 `battle_finished` |

戰鬥掛在 `battle_finished` 訊號上而不是逐個 `emit` 點插一行，逃跑跟中途結束才不會漏。

### main.gd 還缺的一件事：同意的入口

**唯一需要動 main.gd 的地方是給玩家一個開關。** 在 `_go_online_panel()` 的
`buttons.append({"text": "顯示名：旅人", ...})` 前面加一行：

```gdscript
	buttons.append({"text": "體驗回報…", "cb": _go_telemetry_consent})
```

再加一支面板（放在 `_go_online_panel()` 後面即可）：

```gdscript
func _go_telemetry_consent() -> void:
	var body := Telemetry.consent_prompt_bbcode() + "\n\n" + Telemetry.status_line()
	var buttons: Array = []
	if Telemetry.has_consent():
		buttons.append({"text": "不要回報", "cb": func():
			Telemetry.set_consent(false)
			_show_toast("已關閉")
			_go_telemetry_consent()
		})
	else:
		buttons.append({"text": "好，幫忙回報", "cb": func():
			Telemetry.set_consent(true)
			_show_toast("謝謝")
			_go_telemetry_consent()
		})
	buttons.append({"text": "返回", "cb": _go_online_panel})
	_panel("體驗回報", body, buttons)
```

面板上的文字全部來自 `Telemetry.consent_prompt_bbcode()`，改文案只改那一支，
不要在 main.gd 裡另外寫一份。

---

## 4. 伺服器

`supabase/telemetry.sql`（跑在 `schema.sql`、`economy.sql` 之後，可重複執行）

**2026-08-16 已部署到正式專案。** 4 張表、5 張視圖、3 支函式；
權限實測過：`anon` 進得去 `telemetry_ingest`，讀不到 `telemetry_events`、
呼叫不到 `telemetry_prune`。冒煙測試也驗過清洗確實生效 ——
白名單外的事件名整筆丟掉、`player_name` 這種自由文字欄位被洗掉，
留下的只有白名單裡的短 token 與數字。

**每日清理排程也設好了**（2026-08-16）：Integrations → Cron 的
`telemetry-prune-daily`，`0 18 * * *`（GMT）＝台北 02:00，跑
`select public.telemetry_prune();`。

設之前要先在那頁按 **Install integration** 裝 `pg_cron`；沒裝的話按下
「Create cron job」只會回 `relation "cron.job" does not exist`，
而不是提示你去裝。

| 物件 | 作用 |
|---|---|
| `telemetry_events` | 事件本體。RLS 開著、沒有任何 policy、表權限也收乾淨 |
| `telemetry_config` | 上限與事件白名單 |
| `telemetry_quota` | 每個 install 的每小時額度、撞牆次數、人工停權 |
| `telemetry_gate` | 全站每小時上限 |
| `telemetry_ingest()` | 唯一寫入口 |
| `telemetry_clean_props()` | 欄位清洗（內部用，誰都不給） |
| `telemetry_prune()` | 過期清理（內部用，誰都不給） |

### 限流

匿名回報必須開給 `anon`——要玩家先辦帳號才肯收，收到的就只剩最黏的那群人，
數字沒有意義。代價是誰都能打這支 RPC，所以擋量的責任全在這裡：

- 單次呼叫最多 50 筆
- 單一 `install_id` 每小時 600 筆 / 120 次呼叫
- **全站每小時 500000 筆** —— `install_id` 是客戶端給的，換一顆就繞過個人上限，
  真正擋得住灌爆的是這一道
- 撞上限會記在 `telemetry_quota.over_limit_hits`，濫用時人工 `blocked = true`

### 權限（economy.sql 踩過的坑）

PostgreSQL 預設把新函式的 execute 給 `PUBLIC`，而 `anon` 是 `PUBLIC` 的成員，
所以「只 grant 給 authenticated」擋不掉未登入者。順序一定是
**先 `revoke ... from public, anon, authenticated`，再把該給的明確 grant 回去**。

Supabase 另外會對 `public` schema 的新表自動授權給 `anon` / `authenticated`，
所以表也要一張一張 revoke，不能只靠 RLS。

### 看數字

```sql
select * from public.telemetry_chapter_funnel;   -- 哪一章之後人就不見了
select * from public.telemetry_boss_wall;        -- 勸退率由高到低
select * from public.telemetry_death_spots limit 30;
select * from public.telemetry_tutorial_funnel;
select * from public.telemetry_session_len;      -- 一次玩多久
```

視圖都不開放給 `anon` / `authenticated`，只有 Dashboard（`service_role`）讀得到。

定期清理（已排程為 `telemetry-prune-daily`，Integrations → Cron，每天一次）：

```sql
select public.telemetry_prune();
```

---

## 5. 測試

```bash
bash tools/test_economy_sql.sh          # 起臨時 PostgreSQL，跑 schema + economy + telemetry 與兩份情境測試
TEST_FILTER=telemetry bash tools/run_tests.sh
```

SQL 測試（`supabase/telemetry_test.sql`）守的是限流、欄位清洗、事件表接不到帳號、
以及七條側門（讀取／直寫／視圖／內部函式／參數表）。
它必須跑在 `economy_test.sql` **之前**——那支開頭會把 `public` 底下所有表授權給 `anon`，
跑在它後面就測不出權限收斂了。

客戶端測試（`game/scripts/autoload/test_telemetry.gd`）會把
`supabase/telemetry.sql` 的 `allowed_names` 讀出來跟客戶端的事件名對照。
加事件時兩邊都要改，只改一邊測試會擋下來。
