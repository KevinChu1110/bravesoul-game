extends SceneTree
## godot --headless -s res://scripts/systems/test_story_codex.gd


func _initialize() -> void:
	var ok := true
	var sc = root.get_node_or_null("StoryCodex")
	var gs = root.get_node_or_null("GameState")
	if sc == null or gs == null:
		push_error("StoryCodex or GameState missing")
		quit(1)
		return
	gs.reset_new_game()
	sc._load()
	if sc.total_count() < 4:
		push_error("codex entries too few %d" % sc.total_count())
		ok = false
	if sc.is_unlocked("c0_ember_night"):
		push_error("ember should be locked on new game")
		ok = false
	gs.set_flag("c0_sword_triple_pull", true)
	var newly: Array = sc.try_unlock_all()
	if not sc.is_unlocked("c0_ember_night"):
		push_error("ember unlock fail")
		ok = false
	if "c0_ember_night" not in newly and not gs.has_flag("codex.unlocked.c0_ember_night"):
		## try_unlock 應寫入
		push_error("newly unlock flag missing %s" % newly)
		ok = false
	var body: String = sc.entry_bbcode("c0_ember_night")
	if body.find("鏽劍") < 0 and body.find("锈剑") < 0:
		push_error("body missing sword text")
		ok = false
	else:
		print("ember body OK len=", body.length())
	gs.set_flag("c0_village_left", true)
	sc.try_unlock_all()
	if not sc.is_unlocked("c0_wheat_home"):
		push_error("wheat unlock fail")
		ok = false
	print("unlocked ", sc.unlocked_count(), "/", sc.total_count())
	if ok:
		print("CODEX_OK")
		quit(0)
	else:
		print("CODEX_FAIL")
		quit(1)
