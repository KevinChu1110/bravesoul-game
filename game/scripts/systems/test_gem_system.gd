extends SceneTree
## godot --headless -s res://scripts/systems/test_gem_system.gd


func _initialize() -> void:
	var gem = root.get_node_or_null("GemSystem")
	var gs = root.get_node_or_null("GameState")
	var eq = root.get_node_or_null("EquipmentSystem")
	if gem == null or gs == null:
		push_error("autoload missing")
		print("GEM_FAIL")
		quit(1)
		return
	gs.reset_new_game()
	gs.gem_bag = []
	gs.level = 10
	gs.gold = 500

	## 合成 3→1
	gem.add_gem("red", 1, 3)
	assert(gem.count_of("red", 1) == 3, "have 3 red1")
	var fr: Dictionary = gem.fuse("red", 1)
	assert(bool(fr.get("ok", false)), "fuse ok %s" % fr)
	assert(gem.count_of("red", 1) == 0, "consumed")
	assert(gem.count_of("red", 2) == 1, "got red2")
	print("  ok fuse 3→1")

	## 鑲嵌必定成功、替換
	eq._ensure_state()
	var w := {
		"uid": "gw1", "base_id": "t", "name": "測劍", "slot": "weapon",
		"tier": 1, "line": "sword", "quality": "common", "quality_label": "凡",
		"rolled": {"atk": 10, "def": 0, "hp": 0, "crit": 0, "crit_dmg": 0},
	}
	gs.equip_worn["gw1"] = w
	gs.equip_slots["weapon"] = "gw1"
	gs.weapon_loadout = ["gw1", "", ""]
	var gid := str(gs.gem_bag[0].get("id", ""))
	var sr: Dictionary = gem.socket("gw1", gid)
	assert(bool(sr.get("ok", false)), "socket %s" % sr)
	assert(str(gs.equip_worn["gw1"].get("gem", {}).get("color", "")) == "red", "gem on weapon")
	var b: Dictionary = gem.worn_bonuses()
	assert(float(b.get("crit", 0.0)) > 0.0, "crit bonus")
	print("  ok socket + bonuses")

	## 未解鎖
	gs.level = 5
	gs.gem_bag = []
	gem.add_gem("blue", 1, 3)
	var bad: Dictionary = gem.fuse("blue", 1)
	assert(not bool(bad.get("ok", true)), "lv5 cannot fuse")
	print("  ok level gate")

	## 熔爐第二產線
	gs.level = 20
	gs.gold = 3000
	gs.gem_furnace = false
	gs.gem_smelt_day = ""
	gs.gem_smelt_used = 0
	gs.gem_shards = {"red": 0, "yellow": 0, "blue": 0}
	gs.gem_bag = []
	assert(gem.smelt_lines_per_day() == 1, "no furnace = 1 line")
	gem.add_shards("yellow", 6)
	var sm1: Dictionary = gem.smelt("yellow")
	assert(bool(sm1.get("ok", false)), "smelt1 %s" % sm1)
	assert(gem.smelt_left_today() == 0, "line spent")
	var sm_block: Dictionary = gem.smelt("yellow")
	assert(not bool(sm_block.get("ok", true)), "no second line yet")
	var uf: Dictionary = gem.unlock_furnace()
	assert(bool(uf.get("ok", false)), "unlock furnace %s" % uf)
	assert(gem.furnace_unlocked(), "furnace on")
	assert(gem.smelt_lines_per_day() == 2, "two lines")
	## 換日重置後雙線
	gs.gem_smelt_day = "2000-01-01"
	gs.gem_smelt_used = 0
	gem.add_shards("blue", 6)
	assert(bool(gem.smelt("blue").get("ok", false)), "line A")
	assert(bool(gem.smelt("blue").get("ok", false)), "line B furnace")
	assert(gem.smelt_left_today() == 0, "both lines used")
	print("  ok furnace second line")

	## 勳章解鎖（原作 50 枚）
	gs.gem_furnace = false
	gs.gold = 0
	var inv = root.get_node_or_null("InventorySystem")
	if inv:
		inv.add_item("medal", 50)
		var um: Dictionary = gem.unlock_furnace("medal")
		assert(bool(um.get("ok", false)), "medal unlock %s" % um)
		assert(gem.furnace_unlocked(), "furnace from medals")
		assert(int(inv.count("medal")) == 0, "medals spent")
		print("  ok medal unlock")
	else:
		print("  skip medal unlock (no InventorySystem)")

	print("GEM_OK")
	quit(0)
