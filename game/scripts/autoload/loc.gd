extends Node
## 多國語系預留：目前預設繁中，字串以 key 查找。
## 用法：Loc.t("key") 或 Loc.t("key", {"name": "x"})
## 對話仍可暫用中文原文；新文案優先 key。

const DEFAULT_LOCALE := "zh_TW"

## 支援的語言。順序＝標題頁語言鈕循環的順序。
## code 要跟 data/i18n/<code>.json 的檔名一致；label 用該語言自己的寫法
## （玩家在看不懂目前語言的時候，還認得出自己的母語）。
const LOCALES: Array[Dictionary] = [
	{"code": "zh_TW", "label": "繁體中文"},
	{"code": "zh_CN", "label": "简体中文"},
	{"code": "en", "label": "English"},
	{"code": "ja", "label": "日本語"},
	{"code": "ko", "label": "한국어"},
	{"code": "es", "label": "Español"},
]

var locale: String = DEFAULT_LOCALE
var _tables: Dictionary = {}  ## locale -> { key: text }


func _ready() -> void:
	for l in LOCALES:
		_load_locale(str(l["code"]))


## 目前語言在 LOCALES 裡的位置（找不到時當作第一個）
func locale_index() -> int:
	for i in LOCALES.size():
		if str(LOCALES[i]["code"]) == locale:
			return i
	return 0


func locale_label(code: String = "") -> String:
	var want := code if code != "" else locale
	for l in LOCALES:
		if str(l["code"]) == want:
			return str(l["label"])
	return want


## 切到下一個語言（標題頁那顆按鈕用）
func cycle_locale() -> String:
	var nxt: int = (locale_index() + 1) % LOCALES.size()
	set_locale(str(LOCALES[nxt]["code"]))
	return locale


## 這個語言翻了多少（給玩家看的完成度，不要謊稱全翻）。
##
## **要把劇情算進去。** 只算介面表的話，英文會顯示 100% ——
## 而那時候所有台詞還是中文，玩家切過去會覺得被騙。
## 劇情是另外兩份資料（data/dialogues/<code>、data/npc_lines/<code>），
## 用「翻了幾個檔」估，夠誠實也不必把整份載進來。
const STORY_DIRS := ["res://data/dialogues", "res://data/npc_lines"]


func _story_coverage(code: String) -> float:
	var have := 0
	var total := 0
	for d in STORY_DIRS:
		var base := DirAccess.open(d)
		if base == null:
			continue
		var n := 0
		for f in base.get_files():
			if f.ends_with(".json") or f.ends_with(".json.remap"):
				n += 1
		if n == 0:
			continue
		total += n
		if code == DEFAULT_LOCALE:
			have += n
			continue
		var sub := DirAccess.open("%s/%s" % [d, code])
		if sub == null:
			continue
		for f in sub.get_files():
			if f.ends_with(".json") or f.ends_with(".json.remap"):
				have += 1
	if total == 0:
		return 1.0
	return clampf(float(have) / float(total), 0.0, 1.0)


func coverage(code: String = "") -> float:
	var want := code if code != "" else locale
	var base: Dictionary = _tables.get(DEFAULT_LOCALE, {})
	if base.is_empty():
		return 0.0
	var tbl: Dictionary = _tables.get(want, {})
	var n := 0
	for k in base.keys():
		if str(tbl.get(k, "")) != "":
			n += 1
	var ui := float(n) / float(base.size())
	## 介面與劇情各半：兩邊都翻完才算 100%
	return ui * 0.5 + _story_coverage(want) * 0.5


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
