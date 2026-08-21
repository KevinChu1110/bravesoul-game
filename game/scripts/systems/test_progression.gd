extends SceneTree
## 經驗來源的把關測試：godot --headless -s res://scripts/systems/test_progression.gd
##
## 這支守的是一類特別安靜的壞法：**獎勵發了，但其中一種資源是 0。**
##
## 實際踩過兩次：
##   1. 狩獵場整場三波打完，經驗 0 —— 收尾走的是 HuntSystem 那條分支，
##      在 main.gd 給經驗的那段之前就 return 了。獵場比在野外打三隻還差，
##      而面板上寫著「只為鍛鍊與材料」。
##   2. 29 條里程碑任務，經驗 0 —— 獎勵表只有 gold/dust 兩欄，
##      而每天的小委託反而有 xp。通關終章對等級沒有任何貢獻。
##
## 兩件事都不會報錯、不會當掉、測不到畫面上少了什麼；
## 玩家只會覺得「怎麼練不太起來」。所以這裡直接對數字下斷言。

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var gs := root.get_node_or_null("GameState")
	var hunt := root.get_node_or_null("HuntSystem")
	var quest := root.get_node_or_null("QuestSystem")
	if gs == null or hunt == null or quest == null:
		_fail("GameState／HuntSystem／QuestSystem autoload missing")
		return _finish()

	_check_hunt_wave_xp(gs, hunt)
	_check_hunt_run_xp(gs, hunt)
	_check_mission_xp(gs, quest)
	_check_soul_slots_reachable()
	_check_forge_is_a_sink()
	_finish()


## 承諾的每一個魂槽都要拿得到。
##
## 踩過：魂槽表寫「T11 開第三槽」，而鍛造在 T8 就擋下來 ——
## 第三個魂槽是一個玩家再怎麼玩都拿不到的獎勵。兩份程式各自看都沒問題，
## 對起來才知道壞了，而且不會報錯：玩家只會把武器練到頂、
## 發現第三格還是灰的，以為是自己漏了什麼。
func _check_soul_slots_reachable() -> void:
	var soul := root.get_node_or_null("SoulSystem")
	var main_script := load("res://scripts/main.gd")
	if soul == null or main_script == null:
		_fail("SoulSystem 或 main.gd 載不到")
		return
	var max_tier := int(main_script.get("FORGE_MAX_TIER"))
	if max_tier <= 0:
		_fail("讀不到 main.gd 的 FORGE_MAX_TIER")
		return
	var tiers: Array = soul.SLOT_TIERS
	if tiers.is_empty():
		_fail("SoulSystem.SLOT_TIERS 是空的 —— 這條檢查等於沒在檢查")
		return
	for need in tiers:
		if int(need) > max_tier:
			_fail("魂槽要 T%d 才開，但鍛造只到 T%d —— 那一格永遠拿不到" % [int(need), max_tier])
			return
	print("  ok %d 個魂槽門檻（最高 T%d）都在鍛造上限 T%d 之內" % [
		tiers.size(), int(tiers[tiers.size() - 1]), max_tier
	])


## 鍛造是全遊戲最大的金幣去處，價格要跟著階數走。
##
## 踩過：每一階都是固定 50 金，T2 到封頂總共約 430 金 —— 比一趟野外來回還便宜。
## 而全遊戲 24 個收入點對 5 個支出點，實測一趟通關收入 10328、支出 1480。
## 金幣單向累積的結果是「賺錢」在中期之後完全失去意義，
## 而鍛造／戰魂／技能三條養成柱共用的就是這個資源。
func _check_forge_is_a_sink() -> void:
	var gs := root.get_node_or_null("GameState")
	var main_script := load("res://scripts/main.gd")
	if gs == null or main_script == null:
		_fail("GameState 或 main.gd 載不到")
		return
	var per := int(main_script.get("FORGE_COST_PER_TIER"))
	var max_tier := int(main_script.get("FORGE_MAX_TIER"))
	if per <= 0:
		_fail("讀不到 FORGE_COST_PER_TIER")
		return
	## 價格必須隨階上升，否則後期等於免費
	if per * max_tier <= per * 2:
		_fail("升階價沒有隨階數上升，鍛造在後期不再是金幣的去處")
		return
	## 一路練到頂要花的錢，要跟一趟通關的收入是同一個量級。
	## 太便宜＝金幣沒有用；太貴＝逼玩家刷。這裡只擋「太便宜」那一邊。
	var total := 0
	for t in range(2, max_tier):
		total += per * t
	if total < 2000:
		_fail("T2 練到 T%d 只要 %d 金，跟一趟通關上萬的收入不成比例" % [max_tier, total])
		return
	print("  ok 升階價隨階上升，T2→T%d 期望花費約 %d 金（未計失敗重試）" % [max_tier, total])


## 每一波都要給經驗，而且要跟在野外打同一隻怪一樣多
func _check_hunt_wave_xp(gs: Node, hunt: Node) -> void:
	for w in hunt.WAVES:
		var mode := str(w.get("mode", ""))
		var def: Dictionary = WorldContent.enemy_def(mode)
		if def.is_empty():
			_fail("狩獵波次的敵人 %s 在 WorldContent 裡查不到" % mode)
			return
		## 獵場＝野外薄經驗（Formulas.field_xp），材料才是多出來的
		var wild_xp := Formulas.field_xp(int(def.get("max_hp", 50)), 0)
		var got: int = hunt.wave_xp(mode, false)
		if got != wild_xp:
			_fail("狩獵波次 %s 給 %d 經驗，野外同一隻給 %d —— 兩邊要一致" % [mode, got, wild_xp])
			return
		var yard: int = Formulas.arena_xp(int(def.get("max_hp", 50)), false)
		if yard <= got:
			_fail("演武 %s 經驗 %d 應厚於野外／獵場 %d" % [mode, yard, got])
			return
		if got <= 0:
			_fail("狩獵波次 %s 的經驗是 %d" % [mode, got])
			return
		## 練習場次要縮水，但不可以縮成 0（面板寫的是「只剩三成五」不是「沒有」）
		var prac: int = hunt.wave_xp(mode, true)
		if prac <= 0 or prac >= got:
			_fail("狩獵波次 %s 練習經驗 %d 不合理（有獎是 %d）" % [mode, prac, got])
			return
	print("  ok 狩獵三波的經驗都跟野外同一隻怪一致，練習場次縮水但不歸零")


## 真的跑一場，確認經驗有進到 GameState
func _check_hunt_run_xp(gs: Node, hunt: Node) -> void:
	gs.reset_new_game()
	gs.set_flag("c1_entered_city", true)
	var r0: Dictionary = hunt.start_run(false)
	if not bool(r0.get("ok", false)):
		_fail("開不了狩獵：%s" % str(r0.get("msg", "")))
		return
	var before := _total_xp(gs)
	var waves := 0
	while hunt.is_run_active() and waves < 10:
		var r: Dictionary = hunt.on_wave_won()
		if not bool(r.get("ok", false)):
			_fail("第 %d 波結算失敗：%s" % [waves + 1, str(r.get("msg", ""))])
			return
		if int(r.get("xp", 0)) <= 0:
			_fail("第 %d 波回傳的經驗是 %d —— 呼叫端要靠這個數字顯示" % [waves + 1, int(r.get("xp", 0))])
			return
		waves += 1
		if bool(r.get("finished", false)):
			break
	if waves != hunt.WAVES.size():
		_fail("跑完一場只結算了 %d 波，應為 %d 波" % [waves, hunt.WAVES.size()])
		return
	var gained := _total_xp(gs) - before
	if gained <= 0:
		_fail("整場狩獵打完，GameState 的經驗一點都沒動")
		return
	print("  ok 一場狩獵 %d 波實際進帳 %d 經驗" % [waves, gained])


## 每一條里程碑都要發經驗
func _check_mission_xp(gs: Node, quest: Node) -> void:
	var zero: PackedStringArray = []
	for m in quest.MISSIONS:
		var gold_n := int(m.get("gold", 0))
		var xp_n := int(m.get("xp", gold_n * quest.MISSION_XP_PER_GOLD))
		if xp_n <= 0:
			zero.append(str(m.get("id", "?")))
	if zero.size() > 0:
		_fail("這些里程碑不發經驗：%s" % ", ".join(zero))
		return
	print("  ok %d 條里程碑都發經驗" % quest.MISSIONS.size())

	## 領一條真的會進帳
	gs.reset_new_game()
	gs.set_flag("boss.leo_cleared", true)
	var before := _total_xp(gs)
	var r: Dictionary = quest.claim_mission("m_first_boss")
	if not bool(r.get("ok", false)):
		_fail("領不到 m_first_boss：%s" % str(r.get("msg", "")))
		return
	var gained := _total_xp(gs) - before
	if gained <= 0:
		_fail("領了里程碑但經驗沒動（訊息：%s）" % str(r.get("msg", "")))
		return
	if str(r.get("msg", "")).find("經驗") < 0:
		_fail("領獎訊息沒有講經驗，玩家看不到自己拿了什麼：%s" % str(r.get("msg", "")))
		return
	print("  ok 領一條里程碑實際進帳 %d 經驗，訊息也講了" % gained)


## 等級會吃掉 xp，所以比總量而不是比 xp 欄位
func _total_xp(gs: Node) -> int:
	var total := int(gs.xp)
	for lv in range(1, int(gs.level)):
		total += 40 + lv * 25 + (lv * lv) / 2
	return total


func _finish() -> void:
	if _ok:
		print("PROGRESSION_OK")
		quit(0)
	else:
		print("PROGRESSION_FAIL")
		quit(1)
