class_name BattleSim
extends RefCounted
## Tick 驅動戰鬥：雜魚自動；BOSS 王者斬可格擋。
## View 只聽 signal／事件佇列，不重算傷害。

signal event(kind: String, data: Dictionary)
signal battle_ended(won: bool)

const ATB_MAX := 100.0
const RAGE_MAX := 100.0
const KING_SLASH_WINDUP := 1.85  ## 較長前搖，方便看倒數
const PARRY_WINDOW := 0.85      ## 可格擋窗（出手前這段都算成功）
const KING_SLASH_CD := 8.0

## 「差一點」的寬限：窗開之前這麼久按下去，算按早了但**不算用掉機會**。
##
## 沒有這條的話，一次前搖一次機會會變成在罰手速：量過，每次前搖都早按 0.15 秒的玩家
## 跟無腦連按的人拿到一樣的成績（都是 0% 勝率）。那不是在教時機。
## 有了寬限，按早一點點的人收到「太早了」的回饋、機會還在，補按仍然接得住；
## 而連按的人第一下必定落在寬限之外（前搖一開始就按），機會照樣花掉。
const PARRY_EARLY_GRACE := 0.35


var units: Dictionary = {}  ## id -> BattleUnit
var time: float = 0.0
var finished: bool = false
var won: bool = false
var rng: RandomNumberGenerator
var time_scale: float = 1.0

## 慢鏡
var slowmo: float = 0.0
var pending_micro_end: String = ""

## 玩家手動
var player_id: String = "player"

## 白霧模式：僅看破破綻可傷本體；幻影反噬
var fog_mode: bool = false
var fog_vuln_cd: float = 0.0
var fog_vuln_left: float = 0.0
## 本體現形的節奏。玩家沒有辦法決定自己什麼時候出手（ATB 自動填滿就揮），
## 所以「只有發白那一瞬打得中」實際上不是時機考驗，是一個玩家影響不了的傷害稅：
## 原本 1.35/(3.2+1.35) = 30% 的攻擊有效，其餘全部落空。
## 加上兩隻打不死的幻影一起輸出，實測 Lv40 也只有 7% 勝率。
##
## 破綻拉到 38% 的時間佔比，讓這場變成「看準破綻集中輸出」而不是擲骰子。
const FOG_VULN_INTERVAL := 2.2
const FOG_VULN_DURATION := 1.35

## 魔王模式：血量階段誘惑暫停
var demon_mode: bool = false
var sim_paused: bool = false
var temptation_stage: int = 0  ## 1 力量 2 復仇 3 安穩
var stages_done: Array = [false, false, false]
var refuse_count: int = 0

## 阿波模式：高防架勢 + 戰鬥破防（攻擊累積破防條）
var abo_mode: bool = false
var abo_guard: float = 0.0  ## 0~ABO_GUARD_MAX，滿則破防
const ABO_GUARD_MAX := 100.0
var abo_broken_left: float = 0.0  ## 破防持續秒數
const ABO_BREAK_DURATION := 4.5
var abo_base_defense: int = 18
var abo_break_count: int = 0  ## 本場破防次數（成就用）
var abo_heart_score: int = 0  ## 兼容：破防次數別名寫入
## 阿波破防中重拳
var abo_slam_cd: float = 0.0

## 疾影：停拍窗全額傷害 + 風切
var falcon_mode: bool = false
var falcon_stop_cd: float = 0.0
var falcon_stop_left: float = 0.0
const FALCON_STOP_INTERVAL := 3.4
const FALCON_STOP_DURATION := 0.95

## 石拳：岩甲 + 對撞衝鋒 + 落岩
var boar_mode: bool = false
var boar_armor: int = 2
const BOAR_ARMOR_MAX := 2
var boar_charge_cd: float = 0.0
const BOAR_CHARGE_INTERVAL := 6.5
var boar_did_regrow: bool = false

## 裂縫·怒火：密火圈 + 灼燒疊層（漏閃疊層，滿 3 大傷）
var wrath_mode: bool = false
var burn_stacks: int = 0
const BURN_STACK_MAX := 3

## 裂縫·潮噬：刺胞時限 + 普攻／技能減傷相位
var tide_mode: bool = false
var tide_summon_cd: float = 0.0
var tide_wave_left: float = 0.0
var tide_wave_active: bool = false
var tide_player_swings: int = 0  ## 本波玩家出手次數
## 兩波刺胞之間、玩家可以專心打本體的時間。
##
## 原本 11 秒，而清一波要三刀（通關等級約 10 秒）—— 玩家幾乎整場都在清刺胞。
## 實測 Lv25 一場打出 663 點傷害，其中 540 點餵給刺胞，本體只掉 180／480。
## 波次不該是整場戰鬥，它是打斷。
const TIDE_SUMMON_INTERVAL := 18.0

## 刺胞波給玩家幾個「出手週期」去清。
##
## 原本這裡寫死 7.5 秒，而玩家在 speed 10 時每 4 秒才出手一次
## —— 7.5 秒＝1.9 刀，要用 1.9 刀殺掉三隻各 45 血的刺胞，任何等級都做不到。
## 清不掉的罰則又是「最大生命 18%」，是百分比，練等一點用都沒有：
## 每 11 秒固定掉 18%，六波之內必死，跟你多強完全無關。實測全等級 0% 勝率。
##
## 改成用玩家自己的出手節奏算時限，速度變快時限也跟著縮 —— 難度維持在
## 「三刀之內清完，中間不能亂打」，而不是一個跟玩家能力脫鉤的秒數。
const TIDE_CLEAR_CYCLES := 4.0
var tide_phase_skill: bool = false  ## false=普攻減半 true=技傷減半
var tide_phase_cd: float = 0.0
const TIDE_PHASE_INTERVAL := 6.0

## 裂縫·石像：三石像輪流可打 + 落岩；全滅後本體
var statue_mode: bool = false
var statue_active_idx: int = 0
var statue_rotate_cd: float = 0.0
const STATUE_ROTATE_INTERVAL := 3.2
var statue_body_spawned: bool = false
const STATUE_IDS: Array[String] = ["statue_0", "statue_1", "statue_2"]

## 裂縫·時牢：炸彈拆除 + 落岩安全區
var chrono_mode: bool = false
var chrono_rock_cd: float = 0.0
var _chrono_pending_rock: bool = false

## ── 互動式場地機制（非 Discord；戰鬥內時機／反應）──
## kind: "" | "fire_ring" | "time_clock" | "lightning" | "wind_cut" | "rockfall" | "bomb"
## phase: idle | warn | window
var hazard_kind: String = ""
var hazard_phase: String = "idle"
var hazard_cd: float = 0.0
var hazard_timer: float = 0.0
var hazard_reacted: bool = false
const HAZARD_WARN := 0.85
const HAZARD_WINDOW := 0.75
const HAZARD_WARN_WRATH := 0.7
const HAZARD_WINDOW_WRATH := 0.65
## NG+：機制窗略短
var ng_tight_hazards: bool = false
var ng_scale_applied: bool = false


func _init(seed: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()


func add_unit(u: BattleUnit) -> void:
	units[u.id] = u


func get_unit(id: String) -> BattleUnit:
	return units.get(id)


func living_of(team: BattleUnit.Team) -> Array:
	var out: Array = []
	for u in units.values():
		if u.team == team and u.is_alive():
			out.append(u)
	return out


func _emit(kind: String, data: Dictionary = {}) -> void:
	event.emit(kind, data)


func step(dt: float) -> void:
	if finished or sim_paused:
		return
	var real_dt := dt * time_scale
	if slowmo > 0.0:
		real_dt *= 0.25
		slowmo -= dt
		if slowmo <= 0.0:
			slowmo = 0.0
			if pending_micro_end != "":
				_emit("banner_end", {"text": pending_micro_end})
				pending_micro_end = ""

	time += real_dt

	for u in units.values():
		if u.is_alive():
			u.tick_status(real_dt)

	if fog_mode:
		_step_fog_vuln(real_dt)
	if abo_mode:
		_step_abo_guard(real_dt)
		_step_abo_slam(real_dt)
	if falcon_mode:
		_step_falcon_stop(real_dt)
	if boar_mode:
		_step_boar_charge(real_dt)
	if tide_mode:
		_step_tide(real_dt)
	if statue_mode:
		_step_statue(real_dt)
	if chrono_mode:
		_step_chrono_extra(real_dt)
	if hazard_kind != "":
		_step_hazard(real_dt)

	for u in units.values():
		if not u.is_alive():
			continue
		_step_unit(u, real_dt)

	_check_end()


func _step_fog_vuln(dt: float) -> void:
	var real_u := get_unit("white_fog")
	if real_u == null or not real_u.is_alive():
		return
	if fog_vuln_left > 0.0:
		fog_vuln_left -= dt
		real_u.vulnerable = true
		if fog_vuln_left <= 0.0:
			fog_vuln_left = 0.0
			real_u.vulnerable = false
			_emit("fog_hide", {"id": real_u.id})
	else:
		real_u.vulnerable = false
		fog_vuln_cd -= dt
		if fog_vuln_cd <= 0.0:
			fog_vuln_cd = FOG_VULN_INTERVAL
			fog_vuln_left = FOG_VULN_DURATION
			real_u.vulnerable = true
			_emit("fog_reveal", {"id": real_u.id, "duration": FOG_VULN_DURATION})


func _step_unit(u: BattleUnit, dt: float) -> void:
	if u.is_boss:
		u.king_slash_cd = maxf(0.0, u.king_slash_cd - dt)

	match u.state:
		BattleUnit.State.IDLE:
			## 雷歐／魔王必殺前搖（白霧／阿波／疾影／石拳／裂縫特殊自有機制）
			if not fog_mode and not abo_mode and not falcon_mode and not boar_mode \
					and not tide_mode and not statue_mode and not chrono_mode \
					and u.is_boss and u.king_slash_cd <= 0.0 and u.hp < u.max_hp and u.hp <= u.max_hp * 0.70:
				_start_king_slash(u)
				return
			## 時牢本體仍可出必殺
			if chrono_mode and u.is_boss and u.id == "chrono" and u.king_slash_cd <= 0.0 \
					and u.hp < u.max_hp and u.hp <= u.max_hp * 0.65:
				_start_king_slash(u)
				return
			u.atb += Formulas.atb_fill_per_sec(u.speed) * dt * u.atb_rate_mult()
			if u.atb >= ATB_MAX:
				u.atb = 0.0
				_begin_attack(u)
		BattleUnit.State.WINDUP:
			u.state_timer -= dt
			if u.telegraph_active:
				u.telegraph_timer -= dt
				## 格擋窗：前搖最後 PARRY_WINDOW 秒
				if u.state_timer <= PARRY_WINDOW:
					_emit("parry_window", {"attacker": u.id, "open": true})
			if u.state_timer <= 0.0:
				if u.telegraph_active:
					_resolve_king_slash_hit(u)
				else:
					_resolve_strike(u)
		BattleUnit.State.STRIKE:
			u.state_timer -= dt
			if u.state_timer <= 0.0:
				u.state = BattleUnit.State.RECOVER
				u.state_timer = u.recover_time
				_emit("state", {"id": u.id, "state": "recover"})
		BattleUnit.State.RECOVER:
			u.state_timer -= dt
			if u.state_timer <= 0.0:
				u.state = BattleUnit.State.IDLE
				u.telegraph_active = false
				_emit("state", {"id": u.id, "state": "idle"})
				_emit("parry_window", {"attacker": u.id, "open": false})
		BattleUnit.State.CAST:
			u.state_timer -= dt
			if u.state_timer <= 0.0:
				_resolve_skill(u)
		_:
			pass


func _begin_attack(u: BattleUnit) -> void:
	var foes: Array = living_of(
		BattleUnit.Team.ENEMY if u.team == BattleUnit.Team.PLAYER else BattleUnit.Team.PLAYER
	)
	if foes.is_empty():
		return
	var target: BattleUnit = foes[0]
	## 玩家可鎖定：用 target_id
	if u.team == BattleUnit.Team.PLAYER and u.target_id != "":
		var t2 = get_unit(u.target_id)
		if t2 and t2.is_alive():
			target = t2
	## 霧戰預設鎖本體
	if u.team == BattleUnit.Team.PLAYER and fog_mode:
		if u.target_id == "" or get_unit(u.target_id) == null:
			u.target_id = "white_fog"
			target = get_unit("white_fog")
			if target == null or not target.is_alive():
				target = foes[0]
	## 潮噬：有刺胞時優先清 adds
	if u.team == BattleUnit.Team.PLAYER and tide_mode and tide_wave_active:
		for id in ["polyp_0", "polyp_1", "polyp_2"]:
			var pol := get_unit(id)
			if pol and pol.is_alive():
				target = pol
				break
	## 石像：鎖發光那尊／本體
	if u.team == BattleUnit.Team.PLAYER and statue_mode:
		_statue_retarget_player()
		var st := get_unit(u.target_id) if u.target_id != "" else null
		if st and st.is_alive():
			target = st
	u.target_id = target.id

	## 怒氣滿且會技能
	if u.can_skill and u.rage >= RAGE_MAX:
		if u.id == player_id:
			_refresh_player_skill_choice(u)
		u.state = BattleUnit.State.CAST
		u.state_timer = 0.35
		u.rage = 0.0
		_emit("skill_cast", {
			"id": u.id,
			"skill": u.skill_name,
			"skill_id": u.skill_id,
			"kind": u.skill_kind,
			"target": target.id,
		})
		return

	u.state = BattleUnit.State.WINDUP
	u.state_timer = u.windup_time
	_emit("attack_swing", {"id": u.id, "target": target.id})


func cycle_player_target(dir: int = 1) -> String:
	if not fog_mode:
		return ""
	var ids: Array[String] = ["phantom_a", "white_fog", "phantom_b"]
	var p := get_unit(player_id)
	if p == null:
		return ""
	var idx := ids.find(p.target_id)
	if idx < 0:
		idx = 1
	for _i in 3:
		idx = (idx + dir + 3) % 3
		var cand := get_unit(ids[idx])
		if cand and cand.is_alive():
			p.target_id = ids[idx]
			_emit("target_changed", {"id": p.target_id, "name": cand.display_name})
			return p.target_id
	return p.target_id


func set_player_target(id: String) -> void:
	var p := get_unit(player_id)
	var t := get_unit(id)
	if p and t and t.is_alive():
		p.target_id = id
		_emit("target_changed", {"id": id, "name": t.display_name})


func _apply_player_hit_on_fog(attacker: BattleUnit, target: BattleUnit, dmg: int, is_crit: bool, skill_name: String = "") -> void:
	## 幻影：反噬
	if target.is_phantom:
		var recoil := maxi(1, int(round(float(dmg) * 0.35)))
		var dealt_self := attacker.take_damage(recoil)
		## 冰意：打幻影＝自己變慢（戰鬥機制，非對話）
		attacker.atb_slow_left = maxf(attacker.atb_slow_left, 2.8)
		_emit("fog_phantom_hit", {
			"attacker": attacker.id,
			"defender": target.id,
			"recoil": dealt_self,
			"hp": attacker.hp,
			"max_hp": attacker.max_hp,
			"chill": true,
		})
		return
	## 本體但未看破
	if target.is_fog_real and not target.vulnerable:
		_emit("fog_blocked", {"attacker": attacker.id, "defender": target.id})
		return
	## 本體破綻
	var dealt := target.take_damage(dmg)
	if skill_name != "":
		_emit("skill_hit", {
			"attacker": attacker.id,
			"defender": target.id,
			"skill": skill_name,
			"skill_id": attacker.skill_id,
			"kind": "attack",
			"damage": dealt,
			"hp": target.hp,
			"max_hp": target.max_hp,
			"fog_true": true,
		})
	else:
		_emit("hit", {
			"attacker": attacker.id,
			"defender": target.id,
			"damage": dealt,
			"crit": is_crit,
			"hp": target.hp,
			"max_hp": target.max_hp,
			"rage": target.rage,
			"fog_true": true,
		})


func _resolve_strike(u: BattleUnit) -> void:
	var target := get_unit(u.target_id)
	if target == null or not target.is_alive():
		u.state = BattleUnit.State.RECOVER
		u.state_timer = u.recover_time
		return

	var miss_pct := Formulas.miss_chance(u.speed, target.speed, u.hit, target.eva)
	if rng.randi_range(1, 100) <= miss_pct:
		_emit("miss", {"attacker": u.id, "defender": target.id})
		u.state = BattleUnit.State.RECOVER
		u.state_timer = u.recover_time
		return

	var atk_use := float(u.atk) * (u.atk_buff_mult if u.atk_buff_left > 0.0 else 1.0)
	var var_pct := u.dmg_variance if u.dmg_variance > 0.0 else Formulas.default_variance()
	var rolled: Dictionary = Formulas.roll_hit_damage(
		atk_use, target.defense, 1.0, var_pct,
		u.crit, target.crit_resist, u.crit_dmg, rng, false
	)
	var dmg: int = int(rolled.get("damage", 1))
	var is_crit: bool = bool(rolled.get("crit", false))

	if fog_mode and u.team == BattleUnit.Team.PLAYER:
		_apply_player_hit_on_fog(u, target, dmg, is_crit)
		u.state = BattleUnit.State.STRIKE
		u.state_timer = 0.08
		return

	## 阿波架勢中：傷害大減，改灌破防條
	if abo_mode and u.team == BattleUnit.Team.PLAYER and target.id == "abo":
		dmg = _abo_filter_damage(target, dmg, false)
	## 疾影：未停拍只 chip
	if falcon_mode and u.team == BattleUnit.Team.PLAYER and target.id == "falcon":
		dmg = _falcon_filter_damage(target, dmg)
	## 石拳：岩甲層 chip
	if boar_mode and u.team == BattleUnit.Team.PLAYER and target.id == "boar":
		dmg = _boar_filter_damage(target, dmg)
	if tide_mode and u.team == BattleUnit.Team.PLAYER:
		dmg = _tide_filter_damage(target, dmg, false)
		if u.id == player_id and tide_wave_active:
			tide_player_swings += 1
	if statue_mode and u.team == BattleUnit.Team.PLAYER:
		dmg = _statue_filter_damage(target, dmg)
	var dealt := target.take_damage(dmg)
	## 出手也累積戰意，否則戰意只能靠挨打累積，而挨到滿之前人就死了
	if u.can_skill and dealt > 0:
		u.rage = minf(RAGE_MAX, u.rage + Formulas.rage_from_strike())
	_emit("hit", {
		"attacker": u.id,
		"defender": target.id,
		"damage": dealt,
		"crit": is_crit,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"rage": target.rage,
	})
	if abo_mode and u.team == BattleUnit.Team.PLAYER and target.id == "abo":
		_abo_add_guard(28.0 if is_crit else 18.0, "普攻")
	if statue_mode and u.team == BattleUnit.Team.PLAYER:
		_statue_retarget_player()
	u.state = BattleUnit.State.STRIKE
	u.state_timer = 0.08
	if demon_mode:
		_check_demon_stages()


func _refresh_player_skill_choice(u: BattleUnit) -> void:
	## 依當前血量重選優先技能（危急恢復等）
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return
	var n: Node = (tree as SceneTree).root.get_node_or_null("SkillSystem")
	if n == null or not n.has_method("pick_battle_skill"):
		return
	var ratio: float = float(u.hp) / float(maxi(1, u.max_hp))
	var kit: Dictionary = n.call("pick_battle_skill", ratio)
	if kit.is_empty():
		return
	u.skill_id = str(kit.get("id", u.skill_id))
	u.skill_name = str(kit.get("name", u.skill_name))
	u.skill_kind = str(kit.get("kind", "attack"))
	u.skill_mult = float(kit.get("mult", u.skill_mult))
	u.heal_pct = float(kit.get("heal_pct", 0.0))


func _resolve_skill(u: BattleUnit) -> void:
	## 治療技：對自己生效
	if u.skill_kind == "heal" or u.heal_pct > 0.0 and u.skill_id == "emergency_heal":
		var pct: float = u.heal_pct if u.heal_pct > 0.0 else 0.30
		var healed: int = maxi(1, int(round(float(u.max_hp) * pct)))
		var before: int = u.hp
		u.hp = mini(u.max_hp, u.hp + healed)
		var actual: int = u.hp - before
		_emit("skill_hit", {
			"attacker": u.id,
			"defender": u.id,
			"skill": u.skill_name,
			"skill_id": u.skill_id,
			"kind": "heal",
			"damage": 0,
			"heal": actual,
			"hp": u.hp,
			"max_hp": u.max_hp,
		})
		u.state = BattleUnit.State.RECOVER
		u.state_timer = u.recover_time * 1.1
		return

	var target := get_unit(u.target_id)
	if target == null or not target.is_alive():
		var foes: Array = living_of(BattleUnit.Team.ENEMY if u.team == BattleUnit.Team.PLAYER else BattleUnit.Team.PLAYER)
		if foes.is_empty():
			u.state = BattleUnit.State.RECOVER
			u.state_timer = u.recover_time
			return
		target = foes[0]
		u.target_id = target.id

	var atk_s := float(u.atk) * (u.atk_buff_mult if u.atk_buff_left > 0.0 else 1.0)
	var var_s := u.dmg_variance if u.dmg_variance > 0.0 else Formulas.default_variance()
	var sroll: Dictionary = Formulas.roll_hit_damage(
		atk_s, target.defense, u.skill_mult, var_s,
		u.crit, target.crit_resist, u.crit_dmg, rng, true
	)
	var dmg: int = int(sroll.get("damage", 1))
	var skill_crit: bool = bool(sroll.get("crit", false))
	if fog_mode and u.team == BattleUnit.Team.PLAYER:
		_apply_player_hit_on_fog(u, target, dmg, skill_crit, u.skill_name)
		u.state = BattleUnit.State.RECOVER
		u.state_timer = u.recover_time * 1.2
		return

	if abo_mode and u.team == BattleUnit.Team.PLAYER and target.id == "abo":
		dmg = _abo_filter_damage(target, dmg, true)
	if falcon_mode and u.team == BattleUnit.Team.PLAYER and target.id == "falcon":
		dmg = _falcon_filter_damage(target, dmg)
	if boar_mode and u.team == BattleUnit.Team.PLAYER and target.id == "boar":
		dmg = _boar_filter_damage(target, dmg)
	if tide_mode and u.team == BattleUnit.Team.PLAYER:
		dmg = _tide_filter_damage(target, dmg, true)
		if u.id == player_id and tide_wave_active:
			tide_player_swings += 1
	if statue_mode and u.team == BattleUnit.Team.PLAYER:
		dmg = _statue_filter_damage(target, dmg)
	var dealt := target.take_damage(dmg)
	_emit("skill_hit", {
		"attacker": u.id,
		"defender": target.id,
		"skill": u.skill_name,
		"skill_id": u.skill_id,
		"kind": "attack",
		"crit": skill_crit,
		"damage": dealt,
		"hp": target.hp,
		"max_hp": target.max_hp,
	})
	if abo_mode and u.team == BattleUnit.Team.PLAYER and target.id == "abo":
		_abo_add_guard(42.0, u.skill_name)  ## 技能灌破防較多
	if statue_mode and u.team == BattleUnit.Team.PLAYER:
		_statue_retarget_player()
	u.state = BattleUnit.State.RECOVER
	u.state_timer = u.recover_time * 1.2
	if demon_mode:
		_check_demon_stages()


func _step_abo_guard(dt: float) -> void:
	var a := get_unit("abo")
	if a == null or not a.is_alive():
		return
	if abo_broken_left > 0.0:
		abo_broken_left -= dt
		if abo_broken_left <= 0.0:
			abo_broken_left = 0.0
			a.defense = abo_base_defense
			a.vulnerable = false
			a.telegraph_active = false
			_emit("abo_guard_recover", {"id": a.id})
		else:
			a.vulnerable = true
			a.defense = maxi(3, abo_base_defense - 12)


func _step_abo_slam(dt: float) -> void:
	## 破防期間阿波會放「重拳」前搖——要格擋，不是問答
	if abo_broken_left <= 0.0:
		return
	var a := get_unit("abo")
	if a == null or not a.is_alive() or a.telegraph_active:
		return
	abo_slam_cd -= dt
	if abo_slam_cd > 0.0:
		return
	abo_slam_cd = 2.2
	a.state = BattleUnit.State.WINDUP
	a.state_timer = 1.2
	a.telegraph_active = true
	a.parry_used = false
	a.telegraph_timer = 1.2
	var foes: Array = living_of(BattleUnit.Team.PLAYER)
	if not foes.is_empty():
		a.target_id = foes[0].id
	_emit("king_slash_start", {"id": a.id, "windup": 1.2, "label": "重拳", "abo_slam": true})


func _abo_filter_damage(abo: BattleUnit, dmg: int, is_skill: bool) -> int:
	## 未破防：實傷壓到很低（仍有一點反饋）；已破防：全額
	if abo_broken_left > 0.0:
		return dmg
	var chip := maxi(1, int(round(float(dmg) * (0.18 if is_skill else 0.12))))
	return chip


func _falcon_filter_damage(falcon: BattleUnit, dmg: int) -> int:
	## 停拍窗全額；否則 chip（打在殘影／模糊上）
	if falcon_stop_left > 0.0 or falcon.vulnerable:
		return dmg
	return maxi(1, int(round(float(dmg) * 0.14)))


func _boar_filter_damage(_boar: BattleUnit, dmg: int) -> int:
	if boar_armor <= 0:
		return dmg
	## 有岩甲：大減；層數越多越硬
	var mult := 0.12 if boar_armor >= 2 else 0.22
	return maxi(1, int(round(float(dmg) * mult)))


func _step_falcon_stop(dt: float) -> void:
	var f := get_unit("falcon")
	if f == null or not f.is_alive():
		return
	if falcon_stop_left > 0.0:
		falcon_stop_left -= dt
		f.vulnerable = true
		if falcon_stop_left <= 0.0:
			falcon_stop_left = 0.0
			f.vulnerable = false
			_emit("falcon_blur", {"id": f.id})
	else:
		f.vulnerable = false
		falcon_stop_cd -= dt
		if falcon_stop_cd <= 0.0:
			falcon_stop_cd = FALCON_STOP_INTERVAL
			## 低血停拍略短
			var dur := FALCON_STOP_DURATION
			if float(f.hp) / float(f.max_hp) < 0.4:
				dur = 0.72
				falcon_stop_cd = 2.6
			falcon_stop_left = dur
			f.vulnerable = true
			_emit("falcon_stop", {"id": f.id, "duration": dur})


func _step_boar_charge(dt: float) -> void:
	var b := get_unit("boar")
	if b == null or not b.is_alive() or b.telegraph_active:
		return
	## 低血補一層岩甲一次
	if not boar_did_regrow and boar_armor <= 0 and float(b.hp) / float(b.max_hp) <= 0.32:
		boar_armor = 1
		boar_did_regrow = true
		_emit("boar_armor_break", {"armor": boar_armor, "max": BOAR_ARMOR_MAX, "regrow": true})
	boar_charge_cd -= dt
	if boar_charge_cd > 0.0:
		return
	boar_charge_cd = BOAR_CHARGE_INTERVAL
	b.state = BattleUnit.State.WINDUP
	b.state_timer = 1.45
	b.telegraph_active = true
	b.parry_used = false
	b.telegraph_timer = 1.45
	var foes: Array = living_of(BattleUnit.Team.PLAYER)
	if not foes.is_empty():
		b.target_id = foes[0].id
	_emit("king_slash_start", {"id": b.id, "windup": 1.45, "label": "衝鋒", "boar_clash": true})


func _abo_add_guard(amount: float, source: String) -> void:
	if abo_broken_left > 0.0:
		return  ## 破防中不再灌條，專心輸出
	var a := get_unit("abo")
	if a == null or not a.is_alive():
		return
	abo_guard = minf(ABO_GUARD_MAX, abo_guard + amount)
	_emit("abo_guard_changed", {
		"guard": abo_guard,
		"max": ABO_GUARD_MAX,
		"source": source,
	})
	if abo_guard >= ABO_GUARD_MAX:
		abo_guard = 0.0
		abo_broken_left = ABO_BREAK_DURATION
		abo_break_count += 1
		abo_heart_score = abo_break_count
		a.defense = maxi(3, abo_base_defense - 12)
		a.vulnerable = true
		_emit("abo_guard_break", {
			"id": a.id,
			"duration": ABO_BREAK_DURATION,
			"count": abo_break_count,
		})


func _check_demon_stages() -> void:
	if not demon_mode or sim_paused or finished:
		return
	var d := get_unit("demon")
	if d == null or not d.is_alive():
		return
	var r := float(d.hp) / float(maxi(1, d.max_hp))
	## 階段：力量 70% / 復仇 45% / 安穩 20%
	if not stages_done[0] and r <= 0.72:
		_begin_temptation(1)
	elif not stages_done[1] and r <= 0.45:
		_begin_temptation(2)
	elif not stages_done[2] and r <= 0.20:
		_begin_temptation(3)


func _begin_temptation(stage: int) -> void:
	stages_done[stage - 1] = true
	sim_paused = true
	temptation_stage = stage
	## 暫停時清 BOSS 前搖，避免卡在必殺
	var d := get_unit("demon")
	if d:
		d.telegraph_active = false
		if d.state == BattleUnit.State.WINDUP:
			d.state = BattleUnit.State.IDLE
			d.state_timer = 0.0
	var titles := {1: "力量", 2: "復仇", 3: "安穩"}
	var lines := {
		1: "我給你力量。一擊劈開黑焰。你的村、你的人，瞬間安全。你不是慕強。你只是——效率。",
		2: "恨我。恨燒村的焰。把恨鍛成刃——比愛鋒利。",
		3: "放下劍。我替你撐封印。你回村。麥田會在。永不變強的安穩——這不就是「不慕強權」嗎？",
	}
	_emit("temptation", {
		"stage": stage,
		"title": titles.get(stage, ""),
		"text": lines.get(stage, ""),
		"refuse_scale": 1.0 if stage == 1 else (1.35 if stage == 2 else 2.0),
	})


## 玩家選完誘惑；refused=true 削弱魔王
func resolve_temptation(stage: int, refused: bool) -> void:
	if not sim_paused or temptation_stage != stage:
		return
	var d := get_unit("demon")
	if refused:
		refuse_count += 1
		if d:
			d.atk = maxi(6, d.atk - 3)
			d.defense = maxi(4, d.defense - 2)
		var flag_keys: Array[String] = ["", "c6_refuse_power", "c6_refuse_revenge", "c6_refuse_peace"]
		var flag_key: String = flag_keys[stage]
		_emit("temptation_resolved", {
			"stage": stage,
			"refused": true,
			"flag": flag_key,
			"refuse_count": refuse_count,
		})
	else:
		## 聽完仍強制拒絕路徑簡化：灰線也削弱較少
		if d:
			d.atk = maxi(7, d.atk - 1)
		_emit("temptation_resolved", {
			"stage": stage,
			"refused": false,
			"refuse_count": refuse_count,
		})
	sim_paused = false
	temptation_stage = 0
	if stage == 3:
		_emit("demon_shell_break", {"refuse_all": refuse_count >= 3})


func _start_king_slash(u: BattleUnit) -> void:
	u.king_slash_cd = KING_SLASH_CD
	u.state = BattleUnit.State.WINDUP
	u.state_timer = KING_SLASH_WINDUP
	u.telegraph_active = true
	u.parry_used = false
	u.telegraph_timer = KING_SLASH_WINDUP
	var foes: Array = living_of(BattleUnit.Team.PLAYER)
	if not foes.is_empty():
		u.target_id = foes[0].id
	var skill_label := "黑焰必殺" if demon_mode else "王者斬"
	_emit("king_slash_start", {"id": u.id, "windup": KING_SLASH_WINDUP, "label": skill_label})
	_emit("state", {"id": u.id, "state": "telegraph"})


## 玩家現在按下去有沒有東西可以接。給 UI 用（顯示倒數、變綠）。
func parry_window_open() -> bool:
	if sim_paused or finished:
		return false
	if hazard_phase == "window" and not hazard_reacted:
		return true
	for u in units.values():
		if u.is_boss and u.telegraph_active and u.state == BattleUnit.State.WINDUP:
			if u.state_timer <= _parry_win_for(u) and u.state_timer > 0.0:
				return true
	return false


## 統一反應鍵：場地機制窗 or Boss 前搖格擋。
##
## **一次前搖只有一次機會。**
##
## 為什麼要有這條規則：實測過，「完美時機」跟「每 0.1 秒狂按」的結果一模一樣
## —— 雷歐戰兩者都成功格擋 10.18 次、勝率都是 97.8%，差別只有按 10 下還是 658 下。
## 空揮零代價的時候，看倒數這件事就沒有理由做，整個遊戲最核心的機制等於不存在。
##
## 規則：Boss 舉起手（前搖開始）到揮下來之間，玩家按的**第一下**就是這次的答案。
## 按在窗內＝格擋成功；按早了＝這次前搖沒了，下次再來。
##
## 為什麼是「一次機會」而不是「空揮鎖 N 秒」：鎖時間的版本量過，
## 連按確實壓到 0 次格擋，但「手快按早了一下、之後在窗內補按」的玩家
## 也一起被壓到 0% 勝率 —— 那是在罰手速，不是在教時機。
## 一次前搖一次機會的代價剛好落在「這一次」上：連按的人每次前搖都把機會
## 花在第一下（必定在窗外），而按早的人只損失那一次前搖，下一次仍是乾淨的。
##
## 罰則刻意不扣血。目的是讓時機變得有意義，不是懲罰玩家。
func try_react() -> bool:
	if sim_paused:
		return false
	## 1) 火圈／時鐘等 window：機制窗本來就只結算一次（hazard_reacted）
	if hazard_phase == "window" and not hazard_reacted:
		hazard_reacted = true
		_resolve_hazard(true)
		return true
	## 2) Boss 前搖：找正在舉手的那一隻
	var tel := _telegraphing_boss()
	if tel == null:
		## 沒有任何前搖 —— 按了也沒東西可接，但也沒東西可以浪費
		_emit("parry_idle", {})
		return false
	if tel.parry_used:
		_emit("parry_spent", {"boss": tel.id})
		return false
	if try_parry():
		tel.parry_used = true
		return true
	## 差一點：窗還沒開、但已經很接近了 —— 給回饋，不扣機會
	if tel.state_timer <= _parry_win_for(tel) + PARRY_EARLY_GRACE:
		_emit("parry_early", {"boss": tel.id})
		return false
	tel.parry_used = true
	_emit("parry_whiff", {"boss": tel.id})
	return false


## 這隻 Boss 的格擋窗長度（阿波重拳／石拳對撞略寬）
func _parry_win_for(u: BattleUnit) -> float:
	if abo_mode and u.id == "abo":
		return 0.95
	if boar_mode and u.id == "boar":
		return 1.0
	return PARRY_WINDOW


func _telegraphing_boss() -> BattleUnit:
	for u in units.values():
		if u.is_boss and u.is_alive() and u.telegraph_active and u.state == BattleUnit.State.WINDUP:
			return u
	return null


## 玩家在格擋窗按 parry
func try_parry() -> bool:
	if sim_paused:
		return false
	for u in units.values():
		if u.is_boss and u.telegraph_active and u.state == BattleUnit.State.WINDUP:
			var win := _parry_win_for(u)
			if u.state_timer <= win and u.state_timer > 0.0:
				_perfect_parry(u)
				return true
	return false


func _first_telegraph_or_boss() -> BattleUnit:
	for u in units.values():
		if u.is_boss and u.is_alive() and u.telegraph_active:
			return u
	for u in units.values():
		if u.is_boss and u.is_alive():
			return u
	var foes := living_of(BattleUnit.Team.ENEMY)
	if not foes.is_empty():
		return foes[0]
	return null


func _perfect_parry(boss: BattleUnit) -> void:
	boss.telegraph_active = false
	boss.state = BattleUnit.State.RECOVER
	boss.state_timer = 1.2  ## 硬直
	slowmo = 0.85
	var banner := "微末一格"
	if demon_mode:
		banner = "微末到底"
	elif abo_mode and boss.id == "abo":
		banner = "拆招"
	elif boar_mode and boss.id == "boar":
		banner = "對撞"
	pending_micro_end = banner
	_emit("perfect_parry", {"boss": boss.id, "banner": banner})
	_emit("parry_window", {"attacker": boss.id, "open": false})

	var p := get_unit(player_id)
	if p and p.is_alive() and boss.is_alive():
		## 石拳對撞：剝岩甲 + 固傷，不走一般破甲過濾
		if boar_mode and boss.id == "boar":
			if boar_armor > 0:
				boar_armor -= 1
				_emit("boar_armor_break", {"armor": boar_armor, "max": BOAR_ARMOR_MAX})
			var clash_dmg := maxi(8, int(p.atk * 1.6) + 12)
			if boar_armor > 0:
				clash_dmg = maxi(4, int(clash_dmg * 0.5))
			var dealt_b := boss.take_damage(clash_dmg)
			_emit("skill_hit", {
				"attacker": p.id,
				"defender": boss.id,
				"skill": "對撞",
				"damage": dealt_b,
				"hp": boss.hp,
				"max_hp": boss.max_hp,
				"parry_followup": true,
			})
		else:
			var dmg := Formulas.skill_damage(p.atk * (p.atk_buff_mult if p.atk_buff_left > 0.0 else 1.0), boss.defense, 2.4)
			if abo_mode and boss.id == "abo" and abo_broken_left <= 0.0:
				dmg = _abo_filter_damage(boss, dmg, true)
			if falcon_mode and boss.id == "falcon":
				dmg = _falcon_filter_damage(boss, dmg)
			var dealt := boss.take_damage(dmg)
			_emit("skill_hit", {
				"attacker": p.id,
				"defender": boss.id,
				"skill": banner,
				"damage": dealt,
				"hp": boss.hp,
				"max_hp": boss.max_hp,
				"parry_followup": true,
			})
			if abo_mode and boss.id == "abo":
				_abo_add_guard(35.0, banner)
	if demon_mode:
		_check_demon_stages()


func _resolve_king_slash_hit(boss: BattleUnit) -> void:
	boss.telegraph_active = false
	_emit("parry_window", {"attacker": boss.id, "open": false})
	var target := get_unit(boss.target_id)
	if target and target.is_alive():
		## 未格擋：高傷
		var mult := 2.8
		if abo_mode and boss.id == "abo":
			mult = 2.2
		var dmg := Formulas.skill_damage(boss.atk, target.defense, mult)
		var dealt := target.take_damage(dmg)
		_emit("hit", {
			"attacker": boss.id,
			"defender": target.id,
			"damage": dealt,
			"crit": false,
			"hp": target.hp,
			"max_hp": target.max_hp,
			"rage": target.rage,
			"king_slash": true,
		})
	boss.state = BattleUnit.State.RECOVER
	boss.state_timer = boss.recover_time * 1.5
	_emit("king_slash_end", {"id": boss.id, "parried": false})
	if demon_mode:
		_check_demon_stages()


# ── 場地互動機制 ──

func setup_hazard(kind: String, first_cd: float = 4.0) -> void:
	hazard_kind = kind
	hazard_phase = "idle"
	hazard_cd = first_cd
	hazard_timer = 0.0
	hazard_reacted = false


func _step_hazard(dt: float) -> void:
	if hazard_kind == "" or finished:
		return
	match hazard_phase:
		"idle":
			hazard_cd -= dt
			if hazard_cd <= 0.0:
				hazard_phase = "warn"
				hazard_timer = _hazard_warn_time()
				hazard_reacted = false
				_emit("hazard_warn", {"kind": hazard_kind, "warn": hazard_timer})
		"warn":
			hazard_timer -= dt
			if hazard_timer <= 0.0:
				hazard_phase = "window"
				hazard_timer = _hazard_window_time()
				hazard_reacted = false
				_emit("hazard_window", {"kind": hazard_kind, "window": hazard_timer})
		"window":
			hazard_timer -= dt
			if hazard_timer <= 0.0:
				if not hazard_reacted:
					_resolve_hazard(false)
				else:
					## 已在 try_react 處理
					hazard_phase = "idle"
					hazard_cd = _hazard_interval()


func _hazard_warn_time() -> float:
	var t := HAZARD_WARN_WRATH if wrath_mode else HAZARD_WARN
	if ng_tight_hazards:
		t *= 0.9
	return t


func _hazard_window_time() -> float:
	var t := HAZARD_WINDOW_WRATH if wrath_mode else HAZARD_WINDOW
	if ng_tight_hazards:
		t *= 0.9
	return t


func _hazard_interval() -> float:
	if wrath_mode and hazard_kind == "fire_ring":
		return 4.2  ## 比雷歐更密
	if chrono_mode and hazard_kind == "bomb":
		return 7.0
	match hazard_kind:
		"fire_ring":
			return 9.0
		"time_clock":
			return 11.0
		"lightning":
			return 10.0
		"wind_cut":
			return 8.5
		"rockfall":
			return 9.5 if not statue_mode else 7.5
		"bomb":
			return 7.5
		_:
			return 10.0


func _resolve_hazard(success: bool) -> void:
	var p := get_unit(player_id)
	var kind := hazard_kind
	hazard_phase = "idle"
	hazard_cd = _hazard_interval()
	hazard_timer = 0.0
	if p == null or not p.is_alive():
		_emit("hazard_resolve", {"kind": kind, "success": success})
		return
	if success:
		match kind:
			"fire_ring":
				if wrath_mode and burn_stacks > 0:
					burn_stacks = maxi(0, burn_stacks - 1)
					_emit("burn_stacks", {"stacks": burn_stacks, "max": BURN_STACK_MAX})
					_emit("hazard_resolve", {
						"kind": kind,
						"success": true,
						"msg": "躍出火圈 · 灼燒－1（現 %d）" % burn_stacks,
						"burn": burn_stacks,
					})
				else:
					_emit("hazard_resolve", {"kind": kind, "success": true, "msg": "躍出火圈"})
			"time_clock":
				p.atk_buff_left = 4.0
				p.atk_buff_mult = 1.25
				var d := get_unit("demon")
				if d:
					d.atb_slow_left = maxf(d.atb_slow_left, 3.0)
				_emit("hazard_resolve", {"kind": kind, "success": true, "msg": "控時成功：你加速、敵減速"})
			"lightning":
				p.atk_buff_left = 5.0
				p.atk_buff_mult = 1.2
				_emit("hazard_resolve", {"kind": kind, "success": true, "msg": "導雷成功：攻擊上升"})
			"wind_cut":
				_emit("hazard_resolve", {"kind": kind, "success": true, "msg": "避開風切"})
			"rockfall":
				_emit("hazard_resolve", {"kind": kind, "success": true, "msg": "踩進安全區"})
			"bomb":
				_emit("hazard_resolve", {"kind": kind, "success": true, "msg": "拆除炸彈"})
			_:
				_emit("hazard_resolve", {"kind": kind, "success": true})
	else:
		match kind:
			"fire_ring":
				if wrath_mode:
					burn_stacks = mini(BURN_STACK_MAX, burn_stacks + 1)
					_emit("burn_stacks", {"stacks": burn_stacks, "max": BURN_STACK_MAX})
					if burn_stacks >= BURN_STACK_MAX:
						var blast := maxi(1, int(p.max_hp * 0.28))
						var dealt_b := p.take_damage(blast)
						burn_stacks = 0
						_emit("burn_stacks", {"stacks": 0, "max": BURN_STACK_MAX, "detonate": true})
						_emit("hazard_resolve", {
							"kind": kind,
							"success": false,
							"msg": "灼燒滿層！黑焰爆燃",
							"damage": dealt_b,
							"hp": p.hp,
							"max_hp": p.max_hp,
							"burn": 0,
						})
					else:
						var burn := maxi(1, int(p.max_hp * 0.08))
						var dealt := p.take_damage(burn)
						_emit("hazard_resolve", {
							"kind": kind,
							"success": false,
							"msg": "火圈灼傷 · 疊層 %d/%d" % [burn_stacks, BURN_STACK_MAX],
							"damage": dealt,
							"hp": p.hp,
							"max_hp": p.max_hp,
							"burn": burn_stacks,
						})
				else:
					var burn2 := maxi(1, int(p.max_hp * 0.12))
					var dealt2 := p.take_damage(burn2)
					_emit("hazard_resolve", {"kind": kind, "success": false, "msg": "火圈灼傷", "damage": dealt2, "hp": p.hp, "max_hp": p.max_hp})
			"time_clock":
				p.atb_freeze_left = maxf(p.atb_freeze_left, 2.2)
				_emit("hazard_resolve", {"kind": kind, "success": false, "msg": "時鐘錯位：你被凍結出手"})
			"lightning":
				var zap := maxi(1, int(p.max_hp * 0.10))
				var d2 := p.take_damage(zap)
				p.atk_buff_left = 4.0
				p.atk_buff_mult = 0.85
				_emit("hazard_resolve", {"kind": kind, "success": false, "msg": "導雷失敗：受傷且虛弱", "damage": d2, "hp": p.hp, "max_hp": p.max_hp})
			"wind_cut":
				var w := maxi(1, int(p.max_hp * 0.11))
				var dw := p.take_damage(w)
				p.atb_slow_left = maxf(p.atb_slow_left, 2.5)
				_emit("hazard_resolve", {"kind": kind, "success": false, "msg": "風切刮傷，動作變慢", "damage": dw, "hp": p.hp, "max_hp": p.max_hp})
			"rockfall":
				var r := maxi(1, int(p.max_hp * 0.14))
				var dr := p.take_damage(r)
				_emit("hazard_resolve", {"kind": kind, "success": false, "msg": "落岩砸中", "damage": dr, "hp": p.hp, "max_hp": p.max_hp})
			"bomb":
				var bom := maxi(1, int(p.max_hp * 0.16))
				var db := p.take_damage(bom)
				p.atb_slow_left = maxf(p.atb_slow_left, 1.8)
				_emit("hazard_resolve", {"kind": kind, "success": false, "msg": "炸彈爆炸", "damage": db, "hp": p.hp, "max_hp": p.max_hp})
			_:
				_emit("hazard_resolve", {"kind": kind, "success": false})
	## 時牢：副機制 rockfall 結束後切回炸彈
	if chrono_mode and kind == "rockfall" and _chrono_pending_rock:
		_chrono_pending_rock = false
		hazard_kind = "bomb"
		hazard_cd = maxf(hazard_cd, 2.5)
	if p.hp <= 0:
		_check_end()


# ── 裂縫·潮噬 ──

func _tide_filter_damage(target: BattleUnit, dmg: int, is_skill: bool) -> int:
	if target.id.begins_with("polyp"):
		return dmg
	if target.id != "tide":
		return dmg
	## 相位：普攻減半 or 技傷減半
	if tide_phase_skill and is_skill:
		return maxi(1, int(round(float(dmg) * 0.5)))
	if not tide_phase_skill and not is_skill:
		return maxi(1, int(round(float(dmg) * 0.5)))
	return dmg


func _step_tide(dt: float) -> void:
	var boss := get_unit("tide")
	if boss == null or not boss.is_alive() or finished:
		return
	tide_phase_cd -= dt
	if tide_phase_cd <= 0.0:
		tide_phase_cd = TIDE_PHASE_INTERVAL
		tide_phase_skill = not tide_phase_skill
		_emit("tide_phase", {
			"skill_half": tide_phase_skill,
			"label": "他在擋技能 · 改用普攻" if tide_phase_skill else "他在擋普攻 · 改用技能",
		})
	if tide_wave_active:
		tide_wave_left -= dt
		var left := _count_polyps()
		if left <= 0:
			tide_wave_active = false
			tide_wave_left = 0.0
			_emit("tide_wave_clear", {})
			## 清得快要有回報。原本是「清完之後只休息 0.55 個間隔」，
			## 於是清得愈快、下一波來得愈早、要餵的刺胞血量愈多 —— 打得好反而更累。
			tide_summon_cd = TIDE_SUMMON_INTERVAL
		elif tide_wave_left <= 0.0:
			## 未清完：全場 % 傷
			var p := get_unit(player_id)
			if p and p.is_alive():
				var dmg := maxi(1, int(p.max_hp * 0.18))
				var dealt := p.take_damage(dmg)
				_emit("tide_wave_fail", {"damage": dealt, "hp": p.hp, "max_hp": p.max_hp})
				if p.hp <= 0:
					_check_end()
			_kill_all_polyps()
			tide_wave_active = false
			tide_summon_cd = TIDE_SUMMON_INTERVAL
		return
	tide_summon_cd -= dt
	if tide_summon_cd <= 0.0:
		_tide_summon_wave()


func _count_polyps() -> int:
	var n := 0
	for id in ["polyp_0", "polyp_1", "polyp_2"]:
		var u := get_unit(id)
		if u and u.is_alive():
			n += 1
	return n


func _kill_all_polyps() -> void:
	for id in ["polyp_0", "polyp_1", "polyp_2"]:
		var u := get_unit(id)
		if u and u.is_alive():
			u.hp = 0
			u.state = BattleUnit.State.DEAD
			_emit("unit_dead", {"id": id})


## 玩家出手一次要多久（ATB 從 0 填滿）。刺胞波的時限照這個算。
func _player_attack_cycle() -> float:
	var p := get_unit(player_id)
	var sp := p.speed if p != null else 10.0
	var fill := Formulas.atb_fill_per_sec(sp)
	if fill <= 0.0:
		return 4.0
	return ATB_MAX / fill


func _tide_wave_time() -> float:
	return maxf(6.0, _player_attack_cycle() * TIDE_CLEAR_CYCLES)


func _tide_summon_wave() -> void:
	tide_wave_active = true
	tide_wave_left = _tide_wave_time()
	tide_player_swings = 0
	tide_summon_cd = 999.0
	for i in 3:
		var id := "polyp_%d" % i
		var u := get_unit(id)
		if u == null:
			u = BattleUnit.new()
			u.id = id
			u.display_name = "黑焰刺胞"
			u.team = BattleUnit.Team.ENEMY
			u.is_boss = false
			## 一刀一隻。原本 45 血在通關等級要兩刀才死，三隻就要六刀，
			## 而時限只給得起三、四刀 —— 那不是難，是算不出來。
			u.max_hp = 30
			u.atk = 6
			u.defense = 2
			u.speed = 14.0
			u.windup_time = 0.2
			u.recover_time = 0.35
			add_unit(u)
		u.hp = u.max_hp
		u.state = BattleUnit.State.IDLE
		u.atb = float(i) * 20.0
	_emit("tide_summon", {"count": 3, "time": _tide_wave_time()})
	## 玩家優先打刺胞
	var p := get_unit(player_id)
	if p:
		p.target_id = "polyp_0"


# ── 裂縫·石像 ──

func _statue_filter_damage(target: BattleUnit, dmg: int) -> int:
	if target.id == "echo":
		return dmg if statue_body_spawned else 0
	if target.id.begins_with("statue_"):
		var idx := int(target.id.get_slice("_", 1))
		if idx != statue_active_idx:
			_emit("statue_block", {"id": target.id})
			return 0
		return dmg
	return dmg


func _step_statue(dt: float) -> void:
	if finished:
		return
	if not statue_body_spawned:
		var alive_n := 0
		for id in STATUE_IDS:
			var s := get_unit(id)
			if s and s.is_alive():
				alive_n += 1
		if alive_n <= 0:
			_spawn_echo_body()
			return
		statue_rotate_cd -= dt
		if statue_rotate_cd <= 0.0:
			statue_rotate_cd = STATUE_ROTATE_INTERVAL
			## 輪到下一尊仍活著的
			for _i in 3:
				statue_active_idx = (statue_active_idx + 1) % 3
				var cand := get_unit(STATUE_IDS[statue_active_idx])
				if cand and cand.is_alive():
					break
			for i in 3:
				var st := get_unit(STATUE_IDS[i])
				if st and st.is_alive():
					st.vulnerable = (i == statue_active_idx)
			_emit("statue_active", {"idx": statue_active_idx, "id": STATUE_IDS[statue_active_idx]})
			_statue_retarget_player()


func _statue_retarget_player() -> void:
	var p := get_unit(player_id)
	if p == null:
		return
	if statue_body_spawned:
		var e := get_unit("echo")
		if e and e.is_alive():
			p.target_id = "echo"
		return
	var aid := STATUE_IDS[statue_active_idx]
	var a := get_unit(aid)
	if a and a.is_alive():
		p.target_id = aid
	else:
		for id in STATUE_IDS:
			var s := get_unit(id)
			if s and s.is_alive():
				p.target_id = id
				break


func _spawn_echo_body() -> void:
	statue_body_spawned = true
	var e := get_unit("echo")
	if e == null:
		e = BattleUnit.new()
		e.id = "echo"
		e.display_name = "石像殘響"
		e.team = BattleUnit.Team.ENEMY
		e.is_boss = true
		e.max_hp = 160
		e.atk = 14
		e.defense = 8
		e.speed = 9.0
		e.windup_time = 0.28
		e.recover_time = 0.4
		add_unit(e)
	e.hp = e.max_hp
	e.state = BattleUnit.State.IDLE
	e.vulnerable = true
	_emit("echo_spawn", {"hp": e.hp, "max_hp": e.max_hp})
	_statue_retarget_player()


# ── 裂縫·時牢 ──

func _step_chrono_extra(dt: float) -> void:
	## 副機制：在炸彈 idle 時插入落岩安全區
	if not chrono_mode or finished:
		return
	if hazard_kind != "bomb" or hazard_phase != "idle" or _chrono_pending_rock:
		return
	chrono_rock_cd -= dt
	if chrono_rock_cd > 0.0:
		return
	chrono_rock_cd = 9.5
	_chrono_pending_rock = true
	hazard_kind = "rockfall"
	hazard_phase = "warn"
	hazard_timer = _hazard_warn_time()
	hazard_reacted = false
	_emit("hazard_warn", {"kind": "rockfall", "warn": hazard_timer, "chrono_side": true})


func _check_end() -> void:
	if finished:
		return
	var pl := living_of(BattleUnit.Team.PLAYER)
	if pl.is_empty():
		finished = true
		won = false
		battle_ended.emit(false)
		_emit("battle_end", {"won": false})
		return
	if fog_mode:
		var real_u := get_unit("white_fog")
		if real_u == null or not real_u.is_alive():
			## 殺幻影不算贏；本體死才贏
			finished = true
			won = true
			battle_ended.emit(true)
			_emit("battle_end", {"won": true})
		return
	if tide_mode:
		var tb := get_unit("tide")
		if tb == null or not tb.is_alive():
			finished = true
			won = true
			battle_ended.emit(true)
			_emit("battle_end", {"won": true})
		return
	if statue_mode:
		if not statue_body_spawned:
			var any_s := false
			for id in STATUE_IDS:
				var s := get_unit(id)
				if s and s.is_alive():
					any_s = true
					break
			if not any_s:
				_spawn_echo_body()
			return
		var ec := get_unit("echo")
		if ec == null or not ec.is_alive():
			finished = true
			won = true
			battle_ended.emit(true)
			_emit("battle_end", {"won": true})
		return
	var en := living_of(BattleUnit.Team.ENEMY)
	if en.is_empty():
		finished = true
		won = true
		battle_ended.emit(true)
		_emit("battle_end", {"won": true})


## NG+：放大敵方 HP／ATK，並略縮短機制窗
static func apply_ng_plus(sim: BattleSim, mult: float) -> BattleSim:
	if sim == null or mult <= 1.001:
		return sim
	sim.ng_scale_applied = true
	sim.ng_tight_hazards = true
	for u in sim.units.values():
		if u.team != BattleUnit.Team.ENEMY:
			continue
		u.max_hp = maxi(1, int(round(float(u.max_hp) * mult)))
		u.hp = u.max_hp
		u.atk = maxi(1, int(ceil(float(u.atk) * mult)))
	return sim


## 工廠：教學狼
static func make_tutorial_wolf_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 50))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 14))
	p.defense = int(player_stats.get("def", 5))
	p.speed = float(player_stats.get("speed", 10))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var w := BattleUnit.new()
	w.id = "wolf"
	w.display_name = "渣滓之狼"
	w.team = BattleUnit.Team.ENEMY
	w.max_hp = 45
	w.hp = 45
	w.atk = 7
	w.defense = 2
	w.speed = 11.0
	sim.add_unit(w)
	return sim


static func make_leo_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 80))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 22))
	p.defense = int(player_stats.get("def", 8))
	p.speed = float(player_stats.get("speed", 11))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var leo := BattleUnit.new()
	leo.id = "leo"
	leo.display_name = "聖獅·雷歐"
	leo.team = BattleUnit.Team.ENEMY
	leo.is_boss = true
	## 垂直切片數值（完整版再拉到 ~800）
	leo.max_hp = 420
	leo.hp = 420
	leo.atk = 14
	leo.defense = 10
	leo.speed = 9.0
	leo.windup_time = 0.3
	leo.recover_time = 0.45
	leo.king_slash_cd = 2.5  ## 進半血後首發前的冷卻
	sim.add_unit(leo)
	sim.setup_hazard("fire_ring", 5.5)  ## 副機制：火圈閃避
	return sim


static func make_falcon_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.falcon_mode = true
	sim.falcon_stop_cd = 2.0
	sim.falcon_stop_left = 0.0
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 90))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 28))
	p.defense = int(player_stats.get("def", 9))
	p.speed = float(player_stats.get("speed", 13))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var f := BattleUnit.new()
	f.id = "falcon"
	f.display_name = "疾影"
	f.team = BattleUnit.Team.ENEMY
	f.is_boss = true
	f.max_hp = 400
	f.hp = 400
	f.atk = 14
	f.defense = 8
	f.speed = 16.0
	f.windup_time = 0.2
	f.recover_time = 0.35
	sim.add_unit(f)
	sim.setup_hazard("wind_cut", 4.5)
	return sim


static func make_boar_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.boar_mode = true
	sim.boar_armor = BOAR_ARMOR_MAX
	sim.boar_charge_cd = 3.5
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 95))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 28))
	p.defense = int(player_stats.get("def", 10))
	p.speed = float(player_stats.get("speed", 11))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var b := BattleUnit.new()
	b.id = "boar"
	b.display_name = "石拳"
	b.team = BattleUnit.Team.ENEMY
	b.is_boss = true
	## 建議 30+，原本 Lv8 就有 38% 勝率
	b.max_hp = 1150
	b.hp = 1150
	## 建議 30+；atk 16 時 Lv20 是 100% 勝率
	b.atk = 26
	b.defense = 14
	b.speed = 7.5
	b.windup_time = 0.35
	b.recover_time = 0.5
	sim.add_unit(b)
	sim.setup_hazard("rockfall", 5.0)
	return sim


## 通關後裂縫·甲「怒火」：密火圈 + 灼燒疊層
static func make_wrath_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.wrath_mode = true
	sim.burn_stacks = 0
	var p := _rift_player(player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var w := BattleUnit.new()
	w.id = "wrath"
	w.display_name = "無臉·怒火"
	w.team = BattleUnit.Team.ENEMY
	w.is_boss = true
	## 通關後裂縫，原本 Lv12 就 100%
	w.max_hp = 1200
	w.hp = 1200
	## 通關後裂縫；atk 15 時 Lv20 是 98% 勝率
	w.atk = 21
	w.defense = 11
	w.speed = 10.0
	w.windup_time = 0.28
	w.recover_time = 0.42
	w.king_slash_cd = 3.0
	sim.add_unit(w)
	sim.setup_hazard("fire_ring", 2.2)
	return sim


static func _apply_player_skill_stats(p: BattleUnit, player_stats: Dictionary) -> void:
	p.can_skill = bool(player_stats.get("can_skill", true))
	var slash_lv: int = maxi(1, int(player_stats.get("slash_lv", 1)))
	var default_mult: float = 1.8 + 0.12 * float(slash_lv - 1)
	if player_stats.has("skill_mult"):
		p.skill_mult = float(player_stats.get("skill_mult", default_mult))
	else:
		p.skill_mult = default_mult
	p.skill_name = str(player_stats.get("skill_name", "橫斬"))
	p.skill_id = str(player_stats.get("skill_id", "slash"))
	p.skill_kind = str(player_stats.get("skill_kind", "attack"))
	p.heal_pct = float(player_stats.get("heal_pct", 0.0))
	## 爆擊／傷害浮動（對齊 DataTables + 裝備）
	p.crit = float(player_stats.get("crit", Formulas.default_player_crit()))
	p.crit_dmg = float(player_stats.get("crit_dmg", Formulas.default_crit_dmg()))
	p.dmg_variance = float(player_stats.get("dmg_variance", Formulas.default_variance()))


static func _rift_player(player_stats: Dictionary) -> BattleUnit:
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 100))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 32))
	p.defense = int(player_stats.get("def", 11))
	p.speed = float(player_stats.get("speed", 12))
	_apply_player_skill_stats(p, player_stats)
	return p


## 裂縫·乙「潮噬」
static func make_tide_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.tide_mode = true
	sim.tide_summon_cd = 2.5
	sim.tide_phase_cd = 3.0
	sim.tide_phase_skill = false
	var p := _rift_player(player_stats)
	sim.add_unit(p)
	sim.player_id = p.id
	var t := BattleUnit.new()
	t.id = "tide"
	t.display_name = "無臉·潮噬"
	t.team = BattleUnit.Team.ENEMY
	t.is_boss = true
	t.max_hp = 480
	t.hp = 480
	t.atk = 13
	t.defense = 10
	t.speed = 9.0
	t.windup_time = 0.3
	t.recover_time = 0.45
	sim.add_unit(t)
	return sim


## 裂縫·丙「石像殘響」
static func make_statue_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.statue_mode = true
	sim.statue_active_idx = 0
	sim.statue_rotate_cd = 2.0
	sim.statue_body_spawned = false
	var p := _rift_player(player_stats)
	sim.add_unit(p)
	sim.player_id = p.id
	for i in 3:
		var s := BattleUnit.new()
		s.id = "statue_%d" % i
		s.display_name = "黑焰石像·%s" % ["甲", "乙", "丙"][i]
		s.team = BattleUnit.Team.ENEMY
		s.is_boss = false
		## 三尊石像。原本各 120，Lv20 就 92% 勝率
		s.max_hp = 300
		s.hp = 300
		s.atk = 10
		s.defense = 12
		s.speed = 7.0 + float(i)
		s.windup_time = 0.35
		s.recover_time = 0.5
		s.vulnerable = (i == 0)
		sim.add_unit(s)
	p.target_id = "statue_0"
	sim.setup_hazard("rockfall", 4.0)
	return sim


## 裂縫·丁「時牢」
static func make_chrono_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.chrono_mode = true
	sim.chrono_rock_cd = 5.0
	var p := _rift_player(player_stats)
	sim.add_unit(p)
	sim.player_id = p.id
	var c := BattleUnit.new()
	c.id = "chrono"
	c.display_name = "無臉·時牢"
	c.team = BattleUnit.Team.ENEMY
	c.is_boss = true
	## 通關後裂縫，原本 Lv12 就 100%
	c.max_hp = 1150
	c.hp = 1150
	## 通關後裂縫；atk 14 時 Lv20 是 100% 勝率
	c.atk = 20
	c.defense = 11
	c.speed = 9.5
	c.windup_time = 0.3
	c.recover_time = 0.42
	c.king_slash_cd = 4.0
	sim.add_unit(c)
	sim.setup_hazard("bomb", 2.8)
	return sim


static func make_abo_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.abo_mode = true
	sim.abo_guard = 0.0
	sim.abo_broken_left = 0.0
	sim.abo_break_count = 0
	sim.abo_heart_score = 0
	sim.abo_slam_cd = 1.5
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 85))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 26))
	p.defense = int(player_stats.get("def", 9))
	p.speed = float(player_stats.get("speed", 11))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var abo := BattleUnit.new()
	abo.id = "abo"
	abo.display_name = "阿波熊貓"
	abo.team = BattleUnit.Team.ENEMY
	abo.is_boss = true
	## 建議 26+，原本 Lv16 就有 72% 勝率
	abo.max_hp = 950
	abo.hp = 950
	abo.atk = 12
	abo.defense = 18  ## 架勢中高防；破防後大降
	abo.speed = 8.0
	abo.windup_time = 0.32
	abo.recover_time = 0.5
	sim.add_unit(abo)
	sim.abo_base_defense = abo.defense
	return sim


static func make_demon_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.demon_mode = true
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 90))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 28))
	p.defense = int(player_stats.get("def", 10))
	p.speed = float(player_stats.get("speed", 12))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var demon := BattleUnit.new()
	demon.id = "demon"
	demon.display_name = "魔王"
	demon.team = BattleUnit.Team.ENEMY
	demon.is_boss = true
	## 終章魔王。原本 520 血，Lv8 的玩家 22 刀就砍完（每刀約 23）——
	## 六章的建議等級形同虛設。血量對到 Lv30 的輸出：約 22 刀。
	demon.max_hp = 1250
	demon.hp = 1250
	## 攻擊力也要對到建議等級。只加血量的話仗會變長但打不死人 ——
	## 量過：血量翻倍之後 Lv20 仍然 100% 過關，因為玩家一路都在挨不痛的打。
	## 終章魔王要比石拳再高一點，不然最後一戰比前一章還軟。
	demon.atk = 28
	demon.defense = 11
	demon.speed = 10.0
	demon.windup_time = 0.28
	demon.recover_time = 0.42
	demon.king_slash_cd = 4.0
	sim.add_unit(demon)
	sim.setup_hazard("time_clock", 6.0)  ## 副機制：控時時鐘
	return sim


static func make_fog_fight(player_stats: Dictionary) -> BattleSim:
	var sim := BattleSim.new()
	sim.fog_mode = true
	sim.fog_vuln_cd = 1.2  ## 開場稍後第一次破綻
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 80))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 24))
	p.defense = int(player_stats.get("def", 8))
	p.speed = float(player_stats.get("speed", 11))
	_apply_player_skill_stats(p, player_stats)
	p.target_id = "white_fog"
	sim.add_unit(p)
	sim.player_id = p.id

	var real_u := BattleUnit.new()
	real_u.id = "white_fog"
	real_u.display_name = "白霧（本體）"
	real_u.team = BattleUnit.Team.ENEMY
	real_u.is_boss = true
	real_u.is_fog_real = true
	## 白霧是第二章的王，世界地圖上標「建議 18+」。
	## 380 血的時候實測要 Lv30 才打得贏（Lv20 打出 283 就先倒了）——
	## 玩家照著指示在 18 級來，會撞上一場數字上贏不了的仗。
	##
	## 240 是量出來的：測試模型裡的玩家只有等級成長＋鍛造武器，
	## 沒有戰魂也沒有裝備，所以這個數字對真正的玩家是偏保守的。
	## 對一個「遊戲叫你來」的主線王，寧可鬆一點。
	real_u.max_hp = 240
	real_u.hp = 240
	real_u.atk = 13
	real_u.defense = 9
	real_u.speed = 12.0
	sim.add_unit(real_u)

	for pair in [["phantom_a", "幻影甲", Vector2()], ["phantom_b", "幻影乙", Vector2()]]:
		var ph := BattleUnit.new()
		ph.id = str(pair[0])
		ph.display_name = str(pair[1])
		ph.team = BattleUnit.Team.ENEMY
		ph.is_phantom = true
		ph.max_hp = 999
		ph.hp = 999
		## 幻影是來騙你砍錯的，不是來輾血量的。原本兩隻加起來的輸出跟本體一樣多，
		## 於是「認出本體」這件事做對了也沒有回報。罰則留在砍中幻影的 35% 反噬上。
		ph.atk = 5
		ph.defense = 4
		ph.speed = 11.0 + rng_offset(sim)
		sim.add_unit(ph)
	return sim


static func rng_offset(sim: BattleSim) -> float:
	return sim.rng.randf_range(-1.0, 1.5)


## 廣域雜魚／秘境小 Boss（定義來自 WorldContent.enemy_def）
static func make_world_fight(player_stats: Dictionary, mode: String) -> BattleSim:
	var def: Dictionary = {}
	## 避免 class 依賴循環：用字串路徑 preload
	var WC = load("res://scripts/world/world_content.gd")
	if WC:
		def = WC.enemy_def(mode)
	if def.is_empty():
		return make_tutorial_wolf_fight(player_stats)

	var sim := BattleSim.new()
	var p := BattleUnit.new()
	p.id = "player"
	p.display_name = str(player_stats.get("name", "兔勇者"))
	p.team = BattleUnit.Team.PLAYER
	p.max_hp = int(player_stats.get("max_hp", 80))
	p.hp = int(player_stats.get("hp", p.max_hp))
	p.atk = int(player_stats.get("atk", 20))
	p.defense = int(player_stats.get("def", 8))
	p.speed = float(player_stats.get("speed", 11))
	_apply_player_skill_stats(p, player_stats)
	sim.add_unit(p)
	sim.player_id = p.id

	var e := BattleUnit.new()
	e.id = str(def.get("id", mode))
	e.display_name = str(def.get("name", mode))
	e.team = BattleUnit.Team.ENEMY
	e.is_boss = bool(def.get("is_boss", false))
	e.max_hp = int(def.get("max_hp", 60))
	e.hp = e.max_hp
	e.atk = int(def.get("atk", 10))
	e.defense = int(def.get("def", 4))
	e.speed = float(def.get("speed", 10.0))
	if e.is_boss:
		e.windup_time = float(def.get("windup", 0.3))
		e.recover_time = float(def.get("recover", 0.45))
		e.king_slash_cd = float(def.get("king_slash_cd", 3.0))
	sim.add_unit(e)

	var hz := str(def.get("hazard", ""))
	if hz != "":
		sim.setup_hazard(hz, float(def.get("hazard_cd", 4.5)))
	return sim
