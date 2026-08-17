extends Node
## 遊戲紀錄：jsonl 持久化 + 記憶體環緩。
## Autoload：GameLog

signal log_appended(entry: Dictionary)

const PATH := "user://game_log.jsonl"

var _mem: Array = []  ## 最近條目
var _path: String = PATH


func _ready() -> void:
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		# path fixed; max from table
	_load_tail()


func max_lines() -> int:
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		if dt and dt.has_method("log_max_lines"):
			return int(dt.call("log_max_lines"))
	return 2000


func _load_tail() -> void:
	_mem.clear()
	if not FileAccess.file_exists(_path):
		return
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return
	var lines: PackedStringArray = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			lines.append(line)
	var start := maxi(0, lines.size() - 200)
	for i in range(start, lines.size()):
		var d = JSON.parse_string(lines[i])
		if typeof(d) == TYPE_DICTIONARY:
			_mem.append(d)


func append(category: String, message: String, data: Dictionary = {}) -> void:
	var entry := {
		"t": Time.get_datetime_string_from_system(true),
		"unix": Time.get_unix_time_from_system(),
		"cat": category,
		"msg": message,
		"data": data,
	}
	_mem.append(entry)
	while _mem.size() > 300:
		_mem.pop_front()
	var f := FileAccess.open(_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(entry))
		f.close()
	## 裁剪過大檔
	_trim_file_if_needed()
	log_appended.emit(entry)


func _trim_file_if_needed() -> void:
	if not FileAccess.file_exists(_path):
		return
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return
	var all: PackedStringArray = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() != "":
			all.append(line)
	f.close()
	var cap := max_lines()
	if all.size() <= cap:
		return
	var start := all.size() - cap
	var w := FileAccess.open(_path, FileAccess.WRITE)
	if w == null:
		return
	for i in range(start, all.size()):
		w.store_line(all[i])
	w.close()


func combat(msg: String, data: Dictionary = {}) -> void:
	append("combat", msg, data)


func economy(msg: String, data: Dictionary = {}) -> void:
	append("economy", msg, data)


func equip(msg: String, data: Dictionary = {}) -> void:
	append("equip", msg, data)


func account(msg: String, data: Dictionary = {}) -> void:
	append("account", msg, data)


func system(msg: String, data: Dictionary = {}) -> void:
	append("system", msg, data)


func info(cat: String, msg: String, data: Dictionary = {}) -> void:
	append(cat, msg, data)


func recent(n: int = 40, category: String = "") -> Array:
	var out: Array = []
	var i := _mem.size() - 1
	while i >= 0 and out.size() < n:
		var e: Dictionary = _mem[i]
		if category == "" or str(e.get("cat", "")) == category:
			out.append(e)
		i -= 1
	return out


func status_bbcode(n: int = 30) -> String:
	var lines: PackedStringArray = []
	## 走 Loc：面板標題已經是英文了，內文再留中文會像翻譯壞掉
	var loc: Node = null
	if Engine.get_main_loop() is SceneTree:
		loc = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Loc")
	if loc != null and loc.has_method("t"):
		lines.append(str(loc.call("t", "log.header", {"n": n})))
	else:
		lines.append("[b]冒險日誌[/b]（最近 %d 條）" % n)
	lines.append("")
	var list := recent(n)
	if list.is_empty():
		lines.append("（尚無紀錄）")
		return "\n".join(lines)
	for e in list:
		var cat := str(e.get("cat", "?"))
		var t := str(e.get("t", ""))
		if t.length() > 16:
			t = t.substr(11, 8)
		lines.append("[%s] %s %s" % [cat, t, str(e.get("msg", ""))])
	return "\n".join(lines)
