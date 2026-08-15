class_name Formulas
extends RefCounted
## 純函式傷害／命中／爆擊（可單測）
## 數值表：DataTables.combat（若可用）


static func _tbl(path: String, default: float) -> float:
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		if dt and dt.has_method("combat_f"):
			return float(dt.call("combat_f", path, default))
	return default


static func miss_chance(atk_spd: float, def_spd: float, hit: float, eva: float) -> int:
	var spd_term := 0.0
	var diff := def_spd - atk_spd
	if diff > 0.0:
		spd_term = floor(sqrt(5.0 * diff))
	var cap := _tbl("hit.miss_cap", 95.0)
	return int(clampf(spd_term + eva - hit, 0.0, cap))


static func normal_damage(atk: float, defense: float) -> int:
	var def_f := _tbl("damage.normal_def_factor", 0.35)
	var raw := atk * 1.0 - defense * def_f
	var mn := int(_tbl("damage.min_damage", 1.0))
	return maxi(mn, int(round(raw)))


static func skill_damage(atk: float, defense: float, mult: float) -> int:
	var def_f := _tbl("damage.skill_def_factor", 0.25)
	var raw := atk * mult - defense * def_f
	var mn := int(_tbl("damage.min_damage", 1.0))
	return maxi(mn, int(round(raw)))


## 浮動：variance 0~1 比例；rng 可傳 null 用預設無隨機（取中）
static func apply_variance(dmg: int, variance: float, rng: RandomNumberGenerator = null) -> int:
	var mn := int(_tbl("damage.min_damage", 1.0))
	var vmax := _tbl("damage.variance_max", 0.25)
	var v := clampf(variance, 0.0, vmax)
	if v <= 0.001 or rng == null:
		return maxi(mn, dmg)
	var mult := 1.0 + rng.randf_range(-v, v)
	return maxi(mn, int(round(float(dmg) * mult)))


## 爆擊判定：回傳 {damage, crit}
static func apply_crit(dmg: int, crit_rate: float, crit_resist: float, crit_dmg_pct: float, rng: RandomNumberGenerator) -> Dictionary:
	var rmin := _tbl("crit.rate_min", 0.0)
	var rmax := _tbl("crit.rate_max", 75.0)
	var dmin := _tbl("crit.dmg_min", 25.0)
	var dmax := _tbl("crit.dmg_max", 200.0)
	var eff := clampf(crit_rate - crit_resist, rmin, rmax)
	var cd := clampf(crit_dmg_pct, dmin, dmax)
	var is_crit := rng.randi_range(1, 100) <= int(eff)
	var out := dmg
	if is_crit:
		out = int(round(float(dmg) * (1.0 + cd / 100.0)))
	return {"damage": maxi(1, out), "crit": is_crit}


## 完整一擊：基礎 → 浮動 → 爆擊
static func roll_hit_damage(
	atk: float,
	defense: float,
	skill_mult: float,
	variance: float,
	crit_rate: float,
	crit_resist: float,
	crit_dmg_pct: float,
	rng: RandomNumberGenerator,
	is_skill: bool = false
) -> Dictionary:
	var base := skill_damage(atk, defense, skill_mult) if is_skill else normal_damage(atk, defense)
	var floated := apply_variance(base, variance, rng)
	var rolled: Dictionary = apply_crit(floated, crit_rate, crit_resist, crit_dmg_pct, rng)
	rolled["base"] = base
	rolled["floated"] = floated
	return rolled


static func atb_fill_per_sec(speed: float) -> float:
	var fill := _tbl("atb.fill_base", 25.0)
	var sc := _tbl("atb.speed_scale", 0.04)
	var lo := _tbl("atb.speed_floor", 0.5)
	var hi := _tbl("atb.speed_ceil", 2.0)
	return fill * clampf(0.6 + speed * sc, lo, hi)


## 出手命中累積的戰意。
##
## 原本戰意「只」在受傷時累積（見下面的 rage_from_damage），而那個公式要求
## 累計承受 2.5 倍自身最大生命才會滿——玩家在 1.0 倍就死了。實測 3000 場模擬，
## 單機玩家的技能施放次數一律是 0：七招、熟練度、灰鬚指點、演武場練功
## 整條「旅途養招」的養成柱是死的，而教學還在教「怒氣滿了自動放招」。
##
## 改成出手也給，約七刀滿一次，雜魚戰放得出一次、Boss 戰放得出數次。
## 只有 can_skill 的單位吃得到，而 can_skill 目前只有玩家會設。
static func rage_from_strike() -> float:
	return _tbl("rage.per_strike", 14.0)


static func rage_from_damage(dmg: int, max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	return mini(40, int(40.0 * float(dmg) / float(max_hp)))


static func default_player_crit() -> float:
	return _tbl("crit.base_player", 5.0)


static func default_crit_dmg() -> float:
	return _tbl("crit.base_crit_dmg", 50.0)


static func default_variance() -> float:
	return _tbl("damage.variance_default", 0.08)
