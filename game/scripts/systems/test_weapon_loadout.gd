extends SceneTree
## 無頭測試：多武器欄＋戰鬥切欄＋技能嚴格綁定

const BattleSim := preload("res://scripts/battle/battle_sim.gd")


func _initialize() -> void:
	print("== 測試多武器欄 ==")
	test_migration_fields_on_sim()
	test_battle_slot_switch_independent_uses()
	test_auto_switch_on_deplete()
	test_skill_bind_via_refresh()
	print("WEAPON_LOADOUT_OK")
	quit(0)


func test_migration_fields_on_sim() -> void:
	var stats := {
		"name": "兔", "max_hp": 100, "atk": 40, "def": 8, "speed": 10,
		"weapon_class": "sword", "weapon_atk": 10, "can_skill": true,
		"weapon_loadout_active": 0,
		"weapon_loadout": [
			{"index": 0, "uid": "a", "name": "鐵劍", "line": "sword", "weapon_atk": 10, "unlocked": true, "empty": false, "active": true},
			{"index": 1, "uid": "b", "name": "手斧", "line": "axe", "weapon_atk": 14, "unlocked": true, "empty": false, "active": false},
			{"index": 2, "uid": "", "name": "", "line": "", "weapon_atk": 0, "unlocked": false, "empty": true, "active": false},
		],
	}
	## atk 40 = base 30 + weapon 10
	var sim := BattleSim.make_tutorial_wolf_fight(stats)
	assert(sim.weapon_bars.size() == 3, "應有 3 欄快照")
	assert(sim.weapon_bar_active == 0, "作用中應為 0")
	var p := sim.get_unit("player")
	assert(p.weapon_class == "sword", "開戰應為劍")
	assert(p.weapon_uses_left > 0, "劍欄應有次數")
	print("  ok - 開戰灌入多欄")


func test_battle_slot_switch_independent_uses() -> void:
	var stats := {
		"name": "兔", "max_hp": 100, "atk": 40, "def": 8, "speed": 10,
		"weapon_class": "sword", "weapon_atk": 10, "can_skill": true,
		"weapon_loadout_active": 0,
		"weapon_loadout": [
			{"index": 0, "uid": "a", "name": "鐵劍", "line": "sword", "weapon_atk": 10, "unlocked": true, "empty": false, "active": true},
			{"index": 1, "uid": "b", "name": "手斧", "line": "axe", "weapon_atk": 14, "unlocked": true, "empty": false, "active": false},
			{"index": 2, "uid": "c", "name": "飛鏢", "line": "dart", "weapon_atk": 6, "unlocked": true, "empty": false, "active": false},
		],
	}
	var sim := BattleSim.make_tutorial_wolf_fight(stats)
	var p := sim.get_unit("player")
	var sword_max := p.weapon_uses_left
	## 耗兩次劍
	sim._consume_weapon_use(p)
	sim._consume_weapon_use(p)
	var sword_left := p.weapon_uses_left
	assert(sword_left == sword_max - 2, "劍應耗 2")
	assert(sim.switch_weapon_slot(1), "切斧應成功")
	assert(p.weapon_class == "axe", "應為斧")
	assert(p.atk == sim.player_base_atk + 14, "攻擊應換成斧加成")
	var axe_left := p.weapon_uses_left
	sim._consume_weapon_use(p)
	assert(p.weapon_uses_left == axe_left - 1, "斧應獨立耗次")
	assert(sim.switch_weapon_slot(0), "切回劍")
	assert(p.weapon_class == "sword", "回到劍")
	assert(p.weapon_uses_left == sword_left, "劍欄次數應保留")
	## 未解鎖／空欄
	## 清掉第 3 欄
	sim.weapon_bars[2]["empty"] = true
	sim.weapon_bars[2]["line"] = ""
	assert(not sim.switch_weapon_slot(2), "空欄應失敗")
	print("  ok - 切欄獨立次數與攻擊")


func test_auto_switch_on_deplete() -> void:
	## 原作：打光這把 → 自動切下一欄；全光才赤手
	var stats := {
		"name": "兔", "max_hp": 100, "atk": 40, "def": 8, "speed": 10,
		"weapon_class": "sword", "weapon_atk": 10, "can_skill": true,
		"weapon_loadout_active": 0,
		"weapon_loadout": [
			{"index": 0, "uid": "a", "name": "鐵劍", "line": "sword", "weapon_atk": 10, "unlocked": true, "empty": false, "active": true},
			{"index": 1, "uid": "b", "name": "手斧", "line": "axe", "weapon_atk": 14, "unlocked": true, "empty": false, "active": false},
			{"index": 2, "uid": "", "name": "", "line": "", "weapon_atk": 0, "unlocked": true, "empty": true, "active": false},
		],
	}
	var sim := BattleSim.make_tutorial_wolf_fight(stats)
	var p := sim.get_unit("player")
	## 劍次數直接扣光
	p.weapon_uses_left = 0
	sim._persist_active_bar_uses(p)
	var auto_hit := {"ok": false, "idx": -1}
	sim.event.connect(func(kind: String, data: Dictionary):
		if kind == "weapon_slot_switched" and bool(data.get("auto", false)):
			auto_hit["ok"] = true
			auto_hit["idx"] = int(data.get("index", -1))
	)
	sim._ensure_armed_or_bare(p)
	assert(bool(auto_hit["ok"]), "應自動切欄")
	assert(int(auto_hit["idx"]) == 1, "應切到斧欄")
	assert(p.weapon_class == "axe", "應為斧")
	assert(not p.bare_fisted, "還有下一欄不應赤手")
	## 斧也打光 → 無下一欄 → 赤手
	p.weapon_uses_left = 0
	sim._persist_active_bar_uses(p)
	sim._ensure_armed_or_bare(p)
	assert(p.bare_fisted, "全光應赤手")
	print("  ok - 耗盡自動切欄／全光赤手")


func test_skill_bind_via_refresh() -> void:
	## 無 SkillSystem autoload 時 refresh 會把 can_skill 設 false（空 kit）
	## 這裡只驗證 switch 後 weapon_class 驅動
	var stats := {
		"name": "兔", "max_hp": 100, "atk": 30, "def": 8, "speed": 10,
		"weapon_class": "bow", "weapon_atk": 8, "can_skill": true,
		"skill_id": "quick_shot", "skill_name": "迅射", "skill_mult": 1.6,
		"weapon_loadout": [
			{"index": 0, "uid": "b1", "name": "短弓", "line": "bow", "weapon_atk": 8, "unlocked": true, "empty": false, "active": true},
			{"index": 1, "uid": "g1", "name": "火槍", "line": "gun", "weapon_atk": 11, "unlocked": true, "empty": false, "active": false},
			{"index": 2, "uid": "", "name": "", "line": "", "weapon_atk": 0, "unlocked": true, "empty": true, "active": false},
		],
	}
	var sim := BattleSim.make_tutorial_wolf_fight(stats)
	var p := sim.get_unit("player")
	assert(p.weapon_class == "bow", "弓開場")
	assert(sim.switch_weapon_slot(1), "切火槍")
	assert(p.weapon_class == "gun", "應為火槍 line")
	print("  ok - 切欄改 weapon_class（技能綁定輸入）")
