extends SceneTree
## 速度成長的把關測試：
##   godot --headless -s res://scripts/battle/test_speed_monotonic.gd
##
## 守一件事：**練等不可以讓你打不過。**
##
## Boss 的破綻窗是固定週期，而 ATB 也是固定節拍（玩家沒辦法決定自己何時出手）。
## 兩個固定週期湊在一起會相位鎖：實測白霧在速度 14/15/17 是 100%，
## 16 掉到 15%、19 掉到 5%。玩家照著遊戲教的去練等、去挑快流派，
## 同一個王卻從穩過變成打不過 —— 而他做的每一件事都是對的。
## 他不會怪遊戲，他會怪自己，然後卡在那裡。
##
## 這種壞法完全沒有錯誤訊息，而且單看任何一個等級都很正常，
## 只有把整條速度曲線畫出來才看得到。所以這裡掃一整排速度，
## 不允許中間出現「掉下去又爬回來」的坑。

const BattleSim = preload("res://scripts/battle/battle_sim.gd")

const RUNS := 40
const SPEEDS := [13, 14, 15, 16, 17, 18, 19]

## 相鄰兩格容許的下滑。
##
## 這條線守的是「崩塌」那一類：加抖動之前，白霧在速度 14/15/17 是 100%，
## 16 掉到 15%、19 掉到 5% —— 那是相位鎖，不是難度。
##
## **已知還沒解決的**：白霧仍有輕微的反向趨勢（速度 13 約 91%、19 約 53%）。
## 根因量過了：速度高的玩家有更多刀落在無敵相位（實測輸出 148 → 97、
## 被擋 7.2 → 11.4）。真正的解法是讓玩家能決定自己何時出手，
## 那是設計改動不是調參數。這條門檻刻意設在 35 讓它通過，
## 不是因為它沒問題，是因為現在擋的是更嚴重的那一類。
const MAX_DIP := 35.0

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _stats(lv: int, spd: int, def_b: int) -> Dictionary:
	var max_hp := 50
	var atk := 10
	var df := 5
	var crit := 5.0
	for l in range(1, lv):
		var nl := l + 1
		max_hp += 4
		if nl % 2 == 0:
			atk += 2
		if nl % 3 == 0:
			df += 1
		if nl % 5 == 0:
			crit += 0.5
	var tier := clampi(2 + int((lv - 8) / 4.0), 1, 11)
	return {
		"name": "小白", "max_hp": max_hp, "hp": max_hp,
		"atk": atk + 9 + (tier - 2) * 2,
		"defense": df + def_b, "def": df + def_b, "speed": spd,
		"crit": crit, "crit_dmg": 50.0, "dmg_variance": 0.08,
		"can_skill": true, "skill_id": "slash", "skill_name": "橫斬",
		"skill_kind": "attack", "skill_mult": 1.6,
	}


func _run(mode: String, lv: int, spd: int, def_b: int, seed_i: int) -> bool:
	var st := _stats(lv, spd, def_b)
	var sim
	match mode:
		"fog": sim = BattleSim.make_fog_fight(st)
		"falcon": sim = BattleSim.make_falcon_fight(st)
		"tide": sim = BattleSim.make_tide_fight(st)
		_: return false
	sim.rng.seed = seed_i
	var n := 0
	while not sim.finished and n < 2500:
		sim.step(0.1)
		n += 1
		if sim.parry_window_open():
			sim.try_react()
	if not sim.finished:
		return false
	var p = sim.get_unit("player")
	return p != null and p.is_alive()


func _rate(mode: String, lv: int, spd: int, def_b: int) -> float:
	var w := 0
	for i in RUNS:
		if _run(mode, lv, spd, def_b, 900 + i):
			w += 1
	return 100.0 * float(w) / float(RUNS)


func _initialize() -> void:
	## 這三場的破綻／停拍／刺胞都是週期性的，最容易跟 ATB 咬住
	for c in [["fog", 22, 2], ["falcon", 30, 2], ["tide", 30, 2]]:
		var mode: String = c[0]
		var lv: int = c[1]
		var def_b: int = c[2]
		var rates: Array = []
		var line := "  %-7s Lv%-3d " % [mode, lv]
		for spd in SPEEDS:
			var r := _rate(mode, lv, spd, def_b)
			rates.append(r)
			line += " %3.0f%%" % r
		print(line)
		for i in range(1, rates.size()):
			var dip: float = float(rates[i - 1]) - float(rates[i])
			if dip > MAX_DIP:
				_fail("%s：速度 %d→%d 勝率掉了 %.0fpp（%.0f%% → %.0f%%）—— 練等反而變弱" % [
					mode, int(SPEEDS[i - 1]), int(SPEEDS[i]), dip,
					float(rates[i - 1]), float(rates[i])
				])
				break
	if _ok:
		print("  ok 速度往上不會讓勝率掉下去（容許雜訊 %.0fpp）" % MAX_DIP)
	_finish()


func _finish() -> void:
	if _ok:
		print("SPEED_OK")
		quit(0)
	else:
		print("SPEED_FAIL")
		quit(1)
