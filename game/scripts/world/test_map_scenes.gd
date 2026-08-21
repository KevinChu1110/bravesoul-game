extends SceneTree
## godot --headless -s res://scripts/world/test_map_scenes.gd


func _initialize() -> void:
	var ok := true
	var MapSceneRegistry = load("res://scripts/world/map_scene_registry.gd")
	for id in ["village", "town", "mist_village"]:
		if not MapSceneRegistry.has_scene(id):
			push_error("missing scene %s" % id)
			ok = false
			continue
		var path: String = MapSceneRegistry.scene_path(id)
		var ps: PackedScene = load(path) as PackedScene
		if ps == null:
			push_error("load fail %s" % path)
			ok = false
			continue
		var n: Node = ps.instantiate()
		if n == null or not (n is Node2D):
			push_error("instantiate %s" % id)
			ok = false
			continue
		var spawn: Node = n.get_node_or_null("Markers/Spawn")
		if spawn == null:
			push_error("%s no Spawn marker" % id)
			ok = false
		else:
			print("  ok %s spawn=%s" % [id, (spawn as Node2D).position])
		n.free()
	## 慣例路徑：scaffold 產物不強制登錄也能被發現（檔案存在時）
	var coast_path := "res://scenes/maps/coast.tscn"
	if ResourceLoader.exists(coast_path):
		print("  note coast.tscn present")
	if ok:
		print("MAP_SCENES_OK")
		quit(0)
		return
	print("MAP_SCENES_FAIL")
	quit(1)
