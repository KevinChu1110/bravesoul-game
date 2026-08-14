extends Node
## 載入 data/tables/*.json，對齊 Formulas／裝備／倉庫。
## Autoload：DataTables

const COMBAT_PATH := "res://data/tables/combat.json"
const EQUIP_PATH := "res://data/tables/equipment.json"
const ITEMS_META_PATH := "res://data/tables/items_meta.json"
const WEAPON_CLASS_PATH := "res://data/tables/weapon_classes.json"

var combat: Dictionary = {}
var equipment: Dictionary = {}
var items_meta: Dictionary = {}
var weapon_classes: Dictionary = {}
var loaded: bool = false


func _ready() -> void:
	reload()


func reload() -> void:
	combat = _load_json(COMBAT_PATH)
	equipment = _load_json(EQUIP_PATH)
	items_meta = _load_json(ITEMS_META_PATH)
	weapon_classes = _load_json(WEAPON_CLASS_PATH)
	loaded = not combat.is_empty()
	if loaded:
		print("[DataTables] combat/equipment/items_meta/weapon_classes loaded")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("DataTables missing: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


func combat_f(path: String, default: float = 0.0) -> float:
	return float(_dig(combat, path, default))


func combat_i(path: String, default: int = 0) -> int:
	return int(_dig(combat, path, default))


func equip_bases() -> Dictionary:
	return equipment.get("bases", {}) as Dictionary


func equip_qualities() -> Dictionary:
	return equipment.get("qualities", {}) as Dictionary


func float_ranges() -> Dictionary:
	return equipment.get("float_ranges", {}) as Dictionary


func craft_recipes() -> Array:
	var a: Variant = equipment.get("craft_recipes", [])
	if a is Array:
		return a
	return []


func weapon_class_list() -> Array:
	var a: Variant = weapon_classes.get("classes", [])
	if a is Array:
		return a
	return []


func weapon_class_def(id: String) -> Dictionary:
	for c in weapon_class_list():
		if str((c as Dictionary).get("id", "")) == id:
			return c as Dictionary
	return {}


func warehouse_max() -> int:
	var w: Dictionary = items_meta.get("warehouse", {})
	return int(w.get("max_slots", 60))


func log_max_lines() -> int:
	var w: Dictionary = items_meta.get("log", {})
	return int(w.get("max_lines", 2000))


func _dig(root: Dictionary, path: String, default: Variant) -> Variant:
	var cur: Variant = root
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY:
			return default
		if not (cur as Dictionary).has(part):
			return default
		cur = (cur as Dictionary)[part]
	return cur
