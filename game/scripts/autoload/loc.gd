extends Node
## 多國語系預留：目前預設繁中，字串以 key 查找。
## 用法：Loc.t("key") 或 Loc.t("key", {"name": "x"})
## 對話仍可暫用中文原文；新文案優先 key。

const DEFAULT_LOCALE := "zh_TW"
var locale: String = DEFAULT_LOCALE
var _tables: Dictionary = {}  ## locale -> { key: text }


func _ready() -> void:
	_load_locale(DEFAULT_LOCALE)
	## 可擴：en, ja…
	_load_locale("en")


func set_locale(code: String) -> void:
	if not _tables.has(code):
		_load_locale(code)
	if _tables.has(code):
		locale = code


func _load_locale(code: String) -> void:
	var path := "res://data/i18n/%s.json" % code
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		## 編輯器外用 FileAccess
		if not FileAccess.file_exists(path):
			_tables[code] = {}
			return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_tables[code] = {}
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		_tables[code] = data
	else:
		_tables[code] = {}


func t(key: String, vars: Dictionary = {}) -> String:
	var table: Dictionary = _tables.get(locale, {})
	var s: String = str(table.get(key, ""))
	if s == "" and locale != DEFAULT_LOCALE:
		s = str(_tables.get(DEFAULT_LOCALE, {}).get(key, ""))
	if s == "":
		## 回傳 key 本身，方便找漏翻
		s = key
	for k in vars.keys():
		s = s.replace("{%s}" % str(k), str(vars[k]))
	return s


func has_key(key: String) -> bool:
	var table: Dictionary = _tables.get(locale, {})
	return table.has(key) or _tables.get(DEFAULT_LOCALE, {}).has(key)
