extends SceneTree
## Boss 難度曲線的把關測試：godot --headless -s res://scripts/battle/test_boss_curve.gd
##
## 守一件事：**遊戲叫你幾級來，你那一級就要打得贏。**
##
## 世界地圖上寫著「霧隱 建議 18+」「道場 建議 26+」，玩家會照著走。
## 如果那一級其實數字上贏不了，玩家不會知道是自己該練等還是遊戲壞了 ——
## 他只會一直撞牆，然後關掉。
##
## 實測撞過三種壞法，全都不會報錯：
##   白霧  本體 380 血，要 Lv30 才打得贏，而地圖寫 18+
##   潮噬  刺胞每 11 秒來一波、清一波要 10 秒，玩家整場都在清雜兵，
##         一場 663 點傷害有 540 點餵給刺胞，本體只掉 180／480
##   疾影  速度 16 而玩家永遠是 10（升級不加速度），追不上
##
## 這支不驗數值長什麼樣（那會綁死平衡），只驗「該贏得了的等級贏得了」。

const BattleSim = preload("res://scripts/battle/battle_sim.gd")

## 每場的取樣數。少了勝率雜訊會太大，多了 CI 跑不完。
const RUNS := 40
const DT := 0.1
## 到了建議等級，至少要贏這個比例
const MIN_RATE := 55.0

## 另一頭：比建議等級低這麼多的時候，不該打得贏。
##
## 只守下限的話會漏掉反方向的壞法：終章魔王在 Lv8 就有 61% 勝率、
## 石拳（標 30+）在 Lv8 有 38% —— 六個章節的建議等級寫了等於沒寫，
## 玩家一路輾過去，中後段的養成也就沒有意義。
const EARLY_GAP := 10
const MAX_EARLY_RATE := 15.0

## mode, 遊戲自己標的建議等級, 進戰前 main.gd 給的防禦加成
const CURVE: Array = [
	["leo", 10, 3],       ## C1 · 鍛造之後就會遇到
	["fog", 20, 2],       ## C2 · 世界地圖寫「建議 18+」
	["abo", 26, 2],       ## C3 · 世界地圖寫「建議 26+」
	["falcon", 30, 2],    ## C4 · 世界地圖寫「建議 30+」
	["boar", 30, 3],      ## C5 · 世界地圖寫「建議 30+」
	["demon", 30, 4],     ## C6 · 終章
	["wrath", 30, 3],     ## 通關後裂縫
	["tide", 30, 2],
	["statue", 30, 3],
	["chrono", 30, 2],
]

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


## 照 GameState 的成長推該等級的數值（劍流派、一路鍛造上來）。
## 少了武器那一段會嚴重低估真實玩家 —— Lv25 的差距就有 +17 攻擊，
## 拿沒有武器的模型去調平衡會把 Boss 調得太弱。
func _stats(lv: int, def_bonus: int) -> Dictionary:
	var max_hp := 50
	var atk := 10
	var df := 5
	var crit := 5.0
	var spd := 10
	for l in range(1, lv):
		var nl := l + 1
		max_hp += 4
		if nl % 2 == 0:
			atk += 2  ## 基礎 +1、劍流派再 +1
		if nl % 3 == 0:
			df += 1
		if nl % 5 == 0:
			crit += 0.5
		if nl % 4 == 0:
			spd += 1
	## 釘釘給的 T2（攻 +9）起跳，之後每 4 級升一階、每階 +2。
	## 上限直接讀 main.gd 的 FORGE_MAX_TIER —— 寫死數字的話，
	## 哪天鍛造開放到更高階，這個模型會安靜地繼續用舊上限算，
	## 於是低估玩家、把 Boss 調得太弱。
	var max_tier := 8
	var ms := load("res://scripts/main.gd")
	if ms != null and int(ms.get("FORGE_MAX_TIER")) > 0:
		max_tier = int(ms.get("FORGE_MAX_TIER"))
	var tier := clampi(2 + int((lv - 8) / 4.0), 1, max_tier)
	var wpn := 9 + (tier - 2) * 2
	return {
		"name": "小白",
		"max_hp": max_hp, "hp": max_hp,
		"atk": atk + wpn,
		"defense": df + def_bonus, "def": df + def_bonus,
		"speed": spd,
		"crit": crit, "crit_dmg": 50.0, "dmg_variance": 0.08,
		"can_skill": true, "skill_id": "slash", "skill_name": "橫斬",
		"skill_kind": "attack", "skill_mult": 1.6,
	}


func _make(mode: String, st: Dictionary):
	match mode:
		"leo": return BattleSim.make_leo_fight(st)
		"fog": return BattleSim.make_fog_fight(st)
		"abo": return BattleSim.make_abo_fight(st)
		"falcon": return BattleSim.make_falcon_fight(st)
		"boar": return BattleSim.make_boar_fight(st)
		"demon": return BattleSim.make_demon_fight(st)
		"wrath": return BattleSim.make_wrath_fight(st)
		"tide": return BattleSim.make_tide_fight(st)
		"statue": return BattleSim.make_statue_fight(st)
		"chrono": return BattleSim.make_chrono_fight(st)
	return null


## 玩家看時機格擋（不是無腦連按 —— 那條由 test_parry_discipline 守）
func _run(mode: String, lv: int, def_b: int, seed_i: int) -> bool:
	var sim = _make(mode, _stats(lv, def_b))
	if sim == null:
		return false
	sim.rng.seed = seed_i
	var n := 0
	while not sim.finished and n < 2500:
		sim.step(DT)
		n += 1
		## 魔王的三次誘惑會把戰鬥整個暫停等玩家回答。不答的話 sim 永遠不會結束，
		## 而「時限到了玩家還活著」如果算贏，這支測試就會把一場根本沒打完的仗
		## 判成勝利 —— 實際踩過：魔王在 Lv8 顯示 100% 勝率，其實是卡在誘惑畫面。
		if sim.sim_paused and sim.temptation_stage > 0:
			sim.resolve_temptation(sim.temptation_stage, true)
			continue
		if sim.parry_window_open():
			sim.try_react()
	var p = sim.get_unit("player")
	## 打不完＝沒贏。時限是 250 秒，正常的仗 40～90 秒就結束。
	if not sim.finished:
		return false
	return p != null and p.is_alive()


func _initialize() -> void:
	for row in CURVE:
		var mode: String = row[0]
		var lv: int = row[1]
		var def_b: int = row[2]
		var wins := 0
		for i in RUNS:
			if _run(mode, lv, def_b, 5000 + i):
				wins += 1
		var rate := 100.0 * float(wins) / float(RUNS)
		if rate < MIN_RATE:
			_fail("%s 在建議等級 Lv%d 只贏 %.0f%% —— 玩家照著地圖來會撞牆" % [mode, lv, rate])
			continue

		## 反方向：低 EARLY_GAP 級不該打得贏
		var early_lv: int = maxi(1, lv - EARLY_GAP)
		var early_wins := 0
		for i in RUNS:
			if _run(mode, early_lv, def_b, 6000 + i):
				early_wins += 1
		var early_rate := 100.0 * float(early_wins) / float(RUNS)
		if early_rate > MAX_EARLY_RATE:
			_fail("%s 標建議 Lv%d，但 Lv%d 就有 %.0f%% 勝率 —— 建議等級寫了等於沒寫" % [
				mode, lv, early_lv, early_rate
			])
			continue
		print("  ok %-7s Lv%-3d 勝率 %3.0f%%　（Lv%d 只有 %.0f%%）" % [
			mode, lv, rate, early_lv, early_rate
		])
	_finish()


func _finish() -> void:
	if _ok:
		print("BOSS_CURVE_OK")
		quit(0)
	else:
		print("BOSS_CURVE_FAIL")
		quit(1)
