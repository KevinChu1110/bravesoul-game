extends SceneTree
## 無頭測試：驗證器魂切換與暴怒覺醒 (Soul Weapon Switching & Fury Awakening)

const BattleSim := preload("res://scripts/battle/battle_sim.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")


func _initialize() -> void:
	print("== 測試器魂切換與暴怒覺醒 ==")
	test_weapon_style_switching()
	test_fury_awakening()
	print("FURY_AWAKENING_OK")
	quit(0)


func test_weapon_style_switching() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10}
	var sim := BattleSim.make_tutorial_wolf_fight(player_stats)
	var p := sim.get_unit("player")

	assert(sim.switch_soul_style("axe"), "切換為重斧應成功")
	assert(p.weapon_class == "axe", "武器類型應為 axe")
	assert(p.skill_name == "重劈", "招式應為重劈")

	assert(sim.switch_soul_style("dagger"), "切換為雙刃應成功")
	assert(p.weapon_class == "dagger", "武器類型應為 dagger")
	assert(p.skill_name == "瞬斬", "招式應為瞬斬")
	print("  ok - 一鍵切換器魂流派成功")


func test_fury_awakening() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10}
	var sim := BattleSim.make_tutorial_wolf_fight(player_stats)
	var p := sim.get_unit("player")

	assert(not sim.trigger_fury_awakening(), "怒氣未滿時觸發應失敗")

	p.rage = 100.0
	var flags := {"fury": false}
	sim.event.connect(func(kind: String, data: Dictionary):
		if kind == "fury_awakening":
			flags["fury"] = true
	)

	assert(sim.trigger_fury_awakening(), "怒氣滿時觸發覺醒應成功")
	assert(bool(flags["fury"]), "應發送 fury_awakening 事件")
	assert(p.fury_active, "玩家應進入暴怒覺醒狀態")
	assert(p.rage == 0.0, "觸發後怒氣應歸零")
	assert(p.atb_rate_mult() > 1.0, "暴怒狀態攻速應獲得加成")
	print("  ok - 暴怒覺醒觸發成功")
