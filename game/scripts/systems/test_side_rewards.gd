extends SceneTree
## 支線發獎樣板的測試：godot --headless -s res://scripts/systems/test_side_rewards.gd
##
## _grant_side_reward() 把「設旗／清旗／給金／給星屑／評稱號／存檔／冒泡」收成一次宣告。
## 這串動作原本在 7 支支線裡各抄一遍，而其中兩行漏了都不會報錯：
##   TitleCatalog.evaluate_all() 漏了 → 只是少了當下的稱號提示（稱號牆會補評估）
##   SaveManager.save_game()   漏了 → 獎勵離線就沒了，是真的會掉東西
## 所以這裡把「一定要存檔」當成硬性不變量鎖住。

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")


var _w := 0


func _process(_d: float) -> bool:
	_w += 1
	if _w < 20:
		return false

	var main = current_scene
	var gs = root.get_node_or_null("GameState")
	if main == null or gs == null:
		_fail("主場景或 GameState 沒就緒")
		return _finish()
	if not main.has_method("_grant_side_reward"):
		_fail("main.gd 缺少 _grant_side_reward()")
		return _finish()

	_test_full_spec(main, gs)
	_test_saves(main, gs)
	_test_empty_spec(main, gs)
	return _finish()


## 完整規格：旗、清旗、金幣、星屑都要生效
func _test_full_spec(main: Node, gs: Node) -> void:
	gs.reset_new_game()
	gs.set_flag("should.be.cleared", true)
	var gold0: int = gs.gold
	var dust0: int = gs.stardust
	main._grant_side_reward({
		"flags": ["a.one", "a.two"],
		"clear_flags": ["should.be.cleared"],
		"gold": 45,
		"stardust": 3,
		"bubble": "測試",
	})
	if not gs.has_flag("a.one") or not gs.has_flag("a.two"):
		_fail("flags 沒有全部設起來")
		return
	if gs.has_flag("should.be.cleared"):
		_fail("clear_flags 沒有清掉")
		return
	if gs.gold != gold0 + 45:
		_fail("金幣 %d，期望 %d" % [gs.gold, gold0 + 45])
		return
	if gs.stardust != dust0 + 3:
		_fail("星屑 %d，期望 %d" % [gs.stardust, dust0 + 3])
		return
	print("  ok 旗／清旗／金幣／星屑都生效")


## 硬性不變量：發獎一定要落地存檔，否則玩家關掉遊戲就白拿
func _test_saves(main: Node, gs: Node) -> void:
	var sm = root.get_node_or_null("SaveManager")
	if sm == null:
		_fail("SaveManager autoload missing")
		return
	gs.reset_new_game()
	main._grant_side_reward({"flags": ["persist.check"], "gold": 7})
	if not sm.has_save():
		_fail("發獎後沒有存檔 —— 獎勵會在離線後消失")
		return
	## 讀回來確認真的寫進去了
	gs.reset_new_game()
	if gs.has_flag("persist.check"):
		_fail("reset_new_game 沒清乾淨，這個檢查無效")
		return
	sm.load_game()
	if not gs.has_flag("persist.check"):
		_fail("存檔裡沒有剛發的旗標")
		return
	if gs.gold < 7:
		_fail("存檔裡的金幣是 %d，沒收到發的 7" % gs.gold)
		return
	print("  ok 發獎後確實落地存檔（重讀後旗標與金幣都在）")


## 空規格不該爆，也不該亂動狀態
func _test_empty_spec(main: Node, gs: Node) -> void:
	gs.reset_new_game()
	var gold0: int = gs.gold
	main._grant_side_reward({})
	if gs.gold != gold0:
		_fail("空規格竟然改了金幣")
		return
	print("  ok 空規格安全")


func _finish() -> bool:
	if _ok:
		print("SIDE_REWARDS_OK")
		quit(0)
	else:
		print("SIDE_REWARDS_FAIL")
		quit(1)
	return true
