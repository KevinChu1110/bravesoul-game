extends Node
## 體驗回報：玩家沒有明確同意就一個字都不送。
##
## 為什麼不做通用事件系統：通用系統的下場是收了三十種事件、一種都沒拿來改遊戲。
## 這裡只收五種，每一種都對應一個「收到之後會動手改的東西」——
## 見 docs/TELEMETRY.md。要加第六種之前，先寫得出它會讓誰改哪一行。
##
## 隱私守則（不是建議，是這支檔案的實作方式）：
##   1. 預設關閉。沒有人按下同意，_queue 永遠是空的。
##   2. 送出去的字串一律限定 a-z0-9_，玩家取的名字、留言、檔案路徑
##      在型別上就進不來，不必依賴「呼叫端記得別傳」。
##   3. 身分只有一顆本機亂數 install_id，跟帳號、信箱、存檔完全沒有關聯。
##   4. 純單機（連線關掉）時一律不送——玩家關連線就是不想跟伺服器講話。
##
## 失敗處理：送不出去就丟掉。遙測壞掉不可以害到遊戲，寧可少一筆資料。
##
## 設定：user://telemetry.json　　文件：docs/TELEMETRY.md

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const CONFIG_PATH := "user://telemetry.json"
const ENDPOINT := "/rest/v1/rpc/telemetry_ingest"

## 伺服器（supabase/telemetry.sql）認得的事件名。兩邊要一致，
## 客戶端先擋一次是為了不要把注定被丟掉的東西送上網路。
const EVENTS: Array[String] = [
	"session_start",
	"session_tick",
	"chapter_enter",
	"battle_end",
	"tutorial_step",
]

## 算 Boss 的戰鬥。放在這裡而不是讓呼叫端傳，是為了整份資料的
## boss 欄位只有一套定義，之後查數字不會出現「這場算不算 Boss」的爭議。
const BOSS_MODES: Array[String] = [
	"leo", "fog", "abo", "falcon", "boar", "demon",          ## 主線
	"wrath", "tide", "statue", "chrono",                     ## 裂縫
	"scar_lord", "mirror_wraith", "wreck_captain",           ## 秘境
	"black_ronin",                                           ## 支線對決
]

## 允許的欄位與上限。不在表上的 key 直接丟掉。
const PROP_INT := {"level": 999, "ng": 99, "sec": 86400, "dur": 3600}
const PROP_BOOL: Array[String] = ["boss", "won"]
const PROP_STR := {"chapter": 16, "mode": 32, "place": 32, "step": 32}

const BATCH_MAX := 20          ## 一次 HTTP 最多帶幾筆
const QUEUE_MAX := 200         ## 佇列上限，滿了丟最舊的（記憶體不能無限長）
const FLUSH_SEC := 60.0        ## 沒滿也每分鐘送一次
const TICK_SEC := 300          ## 每五分鐘記一次「還在玩」
const SESSION_EVENT_MAX := 400 ## 單次遊玩的總量閘門，防程式跑掉狂送
const FAIL_GIVE_UP := 5        ## 連續失敗這麼多次就整場閉嘴

var consent: bool = false      ## 玩家有沒有按下同意
var install_id: String = ""    ## 本機亂數，跟帳號無關
var session_id: String = ""

var _queue: Array = []
var _inflight: Array = []
var _http: HTTPRequest
var _timer: Timer
var _busy: bool = false
var _muted: bool = false
var _fails: int = 0
var _sent_this_session: int = 0
var _session_t0: int = 0
var _next_tick_sec: int = TICK_SEC
var _next_flush_ms: int = 0
var _place: String = ""
var _battle_t0: int = 0
var _battle_mode: String = ""
var _gate: Node



## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

func _ready() -> void:
	_gate = _resolve_gate()
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)

	_timer = Timer.new()
	_timer.wait_time = 5.0
	_timer.autostart = true
	add_child(_timer)
	_timer.timeout.connect(_on_tick)

	load_config()
	_session_t0 = Time.get_ticks_msec()
	session_id = _new_uuid()

	## 章節進度自己接得到，不必勞煩 main.gd
	if GameState.has_signal("chapter_changed"):
		GameState.chapter_changed.connect(_on_chapter_changed)

	if consent:
		## 不帶 chapter：這支必定在標題畫面送出，值恆為 title，
		## 混進章節漏斗只會製造一個 100% 的假第一名。
		## 玩家實際走到哪由 chapter_enter 負責（讀檔續玩也會經過 set_chapter）。
		track("session_start", {
			"level": GameState.level,
			"ng": GameState.ng_plus,
		})


## ── 設定 ──

## 沒同意之前不產、也不寫 install_id。
## 「預設關閉」的字面意思是連一顆能認出這台機器的號碼都還不該存在——
## 先建好放著只是把「有沒有同意」變成一個開關，而不是一條界線。
func load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	consent = bool((data as Dictionary).get("consent", false))
	install_id = str((data as Dictionary).get("install_id", ""))


func _save_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"consent": consent,
		"install_id": install_id,
	}, "\t"))


## 玩家在設定裡開關。關掉時連還沒送出去的都倒掉——
## 「我不要了」指的是那些資料也別送，不是從下一筆開始。
func set_consent(v: bool) -> void:
	var was := consent
	consent = v
	if not consent:
		_queue.clear()
		_inflight.clear()
	elif install_id == "":
		## 同意的這一刻才產生識別碼
		install_id = _new_uuid()
	_save_config()
	if consent and not was:
		_muted = false
		_fails = 0
		## 不帶 chapter：這支必定在標題畫面送出，值恆為 title，
		## 混進章節漏斗只會製造一個 100% 的假第一名。
		## 玩家實際走到哪由 chapter_enter 負責（讀檔續玩也會經過 set_chapter）。
		track("session_start", {
			"level": GameState.level,
			"ng": GameState.ng_plus,
		})


func has_consent() -> bool:
	return consent


## -s 腳本模式下 autoload 的 _ready 還沒跑，而且絕對路徑 get_node 在那個時間點會噴錯，
## 所以一律從 SceneTree.root 走相對路徑，並且每次都容許重解一次。
func _resolve_gate() -> Node:
	if _gate != null and is_instance_valid(_gate):
		return _gate
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		_gate = (t as SceneTree).root.get_node_or_null("OnlineGate")
	return _gate


## 目前收不收得到（同意了、連線開著、後端也設定好了）
func is_active() -> bool:
	if not consent or _muted:
		return false
	if _resolve_gate() == null:
		return false
	if bool(_gate.get("offline_only")):
		return false
	return bool(_gate.call("is_configured"))


## ── 遊戲側掛鉤（全部可以隨便呼叫，不同意時就是空轉）──

## 探索場景進來時記一下位置，之後戰敗才知道人是在哪裡倒的
func set_place(map_id: String) -> void:
	var m := str(map_id).to_lower()
	if _is_token(m):
		_place = m


func battle_started(mode: String) -> void:
	_battle_mode = str(mode)
	_battle_t0 = Time.get_ticks_msec()


func battle_finished(mode: String, won: bool) -> void:
	var m := str(mode)
	if m.begins_with("spectate:"):
		return  ## 觀戰不是自己在打，算進去會汙染勝率
	var boss := BOSS_MODES.has(m)
	var dur := 0
	if _battle_t0 > 0 and m == _battle_mode:
		dur = int((Time.get_ticks_msec() - _battle_t0) / 1000)
	_battle_t0 = 0
	track("battle_end", {
		"mode": m,
		"boss": boss,
		"won": won,
		"dur": dur,
		"level": GameState.level,
		"place": _place,
		"chapter": str(GameState.chapter),
	})


func note_tutorial(step: String) -> void:
	track("tutorial_step", {"step": str(step), "chapter": str(GameState.chapter)})


func _on_chapter_changed(chapter: String) -> void:
	## 回標題也走 set_chapter("title")，而且每個玩家每次遊玩都會回去好幾次。
	## 照收的話章節漏斗第一名永遠是 title，把真正想看的「誰走到第幾章」壓成雜訊。
	if chapter == "" or chapter == "title":
		return
	track("chapter_enter", {
		"chapter": str(chapter),
		"level": GameState.level,
		"sec": _session_sec(),
	})


## ── 收集 ──

func track(event_name: String, props: Dictionary = {}) -> void:
	if not is_active():
		return
	if not EVENTS.has(event_name):
		return
	if _sent_this_session >= SESSION_EVENT_MAX:
		return
	_sent_this_session += 1
	_queue.append({
		"n": event_name,
		"s": _session_sec(),
		"p": _clean_props(props),
	})
	## 滿了丟最舊的：留新的比留舊的有用，而且記憶體必須有上界
	while _queue.size() > QUEUE_MAX:
		_queue.pop_front()
	if _queue.size() >= BATCH_MAX:
		flush()


## 只留白名單欄位；字串限定 a-z0-9_，自由文字進不來
func _clean_props(props: Dictionary) -> Dictionary:
	var out := {}
	for k in props:
		var key := str(k)
		if PROP_INT.has(key):
			out[key] = clampi(int(props[k]), 0, int(PROP_INT[key]))
		elif PROP_BOOL.has(key):
			out[key] = bool(props[k])
		elif PROP_STR.has(key):
			var v := str(props[k]).to_lower()
			if _is_token(v):
				out[key] = v.substr(0, int(PROP_STR[key]))
	return out


func _is_token(s: String) -> bool:
	if s.is_empty() or s.length() > 64:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true


func _session_sec() -> int:
	if _session_t0 <= 0:
		return 0
	return clampi(int((Time.get_ticks_msec() - _session_t0) / 1000), 0, 86400)


## ── 送出 ──

func _on_tick() -> void:
	if not is_active():
		return
	var sec := _session_sec()
	if sec >= _next_tick_sec:
		_next_tick_sec = sec + TICK_SEC
		track("session_tick", {"sec": sec, "chapter": str(GameState.chapter)})
	if _next_flush_ms == 0:
		_next_flush_ms = Time.get_ticks_msec() + int(FLUSH_SEC * 1000.0)
	elif Time.get_ticks_msec() >= _next_flush_ms:
		flush()


func flush() -> void:
	if _busy or _queue.is_empty() or not is_active():
		return
	if _http == null:
		return  ## -s 腳本模式下 _ready 可能還沒跑
	if _gate == null:
		return
	if install_id == "":
		return  ## 還沒同意過就沒有識別碼，伺服器那支 RPC 也收不了空的
	var url := str(_gate.get("supabase_url")) + ENDPOINT
	var key := str(_gate.get("supabase_anon_key"))
	if url == ENDPOINT or key == "":
		return

	_inflight = _queue.slice(0, BATCH_MAX)
	_queue = _queue.slice(mini(BATCH_MAX, _queue.size()))
	_next_flush_ms = Time.get_ticks_msec() + int(FLUSH_SEC * 1000.0)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % key,
		"Authorization: Bearer %s" % key,
	])
	var body := JSON.stringify({
		"p_install": install_id,
		"p_session": session_id,
		"p_version": _app_version(),
		"p_events": _inflight,
	})
	_busy = true
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_after_fail()


func _on_http_completed(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if code < 200 or code >= 300:
		_after_fail()
		return
	## RPC 的錯誤是 HTTP 200 加上 body 裡一個 error 欄位（見 supabase/telemetry.sql）。
	## 只看狀態碼的話，被限流或被封鎖時客戶端會判成成功、把失敗次數歸零，
	## 於是每分鐘照送一次，永遠湊不滿五次——「連續失敗就整場閉嘴」那道保險等於沒有。
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var err := ""
	if typeof(parsed) == TYPE_DICTIONARY:
		err = str((parsed as Dictionary).get("error", ""))
	if err == "":
		_inflight.clear()
		_fails = 0
		return
	## 被封鎖、或伺服器端整個關掉回報：這是決定不是暫時的失敗，不必等湊滿次數
	if err.find("blocked") >= 0 or err.find("off") >= 0:
		_inflight.clear()
		_queue.clear()
		_muted = true
		return
	_after_fail()


## 送失敗一律丟掉不重送。重送只會在伺服器出事時把佇列變成炸彈，
## 而少幾筆體驗資料完全不影響結論。
func _after_fail() -> void:
	_inflight.clear()
	_fails += 1
	if _fails >= FAIL_GIVE_UP:
		_muted = true
		_queue.clear()


func _notification(what: int) -> void:
	## 關遊戲前盡量把最後一批送掉；送不完就算了，不擋玩家關視窗
	if what != NOTIFICATION_WM_CLOSE_REQUEST and what != NOTIFICATION_EXIT_TREE:
		return
	## EXIT_TREE 進來時 HTTPRequest 已經跟著離開場景樹，這一發必定失敗，
	## 只會在每個同意回報的玩家關遊戲時留下一行紅色錯誤。
	## 這一批本來就是「送到就賺到」，發不出去就安靜收工。
	if _http == null or not _http.is_inside_tree():
		return
	if is_active() and not _queue.is_empty():
		track("session_tick", {"sec": _session_sec(), "chapter": str(GameState.chapter)})
		flush()


func _app_version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", "0"))
	return v.substr(0, 16)


func _new_uuid() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() % 256
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var hex := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]


## ── 玩家面文字 ──

## 同意畫面的說明。講清楚送什麼、不送什麼、關掉會怎樣。
func consent_prompt_bbcode() -> String:
	var lines: PackedStringArray = []
	lines.append(_t("[b]幫忙讓這趟旅途更好走[/b]"))
	lines.append("")
	lines.append(_t("打開之後，遊戲會回報幾個數字：你走到第幾章、在哪裡倒下、"))
	lines.append(_t("哪一場打了幾次、教學看到第幾則、這次玩了多久。"))
	lines.append(_t("我們靠這些知道哪一段太硬、哪一段太悶，然後去改它。"))
	lines.append("")
	lines.append(_t("不會送出：你的名字、信箱、存檔、留言，任何看得出你是誰的東西。"))
	lines.append(_t("連線關掉的時候，一個字也不會送。"))
	lines.append("")
	lines.append(_t("不打開，遊戲一模一樣。隨時可以關，關了就立刻停。"))
	return "\n".join(lines)


func status_line() -> String:
	if not consent:
		return _t("體驗回報：關閉")
	if not is_active():
		return _t("體驗回報：已同意（目前離線，不會送出）")
	return _t("體驗回報：開啟")
