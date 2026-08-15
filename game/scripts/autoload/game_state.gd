extends Node
## 全域進度：flags、主角數值、章節。垂直切片用最小集。

signal flags_changed(key: String, value: Variant)
signal gold_changed(amount: int)
signal chapter_changed(chapter: String)

## 存檔版本。改動存檔結構就 +1，並在 save_migration.gd 補一支對應的升級步驟。
const VERSION := 3

## 主線章節：title | c0 | c1 | c2 | c3 | c4 | c5 | c6 | cleared
var chapter: String = "title"

## 字串 flag → bool / int / String
var flags: Dictionary = {}

var player_name: String = "小白"
var level: int = 1
var xp: int = 0
var gold: int = 30

## 累積遊玩秒數。由 SaveManager 逐幀累加，只算真的在旅途上的時間。
## 存檔面板要靠它讓玩家分辨哪一格是自己投入比較久的那段。
var play_time: float = 0.0

## 武器流派 id（見 data/tables/weapon_classes.json）；與器／魂／招正交
## 舊存檔 sword|soul|iron 會對應到 sword|magic|hammer
var path_style: String = ""

## 簡易面板（之後接裝備／戰魂）
var max_hp: int = 50
var hp: int = 50
var atk: int = 10
var def_stat: int = 5
var speed: int = 10

## 武器顯示名
var weapon_name: String = "空手"
var weapon_atk: int = 0
var weapon_tier: int = 0

## 技能（招）
var skill_slash_lv: int = 0  ## 舊欄位：與 skill_data.slash.lv 同步
var skill_data: Dictionary = {}  ## id -> {lv, mastery}
var has_wheat_stalk: bool = false
var wheat_stalk_broken: bool = false

## 連敗升階（W4）
var forge_fail_streak: int = 0

## 戰魂
var stardust: int = 0  ## 星屑
var souls: Array = []  ## [{id,star,quality,level,equipped}]
var soul_slots: Array = []  ## 長度=槽數，元素=soul id 或 ""

## 背包／快捷欄（楓式）
var inventory: Dictionary = {}  ## item_id -> count
var hotbar: Array = ["", "", "", "", "", "", "", ""]  ## 8 格 item_id
## 可拖視窗位置 { "hud": {x,y}, "hotbar":…, "inv":…, "minimap":… }
var ui_layout: Dictionary = {}

## 裝備實例／倉庫（0.11）
var equip_bag: Array = []  ## 未裝備實例
var equip_worn: Dictionary = {}  ## uid -> inst
var equip_slots: Dictionary = {"weapon": "", "armor": "", "accessory": ""}
var warehouse: Dictionary = {}  ## item_id -> count
var warehouse_equip: Array = []  ## 裝備實例

## 角色爆擊基線（裝備再加成）
var crit_rate: float = 5.0
var crit_dmg: float = 50.0
var dmg_variance: float = 0.08

## 黑焰迴響（NG+ 輕量）：0＝通常；≥1 敵強化層數
var ng_plus: int = 0
## 沾焰：外觀黑邊 + 攻↑（可選）
var stain_flame: bool = false


func _ready() -> void:
	pass


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value
	flags_changed.emit(key, value)


func get_flag(key: String, default: Variant = false) -> Variant:
	return flags.get(key, default)


func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


func add_gold(n: int) -> void:
	gold = max(0, gold + n)
	gold_changed.emit(gold)


func set_chapter(c: String) -> void:
	chapter = c
	chapter_changed.emit(c)


func _equipped_weapon_line() -> String:
	var wuid := str(equip_slots.get("weapon", ""))
	if wuid == "" or not equip_worn.has(wuid):
		return ""
	return str((equip_worn[wuid] as Dictionary).get("line", ""))


func effective_atk() -> int:
	var a := atk + weapon_atk
	if stain_flame:
		a += 3
	a += soul_bonus_atk()
	a += equip_bonus_atk()
	var wb := weapon_class_bonuses()
	a += int(wb.get("atk", 0))
	## 裝備武器線與所選流派一致
	var wline := _equipped_weapon_line()
	var pid := _migrate_path_style(path_style)
	if wline != "" and wline == pid:
		a += 2
	return a


func effective_def() -> int:
	var d := def_stat + soul_bonus_def() + equip_bonus_def()
	var wb := weapon_class_bonuses()
	d += int(wb.get("def", 0))
	return d


func effective_max_hp() -> int:
	var h := max_hp + soul_bonus_hp() + equip_bonus_hp()
	var wb := weapon_class_bonuses()
	h += int(wb.get("hp", 0))
	return h


func effective_crit() -> float:
	var c := crit_rate + equip_bonus_crit()
	var wb := weapon_class_bonuses()
	c += float(wb.get("crit", 0))
	return c


func effective_crit_dmg() -> float:
	return crit_dmg + equip_bonus_crit_dmg()


func effective_variance() -> float:
	return dmg_variance


func equip_bonus_atk() -> int:
	return int(_equip_bonus().get("atk", 0))


func equip_bonus_def() -> int:
	return int(_equip_bonus().get("def", 0))


func equip_bonus_hp() -> int:
	return int(_equip_bonus().get("hp", 0))


func equip_bonus_crit() -> float:
	return float(_equip_bonus().get("crit", 0.0))


func equip_bonus_crit_dmg() -> float:
	return float(_equip_bonus().get("crit_dmg", 0.0))


func _equip_bonus() -> Dictionary:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var es: Node = (tree as SceneTree).root.get_node_or_null("EquipmentSystem")
		if es and es.has_method("bonus_totals"):
			return es.call("bonus_totals")
	return {"atk": 0, "def": 0, "hp": 0, "crit": 0.0, "crit_dmg": 0.0}


func soul_bonus_atk() -> int:
	var b: Dictionary = _soul_bonus_cached()
	return int(b.get("atk", 0))


func soul_bonus_def() -> int:
	var b: Dictionary = _soul_bonus_cached()
	return int(b.get("def", 0))


func soul_bonus_hp() -> int:
	var b: Dictionary = _soul_bonus_cached()
	return int(b.get("hp", 0))


func _soul_bonus_cached() -> Dictionary:
	## 避免循環依賴：有 SoulSystem 時用它
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var n: Node = (tree as SceneTree).root.get_node_or_null("SoulSystem")
		if n and n.has_method("total_equipped_bonus"):
			return n.call("total_equipped_bonus")
	return {"atk": 0, "def": 0, "hp": 0}


func add_stardust(n: int) -> void:
	stardust = maxi(0, stardust + n)


## 升級所需經驗（Lv1→2 約 50，之後緩升）
func xp_to_next() -> int:
	return 40 + level * 25 + (level * level) / 2


## 加經驗；回傳 {gained, levels, messages}
func add_xp(n: int) -> Dictionary:
	var gained := maxi(0, n)
	## 法／弓流派：經驗略增；鎚：升級偏血
	var pid := _migrate_path_style(path_style)
	if pid in ["magic", "bow", "dart"]:
		gained = int(round(float(gained) * 1.06))
	xp += gained
	var levels := 0
	var msgs: PackedStringArray = []
	while level < 40 and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		levels += 1
		## 成長：血必升；攻／防交錯
		max_hp += 4
		hp = mini(effective_max_hp(), hp + 4)
		if level % 2 == 0:
			atk += 1
		if level % 3 == 0:
			def_stat += 1
		if level % 5 == 0:
			crit_rate += 0.5
		if pid in ["hammer", "crystal"]:
			max_hp += 2
			hp = mini(effective_max_hp(), hp + 2)
		if pid in ["sword", "axe", "gun"] and level % 2 == 0:
			atk += 1
		msgs.append("等級提升 → Lv%d（HP %d · 攻 %d · 防 %d）" % [level, max_hp, atk, def_stat])
	return {"gained": gained, "levels": levels, "messages": msgs}


## 綜合戰力（路線建議／軟鎖用）
func power_score() -> int:
	var s := level * 3 + weapon_tier * 4 + effective_atk() + effective_def()
	s += int(effective_crit() / 2.0)
	if path_style != "":
		s += 2
	return s


func _migrate_path_style(p: String) -> String:
	match p:
		"soul":
			return "magic"
		"iron":
			return "hammer"
		_:
			return p


func path_display() -> String:
	var id := _migrate_path_style(path_style)
	if id == "":
		return "未選武器流派"
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		if dt and dt.has_method("weapon_class_def"):
			var d: Dictionary = dt.call("weapon_class_def", id)
			if not d.is_empty():
				return "%s·%s" % [str(d.get("name", id)), str(d.get("title", ""))]
	match id:
		"sword":
			return "劍·劍士"
		"bow":
			return "弓·遊俠"
		"magic":
			return "法·星法"
		"fist":
			return "拳·拳師"
		"axe":
			return "斧·斧衛"
		"hammer":
			return "鎚·鎚守"
		"spear":
			return "槍·槍騎"
		"gun":
			return "火槍·火銃"
		"dart":
			return "鏢·影鏢"
		"crystal":
			return "水晶·晶使"
		_:
			return id


func set_path_style(p: String) -> void:
	path_style = _migrate_path_style(p)


func weapon_class_bonuses() -> Dictionary:
	var id := _migrate_path_style(path_style)
	var out := {"atk": 0, "def": 0, "hp": 0, "crit": 0.0, "speed": 0}
	if id == "" or not (Engine.get_main_loop() is SceneTree):
		return out
	var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
	if dt == null or not dt.has_method("weapon_class_def"):
		return out
	var d: Dictionary = dt.call("weapon_class_def", id)
	if d.is_empty():
		return out
	out.atk = int(d.get("atk", 0))
	out.def = int(d.get("def", 0))
	out.hp = int(d.get("hp", 0))
	out.crit = float(d.get("crit", 0))
	out.speed = int(d.get("speed", 0))
	return out


## 敵強化倍率（NG0=1.0；1→1.15 … 上限約 1.30）
func ng_enemy_mult() -> float:
	if ng_plus <= 0:
		return 1.0
	return minf(1.30, 1.15 + 0.05 * float(ng_plus - 1))


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"chapter": chapter,
		"flags": flags.duplicate(true),
		"player_name": player_name,
		"level": level,
		"xp": xp,
		"path_style": path_style,
		"gold": gold,
		"play_time": play_time,
		"max_hp": max_hp,
		"hp": hp,
		"atk": atk,
		"def_stat": def_stat,
		"speed": speed,
		"weapon_name": weapon_name,
		"weapon_atk": weapon_atk,
		"weapon_tier": weapon_tier,
		"skill_slash_lv": skill_slash_lv,
		"skill_data": skill_data.duplicate(true),
		"has_wheat_stalk": has_wheat_stalk,
		"wheat_stalk_broken": wheat_stalk_broken,
		"forge_fail_streak": forge_fail_streak,
		"ng_plus": ng_plus,
		"stain_flame": stain_flame,
		"stardust": stardust,
		"souls": souls.duplicate(true),
		"soul_slots": soul_slots.duplicate(),
		"inventory": inventory.duplicate(true),
		"hotbar": hotbar.duplicate(),
		"ui_layout": ui_layout.duplicate(true),
		"equip_bag": equip_bag.duplicate(true),
		"equip_worn": equip_worn.duplicate(true),
		"equip_slots": equip_slots.duplicate(true),
		"warehouse": warehouse.duplicate(true),
		"warehouse_equip": warehouse_equip.duplicate(true),
		"crit_rate": crit_rate,
		"crit_dmg": crit_dmg,
		"dmg_variance": dmg_variance,
	}


## 存檔裡的集合欄位不保證是對的型別：手動改過的備份、別台機器推上來的雲存檔、
## 寫到一半的檔，都可能讓某個 key 變成 null 或數字。直接 .duplicate() 會在
## from_dict() 走到一半噴錯中斷，留下半新半舊的混血狀態（章節已經換了、背包還是上一格的），
## 而且下一次自動存檔就把那份混血寫死。所以取集合一律先驗型別。
func _dict_field(d: Dictionary, key: String, fallback: Dictionary = {}) -> Dictionary:
	var v: Variant = d.get(key, fallback)
	if typeof(v) != TYPE_DICTIONARY:
		return fallback.duplicate(true)
	return (v as Dictionary).duplicate(true)


func _array_field(d: Dictionary, key: String, fallback: Array = []) -> Array:
	var v: Variant = d.get(key, fallback)
	if typeof(v) != TYPE_ARRAY:
		return fallback.duplicate(true)
	return (v as Array).duplicate(true)


func from_dict(d: Dictionary) -> void:
	chapter = str(d.get("chapter", "title"))
	flags = _dict_field(d, "flags")
	player_name = str(d.get("player_name", "小白"))
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	path_style = _migrate_path_style(str(d.get("path_style", "")))
	gold = int(d.get("gold", 0))
	play_time = float(d.get("play_time", 0.0))
	max_hp = int(d.get("max_hp", 50))
	hp = int(d.get("hp", max_hp))
	atk = int(d.get("atk", 10))
	def_stat = int(d.get("def_stat", 5))
	speed = int(d.get("speed", 10))
	weapon_name = str(d.get("weapon_name", "空手"))
	weapon_atk = int(d.get("weapon_atk", 0))
	weapon_tier = int(d.get("weapon_tier", 0))
	skill_slash_lv = int(d.get("skill_slash_lv", 0))
	skill_data = _dict_field(d, "skill_data")
	if skill_data.is_empty() and skill_slash_lv > 0:
		skill_data["slash"] = {"lv": skill_slash_lv, "mastery": 0}
	has_wheat_stalk = bool(d.get("has_wheat_stalk", false))
	wheat_stalk_broken = bool(d.get("wheat_stalk_broken", false))
	forge_fail_streak = int(d.get("forge_fail_streak", 0))
	ng_plus = int(d.get("ng_plus", 0))
	stain_flame = bool(d.get("stain_flame", false))
	stardust = int(d.get("stardust", 0))
	souls = _array_field(d, "souls")
	soul_slots = _array_field(d, "soul_slots")
	inventory = _dict_field(d, "inventory")
	hotbar = _array_field(d, "hotbar", ["", "", "", "", "", "", "", ""])
	while hotbar.size() < 8:
		hotbar.append("")
	if hotbar.size() > 8:
		hotbar.resize(8)
	ui_layout = _dict_field(d, "ui_layout")
	equip_bag = _array_field(d, "equip_bag")
	equip_worn = _dict_field(d, "equip_worn")
	equip_slots = _dict_field(d, "equip_slots", {"weapon": "", "armor": "", "accessory": ""})
	warehouse = _dict_field(d, "warehouse")
	warehouse_equip = _array_field(d, "warehouse_equip")
	crit_rate = float(d.get("crit_rate", 5.0))
	crit_dmg = float(d.get("crit_dmg", 50.0))
	dmg_variance = float(d.get("dmg_variance", 0.08))


func reset_new_game() -> void:
	from_dict({
		"chapter": "c0",
		"flags": {},
		"player_name": "小白",
		"level": 1,
		"xp": 0,
		"path_style": "",
		"gold": 30,
		"max_hp": 50,
		"hp": 50,
		"atk": 10,
		"def_stat": 5,
		"speed": 10,
		"weapon_name": "空手",
		"weapon_atk": 0,
		"weapon_tier": 0,
		"skill_slash_lv": 0,
		"skill_data": {},
		"has_wheat_stalk": false,
		"wheat_stalk_broken": false,
		"forge_fail_streak": 0,
		"ng_plus": 0,
		"stain_flame": false,
		"stardust": 0,
		"souls": [],
		"soul_slots": [],
		"inventory": {},
		"hotbar": ["", "", "", "", "", "", "", ""],
		"ui_layout": {},
	})


## 黑焰迴響：升 NG 層、清主線進度 flag，保留養成與外觀／通關紀念
func start_ng_plus_run(with_stain: bool) -> void:
	ng_plus = maxi(1, ng_plus + 1)
	stain_flame = with_stain or stain_flame
	## 保留：數值、金幣、裂縫記錄、外觀 flag
	var keep: Dictionary = {}
	for k in flags.keys():
		var ks := str(k)
		if ks.begins_with("cosmetic.") or ks.begins_with("title.") \
				or ks.begins_with("postgame.") or ks.begins_with("item.") \
				or ks == "game_cleared" or ks == "c1_ding_recognized_sword" \
				or ks == "c1_perfect_parry_once" or ks == "c6_refuse_all" \
				or ks == "c3_abo_perfect" or ks == "c0_wheat_saved" \
				or ks.begins_with("c6_refuse_"):
			keep[ks] = flags[k]
	flags = keep
	flags["game_cleared"] = true  ## 仍可進裂縫
	flags["ng_plus_active"] = true
	flags["ng_plus_loop"] = ng_plus
	if stain_flame:
		flags["cosmetic.ash_edge"] = true
		flags["ng_stain_flame"] = true
	## 主線重跑
	chapter = "c0"
	has_wheat_stalk = true
	wheat_stalk_broken = false
	hp = max_hp
	if skill_slash_lv < 1:
		skill_slash_lv = 1
	if weapon_tier < 1:
		weapon_name = "微末之刃"
		weapon_atk = maxi(weapon_atk, 9)
		weapon_tier = maxi(weapon_tier, 2)
