class_name BattleUnit
extends RefCounted

enum Team { PLAYER, ENEMY }
enum State { IDLE, WINDUP, STRIKE, RECOVER, CAST, DEAD }

var id: String = ""
var display_name: String = ""
var team: Team = Team.ENEMY
var max_hp: int = 10
var hp: int = 10
var atk: int = 5
var defense: int = 2
var speed: float = 10.0
var hit: float = 0.0
var eva: float = 0.0
var crit: float = 5.0
var crit_resist: float = 0.0
var crit_dmg: float = 50.0

var atb: float = 0.0
var rage: float = 0.0
var state: State = State.IDLE
var state_timer: float = 0.0
var target_id: String = ""

## 武器風姿（秒）—— 玩家由 combat.json weapon_tempo 寫入
var windup_time: float = 0.25
var recover_time: float = 0.40
var dmg_variance: float = 0.0

## 武器流派 id（sword/bow/gun/…）；驅動姿態與風姿
var weapon_class: String = ""
## 遠距「被壓」剩餘秒數（>0 = 近身易傷、無開闊輸出加成）
var pressure_left: float = 0.0
## 本場第一次受擊尚可減傷（遠距疾走／反應窗）
var first_hit_guard: bool = true

## 技能
var can_skill: bool = false
var skill_mult: float = 1.8  ## 每段倍率（多段技為單段）
var skill_hits: int = 1  ## 多段攻擊段數
var skill_name: String = "橫斬"
var skill_id: String = "slash"
var skill_kind: String = "attack"  ## attack | heal
var heal_pct: float = 0.0

## BOSS
var is_boss: bool = false
var king_slash_cd: float = 0.0
var telegraph_active: bool = false
## 這次前搖玩家已經按過格擋了嗎。每次前搖開始時清掉。
## 「一次前搖只有一次機會」就靠這一格 —— 見 BattleSim.try_react()。
var parry_used: bool = false
var telegraph_timer: float = 0.0

## 部位破壞系統 (Part Break System)
## 單部位相容欄位（舊 Boss／測試）；多部位用 `parts`。
var has_part: bool = false
var part_name: String = ""
var part_max_hp: int = 0
var part_hp: int = 0
var part_broken: bool = false
## 多部位：[{id, name, max_hp, hp, broken, effect, material, ptype}]
## effect: "def_down" | "enrage" | "expose" | "slow_break"
## ptype: helmet | armor | boots | crown（原作分型）
var parts: Array = []
## 部位全破後本體易傷（對齊原作／boss.py）
var parts_all_broken_vuln: float = 1.0

## 暴怒覺醒 (Fury Awakening) — 原作：怒氣滿＝暴怒，屬性提升
var fury_active: bool = false
var fury_timer: float = 0.0
var fury_atb_mult: float = 1.4  ## 由 BattleSim 依 auto／manual 寫入

## 武器使用次數（原作：歸零→赤手）
var weapon_uses_left: int = -1  ## <0＝未啟用（敵／測試舊路徑）
var weapon_uses_max: int = 0
var bare_fisted: bool = false
var armed_atk: int = 0  ## 持武時的攻擊（赤手前快照）
var armed_weapon_class: String = ""
var armed_can_skill: bool = true

## 白霧戰
var is_phantom: bool = false
var is_fog_real: bool = false
var vulnerable: bool = false

## 狀態：減速／凍結 ATB（冰圈、控時失敗等）
var atb_slow_left: float = 0.0  ## >0 時 ATB 填充變慢
var atb_freeze_left: float = 0.0  ## >0 時 ATB 不漲
var atk_buff_left: float = 0.0
var atk_buff_mult: float = 1.0


func is_alive() -> bool:
	return state != State.DEAD and hp > 0


func atb_rate_mult() -> float:
	if atb_freeze_left > 0.0:
		return 0.0
	var mult: float = 0.45 if atb_slow_left > 0.0 else 1.0
	if fury_active:
		mult *= fury_atb_mult
	return mult


## 累積怒氣；剛滿回 true（給自動暴怒用）
func add_rage(amount: float, cap: float = 100.0) -> bool:
	if amount <= 0.0:
		return false
	var before := rage
	rage = minf(cap, rage + amount)
	return before < cap and rage >= cap


func tick_status(dt: float) -> void:
	if atb_slow_left > 0.0:
		atb_slow_left = maxf(0.0, atb_slow_left - dt)
	if atb_freeze_left > 0.0:
		atb_freeze_left = maxf(0.0, atb_freeze_left - dt)
	if atk_buff_left > 0.0:
		atk_buff_left = maxf(0.0, atk_buff_left - dt)
		if atk_buff_left <= 0.0:
			atk_buff_mult = 1.0
	if pressure_left > 0.0:
		pressure_left = maxf(0.0, pressure_left - dt)
	if fury_active:
		fury_timer = maxf(0.0, fury_timer - dt)
		if fury_timer <= 0.0:
			fury_active = false


## 遠距開闊輸出加成（被壓時無）
func scale_outgoing(dmg: int) -> int:
	return Formulas.scale_ranged_outgoing(weapon_class, pressure_left, dmg)


func take_damage(amount: int) -> int:
	var incoming := amount
	## 玩家：坦克減傷／遠距第一次減傷／被壓易傷，並刷新被壓計時
	if team == Team.PLAYER and amount > 0:
		var st: Dictionary = Formulas.apply_player_incoming_stance(
			weapon_class, pressure_left, first_hit_guard, amount
		)
		incoming = int(st.get("damage", amount))
		pressure_left = float(st.get("pressure", pressure_left))
		first_hit_guard = bool(st.get("first_hit_guard", first_hit_guard))
	var dealt := mini(hp, maxi(0, incoming))
	hp -= dealt
	if dealt > 0:
		add_rage(float(Formulas.rage_from_damage(dealt, max_hp)), 100.0)
	if hp <= 0:
		hp = 0
		state = State.DEAD
		atb = 0.0
		telegraph_active = false
	return dealt


func heal_to_full() -> void:
	hp = max_hp
	if state == State.DEAD:
		state = State.IDLE
