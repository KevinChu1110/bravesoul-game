extends SceneTree
## godot --headless -s res://scripts/world/test_tile_collision.gd


func _initialize() -> void:
	var ok := true
	var Ex = load("res://scripts/world/explore_view.gd")
	if Ex == null:
		push_error("no explore")
		quit(1)
		return
	var ex = Ex.new()
	root.add_child(ex)
	ex.setup("town")
	if not ex._is_solid_cell(Vector2i(0, 0)):
		push_error("border not solid")
		ok = false
	else:
		print("border solid OK")
	var mid := Vector2(200, 400)
	if not ex._can_stand_at(mid):
		push_error("mid should stand")
		ok = false
	else:
		print("mid stand OK")
	var before: Vector2 = ex.player_pos
	ex.player_pos = Vector2(48, 400)
	ex._try_move(0.5, Vector2(-1, 0))
	print("pos after left push ", ex.player_pos, " from near edge")
	if ex.player_pos.x < 30.0:
		push_error("walked through left wall")
		ok = false
	else:
		print("wall block OK")
	print("solid cells ", ex._solid.size())
	if ex._solid.size() < 50:
		push_error("too few solids")
		ok = false
	else:
		print("solids OK")
	# axis slide: into corner wall should not freeze both axes forever
	ex.player_pos = before
	if ok:
		print("COLLISION_OK")
		quit(0)
	else:
		print("COLLISION_FAIL")
		quit(1)
