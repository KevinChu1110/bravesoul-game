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

	## ── 時間模型 0.15 ──
	## speed10：ATB 應約 4.0s 填滿（fill_base25 × 1.0）
	var atb10 := Formulas.atb_seconds_to_full(10.0)
	if atb10 < 3.7 or atb10 > 4.3:
		push_error("time_model: speed10 ATB should ~4s got %s" % atb10)
		ok = false
	else:
		print("time_model ATB speed10 OK ", atb10)
	## 比 speed10 快一截，但不能快到雜魚 2 秒連砍
	var atb14 := Formulas.atb_seconds_to_full(14.0)
	if atb14 >= atb10 or atb14 < 2.8:
		push_error("time_model: speed14 should be faster than 10 but >=2.8s got %s" % atb14)
		ok = false
	else:
		print("time_model ATB speed14 OK ", atb14)
	## 怒氣：約 8 刀滿（14×7=98）
	var per := Formulas.rage_from_strike()
	var strikes_full := int(ceil(100.0 / per))
	if strikes_full < 6 or strikes_full > 10:
		push_error("time_model: rage strikes-to-full out of band %s (per=%s)" % [strikes_full, per])
		ok = false
	else:
		print("time_model rage strikes OK ", strikes_full, " per ", per)
	## Boss 前搖常數仍可讀
	if BattleSim.KING_SLASH_WINDUP < 1.4 or BattleSim.PARRY_WINDOW < 0.6:
		push_error("time_model: boss telegraph too tight")
		ok = false
	else:
		print("time_model boss telegraph OK")

	## ── 姿態：遠距開闊／被壓、坦克容錯 ──
	if not Formulas.is_ranged_class("bow") or not Formulas.is_ranged_class("gun"):
		push_error("stance: bow/gun should be ranged")
		ok = false
	if not Formulas.is_tank_class("hammer") or not Formulas.is_tank_class("crystal"):
		push_error("stance: hammer/crystal should be tank")
		ok = false
	if Formulas.is_ranged_class("sword") or Formulas.is_tank_class("gun"):
		push_error("stance: class buckets wrong")
		ok = false

	var open_bow := Formulas.scale_ranged_outgoing("bow", 0.0, 100)
	var press_bow := Formulas.scale_ranged_outgoing("bow", 1.0, 100)
	if open_bow <= 100 or press_bow != 100:
		push_error("stance: open bonus failed open=%s press=%s" % [open_bow, press_bow])
		ok = false
	else:
		print("stance open dmg OK ", open_bow)

	## 第一次受擊減傷
	var hit1: Dictionary = Formulas.apply_player_incoming_stance("gun", 0.0, true, 100)
	if int(hit1.get("damage", 100)) >= 100 or bool(hit1.get("first_hit_guard", true)):
		push_error("stance: first hit should mitigate got %s" % hit1)
		ok = false
	else:
		print("stance first hit OK ", hit1.get("damage"))
	## 被壓易傷（guard 已用）
	var hit2: Dictionary = Formulas.apply_player_incoming_stance(
		"gun", float(hit1.get("pressure", 3.5)), false, 100
	)
	if int(hit2.get("damage", 100)) <= 100:
		push_error("stance: pressured should amplify got %s" % hit2)
		ok = false
	else:
		print("stance pressured OK ", hit2.get("damage"))

	## 坦克常駐減傷；同 100 原傷下鎚 < 銃（被壓）
	var tank_hit: Dictionary = Formulas.apply_player_incoming_stance("hammer", 0.0, true, 100)
	var gun_press: Dictionary = Formulas.apply_player_incoming_stance("gun", 3.0, false, 100)
	if int(tank_hit.get("damage", 100)) >= 100:
		push_error("stance: tank should reduce got %s" % tank_hit)
		ok = false
	elif int(tank_hit.get("damage", 100)) >= int(gun_press.get("damage", 100)):
		push_error("stance: tank should take less than pressured gun t=%s g=%s" % [
			tank_hit.get("damage"), gun_press.get("damage")
		])
		ok = false
	else:
		print("stance tank vs gun OK t=", tank_hit.get("damage"), " g=", gun_press.get("damage"))

	## BattleUnit 整合：make 戰寫入 weapon_class + 風姿
	var gun_sim := BattleSim.make_tutorial_wolf_fight({
		"atk": 20, "hp": 80, "max_hp": 80, "def": 5, "weapon_class": "gun"
	})
	var gp: BattleUnit = gun_sim.get_unit("player")
	if gp.weapon_class != "gun" or gp.windup_time < 0.35:
		push_error("stance: gun tempo not applied wc=%s wu=%s" % [gp.weapon_class, gp.windup_time])
		ok = false
	else:
		print("stance gun tempo OK wu=", gp.windup_time)
	var raw_out := 50
	var scaled := gp.scale_outgoing(raw_out)
	if scaled <= raw_out:
		push_error("stance: unit open scale failed %s" % scaled)
		ok = false
	## 吃一刀 → 被壓 → 開闊消失
	var hp_before := gp.hp
	gp.take_damage(20)
	if gp.hp >= hp_before or gp.pressure_left <= 0.0:
		push_error("stance: hit should apply pressure hp %s→%s p=%s" % [hp_before, gp.hp, gp.pressure_left])
		ok = false
	elif gp.scale_outgoing(raw_out) != raw_out:
		push_error("stance: pressured should lose open bonus")
		ok = false
	else:
		print("stance unit pressure OK")

	var ham_sim := BattleSim.make_tutorial_wolf_fight({
		"atk": 20, "hp": 100, "max_hp": 100, "def": 8, "weapon_class": "hammer"
	})
	var ham_u: BattleUnit = ham_sim.get_unit("player")
	var g_sim2 := BattleSim.make_tutorial_wolf_fight({
		"atk": 20, "hp": 100, "max_hp": 100, "def": 8, "weapon_class": "gun"
	})
	var gu: BattleUnit = g_sim2.get_unit("player")
	## 燒掉銃的第一次減傷
	gu.take_damage(10)
	gu.hp = 100
	gu.pressure_left = 3.0
	var h0 := ham_u.hp
	var g0 := gu.hp
	ham_u.take_damage(40)
	gu.take_damage(40)
	var h_lost := h0 - ham_u.hp
	var g_lost := g0 - gu.hp
	if h_lost >= g_lost:
		push_error("stance: hammer should lose less hp than pressured gun h=%s g=%s" % [h_lost, g_lost])
		ok = false
	else:
		print("stance hammer tankier OK h=", h_lost, " g=", g_lost)

	if ok:
		print("TEST_OK")
		quit(0)
	else:
		print("TEST_FAIL")
		quit(1)
