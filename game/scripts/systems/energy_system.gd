extends Node
## 能量制（對齊原作「點擊開戰耗能量、自然恢復」）。
## Autoload：EnergySystem
## 參考 bravesoul BALANCE：上限 15、約 30 分＋1；一般 1／首領 3～5。

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const MAX_ENERGY := 15
const REGEN_SEC := 1800.0  ## 30 分鐘回 1
const COST_MOB := 1
const COST_BOSS := 3
const COST_ARENA_RUN := 1
const COST_HUNT_RUN := 1
const COST_VISIT := 0

## 主線大 Boss（耗首領能量）
const BOSS_MODES := {
	"leo": true, "fog": true, "abo": true, "falcon": true, "boar": true, "demon": true,
	"wrath": true, "tide": true, "statue": true, "chrono": true,
	"scar_lord": true, "mirror_wraith": true, "wreck_captain": true,
}


static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)


func _ready() -> void:
	refresh()


func _now() -> float:
	return Time.get_unix_time_from_system()


func refresh() -> void:
	if GameState.energy < 0:
		GameState.energy = MAX_ENERGY
	if GameState.energy_ts <= 0.0:
		GameState.energy_ts = _now()
		return
	if GameState.energy >= MAX_ENERGY:
		GameState.energy_ts = _now()
		return
	var elapsed := _now() - GameState.energy_ts
	if elapsed < REGEN_SEC:
		return
	var gained := int(elapsed / REGEN_SEC)
	if gained <= 0:
		return
	GameState.energy = mini(MAX_ENERGY, GameState.energy + gained)
	GameState.energy_ts += float(gained) * REGEN_SEC
	if GameState.energy >= MAX_ENERGY:
		GameState.energy_ts = _now()


func current() -> int:
	refresh()
	return GameState.energy


func seconds_to_next() -> float:
	refresh()
	if GameState.energy >= MAX_ENERGY:
		return 0.0
	var elapsed := _now() - GameState.energy_ts
	return maxf(0.0, REGEN_SEC - elapsed)


func cost_for_mode(mode: String) -> int:
	## 序章首戰免費，避免卡教學
	if mode == "wolf" and not GameState.has_flag("c0_first_battle"):
		return 0
	## 演武／獵場：開戰已在 start_run 扣過，波次不再扣
	if ArenaSystem and ArenaSystem.is_run_active():
		return 0
	if HuntSystem and HuntSystem.is_run_active():
		return 0
	## 好友挑戰不耗能量（原作）
	if VisitSystem and VisitSystem.pending_id() != "":
		return 0
	if BOSS_MODES.has(mode):
		return COST_BOSS
	## 廣域小王
	var WC = load("res://scripts/world/world_content.gd")
	if WC and WC.has_method("enemy_def"):
		var def: Dictionary = WC.enemy_def(mode)
		if bool(def.get("is_boss", false)):
			return COST_BOSS
	return COST_MOB


func try_spend_run(kind: String) -> Dictionary:
	## kind: arena | hunt
	var cost := COST_ARENA_RUN if kind == "arena" else COST_HUNT_RUN
	if can_afford(cost):
		spend(cost)
		return {"ok": true, "cost": cost, "msg": ""}
	return {
		"ok": false,
		"cost": cost,
		"msg": _t("能量不足，無法開始（需 %d，現有 %d／%d）。") % [cost, current(), MAX_ENERGY],
	}


func can_afford(cost: int) -> bool:
	return current() >= cost


func spend(cost: int) -> bool:
	if cost <= 0:
		return true
	refresh()
	if GameState.energy < cost:
		return false
	var was_full := GameState.energy >= MAX_ENERGY
	GameState.energy -= cost
	if was_full or GameState.energy_ts <= 0.0:
		GameState.energy_ts = _now()
	return true


func try_spend_for_battle(mode: String) -> Dictionary:
	## {ok, cost, msg}
	var cost := cost_for_mode(mode)
	if can_afford(cost):
		spend(cost)
		return {"ok": true, "cost": cost, "msg": ""}
	var wait_m := int(ceil(seconds_to_next() / 60.0))
	return {
		"ok": false,
		"cost": cost,
		"msg": _t("能量不足（需 %d，現有 %d／%d）。約 %d 分鐘後回復 1 點。") % [
			cost, current(), MAX_ENERGY, maxi(1, wait_m)
		],
	}


func grant(n: int) -> void:
	refresh()
	GameState.energy = mini(MAX_ENERGY, GameState.energy + maxi(0, n))
	if GameState.energy >= MAX_ENERGY:
		GameState.energy_ts = _now()


func status_line() -> String:
	refresh()
	if GameState.energy >= MAX_ENERGY:
		return _t("能量 %d／%d（已滿）") % [GameState.energy, MAX_ENERGY]
	var m := int(ceil(seconds_to_next() / 60.0))
	return _t("能量 %d／%d（約 %d 分後＋1）") % [GameState.energy, MAX_ENERGY, maxi(1, m)]
