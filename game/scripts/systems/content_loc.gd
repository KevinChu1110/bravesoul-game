extends RefCounted
## 內容目錄的翻譯層。
##
## 刻意不用 class_name：全域類名要靠 .godot 的 class cache，那份要編輯器
## 掃過才會有。加一個新的 class_name 之後直接 `godot --headless -s` 會噴
## 「Identifier not declared」，CI 上尤其容易踩到。用 const preload 就沒這問題。
##
## 招式、稱號、任務、地圖物件這些東西的名字與說明，原本是直接寫死在
## .gd 的目錄常數裡（skill_system.CATALOG、title_catalog.ENTRIES…）。
## 那些字比 data/i18n 的介面字串還多，介面翻完了、招式名還是中文，
## 韓文玩家看到的仍然是一半中文 —— 這層就是補這個洞。
##
## 做法刻意不動原本的目錄：每個語言放一份 id → {欄位: 譯文} 的覆蓋檔，
##   data/i18n/content/<locale>/<domain>.json
## 讀目錄的時候套上去。沒翻的欄位就留原文，不會變空白或 key。
##
##   {
##     "slash":  {"name": "Wide Slash", "desc": "..."},
##     "hut_a":  {"label": "Charred hut"}
##   }
##
## 繁中不需要覆蓋檔（原文就在 .gd 裡），所以 zh_TW 一律走快速路徑。

const DIR := "res://data/i18n/content"

## domain → {locale: {id: {field: text}}}
static var _cache: Dictionary = {}


static func locale() -> String:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		var loc: Node = (t as SceneTree).root.get_node_or_null("Loc")
		if loc != null:
			return str(loc.get("locale"))
	return "zh_TW"


## 以「原文」當 key 的查表。
##
## 地圖物件標籤這種東西不能用 id 當 key：同一個 id（back_town、camp_fire…）
## 在不同地圖上是不同的字，實測有 39 個這種撞名，用 id 對照會翻錯。
## 這些字又都是「回城」「營火」這種短名詞，同樣的中文本來就該翻成同樣的話，
## 所以直接拿原文當 key —— 撞名問題消失，420 個用處也塌成 384 個要翻的字。
##
##   {"回城": "Back to town", "營火": "Campfire"}
static func text(domain: String, source: String) -> String:
	var lc := locale()
	if lc == "zh_TW" or source == "":
		return source
	var v = _table(domain, lc).get(source, "")
	return str(v) if str(v) != "" else source


## 單一字串：查得到就換掉，查不到回原文
static func t(domain: String, id: String, field: String, fallback: String) -> String:
	var lc := locale()
	if lc == "zh_TW" or id == "":
		return fallback
	var tbl := _table(domain, lc)
	var entry = tbl.get(id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return fallback
	var v = (entry as Dictionary).get(field, "")
	return str(v) if str(v) != "" else fallback


## 把一整筆目錄資料的可翻欄位換掉，回傳新的 Dictionary（不動原本的常數）。
## id 從 id_key 指定的欄位取；fields 沒給就用預設那組。
static func apply(domain: String, row: Dictionary, fields: PackedStringArray = PackedStringArray(), id_key := "id") -> Dictionary:
	var lc := locale()
	if lc == "zh_TW":
		return row
	var id := str(row.get(id_key, ""))
	if id == "":
		return row
	var tbl := _table(domain, lc)
	var entry = tbl.get(id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return row
	var out := row.duplicate(true)
	var keys: Array = (entry as Dictionary).keys() if fields.is_empty() else Array(fields)
	for f in keys:
		var v = (entry as Dictionary).get(f, "")
		## 只覆蓋原本就有的欄位 —— 覆蓋檔打錯欄位名時要看得出來，
		## 而不是靜靜多出一個沒人讀的鍵。
		if str(v) != "" and out.has(f):
			out[f] = v
	return out


## 一整份 id-keyed 目錄（Array[Dictionary]）
static func apply_all(domain: String, rows: Array, fields: PackedStringArray = PackedStringArray(), id_key := "id") -> Array:
	if locale() == "zh_TW":
		return rows
	var out: Array = []
	for r in rows:
		if typeof(r) == TYPE_DICTIONARY:
			out.append(apply(domain, r as Dictionary, fields, id_key))
		else:
			out.append(r)
	return out


## 切語言之後要叫這支，不然畫面語言變了、招式名還是舊的。
static func reload() -> void:
	_cache.clear()


static func _table(domain: String, lc: String) -> Dictionary:
	var per: Dictionary = _cache.get(domain, {})
	if per.has(lc):
		return per[lc]
	var path := "%s/%s/%s.json" % [DIR, lc, domain]
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				data = parsed
	per[lc] = data
	_cache[domain] = per
	return data
