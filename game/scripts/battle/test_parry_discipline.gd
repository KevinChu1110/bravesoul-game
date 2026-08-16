extends SceneTree
## 格擋時機的把關測試：godot --headless -s res://scripts/battle/test_parry_discipline.gd
##
## 守一件事：**看時機要比亂按有用。**
##
## 為什麼值得單獨守：空揮零代價的時候，「完美時機」跟「每 0.1 秒狂按」的結果
## 量出來一模一樣 —— 雷歐戰兩者都成功格擋 10.18 次、勝率都是 97.8%，
## 差別只有按 10 下還是 658 下。那等於整個遊戲最核心的機制不存在：
## 玩家沒有任何理由去看那個倒數。
##
## 這種壞法沒有任何錯誤訊息。戰鬥照跑、數字照跳、格擋照樣成功，
## 只是「時機」這件事對結果毫無影響。所以這裡不驗規則怎麼實作
## （那會綁死做法），只驗**三種玩法跑出來的結果要分得開**。

const BattleSim = preload("res://scripts/battle/battle_sim.gd")

## 每種玩法跑幾場。少於這個數，勝率的雜訊會蓋過差距。
const RUNS := 120
const DT := 0.1
## 這個等級的雷歐戰，看時機的玩家打得贏（實測 97.8%）
const LV := 20

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _stats() -> Dictionary:
	return {
		"name": "小白",
		"max_hp": 50 + LV * 4, "hp": 50 + LV * 4,
		"atk": 10 + LV / 2, "defense": 5 + LV / 3, "speed": 10,
		"crit": 5.0, "crit_dmg": 50.0, "dmg_variance": 0.08,
		"can_skill": true, "skill_id": "slash", "skill_name": "橫斬",
		"skill_kind": "attack", "skill_mult": 1.6,
	}


## 前搖剛開始、還沒進格擋窗的那一小段（模擬「手快按早了」）
func _too_early(sim) -> bool:
	for u in sim.units.values():
		if u.is_boss and u.telegraph_active and u.state == BattleUnit.State.WINDUP:
			if u.state_timer > BattleSim.PARRY_WINDOW \
					and u.state_timer <= BattleSim.PARRY_WINDOW + 0.15:
				return true
	return false


## mode: passive 完全不按／timed 只在窗內按／early 每次先早按一下再補／spam 每幀狂按
func _run(mode: String, seed_i: int) -> Dictionary:
	var sim = BattleSim.make_leo_fight(_stats())
	sim.rng.seed = seed_i
	var n := 0
	var presses := 0
	var hits := 0
	while not sim.finished and n < 1500:
		sim.step(DT)
		n += 1
		var press := false
		match mode:
			"timed":
				press = sim.parry_window_open()
			"early":
				press = sim.parry_window_open() or _too_early(sim)
			"spam":
				press = true
		if press:
			presses += 1
			if sim.try_react():
				hits += 1
	var p = sim.get_unit("player")
	return {
		"won": p != null and p.is_alive(),
		"presses": presses,
		"hits": hits,
	}


func _measure(mode: String) -> Dictionary:
	var wins := 0
	var pr := 0
	var hi := 0
	for i in RUNS:
		var r := _run(mode, 1000 + i)
		if bool(r["won"]):
			wins += 1
		pr += int(r["presses"])
		hi += int(r["hits"])
	return {
		"rate": 100.0 * float(wins) / float(RUNS),
		"presses": float(pr) / float(RUNS),
		"hits": float(hi) / float(RUNS),
	}


func _initialize() -> void:
	var passive := _measure("passive")
	var timed := _measure("timed")
	var early := _measure("early")
	var spam := _measure("spam")

	for row in [["不按", passive], ["看時機", timed], ["早按再補", early], ["狂按", spam]]:
		var m: Dictionary = row[1]
		print("  %-10s 勝率 %5.1f%% · 按鍵 %6.1f · 成功格擋 %5.2f" % [
			row[0], m["rate"], m["presses"], m["hits"]
		])

	## 1) 看時機的玩家要打得贏。這條先掛的話下面幾條都沒意義。
	if float(timed["rate"]) < 80.0:
		_fail("看時機的勝率只有 %.1f%% —— 這場本來就打不贏，量不出時機有沒有用" % float(timed["rate"]))
		return _finish()

	## 2) 狂按不可以跟看時機一樣好。這就是整支測試的重點。
	if float(spam["rate"]) >= float(timed["rate"]) - 30.0:
		_fail("狂按勝率 %.1f%%、看時機 %.1f%% —— 亂按跟看時機差不多好，時機等於沒有意義" % [
			float(spam["rate"]), float(timed["rate"])
		])
		return _finish()

	## 3) 罰則要落在「亂按」而不是「手速」。
	##    早按一下再補的玩家仍然要接得住，否則這條規則只是在罰反應快的人。
	if float(early["rate"]) < float(timed["rate"]) - 20.0:
		_fail("早按再補只有 %.1f%%、看時機 %.1f%% —— 罰到的是手速不是亂按" % [
			float(early["rate"]), float(timed["rate"])
		])
		return _finish()

	## 4) 狂按仍然接得住「整段前搖都在窗內」的短招 —— 那種招本來就沒有時機可言。
	##    但接到的次數要明顯少於看時機，否則第 2 條可能只是血量雜訊湊出來的。
	if float(spam["hits"]) >= float(timed["hits"]) * 0.75:
		_fail("狂按成功格擋 %.2f 次、看時機 %.2f 次 —— 差距不夠，時機沒有真的被考驗" % [
			float(spam["hits"]), float(timed["hits"])
		])
		return _finish()

	print("  ok 看時機 %.1f%% · 早按再補 %.1f%% · 狂按 %.1f%%（不按 %.1f%%）" % [
		float(timed["rate"]), float(early["rate"]), float(spam["rate"]), float(passive["rate"])
	])
	_finish()


func _finish() -> void:
	if _ok:
		print("PARRY_OK")
		quit(0)
	else:
		print("PARRY_FAIL")
		quit(1)
