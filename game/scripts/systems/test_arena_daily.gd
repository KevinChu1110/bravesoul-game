extends SceneTree
## godot --headless -s res://scripts/systems/test_arena_daily.gd


func _initialize() -> void:
	var qs = root.get_node_or_null("QuestSystem")
	var ar = root.get_node_or_null("ArenaSystem")
	var gs = root.get_node_or_null("GameState")
	if qs == null or ar == null or gs == null:
		push_error("autoload missing qs=%s ar=%s gs=%s" % [qs, ar, gs])
		print("ARENA_DAILY_FAIL")
		quit(1)
		return

	## 每日輪替：同一天穩定
	var a: Array = qs.todays_commissions_raw()
	var b: Array = qs.todays_commissions_raw()
	if a.size() != qs.DAILY_PICK:
		push_error("daily pick size %d != %d" % [a.size(), qs.DAILY_PICK])
		print("ARENA_DAILY_FAIL")
		quit(1)
	for i in a.size():
		if str(a[i].get("id")) != str(b[i].get("id")):
			push_error("unstable daily pick")
			print("ARENA_DAILY_FAIL")
			quit(1)
	var has_combat := false
	for c in a:
		if str(c.get("track")) in qs.COMBAT_TRACKS:
			has_combat = true
	if not has_combat:
		push_error("daily pick missing combat")
		print("ARENA_DAILY_FAIL")
		quit(1)
	print("  ok daily rotation pick=%d" % a.size())

	## 今日村莊彙總不應噴錯
	var _sum: String = qs.starpath_summary_bbcode()
	if _sum.find("今日村莊") < 0 and _sum.find("Starpath") < 0 and _sum.find("[b]") < 0:
		push_error("starpath summary empty-ish")
		print("ARENA_DAILY_FAIL")
		quit(1)
	var _rew: int = qs.starpath_reward_count()
	if _rew < 0:
		push_error("reward count")
		print("ARENA_DAILY_FAIL")
		quit(1)
	print("  ok starpath summary reward=%d" % _rew)

	## 競技場
	gs.set_flag("c1_entered_city", true)
	ar.abandon_run()
	var st: Dictionary = ar.start_run(true)
	if not bool(st.get("ok", false)):
		push_error("arena start failed %s" % st)
		print("ARENA_DAILY_FAIL")
		quit(1)
	for _i in 5:
		var r: Dictionary = ar.on_wave_won(80)
		if not bool(r.get("ok", false)):
			push_error("wave %s" % r)
			print("ARENA_DAILY_FAIL")
			quit(1)
		if bool(r.get("finished", false)):
			break
	if ar.is_run_active():
		push_error("still active")
		print("ARENA_DAILY_FAIL")
		quit(1)
	if ar.best_score() <= 0:
		push_error("pb expected")
		print("ARENA_DAILY_FAIL")
		quit(1)
	print("  ok arena clear best=%d" % ar.best_score())

	## 挑戰狀：有獎開戰耗 1
	gs.arena_tickets = 2
	gs.arena_ticket_ts = 0.0
	var st2: Dictionary = ar.start_run(false)
	if not bool(st2.get("ok", false)) or bool(st2.get("practice", true)):
		push_error("ticket run should be rewarded %s" % st2)
		print("ARENA_DAILY_FAIL")
		quit(1)
	if int(gs.arena_tickets) != 1:
		push_error("ticket not spent got %d" % int(gs.arena_tickets))
		print("ARENA_DAILY_FAIL")
		quit(1)
	ar.abandon_run()
	gs.arena_tickets = 0
	var st3: Dictionary = ar.start_run(false)
	if not bool(st3.get("practice", false)):
		push_error("no ticket should force practice")
		print("ARENA_DAILY_FAIL")
		quit(1)
	ar.abandon_run()
	print("  ok challenge tickets")

	## 角鬥日結：換日依昨日最高分發獎
	gs.set_flag("arena.day", "2020-01-01")
	gs.set_flag("arena.day_best", 4500)
	gs.set_flag("arena.runs_today", 2)
	var gold0: int = int(gs.gold)
	var dust0: int = int(gs.stardust)
	ar._refresh_daily()  ## 應結算 4500 → 菁英
	if int(gs.gold) < gold0 + 80:
		push_error("settle gold expected +80 got %s→%s" % [gold0, gs.gold])
		print("ARENA_DAILY_FAIL")
		quit(1)
	if int(gs.stardust) < dust0 + 2:
		push_error("settle dust")
		print("ARENA_DAILY_FAIL")
		quit(1)
	if ar.day_best() != 0:
		push_error("day_best should reset after settle")
		print("ARENA_DAILY_FAIL")
		quit(1)
	if ar.last_settle_msg() == "":
		push_error("settle msg empty")
		print("ARENA_DAILY_FAIL")
		quit(1)
	## 同日再 refresh 不應重複發獎
	var gold1: int = int(gs.gold)
	ar._refresh_daily()
	if int(gs.gold) != gold1:
		push_error("double settle")
		print("ARENA_DAILY_FAIL")
		quit(1)
	print("  ok arena daily settle msg=%s" % ar.last_settle_msg())
	print("ARENA_DAILY_OK")
	quit(0)
