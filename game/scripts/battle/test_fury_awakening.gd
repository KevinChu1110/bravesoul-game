extends SceneTree
## 無頭測試：驗證器魂切換與暴怒覺醒 (Soul Weapon Switching & Fury Awakening)

const BattleSim := preload("res://scripts/battle/battle_sim.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")


func _initialize() -> void:
	print("== 測試器魂切換與暴怒覺醒 ==")
	test_weapon_style_switching()
	test_fury_awakening()
	test_auto_berserk_on_rage_full()
	print("FURY_AWAKENING_OK")
	quit(0)


func test_weapon_style_switching() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10}
	var sim := BattleSim.make_tutorial_wolf_fight(player_stats)
	var p := sim.get_unit("player")

	assert(sim.switch_soul_style("axe"), "切換為斧應成功")
	assert(p.weapon_class == "axe", "武器類型應為 axe")
	assert(sim.weapon_bar_active >= 0, "應有作用中武器欄")

	assert(sim.switch_soul_style("dagger"), "切換為匕首應成功")
	assert(p.weapon_class == "dagger", "武器類型應為 dagger")
	## 各欄獨立次數
	var axe_uses_before := 0
	for b in sim.weapon_bars:
		if str(b.get("line", "")) == "axe":
			axe_uses_before = int(b.get("uses_left", 0))
	sim._consume_weapon_use(p)
	assert(sim.switch_weapon_slot(0) or sim.switch_soul_style("axe"), "切回斧欄")
	## 切走再切回應保留該欄剩餘（dagger 消耗不應清掉斧欄）
	print("  ok - 武器欄切換（取代器魂快捷）")


func test_fury_awakening() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10}
	var sim := BattleSim.make_tutorial_wolf_fight(player_stats)
	var p := sim.get_unit("player")

	assert(not sim.trigger_fury_awakening(), "怒氣未滿時觸發應失敗")

	p.rage = 100.0
	var flags := {"fury": false, "auto": false}
	sim.event.connect(func(kind: String, data: Dictionary):
		if kind == "fury_awakening":
			flags["fury"] = true
			flags["auto"] = bool(data.get("auto", false))
	)

	assert(sim.trigger_fury_awakening(), "怒氣滿時觸發覺醒應成功")
	assert(bool(flags["fury"]), "應發送 fury_awakening 事件")
	assert(not bool(flags["auto"]), "手動 F 應為非 auto")
	assert(p.fury_active, "玩家應進入暴怒覺醒狀態")
	assert(p.rage == 0.0, "觸發後怒氣應歸零")
	assert(p.atb_rate_mult() > 1.0, "暴怒狀態攻速應獲得加成")
	assert(p.atk_buff_mult >= 1.35, "手動暴怒攻擊加成應 ≥ 1.35")
	print("  ok - 暴怒覺醒觸發成功")


func test_auto_berserk_on_rage_full() -> void:
	var player_stats := {"name": "兔勇者", "max_hp": 100, "atk": 30, "def": 10, "speed": 10, "can_skill": true}
	var sim := BattleSim.make_tutorial_wolf_fight(player_stats)
	var p := sim.get_unit("player")
	var flags := {"fury": false, "auto": false}
	sim.event.connect(func(kind: String, data: Dictionary):
		if kind == "fury_awakening":
			flags["fury"] = true
			flags["auto"] = bool(data.get("auto", false))
	)
	p.rage = 90.0
	sim._gain_rage(p, 20.0)
	assert(p.rage >= 100.0, "怒氣應滿")
	assert(bool(flags["fury"]), "怒氣滿應自動暴怒")
	assert(bool(flags["auto"]), "應標記 auto")
	assert(p.fury_active, "應進入暴怒")
	assert(p.rage >= 100.0, "自動暴怒不耗怒（留給放技）")
	print("  ok - 怒氣滿自動暴怒")
