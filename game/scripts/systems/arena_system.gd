extends Node
## 競技場 v1：PVE 波次天梯。仿 HuntSystem；分數記 PB，可選上雲排行。
## Autoload：ArenaSystem

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const DAILY_CAP := 3
const PRACTICE_MULT := 0.35
const LEADERBOARD_BOARD := "arena_best"

## 五波既有雜魚（WorldContent mode），越打越硬
const WAVES: Array[Dictionary] = [
	{"mode": "ash_rat", "label": "第一試 · 灰燼鼠"},
	{"mode": "road_bandit", "label": "第二試 · 荒路殘兵"},
	{"mode": "fog_shade", "label": "第三試 · 霧影"},
	{"mode": "coast_raider", "label": "第四試 · 潮襲海盜"},
	{"mode": "scar_wisp", "label": "終試 · 疤地焰靈"},
]


static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)


func _fk(suffix: String) -> String:
	return "arena.%s" % suffix


func today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func _refresh_daily() -> void:
	var today := today_key()
	if str(GameState.get_flag(_fk("day"), "")) != today:
		GameState.set_flag(_fk("day"), today)
		GameState.set_flag(_fk("runs_today"), 0)


func runs_today() -> int:
	_refresh_daily()
	return int(GameState.get_flag(_fk("runs_today"), 0))


func daily_left() -> int:
	return maxi(0, DAILY_CAP - runs_today())


func is_unlocked() -> bool:
	return GameState.has_flag("c1_entered_city") or GameState.chapter != "c0" \
		or GameState.has_flag("c0_first_battle")


func is_run_active() -> bool:
	return bool(GameState.get_flag(_fk("active"), false))


func current_wave() -> int:
	return int(GameState.get_flag(_fk("wave"), 0))


func is_practice() -> bool:
	return bool(GameState.get_flag(_fk("practice"), false))


func best_score() -> int:
	return int(GameState.get_flag(_fk("best_score"), 0))


func run_score() -> int:
	return int(GameState.get_flag(_fk("score_run"), 0))


func clears_total() -> int:
	return int(GameState.get_flag(_fk("clears_total"), 0))


func status_bbcode() -> String:
	_refresh_daily()
	var lines: PackedStringArray = []
	lines.append(_t("[b]演武競技場[/b]"))
	lines.append(_t("騎士堡演武台。五波雜魚天梯——記個人最高分，不刷獵場材料。"))
	lines.append("")
	if not is_unlocked():
		lines.append(_t("（進入騎士堡後解鎖）"))
		return "\n".join(lines)
	lines.append(_t("今日有獎場次：%d／%d（剩餘 %d）") % [runs_today(), DAILY_CAP, daily_left()])
	lines.append(_t("個人最佳：%d 分 · 通關次數 %d") % [best_score(), clears_total()])
	lines.append(_t("有獎場次用完後仍可練習（金減、分數不上榜）。"))
	if is_run_active():
		lines.append(_t("[color=#c96]進行中：第 %d／%d 試 · 本輪 %d 分[/color]") % [
			current_wave() + 1, WAVES.size(), run_score()
		])
	return "\n".join(lines)


func start_run(force_practice: bool = false) -> Dictionary:
	if not is_unlocked():
		return {"ok": false, "msg": _t("尚未解鎖競技場。")}
	if is_run_active():
		return {"ok": false, "msg": _t("已有進行中的試煉。請先打完或放棄。")}
	_refresh_daily()
	var practice := force_practice or daily_left() <= 0
	GameState.set_flag(_fk("active"), true)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), practice)
	GameState.set_flag(_fk("waves_cleared"), 0)
	GameState.set_flag(_fk("score_run"), 0)
	SaveManager.save_game()
	var msg := _t("試煉開始（練習·不上榜）。") if practice else _t("試煉開始（有獎）。")
	return {
		"ok": true,
		"practice": practice,
		"mode": wave_mode(0),
		"label": wave_label(0),
		"msg": msg,
	}


func abandon_run() -> void:
	_maybe_commit_pb(run_score(), int(GameState.get_flag(_fk("waves_cleared"), 0)))
	GameState.set_flag(_fk("active"), false)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), false)
	GameState.set_flag(_fk("score_run"), 0)
	SaveManager.save_game()


func wave_label(index: int = -1) -> String:
	var i := current_wave() if index < 0 else index
	if i < 0 or i >= WAVES.size():
		return ""
	return _t(str(WAVES[i].get("label", "試煉")))


func wave_mode(index: int = -1) -> String:
	var i := current_wave() if index < 0 else index
	if i < 0 or i >= WAVES.size():
		return "ash_rat"
	return str(WAVES[i].get("mode", "ash_rat"))


func wave_xp(mode: String, practice: bool) -> int:
	var def: Dictionary = WorldContent.enemy_def(mode)
	var xp_n := 12 + int(int(def.get("max_hp", 50)) / 10)
	if practice:
		xp_n = int(float(xp_n) * PRACTICE_MULT)
	return maxi(0, xp_n)


## leftover_hp：戰鬥結束時玩家剩餘 HP（main 傳入）；沒傳就用 0
func on_wave_won(leftover_hp: int = 0) -> Dictionary:
	if not is_run_active():
		return {"ok": false, "msg": _t("沒有進行中的試煉。")}
	var w := current_wave()
	var practice := is_practice()
	var cleared := int(GameState.get_flag(_fk("waves_cleared"), 0)) + 1
	GameState.set_flag(_fk("waves_cleared"), cleared)
	## 分數：每波 1000 + 殘血（上限 200）
	var add := 1000 + mini(200, maxi(0, leftover_hp))
	var score := run_score() + add
	GameState.set_flag(_fk("score_run"), score)
	var xr: Dictionary = GameState.add_xp(wave_xp(wave_mode(w), practice))
	var xp_got := int(xr.get("gained", 0))
	var lv_up := int(xr.get("levels", 0)) > 0
	if w + 1 >= WAVES.size():
		var fin := _finish_run(true)
		fin["xp"] = xp_got
		fin["level_up"] = lv_up
		fin["score"] = score
		return fin
	GameState.set_flag(_fk("wave"), w + 1)
	SaveManager.save_game()
	var nw := w + 1
	return {
		"ok": true,
		"finished": false,
		"next_mode": wave_mode(nw),
		"next_label": wave_label(nw),
		"xp": xp_got,
		"level_up": lv_up,
		"score": score,
		"msg": _t("通過！%s（本輪 %d 分）") % [wave_label(nw), score],
	}


func on_wave_lost() -> Dictionary:
	if not is_run_active():
		return {"ok": false, "msg": ""}
	var score := run_score()
	var waves := int(GameState.get_flag(_fk("waves_cleared"), 0))
	var pb := _maybe_commit_pb(score, waves)
	## 有獎場次仍算消耗（已開戰）
	if not is_practice():
		_refresh_daily()
		GameState.set_flag(_fk("runs_today"), runs_today() + 1)
	GameState.set_flag(_fk("active"), false)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), false)
	GameState.set_flag(_fk("score_run"), 0)
	SaveManager.save_game()
	var msg := _t("試煉中斷。本輪 %d 分（通過 %d 波）。") % [score, waves]
	if pb:
		msg += _t(" 新紀錄！")
	return {"ok": true, "msg": msg, "score": score, "new_pb": pb}


func _finish_run(full_clear: bool) -> Dictionary:
	var practice := is_practice()
	var score := run_score()
	var waves := int(GameState.get_flag(_fk("waves_cleared"), 0))
	if full_clear:
		if not practice:
			_refresh_daily()
			GameState.set_flag(_fk("runs_today"), runs_today() + 1)
		## 有獎／練習通關都算「打過一輪」與每日委託
		GameState.set_flag(_fk("clears_total"), clears_total() + 1)
		QuestSystem.track_day("arena", 1)
	var gold_n := 24 + waves * 8
	if practice:
		gold_n = int(gold_n * PRACTICE_MULT)
	GameState.add_gold(gold_n)
	var pb := _maybe_commit_pb(score, waves)
	## 稱號／任務評估
	TitleCatalog.evaluate_all()
	GameState.set_flag(_fk("active"), false)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), false)
	GameState.set_flag(_fk("score_run"), 0)
	SaveManager.save_game()
	var msg := _t("試煉完成！金 +%d · 得分 %d。") % [gold_n, score]
	if pb:
		msg += _t(" 新個人最佳！")
	## 非練習且刷新 PB → 嘗試上雲
	if pb and not practice:
		_try_submit_leaderboard(score)
	return {
		"ok": true,
		"finished": true,
		"gold": gold_n,
		"score": score,
		"new_pb": pb,
		"practice": practice,
		"msg": msg,
	}


func _maybe_commit_pb(score: int, waves: int) -> bool:
	if score <= best_score():
		return false
	GameState.set_flag(_fk("best_score"), score)
	GameState.set_flag(_fk("best_waves"), waves)
	return true


func _try_submit_leaderboard(score: int) -> void:
	if Engine.get_main_loop() is SceneTree:
		var og: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("OnlineGate")
		if og and og.has_method("is_signed_in") and bool(og.call("is_signed_in")):
			if og.has_method("leaderboard_submit"):
				og.call("leaderboard_submit", LEADERBOARD_BOARD, score)
