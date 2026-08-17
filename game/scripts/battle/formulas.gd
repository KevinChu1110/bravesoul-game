class_name Formulas
extends RefCounted
## 純函式傷害／命中／爆擊／時間模型／姿態（可單測）
## 數值表：DataTables.combat（若可用）
##
## 時間模型鎖版 0.15 —— 見 combat.json → time_model
##   speed10：ATB 4.0s/刀基線；+ windup/recover ≈ 4.5～4.8s 完整週期
##   怒氣：每刀 +14 → 約 8 刀滿；實戰首次技目標 ~25–35s


static func _tbl(path: String, default: float) -> float:
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		if dt and dt.has_method("combat_f"):
			return float(dt.call("combat_f", path, default))
	return default


static func _combat_root() -> Dictionary:
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		if dt != null:
			## 不要用 `"combat" in dt`：Node 上 in 對 script 變數不可靠
			var c: Variant = dt.get("combat")
			if c is Dictionary and not (c as Dictionary).is_empty():
				return c as Dictionary
	return {}


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


## ATB 從 0 填滿所需秒數（不含 windup／recover）
static func atb_seconds_to_full(speed: float) -> float:
	var rate := atb_fill_per_sec(speed)
	if rate <= 0.001:
		return 999.0
	var atb_max := _tbl("time_model.atb_max", 100.0)
	return atb_max / rate


## 出手命中累積的戰意。
##
## 原本戰意「只」在受傷時累積（見下面的 rage_from_damage），而那個公式要求
## 累計承受 2.5 倍自身最大生命才會滿——玩家在 1.0 倍就死了。實測 3000 場模擬，
## 單機玩家的技能施放次數一律是 0：七招、熟練度、灰鬚指點、演武場練功
## 整條「旅途養招」的養成柱是死的，而教學還在教「怒氣滿了自動放招」。
##
## 改成出手也給，約八刀滿一次（14×7=98 未滿 100），雜魚戰放得出一次、Boss 戰放得出數次。
## 只有 can_skill 的單位吃得到，而 can_skill 目前只有玩家會設。
static func rage_from_strike() -> float:
	return _tbl("rage.per_strike", 14.0)


static func rage_from_damage(dmg: int, max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	var cap := int(_tbl("rage.from_damage_cap", 40.0))
	return mini(cap, int(float(cap) * float(dmg) / float(max_hp)))


static func default_player_crit() -> float:
	return _tbl("crit.base_player", 5.0)


static func default_crit_dmg() -> float:
	return _tbl("crit.base_crit_dmg", 50.0)


static func default_variance() -> float:
	return _tbl("damage.variance_default", 0.08)


# ── 姿態（虛擬距離）：遠距開闊／被壓、坦克常駐減傷 ──

const _RANGED_DEFAULT: Array[String] = ["bow", "gun", "magic", "dart", "crystal"]
const _TANK_DEFAULT: Array[String] = ["hammer", "crystal"]


static func _stance_class_list(key: String, fallback: Array[String]) -> Array[String]:
	var root := _combat_root()
	var st: Variant = root.get("stance", {})
	if st is Dictionary:
		var arr: Variant = (st as Dictionary).get(key, null)
		if arr is Array and not (arr as Array).is_empty():
			var out: Array[String] = []
			for x in arr as Array:
				out.append(str(x))
			return out
	return fallback


static func is_ranged_class(weapon_class: String) -> bool:
	if weapon_class.is_empty():
		return false
	return weapon_class in _stance_class_list("ranged_classes", _RANGED_DEFAULT)


static func is_tank_class(weapon_class: String) -> bool:
	if weapon_class.is_empty():
		return false
	return weapon_class in _stance_class_list("tank_classes", _TANK_DEFAULT)


static func pressure_duration() -> float:
	return _tbl("stance.pressure_duration", 3.5)


## 開闊遠距輸出加成（比例，0.12 = +12%）
static func ranged_open_dmg_bonus() -> float:
	return _tbl("stance.ranged_open_dmg_bonus", 0.12)


## 被壓時受傷倍率（1.18 = +18% 近身易傷）
static func ranged_pressured_taken_mult() -> float:
	return _tbl("stance.ranged_pressured_taken_mult", 1.18)


## 本場第一次受擊減傷比例（0.28 = 減 28%）
static func ranged_first_hit_mitigation() -> float:
	return _tbl("stance.ranged_first_hit_mitigation", 0.28)


## 坦克常駐受傷倍率
static func tank_taken_mult() -> float:
	return _tbl("stance.tank_taken_mult", 0.90)


## 遠距開闊時對輸出傷害的修正
static func scale_ranged_outgoing(weapon_class: String, pressure_left: float, dmg: int) -> int:
	if dmg <= 0 or not is_ranged_class(weapon_class):
		return dmg
	if pressure_left > 0.0:
		return dmg
	var b := ranged_open_dmg_bonus()
	if b <= 0.0:
		return dmg
	return maxi(1, int(round(float(dmg) * (1.0 + b))))


## 玩家受傷前的姿態修正（回傳調整後傷害；呼叫端需同步 first_hit_guard / pressure）
## 回傳 {damage, pressure, first_hit_guard}
static func apply_player_incoming_stance(
	weapon_class: String,
	pressure_left: float,
	first_hit_guard: bool,
	raw_dmg: int
) -> Dictionary:
	var dmg := raw_dmg
	var pressure := pressure_left
	var guard := first_hit_guard
	if dmg <= 0:
		return {"damage": dmg, "pressure": pressure, "first_hit_guard": guard}

	var mult := 1.0
	if is_tank_class(weapon_class):
		mult *= tank_taken_mult()

	if is_ranged_class(weapon_class):
		if guard:
			mult *= (1.0 - clampf(ranged_first_hit_mitigation(), 0.0, 0.9))
			guard = false
		elif pressure > 0.0:
			mult *= ranged_pressured_taken_mult()
		pressure = pressure_duration()

	var out := maxi(0, int(round(float(dmg) * mult)))
	## 有實傷時至少 1（與 min_damage 精神一致）；全減傷到 0 才允許 0
	if dmg > 0 and out <= 0 and mult > 0.0:
		out = 1
	return {"damage": out, "pressure": pressure, "first_hit_guard": guard}


## 讀取流派風姿（秒）。優先 combat.json；缺表時用內建 default（與 0.15 鎖版對齊）。
static func weapon_tempo(weapon_class: String) -> Dictionary:
	## 內建表：即使 DataTables 尚未就緒，測試與無頭模擬仍有正確風姿
	var builtin: Dictionary = {
		"sword": {"windup": 0.25, "recover": 0.40},
		"bow": {"windup": 0.30, "recover": 0.38},
		"gun": {"windup": 0.42, "recover": 0.55},
		"magic": {"windup": 0.32, "recover": 0.42},
		"dart": {"windup": 0.18, "recover": 0.28},
		"dagger": {"windup": 0.16, "recover": 0.26},
		"fist": {"windup": 0.20, "recover": 0.32},
		"claw": {"windup": 0.18, "recover": 0.30},
		"axe": {"windup": 0.35, "recover": 0.50},
		"hammer": {"windup": 0.36, "recover": 0.52},
		"spear": {"windup": 0.28, "recover": 0.42},
		"crystal": {"windup": 0.28, "recover": 0.45},
	}
	var base: Dictionary = {"windup": 0.25, "recover": 0.40}
	if builtin.has(weapon_class):
		base = (builtin[weapon_class] as Dictionary).duplicate()
	if weapon_class.is_empty():
		return base
	## combat.json 可覆寫（_tbl 對巢狀 float 可靠）
	var wu := _tbl("weapon_tempo.%s.windup" % weapon_class, base["windup"])
	var rc := _tbl("weapon_tempo.%s.recover" % weapon_class, base["recover"])
	return {"windup": wu, "recover": rc}
