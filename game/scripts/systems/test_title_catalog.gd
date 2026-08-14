extends SceneTree
## godot --headless -s res://scripts/systems/test_title_catalog.gd


func _initialize() -> void:
	var ok := true
	var tc = root.get_node_or_null("TitleCatalog")
	var gs = root.get_node_or_null("GameState")
	if tc == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return
	gs.reset_new_game()
	if tc.unlocked_count() != 0:
		## 可能有殘留 - 清 flags
		gs.flags.clear()
	var n0: int = tc.unlocked_count()
	if n0 != 0:
		push_error("expected 0 unlocked got %d" % n0)
		ok = false
	else:
		print("empty OK")

	gs.set_flag("c1_perfect_parry_once", true)
	var newly: Array = tc.evaluate_all()
	if "以劍抵爪" not in newly and not gs.has_flag("title.claw_parry"):
		push_error("parry title missing")
		ok = false
	else:
		print("parry title OK ", newly)

	gs.set_flag("boss.white_fog_cleared", true)
	gs.set_flag("game_cleared", true)
	gs.set_flag("postgame.rift_wins", 5)
	gs.set_flag("postgame.wrath_cleared", true)
	gs.set_flag("postgame.tide_cleared", true)
	gs.set_flag("postgame.statue_cleared", true)
	gs.set_flag("postgame.chrono_cleared", true)
	tc.evaluate_all()
	if not gs.has_flag("title.fog_seer"):
		push_error("fog seer")
		ok = false
	if not gs.has_flag("title.cleared"):
		push_error("cleared title")
		ok = false
	if not gs.has_flag("title.rift_walker"):
		push_error("rift walker")
		ok = false
	if not gs.has_flag("title.featured_fan"):
		push_error("rift all")
		ok = false
	else:
		print("batch unlock OK count=", tc.unlocked_count())

	var wall: String = tc.wall_bbcode()
	if wall.find("以劍抵爪") < 0:
		push_error("wall missing name")
		ok = false
	else:
		print("wall OK len=", wall.length())

	if ok:
		print("TITLE_OK")
		quit(0)
	else:
		print("TITLE_FAIL")
		quit(1)
