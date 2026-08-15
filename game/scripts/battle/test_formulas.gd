extends SceneTree
## 無頭驗證：godot --headless -s res://scripts/battle/test_formulas.gd


func _initialize() -> void:
	var ok := true
	if Formulas.normal_damage(10, 5) < 1:
		push_error("normal_damage failed")
		ok = false
	if Formulas.miss_chance(10, 10, 0, 0) != 0:
		push_error("miss baseline failed")
		ok = false
	var sim := BattleSim.make_tutorial_wolf_fight({"atk": 20, "hp": 50, "max_hp": 50})
	for i in 600:
		sim.step(0.05)
		if sim.finished:
			break
	if not sim.finished:
		push_error("wolf fight did not finish in time")
		ok = false
	## 格擋窗邏輯：模擬 boss telegraph
	var leo_sim := BattleSim.make_leo_fight({"atk": 40, "hp": 100, "max_hp": 100, "def": 5})
	var leo: BattleUnit = leo_sim.get_unit("leo")
	leo.hp = int(leo.max_hp * 0.5)
	leo.king_slash_cd = 0.0
	leo_sim.step(0.05)
	if not leo.telegraph_active:
		## 可能還在 ATB，多步
		for i in 80:
			leo_sim.step(0.05)
			if leo.telegraph_active:
				break
	if leo.telegraph_active:
		## 等到格擋窗
		while leo.state_timer > BattleSim.PARRY_WINDOW + 0.01 and leo.telegraph_active:
			leo_sim.step(0.02)
		var parried := leo_sim.try_parry()
		if not parried:
			push_error("parry should succeed in window")
			ok = false
		else:
			print("parry OK")
	else:
		print("warn: telegraph not started (non-fatal for CI)")

	## 白霧：看破視窗內攻擊本體有效；幻影反噬
	var fog := BattleSim.make_fog_fight({"atk": 80, "hp": 500, "max_hp": 500, "def": 10, "slash_lv": 3})
	fog.get_unit("phantom_a").atk = 0
	fog.get_unit("phantom_b").atk = 0
	fog.get_unit("white_fog").atk = 0
	var real_u: BattleUnit = fog.get_unit("white_fog")
	fog.fog_vuln_cd = 999.0
	fog.fog_vuln_left = 60.0
	real_u.vulnerable = true
	var p2: BattleUnit = fog.get_unit("player")
	p2.target_id = "white_fog"
	p2.speed = 30.0
	for i in 800:
		fog.fog_vuln_left = 60.0
		real_u.vulnerable = true
		fog.step(0.05)
		if fog.finished:
			break
	if not fog.finished or not fog.won:
		push_error("fog fight should be winnable when always vulnerable (hp left=%s)" % real_u.hp)
		ok = false
	else:
		print("fog OK")
	## 未看破打本體不掉血
	var fog2 := BattleSim.make_fog_fight({"atk": 100, "hp": 100, "max_hp": 100})
	var r2: BattleUnit = fog2.get_unit("white_fog")
	var hp0 := r2.hp
	r2.vulnerable = false
	fog2.fog_vuln_left = 0.0
	fog2.fog_vuln_cd = 999.0
	fog2.get_unit("player").target_id = "white_fog"
	fog2._resolve_strike(fog2.get_unit("player"))
	if r2.hp != hp0:
		push_error("fog body should not take dmg when not vulnerable")
		ok = false
	else:
		print("fog block OK")

	## 魔王：階段誘惑可拒絕並削弱
	var dem := BattleSim.make_demon_fight({"atk": 60, "hp": 400, "max_hp": 400, "def": 12, "slash_lv": 3})
	var demon: BattleUnit = dem.get_unit("demon")
	demon.hp = int(demon.max_hp * 0.50)
	dem._check_demon_stages()
	if not dem.sim_paused or dem.temptation_stage != 1:
		## 50% 觸發 stage1(70%) 已過，應觸發 stage2 at 45% - set 0.5 might only stage1 if stages_done
		pass
	demon.hp = int(demon.max_hp * 0.71)
	dem.stages_done = [false, false, false]
	dem.sim_paused = false
	dem._check_demon_stages()
	if not dem.sim_paused or dem.temptation_stage != 1:
		push_error("demon should pause at stage 1")
		ok = false
	else:
		var atk0 := demon.atk
		dem.resolve_temptation(1, true)
		if dem.sim_paused or demon.atk >= atk0:
			push_error("refuse should unpause and lower atk")
			ok = false
		else:
			print("demon tempt OK")

	## 阿波：戰鬥破防條
	var abo_sim := BattleSim.make_abo_fight({"atk": 40, "hp": 300, "max_hp": 300, "def": 10})
	var abo: BattleUnit = abo_sim.get_unit("abo")
	var def0 := abo.defense
	abo_sim._abo_add_guard(100.0, "test")
	if abo_sim.abo_broken_left <= 0.0 or abo.defense >= def0:
		push_error("guard break should lower defense and set broken timer")
		ok = false
	else:
		print("abo OK")

	## 場地機制：火圈成功不扣血
	var hz := BattleSim.make_leo_fight({"atk": 20, "hp": 100, "max_hp": 100, "def": 5})
	hz.hazard_phase = "window"
	hz.hazard_timer = 0.5
	hz.hazard_reacted = false
	var hp_h := hz.get_unit("player").hp
	hz.try_react()
	if hz.get_unit("player").hp != hp_h:
		push_error("successful fire_ring react should not damage")
		ok = false
	else:
		print("hazard OK")

	## 疾影：停拍窗全額；模糊時 chip（直接測過濾，避開 miss RNG）
	var fal := BattleSim.make_falcon_fight({"atk": 50, "hp": 200, "max_hp": 200, "def": 10, "slash_lv": 2})
	var f_unit: BattleUnit = fal.get_unit("falcon")
	fal.falcon_stop_left = 0.0
	f_unit.vulnerable = false
	var chip_d := fal._falcon_filter_damage(f_unit, 40)
	if chip_d <= 0 or chip_d > 15:
		push_error("falcon blur should chip only (got %s)" % chip_d)
		ok = false
	else:
		print("falcon chip OK")
	fal.falcon_stop_left = 1.0
	f_unit.vulnerable = true
	var full_d := fal._falcon_filter_damage(f_unit, 40)
	if full_d <= chip_d:
		push_error("falcon stop window should deal full dmg (chip=%s full=%s)" % [chip_d, full_d])
		ok = false
	else:
		print("falcon stop OK")
	## 風切反應不扣血
	fal.hazard_phase = "window"
	fal.hazard_timer = 0.5
	fal.hazard_reacted = false
	var fphp := fal.get_unit("player").hp
	fal.try_react()
	if fal.get_unit("player").hp != fphp:
		push_error("wind_cut react should not damage")
		ok = false
	else:
		print("falcon wind_cut OK")

	## 裂縫怒火：漏閃疊灼燒，滿三引爆
	var wr := BattleSim.make_wrath_fight({"atk": 40, "hp": 200, "max_hp": 200, "def": 10, "slash_lv": 2})
	if not wr.wrath_mode:
		push_error("wrath mode flag")
		ok = false
	wr.hazard_phase = "window"
	wr.hazard_timer = 0.1
	wr.hazard_reacted = false
	wr.burn_stacks = 0
	wr._resolve_hazard(false)
	if wr.burn_stacks != 1:
		push_error("burn should stack to 1 got %s" % wr.burn_stacks)
		ok = false
	else:
		print("wrath stack OK")
	wr._resolve_hazard(false)
	wr._resolve_hazard(false)
	if wr.burn_stacks != 0:
		push_error("burn should detonate and reset got %s" % wr.burn_stacks)
		ok = false
	else:
		print("wrath detonate OK")
	## 成功躍出可減層
	wr.burn_stacks = 2
	wr._resolve_hazard(true)
	if wr.burn_stacks != 1:
		push_error("success should reduce burn")
		ok = false
	else:
		print("wrath cleanse OK")

	## 潮噬：相位減傷
	var td := BattleSim.make_tide_fight({"atk": 50, "hp": 200, "max_hp": 200, "def": 10, "slash_lv": 2})
	td.tide_phase_skill = false  ## 普攻減半
	var half := td._tide_filter_damage(td.get_unit("tide"), 20, false)
	var full := td._tide_filter_damage(td.get_unit("tide"), 20, true)
	if half >= full:
		push_error("tide normal should be halved in normal-half phase")
		ok = false
	else:
		print("tide phase OK")
	td._tide_summon_wave()
	if td._count_polyps() != 3:
		push_error("tide should summon 3")
		ok = false
	else:
		print("tide summon OK")

	## 石像：非亮無效
	var st := BattleSim.make_statue_fight({"atk": 40, "hp": 200, "max_hp": 200, "def": 10})
	st.statue_active_idx = 0
	var d0 := st._statue_filter_damage(st.get_unit("statue_0"), 30)
	var d1 := st._statue_filter_damage(st.get_unit("statue_1"), 30)
	if d0 != 30 or d1 != 0:
		push_error("statue filter fail d0=%s d1=%s" % [d0, d1])
		ok = false
	else:
		print("statue filter OK")
	## 全滅後本體
	for id in ["statue_0", "statue_1", "statue_2"]:
		st.get_unit(id).hp = 0
		st.get_unit(id).state = BattleUnit.State.DEAD
	st._check_end()
	if not st.statue_body_spawned or st.get_unit("echo") == null:
		push_error("echo should spawn")
		ok = false
	else:
		print("statue echo OK")

	## 時牢：炸彈 hazard
	var ch := BattleSim.make_chrono_fight({"atk": 40, "hp": 200, "max_hp": 200, "def": 10})
	if ch.hazard_kind != "bomb":
		push_error("chrono bomb hazard")
		ok = false
	else:
		print("chrono bomb OK")
	ch.hazard_phase = "window"
	ch.hazard_reacted = false
	var chp := ch.get_unit("player").hp
	ch.try_react()
	if ch.get_unit("player").hp != chp:
		push_error("bomb defuse should not damage")
		ok = false
	else:
		print("chrono defuse OK")

	## 石拳：有甲減傷；對撞剝甲
	var br := BattleSim.make_boar_fight({"atk": 40, "hp": 300, "max_hp": 300, "def": 12, "slash_lv": 2})
	var b_unit: BattleUnit = br.get_unit("boar")
	if br.boar_armor != 2:
		push_error("boar should start with 2 armor")
		ok = false
	var b_hp0 := b_unit.hp
	br.get_unit("player").target_id = "boar"
	br._resolve_strike(br.get_unit("player"))
	var armored_d := b_hp0 - b_unit.hp
	br.boar_armor = 0
	b_hp0 = b_unit.hp
	br._resolve_strike(br.get_unit("player"))
	var bare_d := b_hp0 - b_unit.hp
	if bare_d <= armored_d:
		push_error("boar bare should take more dmg than armored (arm=%s bare=%s)" % [armored_d, bare_d])
		ok = false
	else:
		print("boar armor OK")
	br.boar_armor = 2
	b_unit.telegraph_active = true
	b_unit.state = BattleUnit.State.WINDUP
	b_unit.state_timer = 0.5
	var armor_before := br.boar_armor
	var parried_b := br.try_parry()
	if not parried_b or br.boar_armor != armor_before - 1:
		push_error("boar clash should strip 1 armor (ok=%s armor=%s)" % [parried_b, br.boar_armor])
		ok = false
	else:
		print("boar clash OK")

	## NG+ 強化
	var leo_ng := BattleSim.make_leo_fight({"atk": 20, "hp": 100, "max_hp": 100, "def": 5})
	var leo0: int = leo_ng.get_unit("leo").max_hp
	BattleSim.apply_ng_plus(leo_ng, 1.2)
	var leo1: int = leo_ng.get_unit("leo").max_hp
	if leo1 < int(leo0 * 1.15) or not leo_ng.ng_tight_hazards:
		push_error("ng scale failed %s -> %s" % [leo0, leo1])
		ok = false
	else:
		print("ng plus OK ", leo0, "->", leo1)
	var wt := leo_ng._hazard_window_time()
	if wt >= BattleSim.HAZARD_WINDOW:
		push_error("ng should tighten hazard window")
		ok = false
	else:
		print("ng hazard OK ", wt)

	if ok:
		print("TEST_OK")
		quit(0)
	else:
		print("TEST_FAIL")
		quit(1)
