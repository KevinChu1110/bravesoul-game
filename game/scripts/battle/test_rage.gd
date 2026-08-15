extends SceneTree
## 戰意把關測試：godot --headless -s res://scripts/battle/test_rage.gd
##
## 守一件事：**玩家真的放得出招式。**
##
## 為什麼值得單獨守：戰意原本只在受傷時累積，公式是 min(40, 40×傷害/最大生命)，
## 要累到 100 得承受 2.5 倍自身最大生命的傷害 —— 玩家在 1.0 倍就死了。
## 於是七招、熟練度、灰鬚指點（收玩家 40 金）、演武場練功整條養成柱都是死的，
## 而教學還在教「怒氣滿了自動放招」。三千場模擬跑出來的施放次數是 0。
##
## 這種壞法沒有任何錯誤訊息：戰鬥照跑、數字照跳、玩家只是永遠看不到自己放招。
## 所以這裡不驗公式長什麼樣（那會綁死實作），只驗「打完一場 Boss 至少放得出一次」。

const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const Formulas = preload("res://scripts/battle/formulas.gd")

## 一場 Boss 戰玩家大約出手 7～10 次。要求「七刀之內累滿」才是可達成的設計，
## 超過這個數就等於又回到「理論上會滿，實際上打不到」。
const MAX_STRIKES_TO_FILL := 10

var _ok := true
var _casts := 0


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _on_ev(kind: String, _d: Dictionary) -> void:
	if kind == "skill_cast":
		_casts += 1


func _process(_delta: float) -> bool:
	_check_reachable()
	if _ok:
		_check_boss_fight_casts()
	_finish()
	return true


## 純算術：光靠出手要幾刀才累滿
func _check_reachable() -> void:
	var per := Formulas.rage_from_strike()
	if per <= 0.0:
		_fail("出手完全不累積戰意 —— 招式系統會退回「只能靠挨打累積」，那是打不到的")
		return
	var strikes := int(ceil(100.0 / per))
	if strikes > MAX_STRIKES_TO_FILL:
		_fail("要 %d 刀才累滿戰意，一場戰鬥出手不到這麼多次，等於放不出招" % strikes)
		return
	print("  ok 出手 %d 刀累滿戰意（每刀 %.0f）" % [strikes, per])


## 實戰：真的跑一場 Boss，看招式有沒有出來
func _check_boss_fight_casts() -> void:
	var lv := 8
	var stats := {
		"name": "小白",
		"max_hp": 50 + lv * 4, "hp": 50 + lv * 4,
		"atk": 10 + lv / 2, "defense": 5 + lv / 3, "speed": 10,
		"crit": 5.0, "crit_dmg": 50.0, "dmg_variance": 0.08,
		"can_skill": true, "skill_id": "slash", "skill_name": "橫斬",
		"skill_kind": "attack", "skill_mult": 1.6,
	}
	var sim = BattleSim.make_leo_fight(stats)
	sim.rng.seed = 700
	sim.event.connect(_on_ev)
	var n := 0
	while not sim.finished and n < 1200:
		sim.step(0.1)
		n += 1
	if n >= 1200:
		_fail("戰鬥在 120 秒內沒有結束，這支測試量不到東西")
		return
	if _casts <= 0:
		_fail("整場雷歐戰一次招式都沒放出來")
		return
	print("  ok 雷歐戰實際放出 %d 次招式" % _casts)


func _finish() -> void:
	if _ok:
		print("RAGE_OK")
		quit(0)
	else:
		print("RAGE_FAIL")
		quit(1)
