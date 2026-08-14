extends Node
## Supabase Realtime WebSocket（Postgres Changes）。
## 失敗時 RoomSystem 自動改用 HTTP 輪詢。
## Autoload：RealtimeBridge

signal connected
signal disconnected
signal event_received(table: String, row: Dictionary)
signal status_line(text: String)

var _ws: WebSocketPeer
var _active: bool = false
var _joined: bool = false
var _room_filter: String = ""  ## room_id uuid
var _ref_i: int = 0
var _heartbeat_acc: float = 0.0
var _reconnect_acc: float = 0.0
var _want_connect: bool = false
var last_status: String = "未連 Realtime"


func is_live() -> bool:
	return _active and _joined and _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func status() -> String:
	return last_status


func subscribe_room_events(room_id: String) -> void:
	_room_filter = room_id.strip_edges()
	_want_connect = _room_filter != "" and OnlineGate.is_signed_in()
	if not _want_connect:
		_teardown()
		return
	_connect_ws()


func unsubscribe() -> void:
	_want_connect = false
	_room_filter = ""
	_teardown()


func _teardown() -> void:
	_active = false
	_joined = false
	if _ws:
		_ws.close()
		_ws = null
	last_status = "Realtime 已斷"
	disconnected.emit()
	status_line.emit(last_status)


func _connect_ws() -> void:
	if not OnlineGate.is_signed_in() or not OnlineGate.is_configured():
		last_status = "Realtime 需上線"
		status_line.emit(last_status)
		return
	var base := OnlineGate.supabase_url.replace("https://", "wss://").replace("http://", "ws://")
	var url := "%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [
		base, OnlineGate.supabase_anon_key.uri_encode()
	]
	_ws = WebSocketPeer.new()
	## 帶 Authorization 需 Godot 4 支援；部分版本用 URL apikey 即可
	var err := _ws.connect_to_url(url)
	if err != OK:
		last_status = "Realtime 連線失敗 %s" % err
		status_line.emit(last_status)
		_ws = null
		return
	_active = true
	_joined = false
	last_status = "Realtime 連線中…"
	status_line.emit(last_status)


func _process(delta: float) -> void:
	if _ws == null:
		if _want_connect:
			_reconnect_acc += delta
			if _reconnect_acc >= 4.0:
				_reconnect_acc = 0.0
				_connect_ws()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	match st:
		WebSocketPeer.STATE_OPEN:
			if not _joined and _room_filter != "":
				_send_join()
			_heartbeat_acc += delta
			if _heartbeat_acc >= 25.0:
				_heartbeat_acc = 0.0
				_send_heartbeat()
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet().get_string_from_utf8()
				_handle_msg(pkt)
		WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
			_active = false
			_joined = false
			_ws = null
			last_status = "Realtime 斷線（將用輪詢）"
			disconnected.emit()
			status_line.emit(last_status)


func _next_ref() -> String:
	_ref_i += 1
	return str(_ref_i)


func _send_join() -> void:
	var topic := "realtime:room-events-%s" % _room_filter.substr(0, 8)
	var payload := {
		"config": {
			"broadcast": {"ack": false, "self": false},
			"presence": {"key": OnlineGate.user_id},
			"postgres_changes": [{
				"event": "INSERT",
				"schema": "public",
				"table": "room_events",
				"filter": "room_id=eq.%s" % _room_filter,
			}],
		}
	}
	var msg := {
		"topic": topic,
		"event": "phx_join",
		"payload": payload,
		"ref": _next_ref(),
		"join_ref": _next_ref(),
	}
	## Supabase 新版 topic 常用 realtime:public:room_events
	var msg2 := {
		"topic": "realtime:public:room_events",
		"event": "phx_join",
		"payload": payload,
		"ref": _next_ref(),
		"join_ref": _next_ref(),
	}
	_send_json(msg2)
	_joined = true
	last_status = "Realtime 已訂閱"
	connected.emit()
	status_line.emit(last_status)


func _send_heartbeat() -> void:
	_send_json({
		"topic": "phoenix",
		"event": "heartbeat",
		"payload": {},
		"ref": _next_ref(),
	})


func _send_json(obj: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(obj))


func _handle_msg(text: String) -> void:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var ev := str(data.get("event", ""))
	var payload: Variant = data.get("payload", {})
	if ev == "phx_reply":
		if payload is Dictionary and str(payload.get("status", "")) == "ok":
			_joined = true
			last_status = "Realtime 頻道 OK"
			status_line.emit(last_status)
		elif payload is Dictionary and str(payload.get("status", "")) == "error":
			last_status = "Realtime 訂閱失敗（用輪詢）"
			status_line.emit(last_status)
		return
	if ev == "postgres_changes" or ev == "INSERT":
		_emit_change(payload)
		return
	## 某些版本包在 payload.data
	if payload is Dictionary:
		var inner: Variant = payload.get("data", null)
		if inner is Dictionary and str(payload.get("type", "")) == "postgres_changes":
			_emit_change(inner)
		elif payload.has("record"):
			_emit_change(payload)


func _emit_change(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	var p: Dictionary = payload
	var rec: Variant = p.get("record", p.get("data", {}))
	if rec is Dictionary and (rec as Dictionary).has("payload"):
		## data.record style
		event_received.emit("room_events", rec)
		return
	if rec is Dictionary and (rec as Dictionary).has("record"):
		var r2: Variant = (rec as Dictionary).get("record", {})
		if r2 is Dictionary:
			event_received.emit("room_events", r2)
			return
	## payload = { columns..., record: {} }
	var record: Variant = p.get("record", {})
	if record is Dictionary and not (record as Dictionary).is_empty():
		event_received.emit("room_events", record)
