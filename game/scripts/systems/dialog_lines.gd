extends RefCounted
class_name DialogLines
## 主線／支線的固定台詞 —— 資料在 res://data/dialogues/*.json，這裡只負責取出與插值。
##
## 跟 NpcLines 的分工：NpcLines 連「該講哪一段」都寫在資料裡（多階段規則）；
## 這裡不管條件，條件仍舊留在 main.gd 的 if／match 裡。
## 原因是這些台詞的分支條件跟遊戲流程綁死（剛打完誰、身上有沒有什麼），
## 硬要塞進 JSON 只會變成把程式碼寫成字串，反而更難讀。
##
## 檔名不影響 key：所有 *.json 會合併成同一張表，key 自己帶命名空間（如 "c2.lantern"）。
## Schema 見 data/dialogues/schema.md。

const DIR := "res://data/dialogues"

static var _table: Dictionary = {}
static var _loaded := false


## 取某段台詞，格式同 _play_dialog 要的 [{speaker, text}, ...]。
## vars 用來填 text 裡的 {名稱} 插槽。
static func lines(key: String, vars: Dictionary = {}) -> Array:
	_ensure_loaded()
	if not _table.has(key):
		push_error("dialogues: 找不到台詞 %s" % key)
		return []
	var out: Array = []
	for item in _table[key]:
		var line: Dictionary = (item as Dictionary).duplicate(true)
		line["text"] = _fill(str(line.get("text", "")), vars, key)
		out.append(line)
	return out


## 這個 key 存不存在（給測試與驗證掃描用）
static func has(key: String) -> bool:
	_ensure_loaded()
	return _table.has(key)


## 列出所有 key（給測試用）
static func all_keys() -> PackedStringArray:
	_ensure_loaded()
	var keys := PackedStringArray()
	for k in _table.keys():
		keys.append(str(k))
	keys.sort()
	return keys


static func _fill(text: String, vars: Dictionary, key: String) -> String:
	if vars.is_empty():
		## 沒給值卻留著插槽 = 呼叫端漏傳，早點吵出來比在畫面上出現「{power}」好
		if text.contains("{"):
			push_error("dialogues: %s 需要插值但沒有傳 vars" % key)
		return text
	var out := text
	for name in vars.keys():
		out = out.replace("{%s}" % str(name), str(vars[name]))
	if out.contains("{"):
		push_error("dialogues: %s 還有沒填的插槽：%s" % [key, out])
	return out


## 目前載進來的是哪個語言。切語言時要重載。
static var _loaded_locale := ""


static func current_locale() -> String:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		var loc: Node = (t as SceneTree).root.get_node_or_null("Loc")
		if loc != null:
			return str(loc.get("locale"))
	return "zh_TW"


## 切語言之後要叫這支，不然畫面語言變了、台詞還是舊的。
static func reload() -> void:
	_loaded = false
	_table.clear()


static func _ensure_loaded() -> void:
	var lc := current_locale()
	if _loaded and _loaded_locale == lc:
		return
	if _loaded_locale != lc:
		_table.clear()
	_loaded = true
	_loaded_locale = lc
	## 先鋪中文原文當底，再用該語言的檔覆蓋 ——
	## 這樣某一句還沒翻的時候，玩家看到的是原文而不是空白或 key。
	_load_dir(DIR, false)
	if lc != "zh_TW":
		## 譯文層是「刻意要蓋掉原文」的，所以這一層允許覆寫。
		## 底層（同一個目錄裡兩個檔定義同一個 key）仍然算撞名錯誤。
		_load_dir("%s/%s" % [DIR, lc], true)


## allow_override=true 時，這一層的 key 會蓋掉先前載入的（譯文層用）。
static func _load_dir(dir_path: String, allow_override: bool) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		## 譯文目錄不存在是正常的（那個語言還沒翻），不要報錯
		if not allow_override:
			push_error("dialogues: 開不了 %s" % dir_path)
		return
	for f in d.get_files():
		## 匯出後 .json 會變成 .json.remap，兩種都要認
		var name := f
		if name.ends_with(".remap"):
			name = name.substr(0, name.length() - 6)
		if not name.ends_with(".json"):
			continue
		var path := "%s/%s" % [dir_path, name]
		var fh := FileAccess.open(path, FileAccess.READ)
		if fh == null:
			push_error("dialogues: 讀不到 %s" % path)
			continue
		var data = JSON.parse_string(fh.get_as_text())
		if typeof(data) != TYPE_DICTIONARY:
			push_error("dialogues: %s 不是合法 JSON 物件" % path)
			continue
		for k in (data as Dictionary).keys():
			if _table.has(k) and not allow_override:
				push_error("dialogues: key 撞名 %s（%s）" % [k, path])
				continue
			_table[k] = data[k]
