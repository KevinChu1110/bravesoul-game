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

## 武器風姿（秒）
var windup_time: float = 0.25
var recover_time: float = 0.40
var dmg_variance: float = 0.0

## 技能
var can_skill: bool = false
var skill_mult: float = 1.8
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
	if atb_slow_left > 0.0:
		return 0.45
	return 1.0


func tick_status(dt: float) -> void:
	if atb_slow_left > 0.0:
		atb_slow_left = maxf(0.0, atb_slow_left - dt)
	if atb_freeze_left > 0.0:
		atb_freeze_left = maxf(0.0, atb_freeze_left - dt)
	if atk_buff_left > 0.0:
		atk_buff_left = maxf(0.0, atk_buff_left - dt)
		if atk_buff_left <= 0.0:
			atk_buff_mult = 1.0


func take_damage(amount: int) -> int:
	var dealt := mini(hp, maxi(0, amount))
	hp -= dealt
	if dealt > 0:
		rage = mini(100.0, rage + float(Formulas.rage_from_damage(dealt, max_hp)))
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
