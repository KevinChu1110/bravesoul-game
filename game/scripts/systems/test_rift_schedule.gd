extends SceneTree
## godot --headless -s res://scripts/systems/test_rift_schedule.gd


func _initialize() -> void:
	var ok := true
	## 使用專案 Autoload 實例
	var rs = root.get_node_or_null("RiftSchedule")
	var gs = root.get_node_or_null("GameState")
	if rs == null or gs == null:
		push_error("autoload missing rs=%s gs=%s" % [rs, gs])
		print("RIFT_SCHEDULE_FAIL")
		quit(1)
		return

	var feat: String = rs.featured_mode()
	if feat not in rs.MODES:
		push_error("featured not in modes")
		ok = false
	else:
		print("featured OK ", feat, " week=", rs.week_index())

	gs.set_flag("postgame.rift_day", "1999-01-01")
	gs.set_flag("postgame.rift_day_used", 3)
	rs.refresh_day()
	if rs.daily_used() != 0:
		push_error("day refresh should reset used")
		ok = false
	else:
		print("day refresh OK")

	var r1: bool = rs.consume_attempt()
	var r2: bool = rs.consume_attempt()
	var r3: bool = rs.consume_attempt()
	var r4: bool = rs.consume_attempt()
	if not (r1 and r2 and r3) or r4:
		push_error("3 rewarded then practice")
		ok = false
	else:
		print("daily cap OK used=", rs.daily_used(), " left=", rs.daily_left())

	gs.set_flag("postgame.rift_attempt_rewarded", true)
	var m: Dictionary = rs.reward_mult(feat)
	if float(m.get("gold", 0)) < 1.4:
		push_error("featured should boost gold")
		ok = false
	else:
		print("featured mult OK ", m)

	gs.set_flag("postgame.rift_attempt_rewarded", false)
	var p: Dictionary = rs.reward_mult("wrath")
	if not bool(p.get("practice", false)) or float(p.get("xp", 1)) > 0.01:
		push_error("practice should zero xp")
		ok = false
	else:
		print("practice mult OK")

	if ok:
		print("RIFT_SCHEDULE_OK")
		quit(0)
	else:
		print("RIFT_SCHEDULE_FAIL")
		quit(1)
