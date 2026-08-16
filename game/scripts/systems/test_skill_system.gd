extends SceneTree
## godot --headless -s res://scripts/systems/test_skill_system.gd


func _initialize() -> void:
	var ok := true
	var sk = root.get_node_or_null("SkillSystem")
	var gs = root.get_node_or_null("GameState")
	if sk == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return
	gs.reset_new_game()
	sk.ensure_skill_map()

	if sk.is_learned("slash"):
		push_error("new game should not know slash")
		ok = false
	sk.grant_c0_slash()
	if not sk.is_learned("slash") or sk.get_lv("slash") != 1:
		push_error("grant slash fail")
		ok = false
	else:
		print("learn slash OK")

	var mult1: float = sk.mult_for("slash")
	if absf(mult1 - 1.8) > 0.01:
		push_error("lv1 mult %s" % mult1)
		ok = false

	## 熟練 → 自動升 Lv2
	var res: Dictionary = sk.add_mastery("slash", 30)
	if not bool(res.get("leveled", false)) or sk.get_lv("slash") != 2:
		push_error("mastery level fail lv=%d res=%s" % [sk.get_lv("slash"), res])
		ok = false
	else:
		print("mastery auto lv2 OK mult=", sk.mult_for("slash"))

	var mult2: float = sk.mult_for("slash")
	if absf(mult2 - 1.8 * 1.12) > 0.02:
		push_error("lv2 mult %s" % mult2)
		ok = false

	## 雷歐後解鎖怒雷
	if sk.is_unlocked("thunder_fury"):
		push_error("thunder should be locked")
		ok = false
	gs.set_flag("boss.leo_cleared", true)
	if not sk.is_unlocked("thunder_fury"):
		push_error("thunder unlock")
		ok = false
	sk.grant_leo_insight()
	if not sk.is_learned("thunder_fury") or not sk.is_learned("counter_strike"):
		push_error("leo insight")
		ok = false
	else:
		print("leo insight OK")

	var kit: Dictionary = sk.pick_battle_skill(1.0)
	if str(kit.get("id", "")) != "thunder_fury":
		push_error("priority should be thunder got %s" % kit)
		ok = false
	else:
		print("priority thunder OK")

	gs.set_flag("c1_forged", true)
	sk.grant_heal_insight()
	var kit_low: Dictionary = sk.pick_battle_skill(0.30)
	if str(kit_low.get("id", "")) != "emergency_heal":
		push_error("low hp should heal got %s" % kit_low)
		ok = false
	else:
		print("low hp heal OK pct=", kit_low.get("heal_pct"))

	## 導師指點
	gs.gold = 100
	var before_m: int = sk.get_mastery("slash")
	var tut: Dictionary = sk.tutor_train("slash")
	if tut.is_empty() or gs.gold != 60:
		push_error("tutor fail gold=%d" % gs.gold)
		ok = false
	elif sk.get_mastery("slash") < before_m and sk.get_lv("slash") == 2:
		## 可能剛好又升了；至少 gold 扣了
		print("tutor OK (maybe leveled)")
	else:
		print("tutor OK mastery=", sk.get_mastery("slash"))

	## 舊存檔相容
	gs.skill_data = {}
	gs.skill_slash_lv = 2
	sk.ensure_skill_map()
	if sk.get_lv("slash") != 2:
		push_error("legacy migrate")
		ok = false
	else:
		print("legacy migrate OK")

	## 戰鬥工廠吃 skill_mult
	var stats := {
		"atk": 20, "hp": 100, "max_hp": 100, "def": 5,
		"slash_lv": 2,
		"skill_mult": 2.6,
		"skill_name": "怒雷狂擊",
		"skill_id": "thunder_fury",
		"can_skill": true,
	}
	var sim = BattleSim.make_leo_fight(stats)
	var p = sim.get_unit("player")
	if p == null or absf(p.skill_mult - 2.6) > 0.01 or p.skill_name != "怒雷狂擊":
		push_error("battle skill stats %s" % (p.skill_name if p else "null"))
		ok = false
	else:
		print("battle kit OK")

	## 十流派：grant_for_weapon_class 發簽名招，且可 learn
	gs.reset_new_game()
	sk.ensure_skill_map()
	var class_sigs := {
		"sword": "blade_dance",
		"bow": "wind_arrow",
		"magic": "star_pierce",
		"fist": "pressure_fist",
		"axe": "heavy_cleave",
		"hammer": "iron_guard",
		"spear": "line_thrust",
		"gun": "powder_shot",
		"dart": "mist_needle",
		"crystal": "prism_ward",
	}
	if not sk.has_method("grant_for_weapon_class"):
		push_error("missing grant_for_weapon_class")
		ok = false
	else:
		for cid in class_sigs.keys():
			gs.skill_data = {}
			gs.skill_slash_lv = 0
			gs.path_style = ""
			var sid: String = str(class_sigs[cid])
			if sk.def_of(sid).is_empty():
				push_error("catalog missing %s for %s" % [sid, cid])
				ok = false
				continue
			var got: Array = sk.grant_for_weapon_class(str(cid))
			if not sk.is_learned("slash"):
				push_error("grant %s should learn slash" % cid)
				ok = false
			if not sk.is_learned(sid):
				push_error("grant %s should learn %s got %s" % [cid, sid, got])
				ok = false
			else:
				## 攻擊招可算倍率；回復招可算 heal_pct
				var kind := str(sk.def_of(sid).get("kind", ""))
				if kind == "attack" and sk.mult_for(sid) < 1.5:
					push_error("sig mult low %s %s" % [sid, sk.mult_for(sid)])
					ok = false
				if kind == "heal" and sk.heal_pct_for(sid) < 0.1:
					push_error("sig heal low %s" % sid)
					ok = false
		print("ten class grant OK")

		## 弓道優先：疾風穿矢 priority 高於 slash
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		sk.grant_for_weapon_class("bow")
		var kit_bow: Dictionary = sk.pick_battle_skill(1.0)
		if str(kit_bow.get("id", "")) != "wind_arrow":
			push_error("bow priority want wind_arrow got %s" % kit_bow)
			ok = false
		else:
			print("bow priority OK")

		## 水晶危急：晶盾吐息
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		sk.grant_for_weapon_class("crystal")
		var kit_cr: Dictionary = sk.pick_battle_skill(0.30)
		if str(kit_cr.get("id", "")) != "prism_ward":
			push_error("crystal low hp want prism_ward got %s" % kit_cr)
			ok = false
		else:
			print("crystal heal pick OK")

	if ok:
		print("SKILL_OK")
		quit(0)
	else:
		print("SKILL_FAIL")
		quit(1)
