extends RefCounted
class_name PathLoadout
## 選武器系統後的發放：該職業兩套武器的起手招 + starter 武器（每系統一次）。
## 6 職業 × 雙武器系統（對等，非主副）——見 SkillSystem.PROFESSION_WEAPONS。
##
## 從 main.gd 抽出，避免路由器再堆養成細節。
## GameState／各 System 走執行期查找（class_name 不可在編譯期引用 autoload）。

static func _root() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


static func _gs() -> Node:
	var r := _root()
	return r.get_node_or_null("GameState") if r else null


static func _sys(name: String) -> Node:
	var r := _root()
	return r.get_node_or_null(name) if r else null


## 舊 id 別名：soul→magic、iron→hammer
static func normalize_class_id(class_id: String) -> String:
	var cid := str(class_id)
	match cid:
		"soul":
			return "magic"
		"iron":
			return "hammer"
	return cid


## 發招：通用橫斬 + 該武器系統起手 + 同職另一武器起手
static func grant_skills_for_path(class_id: String) -> void:
	var sk := _sys("SkillSystem")
	if sk == null:
		return
	if sk.has_method("grant_for_weapon_class"):
		sk.call("grant_for_weapon_class", str(class_id))
	else:
		for sid in ["star_pierce", "iron_guard", "blade_dance", "emergency_heal", "slash"]:
			if sk.has_method("try_unlock"):
				sk.call("try_unlock", sid)


## 發 starter 武器。旗標避免重複；已有更高器階武器時只進背包不強換。
## 回傳 true 表示本次新發了實例。
static func grant_starter_weapon(class_id: String) -> bool:
	var gs := _gs()
	var eq := _sys("EquipmentSystem")
	var dt := _sys("DataTables")
	if gs == null or eq == null or dt == null:
		return false
	var cid := normalize_class_id(class_id)
	var flag := "path.starter_given.%s" % cid
	if gs.has_flag(flag):
		return false
	if not dt.has_method("weapon_class_def"):
		return false
	var d: Dictionary = dt.call("weapon_class_def", cid)
	if d.is_empty():
		return false
	var base_id := str(d.get("starter_weapon", ""))
	if base_id == "" or not eq.has_method("base_def") or eq.call("base_def", base_id).is_empty():
		return false
	var inst: Dictionary = eq.call("roll_instance", base_id, "common")
	if inst.is_empty():
		return false
	eq.call("add_to_bag", inst)
	gs.set_flag(flag, true)
	var starter_tier := int(inst.get("tier", 1))
	var cur_uid := str(gs.equip_slots.get("weapon", ""))
	var should_equip := true
	if cur_uid != "" and gs.equip_worn.has(cur_uid):
		var cur: Dictionary = gs.equip_worn[cur_uid]
		if int(cur.get("tier", 0)) > starter_tier:
			should_equip = false
	if should_equip and eq.has_method("equip"):
		eq.call("equip", str(inst.get("uid", "")))
	return true


## 選流派後一次做完：發招 + starter 武器
static func apply_path_choice(class_id: String) -> void:
	grant_skills_for_path(class_id)
	grant_starter_weapon(class_id)
