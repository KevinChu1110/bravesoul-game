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
	## 用出生點而不是寫死座標。
	## 原本寫的是 Vector2(200, 400) —— 那在 town 的底圖上是城牆頂，
	## 以前碰撞是一個平面矩形所以站得住，接上 walkmask 之後正確地擋掉了。
	## 出生點是「一定要站得住」的點（tools/check_walkmask.py 會顧這條），
	## 拿它當基準才不會每次改佈局就要回來改魔術數字。
	var mid: Vector2 = ex.player_pos
	if not ex._can_stand_at(mid):
		push_error("spawn should stand")
		ok = false
	else:
		print("spawn stand OK")

	## 反過來也要成立：底圖上的城牆不能站。
	## town 的可走區是中央廣場，左上 uv≈(0.05, 0.21) 是城牆。
	var wall := Vector2(40.0 + 0.05 * 3200.0, 80.0 + 0.21 * 1500.0)
	if ex._can_stand_at(wall):
		push_error("wall should NOT stand — walkmask 沒生效？")
		ok = false
	else:
		print("wall block OK")
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
