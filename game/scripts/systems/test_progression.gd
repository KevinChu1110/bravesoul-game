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
	_finish()


## 每一波都要給經驗，而且要跟在野外打同一隻怪一樣多
func _check_hunt_wave_xp(gs: Node, hunt: Node) -> void:
	for w in hunt.WAVES:
		var mode := str(w.get("mode", ""))
		var def: Dictionary = WorldContent.enemy_def(mode)
		if def.is_empty():
			_fail("狩獵波次的敵人 %s 在 WorldContent 裡查不到" % mode)
			return
		## main.gd 雜魚收尾用的同一條公式
		var wild_xp := 12 + int(int(def.get("max_hp", 50)) / 10)
		var got: int = hunt.wave_xp(mode, false)
		if got != wild_xp:
			_fail("狩獵波次 %s 給 %d 經驗，野外同一隻給 %d —— 兩邊要一致" % [mode, got, wild_xp])
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
