extends SceneTree
## 貼圖路徑煙霧測：godot --headless -s res://scripts/art/test_art.gd


func _init() -> void:
	var ok := true
	var checks: Array = [
		["player", SpriteDB.player_idle()],
		["battle_player", SpriteDB.player_battle()],
		["leo", SpriteDB.boss("leo")],
		["fog", SpriteDB.boss("fog")],
		["abo", SpriteDB.boss("abo")],
		["demon", SpriteDB.boss("demon")],
		["falcon", SpriteDB.boss("falcon")],
		["boar", SpriteDB.boss("boar")],
		["town_bg", SpriteDB.map_bg("town")],
		["forest_bg", SpriteDB.map_bg("forest")],
		["battle_leo", SpriteDB.battle_bg("leo")],
		["ding", SpriteDB.explore_entity_tex("ding")],
		["fire_ring", SpriteDB.fx("fire_ring")],
		["tile_stone", SpriteDB.tile("stone")],
		["tile_grass", SpriteDB.tile("grass")],
		["player_atk", SpriteDB.player_pose("attack")],
		["player_skill", SpriteDB.player_pose("skill")],
	]
	for c in checks:
		if c[1] == null:
			push_error("missing texture: %s" % c[0])
			ok = false
		else:
			print("OK ", c[0], " ", c[1].get_size())
	## 音效檔
	for sfx in ["parry", "hit", "slash", "fire", "reveal", "break", "step", "victory"]:
		var path := "res://assets/audio/sfx/%s.wav" % sfx
		if not ResourceLoader.exists(path):
			push_error("missing sfx: %s" % sfx)
			ok = false
		else:
			print("OK sfx ", sfx)
	if ok:
		print("ART_OK")
		quit(0)
	else:
		print("ART_FAIL")
		quit(1)
