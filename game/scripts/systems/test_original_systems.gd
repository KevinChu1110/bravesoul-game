extends SceneTree
## godot --headless -s res://scripts/systems/test_original_systems.gd
## 能量／拜訪鑰匙／四地區／飾品六槽


func _initialize() -> void:
	var ok := true
	var gs = root.get_node_or_null("GameState")
	var es = root.get_node_or_null("EnergySystem")
	var vs = root.get_node_or_null("VisitSystem")
	var eq = root.get_node_or_null("EquipmentSystem")
	var inv = root.get_node_or_null("InventorySystem")
	if gs == null or es == null or vs == null or eq == null or inv == null:
		push_error("autoload missing")
		print("ORIGINAL_SYS_FAIL")
		quit(1)
		return

	gs.reset_new_game()
	gs.level = 1
	gs.energy = 15
	gs.energy_ts = Time.get_unix_time_from_system()

	## 能量
	var c0: int = int(es.cost_for_mode("ash_rat"))
	if c0 != int(es.COST_MOB):
		push_error("mob cost")
		ok = false
	var r: Dictionary = es.try_spend_for_battle("ash_rat")
	if not bool(r.get("ok", false)) or int(gs.energy) != 14:
		push_error("spend mob energy=%s" % gs.energy)
		ok = false
	else:
		print("  ok energy spend mob → %d" % gs.energy)
	gs.energy = 2
	var deny: Dictionary = es.try_spend_for_battle("leo")
	if bool(deny.get("ok", false)):
		push_error("should deny boss cost 3")
		ok = false
	else:
		print("  ok energy deny boss")

	## 好友挑戰／鑰匙／寶箱（非即時 PVP）
	var stxt: String = vs.status_bbcode()
	if stxt.find("好友挑戰") < 0 or stxt.find("不是即時") < 0:
		push_error("visit copy should say 好友挑戰 and 不是即時")
		ok = false
	var t0: Dictionary = vs.begin_challenge("shadow_ash")
	if not bool(t0.get("ok", false)):
		push_error("begin visit %s" % t0)
		ok = false
	if str(t0.get("mode", "")) != "pvp_snap" or int(t0.get("power", 0)) <= 0:
		push_error("visit should be person-shadow pvp_snap with power %s" % t0)
		ok = false
	else:
		print("  ok visit shadow mode=%s power=%d" % [t0.get("mode"), t0.get("power")])
	var win: Dictionary = vs.on_challenge_won(true)
	if not bool(win.get("ok", false)) or vs.key_count() < 1:
		push_error("visit win key")
		ok = false
	else:
		print("  ok visit key=%d" % vs.key_count())
	## 同人不可再挑戰
	var again: Dictionary = vs.begin_challenge("shadow_ash")
	if bool(again.get("ok", false)):
		push_error("same target twice")
		ok = false
	## 湊滿 3 鑰開箱
	inv.add_item("friendship_key", 2)
	gs.level = 16
	var chest: Dictionary = vs.open_chest()
	if not bool(chest.get("ok", false)):
		push_error("chest %s" % chest)
		ok = false
	else:
		print("  ok chest %s" % chest.get("msg"))

	## 四地區
	var RegionCatalog = load("res://scripts/world/region_catalog.gd")
	var regs: Array = RegionCatalog.regions()
	if regs.size() != 4:
		push_error("need 4 regions got %d" % regs.size())
		ok = false
	else:
		print("  ok regions×4")
	gs.set_flag("c0_first_battle", true)
	var open_n: int = RegionCatalog.flat_open_stages().size()
	if open_n < 1:
		push_error("no open stages")
		ok = false
	else:
		print("  ok open stages=%d" % open_n)

	## 飾品六槽
	if eq.ACCESSORY_SLOTS.size() != 6:
		push_error("need 6 accessory slots")
		ok = false
	gs.level = 10
	eq._ensure_state()
	var dt = root.get_node_or_null("DataTables")
	if dt and dt.has_method("reload"):
		dt.call("reload")
	var all_bases: Dictionary = eq.base_def("blade_ring")
	if all_bases.is_empty():
		## fallback：手動建一枚戒指測六槽門檻
		print("  warn blade_ring missing; using synthetic ring")
	var ring: Dictionary = eq.roll_instance("blade_ring")
	if ring.is_empty():
		ring = {
			"uid": "test_ring_1",
			"base_id": "blade_ring",
			"name": "鋒勢指環",
			"slot": "ring",
			"tier": 2,
			"line": "sword",
			"quality": "common",
			"quality_label": "凡",
			"rolled": {"atk": 2, "def": 0, "hp": 2, "crit": 4, "crit_dmg": 10},
			"bound": false,
		}
	ring["slot"] = "ring"
	gs.equip_bag.append(ring)
	var locked: Dictionary = eq.equip(str(ring.get("uid")))
	if bool(locked.get("ok", false)):
		push_error("should lock accessories before lv15")
		ok = false
	else:
		print("  ok accessory locked under lv15 msg=%s" % locked.get("msg"))
	gs.level = 15
	var unlocked: Dictionary = eq.equip(str(ring.get("uid")))
	if not bool(unlocked.get("ok", false)):
		push_error("equip ring fail %s bag=%d" % [unlocked, gs.equip_bag.size()])
		ok = false
	else:
		print("  ok ring equipped at lv15")

	## 存檔遷移 v5→v6
	var SaveMigration = load("res://scripts/autoload/save_migration.gd")
	var mig: Dictionary = SaveMigration.migrate({
		"version": 5,
		"gold": 10,
		"equip_slots": {"weapon": "", "armor": "", "accessory": "eq_old"},
		"equip_bag": [{"uid": "a", "slot": "accessory", "name": "舊墜"}],
		"souls": [],
		"soul_slots": [],
	})
	if not bool(mig.get("ok", false)):
		push_error("migrate fail")
		ok = false
	else:
		var d: Dictionary = mig.get("data", {})
		if int(d.get("energy", -1)) != 15:
			push_error("energy default")
			ok = false
		var sl: Dictionary = d.get("equip_slots", {})
		if str(sl.get("ring", "")) != "eq_old" or sl.has("accessory"):
			push_error("accessory migrate %s" % sl)
			ok = false
		else:
			print("  ok save v5→v6 accessory→ring energy")

	if ok:
		print("ORIGINAL_SYS_OK")
		quit(0)
		return
	print("ORIGINAL_SYS_FAIL")
	quit(1)
