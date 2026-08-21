extends SceneTree
## 無頭測試：多 Boss 部位破壞

const BattleSim := preload("res://scripts/battle/battle_sim.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")


func _initialize() -> void:
	print("== 測試多 Boss 部位破壞 ==")
	_assert_dual("leo", BattleSim.make_leo_fight, 2)
	_assert_dual("falcon", BattleSim.make_falcon_fight, 2)
	_assert_dual("boar", BattleSim.make_boar_fight, 2)
	_assert_dual("abo", BattleSim.make_abo_fight, 2)
	_assert_dual("demon", BattleSim.make_demon_fight, 2)
	_assert_dual("wrath", BattleSim.make_wrath_fight, 2)
	_assert_dual("tide", BattleSim.make_tide_fight, 2)
	_assert_dual("chrono", BattleSim.make_chrono_fight, 2)
	_assert_fog_parts()
	_assert_break_shield_like()
	_assert_threshold_blocks()
	_assert_all_broken_vuln()
	_assert_cycle_not_fog()
	_assert_flee_rift_only()
	print("PART_BREAK_OK")
	quit(0)


func _stats() -> Dictionary:
	return {"name": "兔勇者", "max_hp": 200, "hp": 200, "atk": 40, "def": 12, "speed": 12}


func _assert_dual(label: String, maker: Callable, n: int) -> void:
	var sim: BattleSim = maker.call(_stats())
	var boss := sim._primary_boss_unit()
	assert(boss != null, "%s boss missing" % label)
	assert(boss.parts.size() == n, "%s expected %d parts, got %d" % [label, n, boss.parts.size()])
	print("  ok - %s 部位×%d" % [label, n])


func _assert_fog_parts() -> void:
	var sim := BattleSim.make_fog_fight(_stats())
	var fog := sim.get_unit("white_fog")
	assert(fog != null and fog.parts.size() == 2, "fog should have 2 passive parts")
	print("  ok - fog 被動部位×2")


func _assert_break_shield_like() -> void:
	var sim := BattleSim.make_abo_fight(_stats())
	var abo := sim.get_unit("abo")
	var def0 := abo.defense
	## 原作：本體需壓到門檻以下才可破
	abo.hp = int(float(abo.max_hp) * 0.5)
	sim.focus_part_id = "mail"
	var max_hp := int(abo.parts[1].get("max_hp"))
	sim._process_part_damage(abo, max_hp + 50, true)
	assert(sim.parts_break_unlocked, "threshold should unlock parts")
	assert(bool(abo.parts[1].get("broken")), "abo mail broken")
	assert(abo.defense < def0, "abo def down")
	assert(not sim.pending_part_materials.is_empty(), "break should queue material")
	print("  ok - abo 破甲降防＋掉材")


func _assert_threshold_blocks() -> void:
	var sim := BattleSim.make_leo_fight(_stats())
	var leo := sim._primary_boss_unit()
	leo.hp = leo.max_hp  ## 滿血不可破
	sim.focus_part_id = "shield"
	var shield_max := int(leo.parts[1].get("max_hp"))
	sim._process_part_damage(leo, shield_max + 200, true)
	assert(not bool(leo.parts[1].get("broken")), "full HP should block part break")
	assert(sim.pending_part_materials.is_empty(), "no loot before unlock")
	print("  ok - 滿血擋破部位")


func _assert_all_broken_vuln() -> void:
	var sim := BattleSim.make_abo_fight(_stats())
	var abo := sim.get_unit("abo")
	abo.hp = int(float(abo.max_hp) * 0.4)
	sim.parts_break_unlocked = true
	for i in abo.parts.size():
		sim.focus_part_id = str(abo.parts[i].get("id"))
		var mhp := int(abo.parts[i].get("max_hp"))
		sim._process_part_damage(abo, mhp + 80, true)
	assert(is_equal_approx(abo.parts_all_broken_vuln, BattleSim.ALL_PARTS_BROKEN_BODY_MULT), "all broken vuln")
	print("  ok - 全破本體易傷 ×%.1f" % abo.parts_all_broken_vuln)


func _assert_cycle_not_fog() -> void:
	var sim := BattleSim.make_falcon_fight(_stats())
	sim.focus_part_id = "body"
	var a := sim.cycle_part_focus(1)
	var b := sim.cycle_part_focus(1)
	assert(a != b or sim._primary_boss_unit().parts.size() < 2, "cycle should move")
	print("  ok - falcon 鎖定循環 %s→%s" % [a, b])


func _assert_flee_rift_only() -> void:
	var story := BattleSim.make_leo_fight(_stats())
	assert(not story.allow_part_flee, "leo must not flee")
	assert(not story._try_part_flee(story._primary_boss_unit(), "盔", "enrage"), "leo flee blocked")
	var rift := BattleSim.make_wrath_fight(_stats())
	assert(rift.allow_part_flee, "wrath may flee")
	var boss := rift._primary_boss_unit()
	rift.force_next_part_flee = true
	var fled := rift._try_part_flee(boss, "怒焰面具", "enrage")
	assert(fled and rift.boss_fled and rift.won and rift.finished, "flee should end as won+fled")
	print("  ok - 裂縫可逃走、主線雷歐不可")
