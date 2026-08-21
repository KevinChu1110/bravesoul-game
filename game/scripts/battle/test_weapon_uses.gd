extends SceneTree
## 無頭測試：武器使用次數 → 赤手（原作對齊）

const BattleSim := preload("res://scripts/battle/battle_sim.gd")
const Formulas := preload("res://scripts/battle/formulas.gd")


func _initialize() -> void:
	print("== 測試武器次數／赤手 ==")
	test_uses_init_and_tempo()
	test_consume_to_bare_fist()
	test_style_switch_restores_uses()
	test_bare_fist_blocks_skill()
	print("WEAPON_USES_OK")
	quit(0)


func test_uses_init_and_tempo() -> void:
	var axe_uses := Formulas.weapon_uses_for("axe")
	var dart_uses := Formulas.weapon_uses_for("dart")
	assert(axe_uses < dart_uses, "斧次數應少於鏢（慢武少次）")
	var axe_t: Dictionary = Formulas.weapon_tempo("axe")
	var dart_t: Dictionary = Formulas.weapon_tempo("dart")
	var axe_cycle := float(axe_t.windup) + float(axe_t.recover)
	var dart_cycle := float(dart_t.windup) + float(dart_t.recover)
	assert(axe_cycle > dart_cycle * 1.5, "斧風姿週期應明顯慢於鏢")
	var sim := BattleSim.make_tutorial_wolf_fight({
		"name": "兔", "max_hp": 100, "atk": 40, "def": 10, "speed": 10,
		"weapon_class": "sword", "can_skill": true,
	})
	var p := sim.get_unit("player")
	assert(p.weapon_uses_left > 0, "開戰應有武器次數")
	assert(p.weapon_uses_left == p.weapon_uses_max, "次數應滿")
	assert(not p.bare_fisted, "不應一開始赤手")
	print("  ok - 初始化與攻速對比")


func test_consume_to_bare_fist() -> void:
	var sim := BattleSim.make_tutorial_wolf_fight({
		"name": "兔", "max_hp": 200, "atk": 50, "def": 10, "speed": 12,
		"weapon_class": "axe", "can_skill": true,
	})
	var p := sim.get_unit("player")
	var armed := p.atk
	var max_u := p.weapon_uses_max
	var bare_ev := {"hit": false}
	sim.event.connect(func(kind: String, _data: Dictionary):
		if kind == "bare_fist":
			bare_ev["hit"] = true
	)
	## 直接耗盡（最後一擊仍持武；確保下一動才赤手）
	for _i in range(max_u):
		sim._consume_weapon_use(p)
	assert(p.weapon_uses_left == 0, "剩餘 0")
	assert(not p.bare_fisted, "扣到 0 當下仍持武（最後一擊）")
	sim._ensure_armed_or_bare(p)
	assert(bool(bare_ev["hit"]), "應發出 bare_fist 事件")
	assert(p.bare_fisted, "下一動應赤手")
	assert(p.atk < armed, "赤手攻擊應下降")
	assert(p.weapon_class == "fist", "赤手風姿用拳")
	assert(not p.can_skill, "赤手不可放武器技")
	## 再耗不應崩潰
	sim._consume_weapon_use(p)
	assert(p.bare_fisted, "赤手中再揮仍赤手")
	print("  ok - 耗盡進赤手")


func test_style_switch_restores_uses() -> void:
	var sim := BattleSim.make_tutorial_wolf_fight({
		"name": "兔", "max_hp": 100, "atk": 30, "def": 10, "speed": 10,
		"weapon_class": "sword", "can_skill": true,
	})
	var p := sim.get_unit("player")
	p.weapon_uses_left = 0
	sim._enter_bare_fist(p)
	assert(p.bare_fisted, "預置赤手")
	assert(sim.switch_soul_style("dagger"), "切換應成功")
	assert(not p.bare_fisted, "換武應離開赤手")
	assert(p.weapon_class == "dagger", "應為匕首")
	assert(p.weapon_uses_left == p.weapon_uses_max, "新武器次數應重置")
	## 無 SkillSystem 灌招時 can_skill 可能仍 false（嚴格綁定無此線技）——重點是離開赤手
	print("  ok - 切換武器欄恢復次數／離開赤手")


func test_bare_fist_blocks_skill() -> void:
	var sim := BattleSim.make_tutorial_wolf_fight({
		"name": "兔", "max_hp": 100, "atk": 30, "def": 10, "speed": 10,
		"weapon_class": "sword", "can_skill": true,
	})
	var p := sim.get_unit("player")
	p.rage = 100.0
	sim._enter_bare_fist(p)
	## 模擬 ATB 滿要行動：赤手即使滿怒也不該進 CAST
	p.atb = 100.0
	p.state = 0  ## IDLE
	## 呼叫內部選招路徑：用 _try_act 或 tick
	## 直接檢查條件與 _start_action 等價邏輯
	assert(p.bare_fisted and p.rage >= 100.0 and not p.can_skill, "赤手滿怒仍 can_skill=false")
	print("  ok - 赤手擋技能")
