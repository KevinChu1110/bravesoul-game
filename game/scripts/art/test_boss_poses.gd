extends SceneTree
func _initialize() -> void:
	var ok := true
	for m in ["leo","fog","abo","demon","falcon","boar","wrath","tide","statue","chrono","wolf"]:
		for p in ["idle","telegraph","attack","recover"]:
			var t = SpriteDB.boss_pose(m, p)
			if t == null and p == "idle":
				push_error("missing %s/%s" % [m, p]); ok = false
			elif t:
				pass
		print("OK ", m)
	if ok:
		print("POSE_OK"); quit(0)
	else:
		print("POSE_FAIL"); quit(1)
