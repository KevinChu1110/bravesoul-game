extends RefCounted
class_name NpcLines
## NPC 多階段台詞 —— 資料在 res://data/npc_lines/*.json，這裡只負責選規則。
##
## 加一個新 NPC 或改台詞不需要動程式：丟一個 JSON 進 data/npc_lines/ 就好。
## Schema 見 data/npc_lines/schema.md。
##
## 規則由上而下比對，第一個成立的就用（跟原本一連串 if 的語意一致）；
## 都不成立時回傳空陣列。

const DIR := "res://data/npc_lines"

static var _cache: Dictionary = {}


## GameState 走執行期查找 —— class_name 腳本不可在編譯期引用 autoload 識別字，
## 否則被 `godot -s` 直接載入時會 Compile Error（見 AGENTS.md「寫測試的規矩」）。
static func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameState")
	return null


## 給某個 NPC 目前該講的台詞，格式同舊版：[{speaker, text}, ...]
static func for_npc(npc_id: String) -> Array:
	var doc := _load(npc_id)
	if doc.is_empty():
		return []
	var speaker := str(doc.get("speaker", ""))
	for rule in doc.get("rules", []):
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		if not _matches(rule.get("when", {})):
			continue
		var out: Array = []
		for text in rule.get("lines", []):
			out.append({"speaker": speaker, "text": str(text)})
		return out
	return []


## 這個 NPC 有沒有資料檔（給驗證與工具用）
static func has_npc(npc_id: String) -> bool:
	return not _load(npc_id).is_empty()


## 列出所有 NPC id（給 test 與驗證掃描用）
static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var d := DirAccess.open(DIR)
	if d == null:
		return ids
	for f in d.get_files():
		## 匯出後 .json 會變成 .json.remap，兩種都要認
		var name := f
		if name.ends_with(".remap"):
			name = name.substr(0, name.length() - 6)
		if name.ends_with(".json"):
			ids.append(name.substr(0, name.length() - 5))
	ids.sort()
	return ids


static func _matches(when: Variant) -> bool:
	if typeof(when) != TYPE_DICTIONARY:
		return false
	var w: Dictionary = when
	## 空的 when = 永遠成立（預設規則）
	if w.is_empty():
		return true
	var gs := _gs()
	if gs == null:
		return false
	if w.has("ng_plus_min") and int(gs.ng_plus) < int(w["ng_plus_min"]):
		return false
	for flag in w.get("flags", []):
		if not gs.has_flag(str(flag)):
			return false
	return true


static func _load(npc_id: String) -> Dictionary:
	if _cache.has(npc_id):
		return _cache[npc_id]
	var path := "%s/%s.json" % [DIR, npc_id]
	if not FileAccess.file_exists(path):
		_cache[npc_id] = {}
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cache[npc_id] = {}
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("npc_lines: %s 不是合法 JSON 物件" % path)
		_cache[npc_id] = {}
		return {}
	_cache[npc_id] = data
	return data
