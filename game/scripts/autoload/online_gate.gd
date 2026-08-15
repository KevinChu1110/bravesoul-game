extends Node
## 連線閘門：純單機優先；無後端設定時全 no-op。
## 設定：user://online_settings.json
## 文件：docs/ONLINE.md · docs/ONLINE_SETUP.md

signal status_changed
signal save_conflict(local_updated: String, cloud_updated: String, cloud_payload: Dictionary)

const SaveMigration = preload("res://scripts/autoload/save_migration.gd")

const SETTINGS_PATH := "user://online_settings.json"
const SESSION_PATH := "user://online_session.json"

var offline_only: bool = true
var display_name: String = "星途旅人"
var supabase_url: String = ""
var supabase_anon_key: String = ""

var user_id: String = ""
var access_token: String = ""
var last_error: String = ""
var last_status: String = "純單機"
var last_health: String = "尚未檢測"
var last_health_ok: bool = false
var last_health_ms: int = -1
## 伺服器認定的可交易金幣（影子帳）。市集買東西是扣這一筆，不是扣存檔裡的數字。
var ledger_gold: int = -1
var _http: HTTPRequest
var _busy: bool = false
var _pending: Callable = Callable()
var _queue: Array = []  ## [{method, path, body, auth, prefer, cb}]
var _health_t0: int = 0


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
	display_name = str(data.get("display_name", "星途旅人"))
	supabase_url = str(data.get("supabase_url", "")).strip_edges()
	supabase_anon_key = str(data.get("supabase_anon_key", "")).strip_edges()


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"offline_only": offline_only,
		"display_name": display_name,
		"supabase_url": supabase_url,
		"supabase_anon_key": supabase_anon_key,
	}, "\t"))


func set_offline_only(v: bool) -> void:
	offline_only = v
	save_settings()
	_refresh_status()
	status_changed.emit()


func set_display_name(n: String) -> void:
	display_name = n.strip_edges()
	if display_name == "":
		display_name = "星途旅人"
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
		last_status = "純單機（連線已關）"
	elif not is_configured():
		last_status = "連線關 · 未設定後端"
	elif user_id == "":
		last_status = "可上線 · 未登入"
	else:
		last_status = "已上線 · %s" % user_id.substr(0, mini(8, user_id.length()))


func _save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"user_id": user_id,
		"access_token": access_token,
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
	_refresh_status()


func sign_out() -> void:
	user_id = ""
	access_token = ""
	ledger_gold = -1
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	last_error = ""
	_refresh_status()
	status_changed.emit()


## ── 公開 API（全部可在離線時安全呼叫）──

func sign_in_anonymous(cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_fail("純單機或未設定後端", cb)
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
		_fail("純單機或未設定後端", cb)
		return
	email = email.strip_edges()
	if email.find("@") < 1 or password.length() < 6:
		_fail("信箱無效或密碼少於 6 字", cb)
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
		_fail("純單機或未設定後端", cb)
		return
	email = email.strip_edges()
	if email.find("@") < 1 or password.length() < 1:
		_fail("請輸入信箱與密碼", cb)
		return
	_request(
		"POST",
		"/auth/v1/token?grant_type=password",
		{"email": email, "password": password},
		false,
		_cb_sign_in.bind(cb)
	)


func _cb_sign_in(cb: Callable, ok: bool, body: Variant) -> void:
	if ok:
		_parse_auth(body, cb)
	else:
		_fail("訪客登入失敗：請在 Supabase 開啟 Anonymous Auth。%s" % last_error, cb)


func _parse_auth(body: Variant, cb: Callable) -> void:
	if typeof(body) != TYPE_DICTIONARY:
		_fail("登入回應無效", cb)
		return
	access_token = str(body.get("access_token", ""))
	var user: Variant = body.get("user", {})
	if user is Dictionary:
		user_id = str(user.get("id", ""))
	if user_id == "" and body.has("id"):
		user_id = str(body.get("id", ""))
	if access_token == "" or user_id == "":
		_fail("登入缺 token／user", cb)
		return
	_save_session()
	last_error = ""
	_refresh_status()
	status_changed.emit()
	upsert_profile()
	_ok({"user_id": user_id}, cb)


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
		_fail("未上線", cb)
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


func _cb_push_save(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "推送失敗"), cb)
		return
	ledger_gold = int(row.get("ledger_gold", ledger_gold))
	_ok({"msg": "雲存檔已推送", "ledger_gold": ledger_gold}, cb)


func pull_cloud_save(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request("GET", "/rest/v1/saves?user_id=eq.%s&select=*" % user_id, null, true, _cb_pull_save.bind(cb))


func _cb_pull_save(cb: Callable, ok: bool, body: Variant) -> void:
	if not ok:
		_fail(last_error if last_error != "" else "拉取失敗", cb)
		return
	if body is Array and (body as Array).is_empty():
		_ok({"empty": true, "msg": "雲端尚無存檔"}, cb)
		return
	var row: Dictionary = {}
	if body is Array:
		row = (body as Array)[0]
	elif body is Dictionary:
		row = body
	var cloud_payload: Variant = row.get("payload", {})
	if typeof(cloud_payload) != TYPE_DICTIONARY:
		_fail("雲存檔格式錯誤", cb)
		return
	var cloud_t := str(row.get("updated_at", ""))
	## 雲端那份可能是別台機器、更早的版本推上來的，跟本地檔一樣要先升級。
	## 這裡漏掉的話，跨裝置同步會變成把舊格式直接灌進 GameState。
	var res: Dictionary = SaveMigration.migrate(cloud_payload)
	if not bool(res.get("ok", false)):
		_fail("雲存檔來自更新的版本" if bool(res.get("future", false)) else "雲存檔格式錯誤", cb)
		return
	GameState.from_dict(res.get("data", {}))
	SaveManager.save_game()
	_ok({"msg": "已套用雲存檔", "updated_at": cloud_t}, cb)


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
		_fail("未上線", cb)
		return
	var t := body_text.strip_edges()
	if t.length() < 1 or t.length() > 80:
		_fail("留言需 1～80 字", cb)
		return
	var body := {"user_id": user_id, "place": place, "body": t}
	_request("POST", "/rest/v1/messages", body, true, _cb_msg_post.bind(cb), "return=minimal")


func _cb_msg_post(cb: Callable, ok: bool, _b: Variant) -> void:
	if ok:
		_ok({"msg": "已留下足跡"}, cb)
	else:
		_fail(last_error if last_error != "" else "留言失敗", cb)


func fetch_messages(place: String, cb: Callable = Callable()) -> void:
	if not is_online_enabled():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/messages?place=eq.%s&order=created_at.desc&limit=30" % place.uri_encode()
	_request("GET", path, null, true, _cb_list.bind(cb))


func _cb_list(cb: Callable, ok: bool, body: Variant) -> void:
	var list: Array = []
	if ok and body is Array:
		list = body
	_ok({"list": list}, cb)


func candle_increment(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request("POST", "/rest/v1/rpc/candle_increment", {}, true, _cb_candle.bind(cb))


func _cb_candle(cb: Callable, ok: bool, body: Variant) -> void:
	if ok:
		_ok({"total": body}, cb)
	else:
		_fail("點燈失敗", cb)


## ── 市集 API ──

func market_fetch_listings(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_ok({"list": []}, cb)
		return
	_request(
		"GET",
		"/rest/v1/market_listings?status=eq.active&order=created_at.desc&limit=40&select=*",
		null,
		true,
		_cb_list.bind(cb)
	)


func market_create_listing(item_id: String, qty: int, price: int, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"POST",
		"/rest/v1/rpc/market_list_item",
		{"p_item_id": item_id, "p_qty": qty, "p_price": price},
		true,
		_cb_market_create.bind(cb)
	)


func _cb_market_create(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "上架失敗"), cb)
		return
	_ok({"msg": "上架成功", "row": row}, cb)


func market_cancel_listing(listing_id: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	## 下架與退貨在伺服器同一筆交易裡做完，不會退兩次
	_request(
		"POST",
		"/rest/v1/rpc/market_cancel_listing",
		{"p_listing_id": _as_listing_id(listing_id)},
		true,
		_cb_market_cancel_done.bind(cb)
	)


func _cb_market_cancel_done(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "下架失敗"), cb)
		return
	_ok({
		"msg": "已下架",
		"item_id": str(row.get("item_id", "")),
		"qty": int(row.get("qty", 0)),
	}, cb)


func market_buy(listing_id: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"POST",
		"/rest/v1/rpc/market_buy",
		{"p_listing_id": _as_listing_id(listing_id)},
		true,
		_cb_market_buy.bind(cb)
	)


func _cb_market_buy(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or row.is_empty() or str(row.get("error", "")) != "":
		if row.has("ledger_gold"):
			ledger_gold = int(row.get("ledger_gold", ledger_gold))
		_fail(_rpc_error(ok, row, "購買被拒"), cb)
		return
	_ok({
		"item_id": str(row.get("item_id", "")),
		"qty": int(row.get("qty", 1)),
		"price": int(row.get("price", 0)),
		"msg": "購買成功",
	}, cb)


func market_claim_credit(cb: Callable = Callable()) -> void:
	if not is_signed_in():
		return
	_request("POST", "/rest/v1/rpc/market_claim_credit", {}, true, _cb_market_claim.bind(cb))


func _cb_market_claim(cb: Callable, ok: bool, body: Variant) -> void:
	if ok and body is Dictionary:
		var g := int(body.get("gold", 0))
		if g > 0:
			GameState.add_gold(g)
			SaveManager.save_game()
	if cb.is_valid():
		cb.call({"ok": ok, "body": body})


## ── 房間 API ──

func room_create(mode: String, code: String, max_players: int, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	var body := {
		"host_id": user_id,
		"mode": mode,
		"status": "open",
		"max_players": max_players,
		"code": code,
		"result": "",
	}
	_request("POST", "/rest/v1/rooms", body, true, _cb_room_create.bind(cb), "return=representation")


func _cb_room_create(cb: Callable, ok: bool, body: Variant) -> void:
	if not ok:
		_fail(last_error if last_error != "" else "建房失敗", cb)
		return
	var room: Dictionary = {}
	if body is Array and not (body as Array).is_empty():
		room = (body as Array)[0]
	elif body is Dictionary:
		room = body
	var rid := str(room.get("id", ""))
	if rid == "":
		_fail("建房無 id", cb)
		return
	_request(
		"POST",
		"/rest/v1/room_members",
		{
			"room_id": rid,
			"user_id": user_id,
			"display_name": display_name,
			"is_ready": true,
			"reward_claimed": false,
		},
		true,
		_cb_room_create_join.bind(room, cb),
		"return=minimal"
	)


func _cb_room_create_join(room: Dictionary, cb: Callable, ok: bool, _b: Variant) -> void:
	if ok:
		_ok({"room": room, "msg": "建房成功"}, cb)
	else:
		_fail("建房後入座失敗", cb)


func room_list_open(cb: Callable = Callable(), mode_filter: String = "") -> void:
	if not is_signed_in():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/rooms?status=eq.open&order=updated_at.desc&limit=30&select=*"
	if mode_filter != "":
		path = "/rest/v1/rooms?status=eq.open&mode=eq.%s&order=updated_at.desc&limit=30&select=*" % mode_filter.uri_encode()
	_request("GET", path, null, true, _cb_list.bind(cb))


func room_find_by_code(code: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"GET",
		"/rest/v1/rooms?code=eq.%s&status=eq.open&select=*" % code.uri_encode(),
		null,
		true,
		_cb_room_find.bind(cb)
	)


func _cb_room_find(cb: Callable, ok: bool, body: Variant) -> void:
	if not ok or not (body is Array) or (body as Array).is_empty():
		_fail("找不到開放房間", cb)
		return
	_ok({"room": (body as Array)[0]}, cb)


func room_join(room_id: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"GET",
		"/rest/v1/rooms?id=eq.%s&select=*" % room_id.uri_encode(),
		null,
		true,
		_cb_room_join_fetch.bind(room_id, cb)
	)


func _cb_room_join_fetch(room_id: String, cb: Callable, ok: bool, body: Variant) -> void:
	if not ok or not (body is Array) or (body as Array).is_empty():
		_fail("房間不存在", cb)
		return
	var room: Dictionary = (body as Array)[0]
	if str(room.get("status", "")) != "open":
		_fail("房間已關閉或開戰", cb)
		return
	_request(
		"POST",
		"/rest/v1/room_members",
		{
			"room_id": room_id,
			"user_id": user_id,
			"display_name": display_name,
			"is_ready": false,
			"reward_claimed": false,
		},
		true,
		_cb_room_join_insert.bind(room_id, room, cb),
		"return=minimal"
	)


func _cb_room_join_insert(room_id: String, room: Dictionary, cb: Callable, ok: bool, _b: Variant) -> void:
	if not ok:
		_fail(last_error if last_error != "" else "加入失敗（可能已滿或已在房）", cb)
		return
	_request(
		"PATCH",
		"/rest/v1/rooms?id=eq.%s" % room_id.uri_encode(),
		{"updated_at": Time.get_datetime_string_from_system(true)},
		true,
		Callable(),
		"return=minimal"
	)
	_ok({"room": room, "msg": "已加入"}, cb)


func room_fetch(room_id: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"GET",
		"/rest/v1/rooms?id=eq.%s&select=*" % room_id.uri_encode(),
		null,
		true,
		_cb_room_fetch.bind(room_id, cb)
	)


func _cb_room_fetch(room_id: String, cb: Callable, ok: bool, body: Variant) -> void:
	if not ok:
		_fail("拉房間失敗", cb)
		return
	var room: Dictionary = {}
	if body is Array and not (body as Array).is_empty():
		room = (body as Array)[0]
	_request(
		"GET",
		"/rest/v1/room_members?room_id=eq.%s&select=*&order=joined_at.asc" % room_id.uri_encode(),
		null,
		true,
		_cb_room_fetch_members.bind(room, cb)
	)


func _cb_room_fetch_members(room: Dictionary, cb: Callable, ok: bool, body: Variant) -> void:
	var mem: Array = body if (ok and body is Array) else []
	_ok({"room": room, "members": mem}, cb)


func room_set_ready(room_id: String, ready: bool, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"PATCH",
		"/rest/v1/room_members?room_id=eq.%s&user_id=eq.%s" % [room_id.uri_encode(), user_id],
		{"is_ready": ready},
		true,
		_cb_simple_ok.bind("就緒狀態已更新", "更新就緒失敗", cb),
		"return=minimal"
	)


func room_set_status(room_id: String, status: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"PATCH",
		"/rest/v1/rooms?id=eq.%s&host_id=eq.%s" % [room_id.uri_encode(), user_id],
		{"status": status, "updated_at": Time.get_datetime_string_from_system(true)},
		true,
		_cb_simple_ok.bind("狀態 %s" % status, "改狀態失敗", cb),
		"return=minimal"
	)


func room_report_result(room_id: String, result: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	## 結果與房主自己的領獎標記由伺服器一起蓋，避免重複結算
	_request(
		"POST",
		"/rest/v1/rpc/room_report_result",
		{"p_room_id": room_id, "p_result": result},
		true,
		_cb_room_report.bind(result, cb)
	)


func _cb_room_report(result: String, cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "回報失敗"), cb)
		return
	_ok({"msg": "結果已回報", "result": result}, cb)


func room_claim_reward(room_id: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	## 「查完再標」中間有空隙可以連點兩次；改成伺服器一筆搞定
	_request(
		"POST",
		"/rest/v1/rpc/room_claim_reward",
		{"p_room_id": room_id},
		true,
		_cb_room_claim.bind(cb)
	)


func _cb_room_claim(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "領獎失敗"), cb)
		return
	_ok({"msg": "可領獎"}, cb)


## ── Realtime 事件（HTTP 推／拉；WS 見 RealtimeBridge）──

func room_push_event(room_id: String, kind: String, payload: Dictionary, seq: int = 0, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		return
	var body := {
		"room_id": room_id,
		"kind": kind,
		"seq": seq,
		"payload": payload,
	}
	_request(
		"POST",
		"/rest/v1/room_events",
		body,
		true,
		_cb_simple_ok.bind("event", "push fail", cb) if cb.is_valid() else Callable(),
		"return=minimal"
	)


func room_fetch_events(room_id: String, after_id: int, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/room_events?room_id=eq.%s&id=gt.%d&order=id.asc&limit=40&select=*" % [
		room_id.uri_encode(), after_id
	]
	_request("GET", path, null, true, _cb_list.bind(cb))


func room_push_input(room_id: String, kind: String, payload: Dictionary = {}, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	var body := {
		"room_id": room_id,
		"user_id": user_id,
		"display_name": display_name,
		"kind": kind,
		"payload": payload,
	}
	_request(
		"POST",
		"/rest/v1/room_inputs",
		body,
		true,
		_cb_simple_ok.bind("輸入已送出", "輸入失敗", cb) if cb.is_valid() else Callable(),
		"return=minimal"
	)


func room_fetch_inputs(room_id: String, after_id: int, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_ok({"list": []}, cb)
		return
	var path := "/rest/v1/room_inputs?room_id=eq.%s&id=gt.%d&order=id.asc&limit=30&select=*" % [
		room_id.uri_encode(), after_id
	]
	_request("GET", path, null, true, _cb_list.bind(cb))


func room_leave(room_id: String, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_ok({"msg": "已離"}, cb)
		return
	_request(
		"DELETE",
		"/rest/v1/room_members?room_id=eq.%s&user_id=eq.%s" % [room_id.uri_encode(), user_id],
		null,
		true,
		_cb_room_leave.bind(room_id, cb),
		"return=minimal"
	)


func _cb_room_leave(room_id: String, cb: Callable, ok: bool, _b: Variant) -> void:
	_request(
		"PATCH",
		"/rest/v1/rooms?id=eq.%s&host_id=eq.%s&status=eq.open" % [room_id.uri_encode(), user_id],
		{"status": "closed", "updated_at": Time.get_datetime_string_from_system(true)},
		true,
		Callable(),
		"return=minimal"
	)
	_ok({"msg": "已離開", "ok_http": ok}, cb)


func _cb_simple_ok(ok_msg: String, fail_msg: String, cb: Callable, ok: bool, _b: Variant) -> void:
	if ok:
		_ok({"msg": ok_msg}, cb)
	else:
		_fail(fail_msg, cb)


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


func _as_listing_id(listing_id: String) -> Variant:
	if listing_id.is_valid_int():
		return int(listing_id)
	if listing_id.is_valid_float():
		return int(float(listing_id))
	return listing_id


## ── 排行榜／影子帳 ──

func leaderboard_submit(board: String, score: int, cb: Callable = Callable()) -> void:
	if not is_signed_in():
		_fail("未上線", cb)
		return
	_request(
		"POST",
		"/rest/v1/rpc/leaderboard_submit",
		{"p_board": board, "p_score": maxi(0, score)},
		true,
		_cb_leaderboard.bind(cb)
	)


func _cb_leaderboard(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "上榜失敗"), cb)
		return
	_ok({"msg": "已記錄", "score": int(row.get("score", 0))}, cb)


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


func _cb_ledger(cb: Callable, ok: bool, body: Variant) -> void:
	var row := _rpc_row(body)
	if not ok or str(row.get("error", "")) != "":
		_fail(_rpc_error(ok, row, "查詢餘額失敗"), cb)
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
	lines.append("[b]連線／星途[/b]")
	var lamp := "●" if last_health_ok else "○"
	var lamp_c := "#6c6" if last_health_ok else "#a55"
	lines.append("狀態：%s" % last_status)
	lines.append("健康：[color=%s]%s %s[/color]" % [lamp_c, lamp, last_health])
	if last_health_ms >= 0:
		lines.append("延遲：約 %d ms" % last_health_ms)
	if last_error != "":
		lines.append("[color=#a55]最近錯誤：%s[/color]" % humanize_error(last_error))
	if is_signed_in() and ledger_gold >= 0:
		lines.append("市集可用金幣：%d" % ledger_gold)
	lines.append("顯示名：%s" % display_name)
	lines.append("純單機：%s" % ("是" if offline_only else "否"))
	lines.append("後端：%s" % ("已設定" if is_configured() else "未設定"))
	if is_configured():
		var host := supabase_url.replace("https://", "").replace("http://", "")
		if host.length() > 28:
			host = host.substr(0, 28) + "…"
		lines.append("URL：%s" % host)
	lines.append("")
	lines.append("不連線也能走完整趟旅途。連上之後多了：雲端存檔、旅人殘影、留言石、市集、裂縫房。")
	return "\n".join(lines)


## 把 API 技術錯誤翻成玩家可讀中文
func humanize_error(raw: String) -> String:
	var s := raw.strip_edges()
	if s == "":
		return ""
	var low := s.to_lower()
	## 市集／共鬥的伺服器判定
	if "not signed in" in low:
		return "尚未登入，請先上線"
	if "bad payload" in low:
		return "存檔內容有問題，無法上傳"
	if "bad result" in low:
		return "戰果格式不對"
	if "bad board" in low:
		return "榜別不對"
	if "score out of range" in low:
		return "分數超出合理範圍"
	if "not enough gold" in low:
		return "可用金幣不足（市集認的是伺服器那筆餘額，先推一次雲存檔試試）"
	if "not enough items" in low:
		return "伺服器還沒認到這些材料，先推一次雲存檔再上架"
	if "price out of range" in low:
		return "訂價超出合理範圍，請調低一點"
	if "item not tradeable" in low:
		return "此物不可上架"
	if "bad qty" in low:
		return "數量不對"
	if "too many listings" in low:
		return "掛單已達上限，先下架幾筆"
	if "daily listing limit" in low:
		return "今天上架次數已達上限"
	if "market blocked" in low:
		return "此帳號的市集功能已停用"
	if "listing gone" in low:
		return "這筆掛單已被買走或下架"
	if "cannot buy own" in low:
		return "不能買自己的掛單"
	if "already claimed" in low or "already settled" in low:
		return "這份獎勵已經領過了"
	if "no win yet" in low:
		return "這場還沒打贏"
	if "not a member" in low:
		return "你不在這個房間裡"
	if "not host" in low:
		return "只有房主能回報結果"
	if "room gone" in low:
		return "房間已經不在了"
	if "reward_claimed is server-managed" in low:
		return "領獎狀態由伺服器管理，請用遊戲內的領獎鍵"
	if "payload too large" in low:
		return "存檔太大，無法上傳"
	if "message rate limit" in low:
		return "留言太頻繁，喘口氣再說"
	if "anonymous_provider_disabled" in low or "anonymous sign-ins are disabled" in low:
		return "訪客登入未開啟（請在 Supabase Auth 開啟 Anonymous）"
	if "email_address_invalid" in low:
		return "Email 格式無效，請用真實信箱格式"
	if "invalid_credentials" in low or "invalid login" in low:
		return "帳號或密碼錯誤"
	if "user_already_exists" in low or "already registered" in low:
		return "此 Email 已註冊，請直接登入"
	if "email_not_confirmed" in low:
		return "信箱尚未驗證（開發可在 Dashboard 關閉 Confirm email）"
	if "pgrst205" in low or "could not find the table" in low:
		return "資料表尚未建立（需執行 supabase/schema.sql）"
	if "jwt" in low and ("expired" in low or "invalid" in low):
		return "登入已過期，請重新登入"
	if "permission" in low or "rls" in low or "42501" in low:
		return "沒有權限（請確認已登入且 RLS 政策正確）"
	if "network" in low or "failed to connect" in low or "timed out" in low:
		return "網路連不上後端，請檢查網址與網路"
	if "secret api key required" in low:
		return "金鑰類型不對（請用 publishable／anon key，不要用 service_role）"
	if "未設定後端" in s or "純單機" in s:
		return s
	if s.begins_with("HTTP "):
		## 截短
		if s.length() > 100:
			return "伺服器回應異常：" + s.substr(0, 100) + "…"
		return "伺服器回應異常：" + s
	if s.length() > 120:
		return s.substr(0, 120) + "…"
	return s


## 健康檢查：Auth health + REST 探活
func health_check(cb: Callable = Callable()) -> void:
	if offline_only:
		last_health_ok = false
		last_health = "純單機模式（未連線）"
		last_health_ms = -1
		if cb.is_valid():
			cb.call({"ok": false, "msg": last_health, "health": last_health})
		return
	if not is_configured():
		last_health_ok = false
		last_health = "未設定 URL／金鑰"
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


func _cb_health_auth(cb: Callable, ok: bool, body: Variant) -> void:
	if not ok:
		last_health_ok = false
		last_health = humanize_error(last_error if last_error != "" else "Auth 探活失敗")
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


func _cb_health_rest(cb: Callable, ok: bool, body: Variant) -> void:
	last_health_ms = Time.get_ticks_msec() - _health_t0
	if not ok:
		var err := humanize_error(last_error)
		## 表不存在特別標
		if "PGRST205" in last_error or "找不到" in err or "could not find the table" in last_error.to_lower():
			last_health = "後端通，但缺資料表（請跑 schema）"
		else:
			last_health = err if err != "" else "REST 探活失敗"
		last_health_ok = false
		_fail(last_health, cb)
		return
	last_health_ok = true
	var who := "已登入" if is_signed_in() else "未登入（僅探活）"
	last_health = "正常 · %s · %d ms" % [who, last_health_ms]
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
		_fail("未設定後端", cb0)
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
			_fail("未知 method", _pending)
			_pending = Callable()
			_pump_queue()
			return
	if err != OK:
		_busy = false
		var pcb := _pending
		_pending = Callable()
		_fail("HTTP 啟動失敗 %s" % err, pcb)
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
