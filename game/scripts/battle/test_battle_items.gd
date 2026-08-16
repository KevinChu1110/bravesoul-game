extends SceneTree
## 戰鬥中用道具的把關測試：godot --headless -s res://scripts/battle/test_battle_items.gd
##
## 守一件事：**戰鬥中喝藥要真的回血。**
##
## 為什麼值得單獨守：開戰時玩家的 HP 被快照進 BattleUnit，之後整場只有那一份在動，
## GameState.hp 要到戰鬥結束才被寫回去。喝藥原本只加 GameState.hp，於是：
##   1. 戰鬥單位一滴都沒回 —— 藥等於沒效
##   2. GameState.hp 通常還停在滿血，夾完之後 healed 是 0，訊息顯示「HP +0」
##   3. 藥還是被扣掉了
## 三件事湊起來就是「藥被吃掉但什麼都沒發生」。不報錯、不當掉，
## 玩家在最需要那瓶藥的時候只能懷疑自己看錯。
##
## 這裡走真的主場景、真的開一場戰、真的打掉血再喝，
## 因為壞的地方在「誰是 HP 的權威」這條接線上，用假物件測不到。

var _ok := true
var _step := 0
var _wait := 0
var _main: Node = null
var _battle: Node = null


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")


func _process(_d: float) -> bool:
	_wait += 1
	match _step:
		0:
			if _wait < 20:
				return false
			_main = current_scene
			if _main == null:
				_fail("main scene 沒載起來")
				return _finish()
			var gs := root.get_node_or_null("GameState")
			var inv := root.get_node_or_null("InventorySystem")
			if gs == null or inv == null:
				_fail("GameState／InventorySystem autoload missing")
				return _finish()
			gs.reset_new_game()
			inv.add_item("hp_s", 3)
			_main.call("_start_battle_raw", "wolf")
			_step = 1
			_wait = 0
		1:
			if _wait < 10:
				return false
			_check_in_battle()
			return _finish()
	return false


func _check_in_battle() -> void:
	var gs := root.get_node_or_null("GameState")
	var inv := root.get_node_or_null("InventorySystem")
	var host: Node = _main.get("host")
	if host == null or host.get_child_count() == 0:
		_fail("開戰後 host 底下沒有東西")
		return
	_battle = host.get_child(host.get_child_count() - 1)
	var sim = _battle.get("sim")
	if sim == null:
		_fail("戰鬥畫面沒有 sim")
		return
	var p = sim.get_unit("player")
	if p == null:
		_fail("戰鬥裡沒有玩家單位")
		return

	## 開戰時要接手 HP 權威。沒接手＝喝藥只會加到 GameState 上，戰鬥單位收不到。
	var authority: Callable = inv.get("hp_authority")
	if not authority.is_valid():
		_fail("開戰後 InventorySystem.hp_authority 沒有被接手")
		return

	## 打掉一半血，留出回復空間
	p.hp = maxi(1, int(p.max_hp / 2))
	var hp_before: int = p.hp
	var count_before: int = inv.count("hp_s")

	var r: Dictionary = inv.use_item("hp_s")
	if not bool(r.get("ok", false)):
		_fail("戰鬥中用不了小紅水：%s" % str(r.get("msg", "")))
		return
	if inv.count("hp_s") != count_before - 1:
		_fail("藥的數量沒有正確扣除")
		return

	var healed := int(r.get("heal", 0))
	if healed <= 0:
		_fail("戰鬥中喝藥回了 %d —— 藥被吃掉但沒效果（訊息：%s）" % [healed, str(r.get("msg", ""))])
		return
	if p.hp <= hp_before:
		_fail("回報回了 %d，但戰鬥單位的 HP 還是 %d（開喝前 %d）" % [healed, p.hp, hp_before])
		return
	if p.hp - hp_before != healed:
		_fail("戰鬥單位回了 %d，訊息說回了 %d，兩邊對不上" % [p.hp - hp_before, healed])
		return

	## 左上狀態板讀的是 GameState.hp。不同步的話畫面上會有兩條血條各說各話。
	if int(gs.hp) != p.hp:
		_fail("戰鬥單位 HP 是 %d，GameState.hp 是 %d —— 兩條血條會不一致" % [p.hp, int(gs.hp)])
		return

	print("  ok 戰鬥中喝藥：%d → %d（回 %d），數量扣 1，GameState 同步" % [
		hp_before, p.hp, healed
	])

	## 滿血時喝藥要老實回 0，不可以假裝有效
	p.hp = p.max_hp
	var r2: Dictionary = inv.use_item("hp_s")
	if int(r2.get("heal", -1)) != 0:
		_fail("滿血喝藥回報回了 %s，應為 0" % str(r2.get("heal", -1)))
		return
	print("  ok 滿血喝藥老實回報回 0")


func _finish() -> bool:
	if _ok:
		print("BATTLE_ITEMS_OK")
		quit(0)
	else:
		print("BATTLE_ITEMS_FAIL")
		quit(1)
	return true
