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

	## 6 職 × 雙武器：grant 發本系起手 + 同職另一系起手
	gs.reset_new_game()
	sk.ensure_skill_map()
	var class_sigs := {
		"sword": "slash",
		"spear": "line_thrust",
		"axe": "axe_split",
		"hammer": "stone_crush",
		"dagger": "quick_stab",
		"dart": "mist_needle",
		"fist": "combo_fist",
		"claw": "claw_rake",
		"magic": "magic_bolt",
		"crystal": "shard_bolt",
		"bow": "quick_shot",
		"gun": "powder_shot",
	}
	## 同職另一武器起手（對等，非主副）
	var sibling_sig := {
		"sword": "line_thrust",
		"spear": "slash",
		"axe": "stone_crush",
		"hammer": "axe_split",
		"dagger": "mist_needle",
		"dart": "quick_stab",
		"fist": "claw_rake",
		"claw": "combo_fist",
		"magic": "shard_bolt",
		"crystal": "magic_bolt",
		"bow": "powder_shot",
		"gun": "quick_shot",
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
			var sib: String = str(sibling_sig.get(cid, ""))
			if sib != "" and not sk.is_learned(sib):
				push_error("grant %s should also learn sibling %s got %s" % [cid, sib, got])
				ok = false
			else:
				var kind := str(sk.def_of(sid).get("kind", ""))
				var hits: int = int(sk.def_of(sid).get("hits", 1))
				if kind == "attack" and (sk.mult_for(sid) * hits) < 1.2:
					push_error("sig mult low %s %s" % [sid, sk.mult_for(sid)])
					ok = false
		print("12 weapon systems grant + sibling OK")

		## 職業對照
		if sk.profession_of("bow") != "ranger" or sk.profession_of("gun") != "ranger":
			push_error("ranger profession map fail")
			ok = false
		if sk.profession_of("dagger") != "ninja" or sk.profession_of("dart") != "ninja":
			push_error("ninja profession map fail")
			ok = false
		if str(sk.sibling_weapon("bow")) != "gun" or str(sk.sibling_weapon("dart")) != "dagger":
			push_error("sibling weapon fail bow/gun or dart/dagger")
			ok = false
		else:
			print("profession dual-weapon map OK")

		## 弓優先：當前武器系統 quick_shot，不該被同職火槍蓋掉
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		gs.path_style = "bow"
		sk.grant_for_weapon_class("bow")
		var kit_bow: Dictionary = sk.pick_battle_skill(1.0)
		if str(kit_bow.get("id", "")) != "quick_shot":
			push_error("bow priority want quick_shot got %s" % kit_bow)
			ok = false
		else:
			print("bow priority OK")

		## 切到火槍系統：應放 powder_shot（同職另一套）
		gs.path_style = "gun"
		var kit_gun: Dictionary = sk.pick_battle_skill(1.0)
		if str(kit_gun.get("id", "")) != "powder_shot":
			push_error("gun line want powder_shot got %s" % kit_gun)
			ok = false
		else:
			print("gun line priority OK")

		## 忍者：選鏢也會拿到匕首急刺；當前線 mist_needle
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		gs.path_style = "dart"
		sk.grant_for_weapon_class("dart")
		if not sk.is_learned("mist_needle") or not sk.is_learned("quick_stab"):
			push_error("ninja dart grant missing dual skills")
			ok = false
		var kit_dart: Dictionary = sk.pick_battle_skill(1.0)
		if str(kit_dart.get("id", "")) != "mist_needle":
			push_error("dart priority want mist_needle got %s" % kit_dart)
			ok = false
		else:
			print("ninja dual dart OK")

		gs.path_style = "dagger"
		var kit_dag: Dictionary = sk.pick_battle_skill(1.0)
		if str(kit_dag.get("id", "")) != "quick_stab":
			push_error("dagger priority want quick_stab got %s" % kit_dag)
			ok = false
		else:
			print("ninja dual dagger OK")

		## 水晶危急：晶盾吐息（path crystal 時可 unlock）
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		gs.path_style = "crystal"
		sk.grant_for_weapon_class("crystal")
		if not sk.is_learned("prism_ward"):
			## grant 應 try_unlock 到
			push_error("crystal grant should unlock prism_ward")
			ok = false
		var kit_cr: Dictionary = sk.pick_battle_skill(0.30)
		if str(kit_cr.get("id", "")) != "prism_ward":
			push_error("crystal low hp want prism_ward got %s" % kit_cr)
			ok = false
		else:
			print("crystal heal pick OK")

		## 高等級解鎖暴怒技
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		gs.path_style = "bow"
		gs.level = 16
		sk.grant_for_weapon_class("bow")
		if not sk.is_learned("arrow_storm"):
			push_error("bow lv16 should unlock arrow_storm")
			ok = false
		else:
			var kit_ult: Dictionary = sk.pick_battle_skill(1.0)
			if str(kit_ult.get("id", "")) != "arrow_storm":
				push_error("bow ult priority want arrow_storm got %s" % kit_ult)
				ok = false
			elif int(kit_ult.get("hits", 1)) != 10:
				push_error("arrow_storm hits want 10 got %s" % kit_ult)
				ok = false
			else:
				print("bow ultimate pick OK hits=", kit_ult.get("hits"))

		## 真多段：連擊技 hits>1 且戰鬥會逐段 emit
		if sk.hits_for("combo_fist") != 3 or sk.hits_for("shinra") != 16:
			push_error("hits_for multi fail")
			ok = false
		else:
			print("hits_for multi OK")
		gs.skill_data = {}
		gs.skill_slash_lv = 0
		gs.path_style = "fist"
		gs.level = 1
		sk.grant_for_weapon_class("fist")
		var kit_cf: Dictionary = sk.pick_battle_skill(1.0)
		if str(kit_cf.get("id", "")) != "combo_fist" or int(kit_cf.get("hits", 1)) != 3:
			push_error("combo_fist kit fail %s" % kit_cf)
			ok = false
		else:
			var stats_m := {
				"atk": 30, "hp": 200, "max_hp": 200, "def": 5,
				"skill_mult": float(kit_cf.get("mult", 0.6)),
				"skill_hits": 3,
				"skill_name": "連環拳",
				"skill_id": "combo_fist",
				"skill_kind": "attack",
				"can_skill": true,
				"weapon_class": "fist",
			}
			var sim_m = BattleSim.make_leo_fight(stats_m)
			var pu = sim_m.get_unit("player")
			if pu == null or pu.skill_hits != 3:
				push_error("battle unit skill_hits %s" % (pu.skill_hits if pu else -1))
				ok = false
			else:
				var enemy = sim_m.get_unit("leo")
				if enemy == null:
					var foes: Array = sim_m.living_of(BattleUnit.Team.ENEMY)
					if not foes.is_empty():
						enemy = foes[0]
				if enemy != null:
					var hp0: int = enemy.hp
					pu.target_id = enemy.id
					pu.skill_hits = 3
					pu.skill_mult = 0.6
					pu.skill_kind = "attack"
					pu.skill_id = "combo_fist"
					pu.skill_name = "連環拳"
					sim_m._resolve_skill(pu)
					var dealt_m: int = hp0 - enemy.hp
					if dealt_m <= 0:
						push_error("multi hit dealt no dmg hp0=%d hp1=%d" % [hp0, enemy.hp])
						ok = false
					else:
						print("multi-hit resolve OK dealt=", dealt_m, " from 3 segments")
				else:
					push_error("multi-hit test missing enemy")
					ok = false

	if ok:
		print("SKILL_OK")
		quit(0)
	else:
		print("SKILL_FAIL")
		quit(1)
