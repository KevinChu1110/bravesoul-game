extends SceneTree
## godot --headless -s res://scripts/systems/test_soul_system.gd


func _initialize() -> void:
	var ok := true
	var ss = root.get_node_or_null("SoulSystem")
	var gs = root.get_node_or_null("GameState")
	if ss == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return
	gs.reset_new_game()
	gs.weapon_tier = 2
	gs.weapon_atk = 9
	gs.stardust = 10
	ss.ensure_slots()
	if ss.slot_count() != 1:
		push_error("tier2 should have 1 slot got %d" % ss.slot_count())
		ok = false
	else:
		print("slots OK")

	var starter: Dictionary = ss.grant_starter_soul()
	if starter.is_empty():
		push_error("starter empty")
		ok = false
	var b: Dictionary = ss.total_equipped_bonus()
	if int(b.get("atk", 0)) < 1:
		push_error("starter should give atk")
		ok = false
	else:
		print("starter equip OK atk+", b.get("atk"))

	var before: int = int(gs.stardust)
	var rolled: Dictionary = ss.ritual()
	if rolled.is_empty() or int(gs.stardust) != before - int(ss.RITUAL_COST):
		push_error("ritual fail")
		ok = false
	else:
		print("ritual OK ", ss.soul_display(rolled), " dust=", gs.stardust)

	## 合成：塞 3 顆同款
	gs.souls = []
	gs.soul_slots = [""]
	for i in 3:
		gs.souls.append({
			"id": "t%d" % i, "star": "破軍", "quality": "凡", "level": 0, "equipped": false
		})
	var fused: Dictionary = ss.fuse("破軍", "凡", 0)
	if fused.is_empty() or int(fused.get("level", -1)) != 1:
		push_error("fuse fail")
		ok = false
	else:
		print("fuse OK ", ss.soul_display(fused), " bag=", ss.bag_souls().size())

	gs.weapon_tier = 6
	ss.ensure_slots()
	if ss.slot_count() != 2:
		push_error("tier6 slots")
		ok = false
	else:
		print("tier6 slots OK")

	if ok:
		print("SOUL_OK")
		quit(0)
	else:
		print("SOUL_FAIL")
		quit(1)
