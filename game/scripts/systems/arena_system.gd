extends Node
## 演武場 v1：PVE 波次天梯（對齊原作演武／角鬥精神）。仿 HuntSystem；分數記 PB，可選上雲排行。
## Autoload：ArenaSystem

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const DAILY_CAP := 3  ## 相容舊日結統計；有獎開戰改走挑戰狀
const PRACTICE_MULT := 0.35
const LEADERBOARD_BOARD := "arena_best"
## 原作演武：挑戰狀上限 5、約 90 分回 1（參考 bot／考據）
const TICKET_MAX := 5
const TICKET_REGEN_SEC := 90.0 * 60.0

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


func day_best() -> int:
	return int(GameState.get_flag(_fk("day_best"), 0))


func last_settle_msg() -> String:
	return str(GameState.get_flag(_fk("last_settle_msg"), ""))


## 原作角鬥場：每日依排名結算報酬。本作以「當日最高分」分檔發獎（本地）。
func rank_reward_for_score(score: int) -> Dictionary:
	if score <= 0:
		return {"gold": 0, "dust": 0, "tier": 0, "label": _t("未上榜")}
	if score >= 6000:
		return {"gold": 120, "dust": 3, "tier": 4, "label": _t("角鬥·至尊")}
	if score >= 4000:
		return {"gold": 80, "dust": 2, "tier": 3, "label": _t("角鬥·菁英")}
	if score >= 2000:
		return {"gold": 40, "dust": 1, "tier": 2, "label": _t("角鬥·精銳")}
	return {"gold": 15, "dust": 0, "tier": 1, "label": _t("角鬥·新銳")}


func _note_day_score(score: int) -> void:
	if score <= 0:
		return
	if score > day_best():
		GameState.set_flag(_fk("day_best"), score)


func _settle_previous_day(prev_day: String) -> void:
	if prev_day == "":
		return
	var settle_key := _fk("settled_%s" % prev_day)
	if GameState.has_flag(settle_key):
		return
	var score := day_best()
	var rew: Dictionary = rank_reward_for_score(score)
	GameState.set_flag(settle_key, true)
	var gold_n := int(rew.get("gold", 0))
	var dust_n := int(rew.get("dust", 0))
	if gold_n > 0:
		GameState.add_gold(gold_n)
	if dust_n > 0:
		GameState.add_stardust(dust_n)
	var gem_n := 0
	var tier := int(rew.get("tier", 0))
	if tier > 0 and Engine.get_main_loop() is SceneTree:
		var gem: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GemSystem")
		if gem != null and gem.has_method("grant_arena_settle_shards"):
			gem_n = int(gem.call("grant_arena_settle_shards", tier))
	var msg: String
	if score <= 0:
		msg = _t("角鬥日結（%s）：昨日未參賽。") % prev_day
	else:
		msg = _t("角鬥日結（%s）：昨日最高 %d →【%s】金 +%d") % [
			prev_day, score, str(rew.get("label", "")), gold_n
		]
		if dust_n > 0:
			msg += _t(" · 星屑 +%d") % dust_n
		if gem_n > 0:
			msg += _t(" · 寶石碎片 +%d") % gem_n
		var med_n := mini(4, maxi(1, tier))
		if Engine.get_main_loop() is SceneTree:
			var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
			if inv != null and inv.has_method("add_item"):
				inv.call("add_item", "medal", med_n)
				msg += _t(" · 勳章 +%d") % med_n
	GameState.set_flag(_fk("last_settle_msg"), msg)
	GameState.set_flag(_fk("last_settle_gold"), gold_n)
	GameState.set_flag(_fk("last_settle_score"), score)


func _refresh_daily() -> void:
	var today := today_key()
	var prev := str(GameState.get_flag(_fk("day"), ""))
	if prev != "" and prev != today:
		## 換日：先結算昨日日榜，再清今日場次
		_settle_previous_day(prev)
		GameState.set_flag(_fk("day"), today)
		GameState.set_flag(_fk("runs_today"), 0)
		GameState.set_flag(_fk("day_best"), 0)
	elif prev == "":
		GameState.set_flag(_fk("day"), today)
		GameState.set_flag(_fk("runs_today"), 0)


func runs_today() -> int:
	_refresh_daily()
	return int(GameState.get_flag(_fk("runs_today"), 0))


func daily_left() -> int:
	## 對外「剩餘有獎」改以挑戰狀為準
	return tickets()


func _refresh_tickets() -> void:
	var n := int(GameState.arena_tickets)
	var ts := float(GameState.arena_ticket_ts)
	var now := Time.get_unix_time_from_system()
	if n >= TICKET_MAX:
		GameState.arena_tickets = TICKET_MAX
		GameState.arena_ticket_ts = 0.0
		return
	if ts <= 0.0:
		GameState.arena_ticket_ts = now
		return
	var gained := int(floor((now - ts) / TICKET_REGEN_SEC))
	if gained <= 0:
		return
	n = mini(TICKET_MAX, n + gained)
	GameState.arena_tickets = n
	if n >= TICKET_MAX:
		GameState.arena_ticket_ts = 0.0
	else:
		GameState.arena_ticket_ts = ts + float(gained) * TICKET_REGEN_SEC


func tickets() -> int:
	_refresh_tickets()
	return int(GameState.arena_tickets)


func ticket_regen_left_sec() -> float:
	_refresh_tickets()
	if tickets() >= TICKET_MAX:
		return 0.0
	var ts := float(GameState.arena_ticket_ts)
	if ts <= 0.0:
		return TICKET_REGEN_SEC
	var now := Time.get_unix_time_from_system()
	var left := TICKET_REGEN_SEC - fmod(now - ts, TICKET_REGEN_SEC)
	return maxf(0.0, left)


func try_spend_ticket() -> bool:
	_refresh_tickets()
	if int(GameState.arena_tickets) <= 0:
		return false
	GameState.arena_tickets = int(GameState.arena_tickets) - 1
	if float(GameState.arena_ticket_ts) <= 0.0:
		GameState.arena_ticket_ts = Time.get_unix_time_from_system()
	return true


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
	_refresh_tickets()
	var lines: PackedStringArray = []
	lines.append(_t("[b]演武場[/b]（給經驗）· [b]角鬥日結[/b]（給排名獎）"))
	lines.append(_t("魔王敗後二十年，傭兵團仍用演武台磨刀——五波雜魚天梯，不刷獵場材料。"))
	lines.append("")
	if not is_unlocked():
		lines.append(_t("（進入騎士堡後解鎖）"))
		return "\n".join(lines)
	var tix := tickets()
	lines.append(_t("挑戰狀：%d／%d") % [tix, TICKET_MAX])
	if tix < TICKET_MAX:
		var mins := int(ceil(ticket_regen_left_sec() / 60.0))
		lines.append(_t("（約 %d 分後回復 1 張）") % maxi(1, mins))
	lines.append(_t("今日最高：%d 分 · 生涯最佳：%d · 通關 %d") % [day_best(), best_score(), clears_total()])
	lines.append(_t("消耗挑戰狀＝有獎演武（經驗比野外厚＋上榜）；無狀仍可練習（金減、不上榜）。"))
	lines.append(_t("角鬥日結：換日依昨日最高分發金／星屑／寶石（新銳／精銳／菁英／至尊）。"))
	var settle := last_settle_msg()
	if settle != "":
		lines.append("[color=#8c8]%s[/color]" % settle)
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
	_refresh_tickets()
	var practice := force_practice
	if not practice:
		if tickets() <= 0:
			practice = true
		elif not try_spend_ticket():
			practice = true
	GameState.set_flag(_fk("active"), true)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), practice)
	GameState.set_flag(_fk("waves_cleared"), 0)
	GameState.set_flag(_fk("score_run"), 0)
	SaveManager.save_game()
	var msg := _t("演武開始（練習·不上榜）。") if practice else _t("演武開始（消耗挑戰狀·有獎）。")
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
	return Formulas.arena_xp(int(def.get("max_hp", 50)), practice)


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
	_note_day_score(score)
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
