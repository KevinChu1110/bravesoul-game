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


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var d := DirAccess.open(DIR)
	if d == null:
		push_error("dialogues: 開不了 %s" % DIR)
		return
	for f in d.get_files():
		## 匯出後 .json 會變成 .json.remap，兩種都要認
		var name := f
		if name.ends_with(".remap"):
			name = name.substr(0, name.length() - 6)
		if not name.ends_with(".json"):
			continue
		var path := "%s/%s" % [DIR, name]
		var fh := FileAccess.open(path, FileAccess.READ)
		if fh == null:
			push_error("dialogues: 讀不到 %s" % path)
			continue
		var data = JSON.parse_string(fh.get_as_text())
		if typeof(data) != TYPE_DICTIONARY:
			push_error("dialogues: %s 不是合法 JSON 物件" % path)
			continue
		for k in (data as Dictionary).keys():
			if _table.has(k):
				push_error("dialogues: key 撞名 %s（%s）" % [k, path])
				continue
			_table[k] = data[k]
