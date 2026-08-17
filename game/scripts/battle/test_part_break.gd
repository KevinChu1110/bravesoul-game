extends SceneTree
## 無頭測試：驗證 BOSS 部位破壞機制 (Part Break System)

const BattleSim := preload("res://scripts/battle/battle_sim.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")


func _initialize() -> void:
	print("== 測試 BOSS 部位破壞機制 ==")
	test_part_break_setup()
	test_part_break_trigger()
	print("PART_BREAK_OK")
	quit(0)


func test_part_break_setup() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10}
	var sim := BattleSim.make_leo_fight(player_stats)
	var leo := sim.get_unit("leo")
	assert(leo != null, "Leo 應存在")
	assert(leo.has_part, "Leo 應包含可破壞部位")
	assert(leo.part_name == "騎士重盾", "部位名稱應為騎士重盾")
	assert(leo.part_hp > 0, "部位 HP 應大於 0")
	assert(not leo.part_broken, "初始部位不應為破壞狀態")
	print("  ok - 建立含有部位的 BOSS 成功")


func test_part_break_trigger() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10}
	var sim := BattleSim.make_leo_fight(player_stats)
	var leo := sim.get_unit("leo")
	var flags := {"broken": false}

	sim.event.connect(func(kind: String, data: Dictionary):
		if kind == "part_broken":
			flags["broken"] = true
			assert(data.get("boss_id") == "leo", "應為 Leo 部位破壞")
	)

	# 模擬對 Leo 部位施加大量傷害
	leo.telegraph_active = true
	leo.state = BattleUnit.State.WINDUP
	sim._process_part_damage(leo, leo.part_max_hp + 10, true)

	assert(leo.part_broken, "部位應已劃分為破壞狀態")
	assert(bool(flags["broken"]), "應觸發 part_broken 事件")
	assert(leo.state == BattleUnit.State.RECOVER, "前搖中的 BOSS 部位被破壞應陷入 RECOVER 擊暈")
	print("  ok - 部位破壞與擊暈觸發成功")
