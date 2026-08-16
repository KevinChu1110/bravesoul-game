extends SceneTree
## 多格存檔與舊檔升級把關：godot --headless -s res://scripts/autoload/test_save_slots.gd
##
## 這支守的是玩家唯一不能重來的東西。三件最容易破的事：
##
##   1. 舊檔升得上來 —— 改存檔結構的人只會測新檔。舊檔壞掉不會噴錯，
##      只會讓玩家的數值悄悄不對，所以每一種舊格式都得在這裡走一次。
##   2. 四格互不干擾 —— 存第 2 格不可以動到第 1 格；刪一格不可以連累別格。
##   3. 升級不會把資料吃掉 —— 未來版本的檔要原樣退回，壞檔不能讓遊戲當掉。
##
## 注意：用 `-s` 跑時 autoload 的 _ready 在 _initialize 之後才執行，
## 所以檢查全部放在第一個影格（見 scripts/art/test_bgm.gd）。
##
## 也注意：測試會改 SaveManager.root_dir 指到獨立資料夾再動手，
## 不然跑一次測試就把開發機上真正的存檔洗掉了。

const SaveMigration = preload("res://scripts/autoload/save_migration.gd")

## 面板只能在執行期 load()，不能 preload —— 它直接寫 SaveManager／GameState，
## 而 `-s` 腳本編譯的時候 autoload 還沒註冊（見 AGENTS.md「寫測試的規矩」）。
const PANEL_PATH := "res://scripts/ui/panels/save_slots_panel.gd"

const TEST_ROOT := "user://_test_save_slots"


## 假宿主：面板只准碰 main.gd 的公開介面（見 main.gd「面板宿主介面」），
## 所以照著那三支做一個殼就能在沒有主場景的情況下驗面板。
## 這支還兼一個用途：面板還沒接進 main.gd 之前，test_panels.gd 驗不到它。
class FakeHost:
	extends Node
	var title := ""
	var body := ""
	var buttons: Array = []
	var toasts: PackedStringArray = []

	func ui_panel(t: String, b: String, btns: Array) -> void:
		title = t
		body = b
		buttons = btns

	func ui_toast(msg: String) -> void:
		toasts.append(msg)

	func ui_goto(_target: String) -> bool:
		return true

	## 找出文字含某段字的按鈕；找不到回空字典
	func find_button(needle: String) -> Dictionary:
		for b in buttons:
			if str((b as Dictionary).get("text", "")).find(needle) >= 0:
				return b
		return {}

	func press(needle: String) -> bool:
		var b := find_button(needle)
		if b.is_empty():
			return false
		(b["cb"] as Callable).call()
		return true

var _ok := true
var _done := false


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var sm := root.get_node_or_null("SaveManager")
	var gs := root.get_node_or_null("GameState")
	if sm == null or gs == null:
		_fail("SaveManager／GameState autoload missing")
		return _finish()

	## 版本號兩邊要對齊，不然存進去的 version 跟升級表認得的不是同一個
	if int(gs.VERSION) != int(SaveMigration.CURRENT):
		_fail("GameState.VERSION=%d 與升級表的 %d 不一致" % [int(gs.VERSION), int(SaveMigration.CURRENT)])
		return _finish()

	## 純算資料的部分不必碰檔案
	_check_v1_upgrade()
	_check_v2_upgrade()
	_check_v3_upgrade()
	_check_idempotent()
	_check_future_version()
	_check_garbage()
	_check_no_mutation()
	_check_state_round_trip(gs)

	## 碰檔案的部分先搬到獨立資料夾
	_wipe_test_root()
	var was_root: String = sm.root_dir
	var was_slot: int = sm.current_slot
	sm.root_dir = TEST_ROOT
	sm.current_slot = 1

	_check_slots_independent(sm, gs)
	_check_old_file_loads(sm, gs)
	_check_summaries(sm, gs)
	_check_legacy_adopt(sm)
	_check_panel(sm, gs)

	sm.root_dir = was_root
	sm.current_slot = was_slot
	_wipe_test_root()
	return _finish()


# ─── 舊檔資料 ───

## 0.13 以前的存檔長這樣：沒有 version、招式只有一個欄位、
## 武器流派還叫 soul／iron、快捷欄只存了用到的幾格、戰魂的 equipped 各記各的。
func _v1_save() -> Dictionary:
	return {
		"chapter": "c3",
		"player_name": "小白",
		"level": 12,
		"gold": 340,
		"path_style": "soul",
		"skill_slash_lv": 4,
		"hotbar": ["hp_s", "bread"],
		## 第 1 顆在槽上、第 2 顆不在，但兩顆的 equipped 都是 true —— 這正是
		## 舊版換槽漏更新造成的走樣，第 3 版要照 soul_slots 把它們扳回來
		"soul_slots": ["soul_a", ""],
		"souls": [
			{"id": "soul_a", "star": "破軍", "quality": "凡", "level": 2, "equipped": true},
			{"id": "soul_b", "star": "貪狼", "quality": "靈", "level": 0, "equipped": true},
		],
	}


func _check_v1_upgrade() -> void:
	var res: Dictionary = SaveMigration.migrate(_v1_save())
	if not bool(res.get("ok", false)):
		_fail("第 1 版存檔升不上來：%s" % str(res.get("reason", "")))
		return
	var d: Dictionary = res.get("data", {})

	if int(d.get("version", 0)) != int(SaveMigration.CURRENT):
		_fail("升完版本是 %s，應該是 %d" % [str(d.get("version")), int(SaveMigration.CURRENT)])
		return
	var applied: PackedStringArray = res.get("applied", PackedStringArray())
	if applied.size() != int(SaveMigration.CURRENT) - 1:
		_fail("第 1 版應該走 %d 步，實際走了 %s" % [int(SaveMigration.CURRENT) - 1, str(applied)])
		return

	## 欄位拆分：一個等級展開成每招各自的等級與熟練
	var sd: Dictionary = d.get("skill_data", {})
	if not sd.has("slash") or int((sd["slash"] as Dictionary).get("lv", 0)) != 4:
		_fail("斬擊等級沒有展開成招式資料，實際 %s" % str(sd))
		return

	## 值改名
	if str(d.get("path_style", "")) != "magic":
		_fail("武器流派 soul 應該改名成 magic，實際 %s" % str(d.get("path_style")))
		return

	## 長度語意：快捷欄固定 8 格
	var hb: Array = d.get("hotbar", [])
	if hb.size() != 8 or str(hb[0]) != "hp_s" or str(hb[7]) != "":
		_fail("快捷欄沒有補滿 8 格，實際 %s" % str(hb))
		return

	## 欄位新增：舊檔沒有遊玩時間，要補 0 而不是留空
	if not d.has("play_time") or float(d.get("play_time", -1.0)) != 0.0:
		_fail("舊檔沒補上遊玩時間，實際 %s" % str(d.get("play_time")))
		return

	## 語意改變：equipped 改成照 soul_slots 重算
	var souls: Array = d.get("souls", [])
	if souls.size() != 2:
		_fail("戰魂數量被改動了：%s" % str(souls))
		return
	if not bool((souls[0] as Dictionary).get("equipped", false)):
		_fail("在槽上的戰魂應該是已裝備")
		return
	if bool((souls[1] as Dictionary).get("equipped", true)):
		_fail("不在任何槽上的戰魂還掛著已裝備 —— 舊值被沿用了，語意升級沒生效")
		return

	print("  ok 第 1 版舊檔升到第 %d 版（欄位拆分／改名／新增／語意重算都對）" % int(SaveMigration.CURRENT))


## 從第 2 版起跳的檔不可以再跑一次 1→2，不然會把已經整理好的招式資料弄回去
func _check_v2_upgrade() -> void:
	var v2 := {
		"version": 2,
		"chapter": "c1",
		"skill_slash_lv": 1,
		"skill_data": {"slash": {"lv": 7, "mastery": 30}},
		"path_style": "magic",
		"hotbar": ["", "", "", "", "", "", "", ""],
		"soul_slots": [],
		"souls": [{"id": "soul_x", "equipped": true}],
	}
	var res: Dictionary = SaveMigration.migrate(v2)
	if not bool(res.get("ok", false)):
		_fail("第 2 版存檔升不上來：%s" % str(res.get("reason", "")))
		return
	var applied: PackedStringArray = res.get("applied", PackedStringArray())
	if applied.is_empty() or applied[0] != "2→3":
		_fail("第 2 版第一步應該是 2→3，實際 %s" % str(applied))
		return
	var d: Dictionary = res.get("data", {})
	var lv := int(((d.get("skill_data", {}) as Dictionary).get("slash", {}) as Dictionary).get("lv", 0))
	if lv != 7:
		_fail("第 2 版的招式資料被 1→2 蓋掉了，等級變成 %d" % lv)
		return
	## 沒有任何槽，所以那顆魂的已裝備要被扳成 false
	if bool(((d.get("souls", []) as Array)[0] as Dictionary).get("equipped", true)):
		_fail("沒有魂槽時 equipped 還是 true")
		return
	print("  ok 第 2 版從 2→3 起跳，不會倒著把資料改回去")


## 3 → 4：倉庫與市集被移除，寄放在那裡的東西必須全數還給玩家。
## 這一步如果只是把欄位刪掉，存檔讀得出來、遊戲也不報錯，但玩家的材料與裝備
## 會安安靜靜消失 —— 正是升級表存在的理由，所以這裡逐項清點。
func _check_v3_upgrade() -> void:
	var v3 := {
		"version": 3,
		"chapter": "cleared",
		"play_time": 120.0,
		"inventory": {"hp_s": 2, "hunt_hide": 1},
		"warehouse": {"hp_s": 5, "hunt_bone": 3},
		"equip_bag": [{"uid": "a", "id": "rusty_blade"}],
		"warehouse_equip": [{"uid": "b", "id": "dawn_blade"}],
		"souls": [],
		"soul_slots": [],
		"flags": {
			"market.local_listings": [
				{"item_id": "hunt_hide", "qty": 4, "price": 30},
				{"qty": 9},
			],
			"market.pending_credit": 120,
			"c1_forged": true,
		},
	}
	var res: Dictionary = SaveMigration.migrate(v3)
	if not bool(res.get("ok", false)):
		_fail("第 3 版存檔升不上來：%s" % str(res.get("reason", "")))
		return
	var d: Dictionary = res.get("data", {})

	var inv: Dictionary = d.get("inventory", {})
	## 背包 2 + 倉庫 5 = 7；掛單退的 4 加在原本的 1 上 = 5
	if int(inv.get("hp_s", 0)) != 7:
		_fail("倉庫裡的小紅水沒有倒回背包：hp_s=%d，期望 7" % int(inv.get("hp_s", 0)))
		return
	if int(inv.get("hunt_bone", 0)) != 3:
		_fail("倉庫獨有的材料整批不見了：hunt_bone=%d，期望 3" % int(inv.get("hunt_bone", 0)))
		return
	if int(inv.get("hunt_hide", 0)) != 5:
		_fail("市集掛單沒有退貨：hunt_hide=%d，期望 5" % int(inv.get("hunt_hide", 0)))
		return

	var eq: Array = d.get("equip_bag", [])
	if eq.size() != 2:
		_fail("倉庫裡的裝備沒有倒回未裝備清單，剩 %d 件" % eq.size())
		return

	if d.has("warehouse") or d.has("warehouse_equip"):
		_fail("倉庫欄位倒完之後應該一併移除")
		return
	var flags: Dictionary = d.get("flags", {})
	if flags.has("market.local_listings") or flags.has("market.pending_credit"):
		_fail("市集殘留的旗標沒有清掉：%s" % str(flags.keys()))
		return
	if not bool(flags.get("c1_forged", false)):
		_fail("清市集旗標時把別的旗標一起清掉了")
		return
	print("  ok 第 3 版升到第 4 版：倉庫與掛單的東西全數退回背包，殘留旗標清乾淨")


## 已經是最新版的檔再升一次要原封不動 —— 遊戲每次載入都會呼叫，不能每次都變一點
func _check_idempotent() -> void:
	var once: Dictionary = SaveMigration.migrate(_v1_save())
	var twice: Dictionary = SaveMigration.migrate(once.get("data", {}))
	if not bool(twice.get("ok", false)):
		_fail("最新版的檔再升一次失敗了")
		return
	if not (twice.get("applied", PackedStringArray()) as PackedStringArray).is_empty():
		_fail("最新版的檔不該再跑任何步驟，實際 %s" % str(twice.get("applied")))
		return
	if JSON.stringify(once.get("data", {})) != JSON.stringify(twice.get("data", {})):
		_fail("同一份檔升兩次結果不一樣")
		return
	print("  ok 升級可重複執行，第二次不再改動任何欄位")


## 玩家在另一台裝了新版、存檔同步回這台舊版：只能擋下來，不能降級寫壞
func _check_future_version() -> void:
	var future := {"version": int(SaveMigration.CURRENT) + 5, "player_name": "未來的我", "level": 99}
	var res: Dictionary = SaveMigration.migrate(future)
	if bool(res.get("ok", false)):
		_fail("比現在還新的存檔不該被當成升級成功")
		return
	if not bool(res.get("future", false)):
		_fail("比現在還新的存檔沒有被標記出來，面板無法跟玩家解釋")
		return
	var d: Dictionary = res.get("data", {})
	if int(d.get("version", 0)) != int(SaveMigration.CURRENT) + 5 or str(d.get("player_name", "")) != "未來的我":
		_fail("比現在還新的存檔被動過了：%s" % str(d))
		return
	print("  ok 比目前新的存檔原樣退回並標記，不會被降級覆寫")


## 檔案被截斷、被亂改：要回失敗，不可以當掉，也不可以吐出半份資料
func _check_garbage() -> void:
	for bad in [null, "", 42, [], [1, 2, 3]]:
		var res: Dictionary = SaveMigration.migrate(bad)
		if bool(res.get("ok", false)):
			_fail("壞資料 %s 竟然升級成功" % str(bad))
			return
	var empty: Dictionary = SaveMigration.migrate({})
	if not bool(empty.get("ok", false)):
		_fail("空字典應該當成最舊的檔升上來，而不是失敗")
		return
	if int((empty.get("data", {}) as Dictionary).get("version", 0)) != int(SaveMigration.CURRENT):
		_fail("空字典升完沒有蓋上版本號")
		return
	print("  ok 壞資料一律回失敗；空存檔當成最舊的檔升上來")


## 升級不可以就地改壞呼叫端手上那份 —— 呼叫端還要拿原檔比對存檔時間
func _check_no_mutation() -> void:
	var src := _v1_save()
	var before := JSON.stringify(src)
	SaveMigration.migrate(src)
	if JSON.stringify(src) != before:
		_fail("升級把傳進去的字典就地改掉了")
		return
	print("  ok 升級不會改到傳進來的原始存檔")


## GameState 的每個欄位都要存得下、也讀得回。
##
## 這條守的是「加了新欄位卻忘了寫進 to_dict」。升級表守的是舊檔，
## 這條守的是新檔 —— 而且是更常發生的那一種：欄位漏存不會噴任何訊息，
## 玩家只會覺得某個東西每次讀檔就自己變回去，還以為是自己記錯。
##
## 欄位名是從 get_script_property_list() 撈的，不是手抄一張表。
## 手抄的表就是漏抄的那一欄不會有人發現；用撈的，以後有人加欄位不必記得回來改這裡，
## 忘了加進 to_dict 當場就紅。
func _check_state_round_trip(gs: Node) -> void:
	var names: Array[String] = []
	for p in gs.get_script().get_script_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(str(p["name"]))
	if names.is_empty():
		_fail("列不出 GameState 的欄位 —— 這條檢查會變成空轉")
		return

	gs.reset_new_game()
	var want := {}
	var i := 0
	for n in names:
		i += 1
		var v: Variant = _odd_value(gs.get(n), i)
		if typeof(v) == TYPE_NIL:
			_fail("欄位 %s 是沒見過的型別，補一個測試值進 _odd_value()" % n)
			return
		gs.set(n, v)
		want[n] = v

	var d: Dictionary = gs.to_dict()
	for n2 in names:
		if not d.has(n2):
			_fail("欄位 %s 沒被寫進存檔 —— 玩家每次讀檔都會弄丟它" % n2)
			return

	gs.reset_new_game()
	gs.from_dict(d)
	for n3 in names:
		if str(gs.get(n3)) != str(want[n3]):
			_fail("欄位 %s 走一趟存讀就變了：存進去 %s，讀回來 %s"
				% [n3, str(want[n3]), str(gs.get(n3))])
			return
	gs.reset_new_game()
	print("  ok GameState %d 個欄位存得下也讀得回" % names.size())


## 造一個「跟預設不一樣」的值，而且每個欄位都不同 ——
## 值都不一樣，連「兩個欄位讀回來對調」都會被抓到。
func _odd_value(cur: Variant, i: int) -> Variant:
	match typeof(cur):
		TYPE_BOOL:
			return not bool(cur)
		TYPE_INT:
			return 1000 + i
		TYPE_FLOAT:
			return 1000.0 + float(i)
		TYPE_STRING:
			return "zz%d" % i
		TYPE_DICTIONARY:
			return {"k%d" % i: i}
		TYPE_ARRAY:
			## 給滿 8 格：快捷欄讀回來時會被補到 8 格，
			## 少給幾格的話它會跟存進去的不一樣長，變成一條假的不一致
			var a: Array = []
			for j in 8:
				a.append("v%d_%d" % [i, j])
			return a
	return null


# ─── 真的碰檔案的部分 ───

func _check_slots_independent(sm: Node, gs: Node) -> void:
	gs.reset_new_game()
	gs.player_name = "甲"
	gs.level = 5
	if sm.save_game(1) != OK:
		_fail("第 1 格存不進去")
		return

	gs.reset_new_game()
	gs.player_name = "乙"
	gs.level = 9
	if sm.save_game(2) != OK:
		_fail("第 2 格存不進去")
		return

	if sm.load_game(1) != OK or str(gs.player_name) != "甲" or int(gs.level) != 5:
		_fail("寫第 2 格把第 1 格弄壞了：%s Lv%d" % [str(gs.player_name), int(gs.level)])
		return
	if sm.load_game(2) != OK or str(gs.player_name) != "乙" or int(gs.level) != 9:
		_fail("第 2 格讀回來不對：%s Lv%d" % [str(gs.player_name), int(gs.level)])
		return

	## 無參數的存讀（main.gd 到處在用）要落在目前這一格
	sm.current_slot = 2
	gs.level = 21
	if sm.save_game() != OK:
		_fail("無參數存檔失敗")
		return
	if sm.load_game(1) != OK or int(gs.level) != 5:
		_fail("無參數存檔寫到別格去了")
		return
	if sm.load_game(2) != OK or int(gs.level) != 21:
		_fail("無參數存檔沒寫進目前這一格")
		return

	## 刪一格不可以連累別格
	if sm.delete_slot(1) != OK:
		_fail("第 1 格刪不掉")
		return
	if sm.has_save_in(1):
		_fail("第 1 格刪完還在")
		return
	if not sm.has_save_in(2) or not sm.has_save():
		_fail("刪第 1 格連第 2 格一起沒了")
		return

	## 開新旅途要挑空格，不能挑到玩家正在玩的那一格
	if int(sm.first_empty_slot()) != 1:
		_fail("第 1 格空著，卻不是第一個可用的空格：%d" % int(sm.first_empty_slot()))
		return
	for s in range(1, int(sm.SLOT_COUNT) + 1):
		if not sm.has_save_in(s):
			gs.player_name = "填格子"
			sm.save_game(s)
	if int(sm.first_empty_slot()) != 0:
		_fail("四格都滿了還回報有空格")
		return
	for s2 in range(1, int(sm.SLOT_COUNT) + 1):
		if s2 != 2:
			sm.delete_slot(s2)
	print("  ok 四格各自獨立：互不覆寫、刪一格不連累別格、無參數存讀落在目前這格")


## 這支是整個第 6 步的核心：把一份舊格式的檔直接放進格子裡，
## 走完整條載入路徑，確認玩家真的接得回自己的進度。
func _check_old_file_loads(sm: Node, gs: Node) -> void:
	var slot := 3
	var raw := _v1_save()
	raw["saved_at"] = int(Time.get_unix_time_from_system()) - 7200
	var f := FileAccess.open(sm.slot_path(slot), FileAccess.WRITE)
	if f == null:
		_fail("寫不出舊格式測試檔")
		return
	f.store_string(JSON.stringify(raw, "\t"))
	f.close()

	## 摘要要能直接讀舊檔，而且標出它是舊的
	var pre: Dictionary = sm.slot_summary(slot)
	if not bool(pre.get("outdated", false)) or str(pre.get("name", "")) != "小白":
		_fail("舊檔的摘要不對：%s" % str(pre))
		return

	gs.reset_new_game()
	if sm.load_game(slot) != OK:
		_fail("舊格式的檔載不起來")
		return

	if int(gs.level) != 12 or int(gs.gold) != 340 or str(gs.chapter) != "c3":
		_fail("舊檔的進度沒接回來：Lv%d 金 %d 章節 %s" % [int(gs.level), int(gs.gold), str(gs.chapter)])
		return
	if str(gs.path_style) != "magic":
		_fail("舊檔的武器流派沒改名：%s" % str(gs.path_style))
		return
	if int((gs.skill_data.get("slash", {}) as Dictionary).get("lv", 0)) != 4:
		_fail("舊檔的招式沒展開：%s" % str(gs.skill_data))
		return
	if gs.hotbar.size() != 8:
		_fail("舊檔的快捷欄沒補滿：%s" % str(gs.hotbar))
		return
	if bool((gs.souls[1] as Dictionary).get("equipped", true)):
		_fail("舊檔的戰魂裝備狀態沒有重算")
		return

	## 升完要當場寫回，不然下次開遊戲又是舊格式
	var back: Dictionary = sm.slot_summary(slot)
	if int(back.get("version", 0)) != int(SaveMigration.CURRENT) or bool(back.get("outdated", true)):
		_fail("升級後沒有寫回檔案，摘要還是 %s" % str(back))
		return
	## 寫回不是玩家存的檔，存檔時間要保留原本的，不能變成「剛剛」
	if int(back.get("saved_at", 0)) != int(raw["saved_at"]):
		_fail("寫回時把存檔時間改掉了")
		return
	print("  ok 舊格式的檔可以直接載入、進度完整接回、並自動寫回成新格式")


func _check_summaries(sm: Node, gs: Node) -> void:
	var list: Array = sm.slot_summaries()
	if list.size() != int(sm.SLOT_COUNT):
		_fail("摘要應該有 %d 格，實際 %d" % [int(sm.SLOT_COUNT), list.size()])
		return

	## 空格要明確講自己是空的，不能假裝有紀錄
	var empty: Dictionary = sm.slot_summary(4)
	if bool(empty.get("used", true)):
		_fail("沒存過的第 4 格被當成有紀錄")
		return

	gs.reset_new_game()
	gs.player_name = "丙"
	gs.level = 30
	gs.chapter = "c6"
	gs.play_time = 3 * 3600 + 12 * 60
	sm.save_game(4)
	var s: Dictionary = sm.slot_summary(4)
	for key in ["name", "place", "level", "play_time_text", "saved_at_text"]:
		if str(s.get(key, "")) == "":
			_fail("摘要缺了 %s：%s" % [key, str(s)])
			return
	if str(s.get("place", "")) != "塔下營地":
		_fail("章節沒有換成地名，實際 %s" % str(s.get("place")))
		return
	if str(s.get("play_time_text", "")) != "3 小時 12 分":
		_fail("遊玩時間排版不對：%s" % str(s.get("play_time_text")))
		return
	if str(s.get("saved_at_text", "")) != "剛剛":
		_fail("剛存的檔應該顯示剛剛，實際 %s" % str(s.get("saved_at_text")))
		return
	## 摘要是玩家直接讀的，不可以出現 c6 這種內部代號
	if "c6" in str(s.get("place", "")):
		_fail("摘要把章節代號漏給玩家看了")
		return
	print("  ok 摘要有角色名／地名／等級／遊玩時間／存檔時間，空格也標得出來")


## 0.14 之前的單檔要自己搬進第 1 格，而且不能重複搬
func _check_legacy_adopt(sm: Node) -> void:
	if sm.has_save_in(1):
		sm.delete_slot(1)
	var old := _v1_save()
	old["player_name"] = "從前的我"
	var f := FileAccess.open(sm.legacy_path(), FileAccess.WRITE)
	if f == null:
		_fail("寫不出舊的單一存檔")
		return
	f.store_string(JSON.stringify(old, "\t"))
	f.close()

	if not sm._adopt_legacy_save():
		_fail("舊的單一存檔沒有被搬進第 1 格")
		return
	if str(sm.slot_summary(1).get("name", "")) != "從前的我":
		_fail("搬過來的內容不對：%s" % str(sm.slot_summary(1)))
		return
	if FileAccess.file_exists(sm.legacy_path()):
		_fail("搬完之後舊檔還在原地，下次開遊戲會再搬一次")
		return
	## 第 1 格已經有東西了就不准再蓋
	var f2 := FileAccess.open(sm.legacy_path(), FileAccess.WRITE)
	f2.store_string(JSON.stringify({"player_name": "不該出現"}, "\t"))
	f2.close()
	if sm._adopt_legacy_save():
		_fail("第 1 格有紀錄時還去搬舊檔，玩家的進度會被蓋掉")
		return
	print("  ok 舊的單一存檔搬進第 1 格且只搬一次，不會蓋掉已有的紀錄")


## 面板：列得出四格、空格能開新旅途、刪除要按兩次、載入會通知宿主接畫面
func _check_panel(sm: Node, gs: Node) -> void:
	## 留一格空的出來，才驗得到「新的旅途」那條路
	if sm.has_save_in(4):
		sm.delete_slot(4)

	var panel_script: GDScript = load(PANEL_PATH)
	if panel_script == null:
		_fail("存檔面板載不起來")
		return
	var host := FakeHost.new()
	var panel: RefCounted = panel_script.new(host)
	var resumed: Array = []
	panel.on_loaded = func() -> void:
		resumed.append(true)
	panel.open()

	if host.title != "旅途紀錄":
		_fail("面板標題不對：%s" % host.title)
		host.free()
		return
	## 章節代號、檔名這些內部字眼不可以出現在玩家讀的那一面
	for leak in ["c0", "c6", "slot_", ".json", "version"]:
		if leak in host.body:
			_fail("面板內文漏出內部字眼「%s」" % leak)
			host.free()
			return
	if host.find_button("第 4 格 · 新的旅途").is_empty():
		_fail("空的第 4 格沒有開新旅途的按鈕：%s" % str(host.buttons))
		host.free()
		return
	if host.find_button("第 2 格 · 接著走").is_empty() or host.find_button("第 2 格 · 刪掉").is_empty():
		_fail("有紀錄的第 2 格少了按鈕：%s" % str(host.buttons))
		host.free()
		return

	## 刪除按第一次只是舉手，檔案要還在
	host.press("第 2 格 · 刪掉")
	if not sm.has_save_in(2):
		_fail("刪除按第一次就把檔刪了")
		host.free()
		return
	if host.find_button("第 2 格 · 再按一次").is_empty():
		_fail("刪除按第一次之後沒有要求確認：%s" % str(host.buttons))
		host.free()
		return
	host.press("第 2 格 · 再按一次")
	if sm.has_save_in(2):
		_fail("刪除按第二次沒有真的刪掉")
		host.free()
		return

	## 空格開新旅途：寫得出檔，而且要通知宿主把畫面接過去
	host.press("第 4 格 · 新的旅途")
	if not sm.has_save_in(4):
		_fail("開新旅途沒有寫進第 4 格")
		host.free()
		return
	if resumed.size() != 1:
		_fail("開新旅途沒有通知宿主接畫面")
		host.free()
		return

	## 載入既有紀錄：進度要真的回到 GameState
	panel.open()
	gs.reset_new_game()
	host.press("第 3 格 · 接著走")
	if int(gs.level) != 12 or str(gs.chapter) != "c3":
		_fail("面板載入第 3 格沒有把進度接回來：Lv%d %s" % [int(gs.level), str(gs.chapter)])
		host.free()
		return
	if resumed.size() != 2:
		_fail("載入之後沒有通知宿主接畫面")
		host.free()
		return

	host.free()
	print("  ok 面板列得出四格、刪除要按兩次、開新旅途與載入都會通知宿主")


# ─── 收尾 ───

func _wipe_test_root() -> void:
	var d := DirAccess.open(TEST_ROOT)
	if d == null:
		return
	for sub in d.get_directories():
		var sd := DirAccess.open(TEST_ROOT.path_join(sub))
		if sd != null:
			for fn in sd.get_files():
				sd.remove(fn)
		d.remove(sub)
	for fn2 in d.get_files():
		d.remove(fn2)
	DirAccess.remove_absolute(TEST_ROOT)


func _finish() -> bool:
	if _ok:
		print("SAVE_SLOTS_OK")
		quit(0)
	else:
		print("SAVE_SLOTS_FAIL")
		quit(1)
	return true
