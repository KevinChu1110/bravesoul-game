extends Node
## 連線閘門：純單機優先；無後端設定時全 no-op。
## 設定：user://online_settings.json
## 文件：docs/ONLINE.md · docs/ONLINE_SETUP.md

signal status_changed
signal save_conflict(local_updated: String, cloud_updated: String, cloud_payload: Dictionary)

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const SaveMigration = preload("res://scripts/autoload/save_migration.gd")

const SETTINGS_PATH := "user://online_settings.json"
const SESSION_PATH := "user://online_session.json"

var offline_only: bool = true
var display_name: String = _t("星途旅人")
var supabase_url: String = ""
var supabase_anon_key: String = ""

var user_id: String = ""
var access_token: String = ""
var last_error: String = ""
var last_status: String = _t("純單機")
var last_health: String = _t("尚未檢測")
var last_health_ok: bool = false
var last_health_ms: int = -1
## 伺服器認定的可交易金幣（影子帳）。市集買東西是扣這一筆，不是扣存檔裡的數字。
var ledger_gold: int = -1
## 通關蠟燭總數（全服）。-1＝尚未拉過；離線顯示用 GameState 快取。
var candle_total: int = -1
var refresh_token: String = ""
var _http: HTTPRequest
var _busy: bool = false
var _pending: Callable = Callable()
var _queue: Array = []  ## [{method, path, body, auth, prefer, cb}]
var _health_t0: int = 0
var _candle_fetching: bool = false
## OAuth（Google / Discord / Facebook / X）
const OAuthCallbackServer = preload("res://scripts/autoload/oauth_callback_server.gd")
const OAUTH_PROVIDERS: PackedStringArray = ["google", "discord", "facebook", "twitter"]
## Supabase redirect_to：官網靜態頁（再轉回本機 8765 給遊戲收 token）
const OAUTH_WEB_REDIRECT := "https://kevinchu1110.github.io/bravesoul-game/pages/auth-callback.html"
var oauth_redirect_url: String = OAUTH_WEB_REDIRECT
var _oauth: RefCounted = null  ## OAuthCallbackServer
var _oauth_cb: Callable = Callable()
var _oauth_provider: String = ""
var _oauth_deadline_msec: int = 0



## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	load_settings()
	_load_session()
	_refresh_status()


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		save_settings()
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	offline_only = bool(data.get("offline_only", true))
	display_name = str(data.get("display_name", _t("星途旅人")))
	supabase_url = str(data.get("supabase_url", "")).strip_edges()
	supabase_anon_key = str(data.get("supabase_anon_key", "")).strip_edges()
	var redir := str(data.get("oauth_redirect_url", "")).strip_edges()
	oauth_redirect_url = redir if redir != "" else OAUTH_WEB_REDIRECT


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"offline_only": offline_only,
		"display_name": display_name,
		"supabase_url": supabase_url,
		"supabase_anon_key": supabase_anon_key,
		"oauth_redirect_url": oauth_redirect_url,
	}, "\t"))


func set_offline_only(v: bool) -> void:
	offline_only = v
	save_settings()
	_refresh_status()
	status_changed.emit()


func set_display_name(n: String) -> void:
	display_name = n.strip_edges()
	if display_name == "":
		display_name = _t("星途旅人")
	save_settings()
	status_changed.emit()


func set_backend(url: String, anon_key: String) -> void:
	supabase_url = url.strip_edges().trim_suffix("/")
	supabase_anon_key = anon_key.strip_edges()
	save_settings()
	_refresh_status()
	status_changed.emit()


func is_configured() -> bool:
	return supabase_url != "" and supabase_anon_key != ""


func is_online_enabled() -> bool:
	return not offline_only and is_configured()


func is_signed_in() -> bool:
	return is_online_enabled() and user_id != "" and access_token != ""


func status_line() -> String:
	return last_status


func _refresh_status() -> void:
	if offline_only:
		last_status = _t("純單機（連線已關）")
	elif not is_configured():
		last_status = _t("連線關 · 未設定後端")
	elif user_id == "":
		last_status = _t("可上線 · 未登入")
	else:
		last_status = _t("已上線 · %s") % user_id.substr(0, mini(8, user_id.length()))


func _save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"user_id": user_id,
		"access_token": access_token,
		"refresh_token": refresh_token,
	}, "\t"))


func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	user_id = str(data.get("user_id", ""))
	access_token = str(data.get("access_token", ""))
	refresh_token = str(data.get("refresh_token", ""))
	_refresh_status()


func sign_out() -> void:
	_oauth_cancel()
	user_id = ""
	access_token = ""
	refresh_token = ""
	ledger_gold = -1
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	last_error = ""
	_refresh_status()
	status_changed.emit()


## ⚠ `_cb_*` 的參數順序：**cb 一定要放最後一個**。
##
## 送出時寫的是 `_cb_xxx.bind(cb)`，而 Godot 的 `Callable.bind()` 是把綁定的參數
## 接在**呼叫端參數的後面**，不是前面。HTTP 回來時呼叫的是 `cb.call(ok, body)`，
## 所以實際簽名是 `(ok, body, cb)`。
##
## 這十支原本全部宣告成 `(cb, ok, body)` —— 第一個參數就型別不符，
## Godot 只噴一行 "Invalid type in function" 然後把整個回呼丟掉。
## 結果是連線面板每一顆按鈕都毫無反應：不是「連不上會失敗」，
## 是**連失敗都通知不到玩家**，狀態列永遠停在「尚未檢測」。
##
## 這種錯不會讓遊戲當掉，也不會讓測試變紅（離線路徑根本走不到 _cb_*），
## 所以加一支 test_online_callbacks.gd 直接對簽名下斷言。

## ── 公開 API（全部可在離線時安全呼叫）──

func sign_in_anonymous(cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_fail(_t("純單機或未設定後端"), cb)
		return
	_request(
		"POST",
		"/auth/v1/signup",
		{"data": {"app": "cuiling_bravesoul"}},
		false,
		_cb_sign_in.bind(cb)
	)


## Email + 密碼註冊（Supabase Auth）
func sign_up_email(email: String, password: String, cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_fail(_t("純單機或未設定後端"), cb)
		return
	email = email.strip_edges()
	if email.find("@") < 1 or password.length() < 6:
		_fail(_t("信箱無效或密碼少於 6 字"), cb)
		return
	_request(
		"POST",
		"/auth/v1/signup",
		{"email": email, "password": password, "data": {"app": "cuiling_bravesoul"}},
		false,
		_cb_sign_in.bind(cb)
	)


## Email + 密碼登入
func sign_in_email(email: String, password: String, cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_fail(_t("純單機或未設定後端"), cb)
		return
	email = email.strip_edges()
	if email.find("@") < 1 or password.length() < 1:
		_fail(_t("請輸入信箱與密碼"), cb)
		return
	_request(
		"POST",
		"/auth/v1/token?grant_type=password",
		{"email": email, "password": password},
		false,
		_cb_sign_in.bind(cb)
	)


func _cb_sign_in(ok: bool, body: Variant, cb: Callable) -> void:
	if ok:
		_parse_auth(body, cb)
	else:
		_fail(_t("登入失敗：%s") % last_error, cb)


func _parse_auth(body: Variant, cb: Callable) -> void:
	if typeof(body) != TYPE_DICTIONARY:
		_fail(_t("登入回應無效"), cb)
		return
	access_token = str(body.get("access_token", ""))
	if body.has("refresh_token"):
		refresh_token = str(body.get("refresh_token", ""))
	var user: Variant = body.get("user", {})
	if user is Dictionary:
		user_id = str(user.get("id", ""))
		## OAuth 顯示名
		var meta: Variant = user.get("user_metadata", {})
		if meta is Dictionary:
			var dn := str(meta.get("full_name", meta.get("name", meta.get("user_name", ""))))
			if dn != "":
				display_name = dn
	if user_id == "" and body.has("id"):
		user_id = str(body.get("id", ""))
	if access_token == "":
		_fail(_t("登入缺 token"), cb)
		return
	if user_id == "":
		## OAuth hash 流程常只有 token → 再打 /user
		_request("GET", "/auth/v1/user", null, true, _cb_oauth_user.bind(cb))
		return
	_finish_sign_in(cb)


func _cb_oauth_user(ok: bool, body: Variant, cb: Callable) -> void:
	if not ok or typeof(body) != TYPE_DICTIONARY:
		_fail(_t("無法取得使用者資料"), cb)
		return
	user_id = str(body.get("id", ""))
	var meta: Variant = body.get("user_metadata", {})
	if meta is Dictionary:
		var dn := str(meta.get("full_name", meta.get("name", meta.get("user_name", ""))))
		if dn != "":
			display_name = dn
	if user_id == "":
		_fail(_t("登入缺 user id"), cb)
		return
	_finish_sign_in(cb)


func _finish_sign_in(cb: Callable) -> void:
	_save_session()
	last_error = ""
	_refresh_status()
	status_changed.emit()
	upsert_profile()
	refresh_candle_soft()
	_ok({"user_id": user_id, "display_name": display_name}, cb)


## ── Social OAuth（Google / Discord / Facebook / X=twitter）──

func oauth_provider_label(provider: String) -> String:
	match provider:
		"google":
			return "Google"
		"discord":
			return "Discord"
		"facebook":
			return "Facebook"
		"twitter":
			return "X"
		_:
			return provider


func sign_in_oauth(provider: String, cb: Callable = Callable()) -> void:
	provider = provider.strip_edges().to_lower()
	if provider == "x":
		provider = "twitter"
	if provider not in OAUTH_PROVIDERS:
		_fail(_t("不支援的登入方式：%s") % provider, cb)
		return
	if not is_online_enabled():
		_fail(_t("純單機或未設定後端"), cb)
		return
	_oauth_cancel()
	_oauth = OAuthCallbackServer.new()
	var err: Error = _oauth.listen()
	if err != OK:
		_oauth = null
		_fail(_t("無法開啟本機登入埠（8765 被占用？）"), cb)
		return
	_oauth_cb = cb
	_oauth_provider = provider
	_oauth_deadline_msec = Time.get_ticks_msec() + 180000  ## 3 分鐘
	## Supabase 導向官網 callback → 官網再轉本機 8765 給遊戲
	var redirect: String = oauth_redirect_url if oauth_redirect_url != "" else OAUTH_WEB_REDIRECT
	var url := "%s/auth/v1/authorize?provider=%s&redirect_to=%s" % [
		supabase_url.trim_suffix("/"),
		provider.uri_encode(),
		redirect.uri_encode(),
	]
	var open_err := OS.shell_open(url)
	if open_err != OK:
		_oauth_cancel()
		_fail(_t("無法開啟瀏覽器"), cb)
		return
	last_status = _t("瀏覽器登入中（%s）…") % oauth_provider_label(provider)
	status_changed.emit()


func _oauth_cancel() -> void:
	if _oauth != null and _oauth.has_method("stop"):
		_oauth.stop()
	_oauth = null
	_oauth_cb = Callable()
	_oauth_provider = ""
	_oauth_deadline_msec = 0


func _process(_delta: float) -> void:
	if _oauth == null:
		return
	if _oauth.has_method("poll"):
		_oauth.poll()
	if _oauth_deadline_msec > 0 and Time.get_ticks_msec() > _oauth_deadline_msec:
		var cb := _oauth_cb
		_oauth_cancel()
		_fail(_t("登入逾時，請重試"), cb)
		return
	if _oauth.has_method("is_done") and bool(_oauth.is_done()):
		var payload: Dictionary = _oauth.take_result() if _oauth.has_method("take_result") else {}
		var cb2 := _oauth_cb
		var prov := _oauth_provider
		_oauth_cancel()
		if not bool(payload.get("ok", false)):
			_fail(_t("%s 登入取消或失敗") % oauth_provider_label(prov), cb2)
			return
		access_token = str(payload.get("access_token", ""))
		refresh_token = str(payload.get("refresh_token", ""))
		if access_token == "":
			_fail(_t("未取得 access_token"), cb2)
			return
		## 用 token 換 user
		_request("GET", "/auth/v1/user", null, true, _cb_oauth_user.bind(cb2))


func upsert_profile() -> void:
	if not is_signed_in():
		return
	_request(
		"POST",
		"/rest/v1/profiles",
		{
			"user_id": user_id,
			"display_name": display_name,
			"updated_at": Time.get_datetime_string_from_system(true),
		},
		true,
		Callable(),
		"resolution=merge-duplicates,return=minimal"
	)


func push_cloud_save(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail(_t("未上線"), cb)
		return
	var payload: Dictionary = GameState.to_dict()
	## 存檔只能經 save_push 進資料庫；伺服器同時更新可交易金幣／物品的帳
	_request(
		"POST",
		"/rest/v1/rpc/save_push",
		{"p_payload": payload, "p_schema_version": int(payload.get("version", 1))},
		true,
		_cb_push_save.bind(cb)
	)


func _cb_push_save(ok: bool, body: Variant, cb: Callable) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, _t("推送失敗")), cb)
		return
	ledger_gold = int(row.get("ledger_gold", ledger_gold))
	_ok({"msg": _t("雲存檔已推送"), "ledger_gold": ledger_gold}, cb)


func pull_cloud_save(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail(_t("未上線"), cb)
		return
	_request("GET", "/rest/v1/saves?user_id=eq.%s&select=*" % user_id, null, true, _cb_pull_save.bind(cb))


func _cb_pull_save(ok: bool, body: Variant, cb: Callable) -> void:
	if not ok:
		_fail(last_error if last_error != "" else _t("拉取失敗"), cb)
		return
	if body is Array and (body as Array).is_empty():
		_ok({"empty": true, "msg": _t("雲端尚無存檔")}, cb)
		return
	var row: Dictionary = {}
	if body is Array:
		row = (body as Array)[0]
	elif body is Dictionary:
		row = body
	var cloud_payload: Variant = row.get("payload", {})
	if typeof(cloud_payload) != TYPE_DICTIONARY:
		_fail(_t("雲存檔格式錯誤"), cb)
		return
	var cloud_t := str(row.get("updated_at", ""))
	## 雲端那份可能是別台機器、更早的版本推上來的，跟本地檔一樣要先升級。
	## 這裡漏掉的話，跨裝置同步會變成把舊格式直接灌進 GameState。
	var res: Dictionary = SaveMigration.migrate(cloud_payload)
	if not bool(res.get("ok", false)):
		_fail(_t("雲存檔來自更新的版本") if bool(res.get("future", false)) else _t("雲存檔格式錯誤"), cb)
		return
	GameState.from_dict(res.get("data", {}))
	SaveManager.save_game()
	_ok({"msg": _t("已套用雲存檔"), "updated_at": cloud_t}, cb)


func push_presence(map_id: String, chapter: String = "") -> void:
	if not is_signed_in():
		return
	if chapter == "":
		chapter = GameState.chapter
	_request(
		"POST",
		"/rest/v1/presence",
		{
			"user_id": user_id,
			"display_name": display_name,
			"map_id": map_id,
			"chapter": chapter,
			"cosmetic": "",
			"updated_at": Time.get_datetime_string_from_system(true),
		},
		true,
		Callable(),
		"resolution=merge-duplicates,return=minimal"
	)


func fetch_presence(map_id: String, cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/presence?map_id=eq.%s&order=updated_at.desc&limit=20" % map_id.uri_encode()
	_request("GET", path, null, true, _cb_list.bind(cb))


func post_message(place: String, body_text: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail(_t("未上線"), cb)
		return
	var t := body_text.strip_edges()
	if t.length() < 1 or t.length() > 80:
		_fail(_t("留言需 1～80 字"), cb)
		return
	var body := {"user_id": user_id, "place": place, "body": t}
	_request("POST", "/rest/v1/messages", body, true, _cb_msg_post.bind(cb), "return=minimal")


func _cb_msg_post(ok: bool, _b: Variant, cb: Callable) -> void:
	if ok:
		_ok({"msg": _t("已留下足跡")}, cb)
	else:
		_fail(last_error if last_error != "" else _t("留言失敗"), cb)


func fetch_messages(place: String, cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/messages?place=eq.%s&order=created_at.desc&limit=30" % place.uri_encode()
	_request("GET", path, null, true, _cb_list.bind(cb))


func _cb_list(ok: bool, body: Variant, cb: Callable) -> void:
	var list: Array = []
	if ok and body is Array:
		list = body
	_ok({"list": list}, cb)


func candle_increment(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail(_t("未上線"), cb)
		return
	_request("POST", "/rest/v1/rpc/candle_increment", {}, true, _cb_candle.bind(cb))


func _cb_candle(ok: bool, body: Variant, cb: Callable) -> void:
	if ok:
		var total := _parse_candle_total(body)
		if total >= 0:
			_cache_candle_total(total)
		_ok({"total": total if total >= 0 else body}, cb)
	else:
		_fail(_t("點燈失敗"), cb)


## 讀全服燭火（不需登入，只需後端開啟）。結果快取到 candle_total／存檔。
func fetch_candle_total(cb: Callable = Callable(), force: bool = false) -> void:
	if not is_online_enabled():
		_ok({"total": candle_total_cached(), "cached": true}, cb)
		return
	if _candle_fetching and not force:
		_ok({"total": candle_total if candle_total >= 0 else candle_total_cached(), "pending": true}, cb)
		return
	_candle_fetching = true
	_request("GET", "/rest/v1/candles?id=eq.1&select=total", null, false, _cb_candle_fetch.bind(cb))


func _cb_candle_fetch(ok: bool, body: Variant, cb: Callable) -> void:
	_candle_fetching = false
	if not ok:
		_fail(last_error if last_error != "" else _t("讀取燭火失敗"), cb)
		return
	var total := _parse_candle_total(body)
	if total < 0 and body is Array and not (body as Array).is_empty():
		var row: Variant = (body as Array)[0]
		if row is Dictionary:
			total = int(row.get("total", -1))
	if total >= 0:
		_cache_candle_total(total)
	_ok({"total": total, "cached": false}, cb)


func _parse_candle_total(body: Variant) -> int:
	if typeof(body) == TYPE_INT or typeof(body) == TYPE_FLOAT:
		return int(body)
	if typeof(body) == TYPE_STRING and str(body).is_valid_int():
		return int(body)
	if body is Dictionary:
		return int(body.get("total", -1))
	if body is Array and not (body as Array).is_empty():
		var first: Variant = (body as Array)[0]
		if first is Dictionary:
			return int(first.get("total", -1))
		if typeof(first) == TYPE_INT or typeof(first) == TYPE_FLOAT:
			return int(first)
	return -1


func _cache_candle_total(total: int) -> void:
	candle_total = maxi(0, total)
	if Engine.get_main_loop() is SceneTree:
		var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
		if gs and gs.has_method("set_flag"):
			gs.call("set_flag", "meta.candle_total_cache", candle_total)


func candle_total_cached() -> int:
	if candle_total >= 0:
		return candle_total
	if Engine.get_main_loop() is SceneTree:
		var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
		if gs and gs.has_method("get_flag"):
			return int(gs.call("get_flag", "meta.candle_total_cache", -1))
	return -1


## UI 用：「晨光燭火：123 人」／快取／未知
func candle_line(compact: bool = false) -> String:
	var n := candle_total_cached()
	if n < 0:
		return _t("晨光燭火：—") if not compact else _t("燭火 —")
	if compact:
		return _t("燭火 %d") % n
	if candle_total >= 0:
		return _t("晨光燭火：%d 人點過") % n
	return _t("晨光燭火：%d 人（快取）") % n


## 標題／儀表板進場時軟拉一次（失敗安靜）
func refresh_candle_soft() -> void:
	if not is_online_enabled():
		return
	fetch_candle_total(Callable(), false)


## ── RPC 小工具 ──

## RPC 回來的可能是物件、也可能是包一層的陣列
func _rpc_row(body: Variant) -> Dictionary:
	if body is Dictionary:
		return body
	if body is Array and not (body as Array).is_empty():
		var first: Variant = (body as Array)[0]
		if first is Dictionary:
			return first
	return {}


func _rpc_error(http_ok: bool, row: Dictionary, fallback: String) -> String:
	var e := str(row.get("error", ""))
	if e != "":
		return e
	if not http_ok and last_error != "":
		return last_error
	return fallback


## ── 排行榜／影子帳 ──

func leaderboard_submit(board: String, score: int, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail(_t("未上線"), cb)
		return
	_request(
		"POST",
		"/rest/v1/rpc/leaderboard_submit",
		{"p_board": board, "p_score": maxi(0, score)},
		true,
		_cb_leaderboard.bind(cb)
	)


func _cb_leaderboard(ok: bool, body: Variant, cb: Callable) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, _t("上榜失敗")), cb)
		return
	_ok({"msg": _t("已記錄"), "score": int(row.get("score", 0))}, cb)


func leaderboard_fetch(board: String, cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/leaderboard?board=eq.%s&order=score.desc&limit=50&select=*" % board.uri_encode()
	_request("GET", path, null, true, _cb_list.bind(cb))


## 查伺服器認定的可交易餘額（市集面板顯示用）
func fetch_ledger(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_ok({"gold": 0, "items": {}}, cb)
		return
	_request("POST", "/rest/v1/rpc/econ_state", {}, true, _cb_ledger.bind(cb))


func _cb_ledger(ok: bool, body: Variant, cb: Callable) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, _t("查詢餘額失敗")), cb)
		return
	ledger_gold = int(row.get("gold", 0))
	var items: Variant = row.get("items", {})
	_ok({
		"gold": ledger_gold,
		"items": items if items is Dictionary else {},
		"seeded": bool(row.get("seeded", false)),
	}, cb)


func panel_bbcode() -> String:
	var lines: PackedStringArray = []
	lines.append(_t("[b]連線／星途[/b]"))
	var lamp := "●" if last_health_ok else "○"
	var lamp_c := "#6c6" if last_health_ok else "#a55"
	lines.append(_t("狀態：%s") % last_status)
	lines.append(_t("健康：[color=%s]%s %s[/color]") % [lamp_c, lamp, last_health])
	if last_health_ms >= 0:
		lines.append(_t("延遲：約 %d ms") % last_health_ms)
	if last_error != "":
		lines.append(_t("[color=#a55]最近錯誤：%s[/color]") % humanize_error(last_error))
	if is_signed_in() and ledger_gold >= 0:
		lines.append(_t("伺服器記錄的金幣：%d") % ledger_gold)
	lines.append(_t("顯示名：%s") % display_name)
	lines.append(_t("純單機：%s") % (_t("是") if offline_only else _t("否")))
	lines.append(_t("後端：%s") % (_t("已設定") if is_configured() else _t("未設定")))
	if is_configured():
		var host := supabase_url.replace("https://", "").replace("http://", "")
		if host.length() > 28:
			host = host.substr(0, 28) + "…"
		lines.append("URL：%s" % host)
	lines.append("")
	lines.append(candle_line(false))
	lines.append(_t("不連線也能走完整趟旅途。連上之後多了：雲端存檔、旅人殘影、留言石、通關蠟燭。"))
	return "\n".join(lines)


## 把 API 技術錯誤翻成玩家可讀中文
func humanize_error(raw: String) -> String:
	var s := raw.strip_edges()
	if s == "":
		return ""
	var low := s.to_lower()
	## 伺服器判定（supabase/economy.sql 會回的每一種）
	if "not signed in" in low:
		return _t("尚未登入，請先上線")
	if "bad payload" in low:
		return _t("存檔內容有問題，無法上傳")
	if "payload too large" in low:
		return _t("存檔太大，無法上傳")
	if "bad board" in low:
		return _t("榜別不對")
	if "score out of range" in low:
		return _t("分數超出合理範圍")
	if "message rate limit" in low:
		return _t("留言太頻繁，喘口氣再說")
	if "anonymous_provider_disabled" in low or "anonymous sign-ins are disabled" in low:
		return _t("訪客登入未開啟（請在 Supabase Auth 開啟 Anonymous）")
	if "email_address_invalid" in low:
		return _t("Email 格式無效，請用真實信箱格式")
	if "invalid_credentials" in low or "invalid login" in low:
		return _t("帳號或密碼錯誤")
	if "user_already_exists" in low or "already registered" in low:
		return _t("此 Email 已註冊，請直接登入")
	if "email_not_confirmed" in low:
		return _t("信箱尚未驗證（開發可在 Dashboard 關閉 Confirm email）")
	if "pgrst205" in low or "could not find the table" in low:
		return _t("資料表尚未建立（需執行 supabase/schema.sql）")
	if "jwt" in low and ("expired" in low or "invalid" in low):
		return _t("登入已過期，請重新登入")
	if "permission" in low or "rls" in low or "42501" in low:
		return _t("沒有權限（請確認已登入且 RLS 政策正確）")
	if "network" in low or "failed to connect" in low or "timed out" in low:
		return _t("網路連不上後端，請檢查網址與網路")
	if "secret api key required" in low:
		return _t("金鑰類型不對（請用 publishable／anon key，不要用 service_role）")
	if _t("未設定後端") in s or _t("純單機") in s:
		return s
	if s.begins_with("HTTP "):
		## 截短
		if s.length() > 100:
			return _t("伺服器回應異常：") + s.substr(0, 100) + "…"
		return _t("伺服器回應異常：") + s
	if s.length() > 120:
		return s.substr(0, 120) + "…"
	return s


## 健康檢查：Auth health + REST 探活
func health_check(cb: Callable = Callable()) -> void:
	if offline_only:
		last_health_ok = false
		last_health = _t("純單機模式（未連線）")
		last_health_ms = -1
		if cb.is_valid():
			cb.call({"ok": false, "msg": last_health, "health": last_health})
		return
	if not is_configured():
		last_health_ok = false
		last_health = _t("未設定 URL／金鑰")
		last_health_ms = -1
		if cb.is_valid():
			cb.call({"ok": false, "msg": last_health, "error": true, "health": last_health})
		return
	_health_t0 = Time.get_ticks_msec()
	## 先打 Auth health（不需登入）
	_request(
		"GET",
		"/auth/v1/health",
		null,
		false,
		_cb_health_auth.bind(cb)
	)


func _cb_health_auth(ok: bool, body: Variant, cb: Callable) -> void:
	if not ok:
		last_health_ok = false
		last_health = humanize_error(last_error if last_error != "" else _t("Auth 探活失敗"))
		last_health_ms = Time.get_ticks_msec() - _health_t0
		_fail(last_health, cb)
		return
	## 再探 REST（profiles 空表也 OK）
	_request(
		"GET",
		"/rest/v1/profiles?select=user_id&limit=1",
		null,
		true,
		_cb_health_rest.bind(cb)
	)


func _cb_health_rest(ok: bool, body: Variant, cb: Callable) -> void:
	last_health_ms = Time.get_ticks_msec() - _health_t0
	if not ok:
		var err := humanize_error(last_error)
		## 表不存在特別標
		if "PGRST205" in last_error or _t("找不到") in err or "could not find the table" in last_error.to_lower():
			last_health = _t("後端通，但缺資料表（請跑 schema）")
		else:
			last_health = err if err != "" else _t("REST 探活失敗")
		last_health_ok = false
		_fail(last_health, cb)
		return
	last_health_ok = true
	var who := _t("已登入") if is_signed_in() else _t("未登入（僅探活）")
	last_health = _t("正常 · %s · %d ms") % [who, last_health_ms]
	_refresh_status()
	status_changed.emit()
	_ok({"ok": true, "msg": last_health, "ms": last_health_ms, "health": last_health}, cb)


## ── HTTP（佇列）──

func _headers(auth: bool, prefer: String = "") -> PackedStringArray:
	var h := PackedStringArray()
	h.append("Content-Type: application/json")
	h.append("apikey: %s" % supabase_anon_key)
	if auth and access_token != "":
		h.append("Authorization: Bearer %s" % access_token)
	else:
		h.append("Authorization: Bearer %s" % supabase_anon_key)
	if prefer != "":
		h.append("Prefer: %s" % prefer)
	return h


func _request(
	method: String,
	path: String,
	body: Variant,
	use_user_auth: bool,
	cb: Callable = Callable(),
	prefer: String = ""
) -> void:
	_queue.append({
		"method": method,
		"path": path,
		"body": body,
		"auth": use_user_auth,
		"prefer": prefer,
		"cb": cb,
	})
	_pump_queue()


func _pump_queue() -> void:
	if _busy:
		return
	if _queue.is_empty():
		return
	if not is_configured():
		var job0: Dictionary = _queue.pop_front()
		var cb0: Callable = job0.get("cb", Callable())
		_fail(_t("未設定後端"), cb0)
		_pump_queue()
		return
	var job: Dictionary = _queue.pop_front()
	_busy = true
	_pending = job.get("cb", Callable())
	var method: String = str(job.get("method", "GET"))
	var path: String = str(job.get("path", ""))
	var body: Variant = job.get("body", null)
	var use_auth: bool = bool(job.get("auth", true))
	var prefer: String = str(job.get("prefer", ""))
	var url := supabase_url + path
	var headers := _headers(use_auth, prefer)
	var err: Error = OK
	match method:
		"GET":
			err = _http.request(url, headers, HTTPClient.METHOD_GET)
		"POST":
			var raw := "" if body == null else JSON.stringify(body)
			err = _http.request(url, headers, HTTPClient.METHOD_POST, raw)
		"PATCH":
			err = _http.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(body if body != null else {}))
		"DELETE":
			err = _http.request(url, headers, HTTPClient.METHOD_DELETE)
		_:
			_busy = false
			_fail(_t("未知 method"), _pending)
			_pending = Callable()
			_pump_queue()
			return
	if err != OK:
		_busy = false
		var pcb := _pending
		_pending = Callable()
		_fail(_t("HTTP 啟動失敗 %s") % err, pcb)
		_pump_queue()


func _on_http_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var cb := _pending
	_pending = Callable()
	var text := body.get_string_from_utf8()
	var parsed: Variant = null
	if text != "":
		parsed = JSON.parse_string(text)
	if response_code >= 200 and response_code < 300:
		last_error = ""
		if cb.is_valid():
			cb.call(true, parsed if parsed != null else text)
		_pump_queue()
		return
	var snippet := text.substr(0, 160)
	## 嘗試抽 JSON msg
	if parsed is Dictionary:
		var m := str(parsed.get("msg", parsed.get("message", parsed.get("error_description", ""))))
		var code := str(parsed.get("error_code", parsed.get("code", "")))
		if m != "":
			snippet = ("%s %s" % [code, m]).strip_edges()
	last_error = humanize_error("HTTP %d %s" % [response_code, snippet])
	if cb.is_valid():
		cb.call(false, parsed)
	_pump_queue()


func _ok(data: Dictionary, cb: Callable) -> void:
	last_error = ""
	var out := data.duplicate()
	if not out.has("ok"):
		out["ok"] = true
	if cb.is_valid():
		cb.call(out)


func _fail(msg: String, cb: Callable) -> void:
	last_error = humanize_error(msg) if msg != "" else msg
	## 保留原文若 humanize 太短且不像技術碼
	if last_error == "" and msg != "":
		last_error = msg
	_refresh_status()
	if cb.is_valid():
		cb.call({"ok": false, "msg": last_error, "error": true, "raw": msg})
