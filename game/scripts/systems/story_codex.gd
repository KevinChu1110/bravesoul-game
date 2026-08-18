extends Node
## 旅途手札（翠嶺手札）：依旗標解鎖短文，對齊小說場景卡。
## 全文小說在 docs/story/novel/；遊戲內只放精華 body。

const CODEX_PATH := "res://data/story/codex.json"

var _entries: Array = []
var _by_id: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	_entries.clear()
	_by_id.clear()
	if not FileAccess.file_exists(CODEX_PATH):
		push_warning("StoryCodex: missing %s" % CODEX_PATH)
		return
	var f := FileAccess.open(CODEX_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var arr: Variant = data.get("entries", [])
	if not (arr is Array):
		return
	for e in arr:
		if e is Dictionary:
			var d: Dictionary = e
			_entries.append(d)
			_by_id[str(d.get("id", ""))] = d
	_entries.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))


func entries() -> Array:
	return _entries


func entry(id: String) -> Dictionary:
	var e: Variant = _by_id.get(id, {})
	if e is Dictionary:
		return e
	return {}


func is_unlocked(id: String) -> bool:
	var d: Dictionary = entry(id)
	if d.is_empty():
		return false
	## 已讀／已解鎖旗標（持久）
	var unlocked_key := "codex.unlocked.%s" % id
	if GameState.has_flag(unlocked_key):
		return true
	var flag := str(d.get("unlock_flag", ""))
	if flag != "" and GameState.has_flag(flag):
		return true
	var anyf: Variant = d.get("unlock_any_flags", [])
	if anyf is Array:
		for f2 in anyf:
			if GameState.has_flag(str(f2)):
				return true
	return false


## 掃全部條目：條件滿足就寫入 codex.unlocked.*；回傳本輪新解鎖 id
func try_unlock_all() -> Array:
	var newly: Array = []
	for d in _entries:
		var id := str(d.get("id", ""))
		if id == "":
			continue
		var ukey := "codex.unlocked.%s" % id
		if GameState.has_flag(ukey):
			continue
		if is_unlocked(id):
			GameState.set_flag(ukey, true)
			newly.append(id)
	return newly


func unlocked_count() -> int:
	var n := 0
	for d in _entries:
		if is_unlocked(str(d.get("id", ""))):
			n += 1
	return n


func total_count() -> int:
	return _entries.size()


func display_title(id: String) -> String:
	var d: Dictionary = entry(id)
	if d.is_empty():
		return id
	return str(d.get("title", id))


func list_line(id: String) -> String:
	var d: Dictionary = entry(id)
	if d.is_empty():
		return id
	var ch := str(d.get("chapter", ""))
	var title := str(d.get("title", id))
	if is_unlocked(id):
		return "· [%s] %s" % [ch, title]
	return "· [%s] ？？？（%s）" % [ch, str(d.get("unlock_hint", "未解鎖"))]


func panel_list_bbcode() -> String:
	try_unlock_all()
	var lines: PackedStringArray = []
	lines.append("[b]翠嶺手札[/b]  %d／%d" % [unlocked_count(), total_count()])
	lines.append("旅途解鎖的故事精華。全文在連載／小說稿；這裡只收你走過的夜。")
	lines.append("")
	var book := -1
	for d in _entries:
		var b := int(d.get("book", 1))
		if b != book:
			book = b
			lines.append("[color=#8cf]— 第一部 · 微末的開始 —[/color]" if book == 1 else "[color=#8cf]— 第 %d 部 —[/color]" % book)
		var id := str(d.get("id", ""))
		if is_unlocked(id):
			lines.append("[b]%s[/b]" % list_line(id))
			var sum := str(d.get("summary", ""))
			if sum != "":
				lines.append("    %s" % sum)
		else:
			lines.append("[color=#666]%s[/color]" % list_line(id))
	return "\n".join(lines)


func entry_bbcode(id: String) -> String:
	var d: Dictionary = entry(id)
	if d.is_empty():
		return "（無此手札）"
	if not is_unlocked(id):
		return "尚未解鎖。\n條件：%s" % str(d.get("unlock_hint", "？"))
	var lines: PackedStringArray = []
	lines.append("[b]%s[/b]" % str(d.get("title", id)))
	lines.append("%s · %s" % [str(d.get("chapter", "")), str(d.get("scene", ""))])
	lines.append("")
	lines.append(str(d.get("body", "")))
	return "\n".join(lines)


func unlocked_ids() -> Array:
	var out: Array = []
	for d in _entries:
		var id := str(d.get("id", ""))
		if is_unlocked(id):
			out.append(id)
	return out
