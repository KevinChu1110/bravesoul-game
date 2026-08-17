extends Node
## 顯示設定：全螢幕／視窗 + 解析度，存 user://display_settings.json
## 預設：全螢幕；解析度 1280×720（邏輯 viewport 固定 16:9）

const PATH := "user://display_settings.json"

## 常用 16:9 視窗解析度（視窗模式用）
const RESOLUTIONS: Array = [
	{"id": "1280x720", "w": 1280, "h": 720, "label": "1280 × 720"},
	{"id": "1366x768", "w": 1366, "h": 768, "label": "1366 × 768"},
	{"id": "1600x900", "w": 1600, "h": 900, "label": "1600 × 900"},
	{"id": "1920x1080", "w": 1920, "h": 1080, "label": "1920 × 1080"},
	{"id": "2560x1440", "w": 2560, "h": 1440, "label": "2560 × 1440"},
]

## windowed | fullscreen | exclusive
var mode: String = "fullscreen"
var res_id: String = "1280x720"
var vsync: bool = true


func _ready() -> void:
	load_settings()
	## 等一幀再套用，避免啟動時 DisplayServer 尚未就緒
	call_deferred("apply")


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		## 首次：預設全螢幕
		mode = "fullscreen"
		res_id = "1280x720"
		vsync = true
		save_settings()
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	mode = str(data.get("mode", "fullscreen"))
	if mode not in ["windowed", "fullscreen", "exclusive"]:
		mode = "fullscreen"
	res_id = str(data.get("res_id", "1280x720"))
	if _res_def(res_id).is_empty():
		res_id = "1280x720"
	vsync = bool(data.get("vsync", true))


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("DisplaySettings: cannot write %s" % PATH)
		return
	f.store_string(JSON.stringify({
		"mode": mode,
		"res_id": res_id,
		"vsync": vsync,
	}, "\t"))


func _res_def(id: String) -> Dictionary:
	for r in RESOLUTIONS:
		if str(r.get("id", "")) == id:
			return r
	return {}


func res_label(id: String = "") -> String:
	var d := _res_def(id if id != "" else res_id)
	return str(d.get("label", res_id))


func mode_label() -> String:
	match mode:
		"windowed":
			return "視窗"
		"exclusive":
			return "獨占全螢幕"
		_:
			return "全螢幕"


func apply() -> void:
	var win := get_window()
	if win == null:
		return

	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var r := _res_def(res_id)
	var w: int = int(r.get("w", 1280))
	var h: int = int(r.get("h", 720))

	match mode:
		"windowed":
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			## 限制不超過螢幕
			var scr := DisplayServer.screen_get_size()
			w = mini(w, maxi(640, scr.x - 40))
			h = mini(h, maxi(360, scr.y - 80))
			win.size = Vector2i(w, h)
			## 置中
			var pos := (scr - Vector2i(w, h)) / 2
			if pos.x < 0:
				pos.x = 0
			if pos.y < 0:
				pos.y = 0
			win.position = pos
		"exclusive":
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			## 無邊框全螢幕（切換較快，多螢幕友善）
			win.mode = Window.MODE_FULLSCREEN

	print("DisplaySettings apply mode=%s res=%s vsync=%s" % [mode, res_id, vsync])


func set_mode(m: String) -> void:
	if m not in ["windowed", "fullscreen", "exclusive"]:
		return
	mode = m
	save_settings()
	apply()


func set_resolution(id: String) -> void:
	if _res_def(id).is_empty():
		return
	res_id = id
	save_settings()
	## 僅視窗模式改變尺寸有感；全螢幕仍記住供切回
	apply()


func cycle_mode() -> void:
	match mode:
		"fullscreen":
			set_mode("windowed")
		"windowed":
			set_mode("exclusive")
		_:
			set_mode("fullscreen")


func cycle_resolution(delta: int = 1) -> void:
	var idx := 0
	for i in RESOLUTIONS.size():
		if str(RESOLUTIONS[i].get("id", "")) == res_id:
			idx = i
			break
	idx = (idx + delta) % RESOLUTIONS.size()
	if idx < 0:
		idx += RESOLUTIONS.size()
	set_resolution(str(RESOLUTIONS[idx].get("id", "1280x720")))


func set_vsync(on: bool) -> void:
	vsync = on
	save_settings()
	apply()


## 解析度只有視窗模式吃得到（apply() 只在 windowed 分支動 win.size）。
## 全螢幕下玩家選 1920×1080，面板照樣打勾、照樣跳提示，但什麼都沒發生 ——
## 講清楚比讓他一直試好。
func res_is_effective() -> bool:
	return mode == "windowed"


func summary_line() -> String:
	var res_part := res_label()
	if not res_is_effective():
		res_part = "%s（全螢幕下由螢幕決定）" % res_label()
	return "顯示：%s · %s · 垂直同步 %s" % [
		mode_label(),
		res_part,
		"開" if vsync else "關",
	]
