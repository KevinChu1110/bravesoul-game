extends SceneTree
## 對話選項的把關測試：godot --headless -s res://scripts/systems/test_dialog_choices.gd
##
## 守一件事：**選項要真的有分別，而且只影響自己那段對話。**
##
## 踩過兩種壞法，都不會報錯：
##   1. 演武場練功選「離開」照樣練 —— after 回呼無條件就跑 _side_training_do()，
##      連每日額度都一起扣掉。玩家選了「不要」，遊戲還是做了。
##   2. 練功點「開練」會扣 30 金並把小芽支線靜默結案 —— _on_choice 是全域的，
##      原本只認「畫面是 C1_TOWN + 選了 index 0」，而演武場的畫面鍵剛好也是
##      C1_TOWN、第一項剛好也是 index 0。兩段不相干的對話共用一個處理器。
##
## 玩家的感覺是「錢突然少了 30」，沒有任何訊息、沒有任何錯誤。

var _ok := true
var _step := 0
var _wait := 0
var _main: Node = null


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


## 呼叫不存在的方法時，Godot 只會噴一行 SCRIPT ERROR 然後繼續跑，
## 測試照樣走到最後印 OK —— 那是假綠燈。這裡先確認方法在，不在就當場失敗。
func _call(target: Node, method: String, arg: Variant = null) -> void:
	if not target.has_method(method):
		_fail("main.gd 沒有 %s()，這支測試等於沒在測" % method)
		return
	if arg == null:
		target.call(method)
	else:
		target.call(method, arg)


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 20:
		return false
	_main = current_scene
	var gs := root.get_node_or_null("GameState")
	if _main == null or gs == null:
		_fail("主場景／GameState 沒就緒")
		return _finish()
	_check_training_leave(gs)
	_check_training_does_not_touch_sprout(gs)
	return _finish()


## 選「離開」不該練，也不該吃掉每日額度
func _check_training_leave(gs: Node) -> void:
	gs.reset_new_game()
	gs.set_flag("c1_entered_city", true)
	gs.set_flag("c1_forged", true)
	var xp0 := int(gs.xp)
	var done0 := int(gs.get_flag("meta.train_today", 0))
	_call(_main, "_side_training_spar", "training_ring")
	_main.set("_last_choice", 1)          ## 玩家選「離開」
	_main.call("_on_dialogue_finished")
	if int(gs.xp) != xp0:
		_fail("選了「離開」還是給了經驗（%d → %d）" % [xp0, int(gs.xp)])
		return
	if int(gs.get_flag("meta.train_today", 0)) != done0:
		_fail("選了「離開」還是扣掉每日練功額度")
		return
	print("  ok 練功選「離開」：不給經驗、不扣額度")

	## 選「開練」要真的練
	gs.reset_new_game()
	gs.set_flag("c1_entered_city", true)
	gs.set_flag("c1_forged", true)
	var xp1 := int(gs.xp)
	_call(_main, "_side_training_spar", "training_ring")
	_main.set("_last_choice", 0)          ## 玩家選「開練」
	_main.call("_on_dialogue_finished")
	if int(gs.xp) <= xp1:
		_fail("選了「開練」卻沒有練（經驗沒動）")
		return
	print("  ok 練功選「開練」：確實給了經驗")


## 練功的選項不可以觸發小芽支線
func _check_training_does_not_touch_sprout(gs: Node) -> void:
	gs.reset_new_game()
	gs.set_flag("c1_entered_city", true)
	gs.set_flag("c1_forged", true)
	gs.set_flag("c1_sprout_asked", true)   ## 已問過小芽，但還沒完成
	gs.add_gold(200)
	var gold0 := int(gs.gold)
	_call(_main, "_side_training_spar", "training_ring")
	## 直接打全域選項處理器，模擬玩家點第一項
	_main.call("_on_choice", 0)
	if int(gs.gold) != gold0:
		_fail("在演武場點第一項就被扣了 %d 金 —— 小芽支線被誤觸" % (gold0 - int(gs.gold)))
		return
	if bool(gs.has_flag("c1_sprout_done")):
		_fail("在演武場點第一項就把小芽支線結案了")
		return
	print("  ok 練功的選項不會誤觸小芽支線")


func _finish() -> bool:
	if _ok:
		print("DIALOG_CHOICES_OK")
		quit(0)
	else:
		print("DIALOG_CHOICES_FAIL")
		quit(1)
	return true
