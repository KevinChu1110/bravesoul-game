extends Node
## 真多人房：裂縫 + 狩獵 + Realtime 同屏轉播。
## 房主跑 BattleSim；成員可觀戰（WS 優先，HTTP 輪詢 fallback）。
## Autoload：RoomSystem

signal lobby_updated
signal room_event(kind: String, data: Dictionary)
signal spectate_event(kind: String, payload: Dictionary)
signal spectate_ended(won: bool)

const POLL_SEC := 2.5
const SPECTATE_POLL_SEC := 0.4
const MAX_PLAYERS := 4
const COOP_GOLD_PER_MEMBER := 40
const COOP_ATK_PER_MEMBER := 2
const COOP_DEF_PER_MEMBER := 1
const MODE_HUNT := "hunt"
const BROADCAST_MIN_INTERVAL := 0.45
const INPUT_POLL_IDLE := 0.22
const INPUT_POLL_HOT := 0.12  ## 連招窗期間更快拉


var current_room: Dictionary = {}
var members: Array = []
var open_rooms: Array = []
var filter_kind: String = "rift"  ## rift | hunt · 瀏覽用
var _poll_acc: float = 0.0
var _in_lobby: bool = false
var _is_host: bool = false
var _battle_started_local: bool = false
var last_created_code: String = ""
var estimated_rtt_ms: float = 120.0
var sync_window_hot: bool = false  ## 房主／觀戰端：連招窗開啟中

## Realtime 同屏
var spectating: bool = false
var coop_controlling: bool = false  ## 成員可操作
var last_snap: Dictionary = {}
var _event_seq: int = 0
var _last_event_id: int = 0
var _last_input_id: int = 0
var _broadcast_acc: float = 99.0
var _spectate_poll_acc: float = 0.0
var _input_poll_acc: float = 0.0
var _realtime_hooked: bool = false
var _input_send_cd: Dictionary = {}  ## kind -> last sec


func _ready() -> void:
	call_deferred("_hook_realtime")


func _hook_realtime() -> void:
	if _realtime_hooked:
		return
	_realtime_hooked = true
	if Engine.get_main_loop() is SceneTree:
		var rb: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RealtimeBridge")
		if rb and rb.has_signal("event_received"):
			rb.event_received.connect(_on_realtime_row)


func _process(delta: float) -> void:
	if (spectating or coop_controlling) and OnlineGate.is_signed_in():
		## WS 活著就少輪詢事件
		var live := false
		if Engine.get_main_loop() is SceneTree:
			var rb: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RealtimeBridge")
			if rb and rb.has_method("is_live"):
				live = bool(rb.call("is_live"))
		_spectate_poll_acc += delta
		var need := SPECTATE_POLL_SEC if not live else 2.0
		if _spectate_poll_acc >= need:
			_spectate_poll_acc = 0.0
			_poll_events()
	## 房主拉成員輸入（連招窗期間加速）
	if should_broadcast() and OnlineGate.is_signed_in():
		_input_poll_acc += delta
		var ipoll := INPUT_POLL_HOT if sync_window_hot else INPUT_POLL_IDLE
		if _input_poll_acc >= ipoll:
			_input_poll_acc = 0.0
			_poll_inputs()
	if not _in_lobby:
		return
	if not OnlineGate.is_signed_in():
		return
	_poll_acc += delta
	if _poll_acc < POLL_SEC:
		return
	_poll_acc = 0.0
	_poll_once()


func is_in_room() -> bool:
	return not current_room.is_empty() and str(current_room.get("id", "")) != ""


func room_id() -> String:
	return str(current_room.get("id", ""))


func room_mode() -> String:
	return str(current_room.get("mode", "wrath"))


func room_status() -> String:
	return str(current_room.get("status", ""))


func room_code() -> String:
	return str(current_room.get("code", last_created_code))


func is_host() -> bool:
	return _is_host


func is_hunt_room() -> bool:
	return room_mode() == MODE_HUNT


func is_rift_room() -> bool:
	return is_in_room() and not is_hunt_room()


func member_count() -> int:
	return maxi(1, members.size())


func online_ready() -> bool:
	return OnlineGate.is_signed_in()


func leave_silent() -> void:
	stop_spectate()
	_in_lobby = false
	_battle_started_local = false
	current_room = {}
	members = []
	_is_host = false
	_event_seq = 0
	_last_event_id = 0
	_last_input_id = 0
	last_snap = {}
	_input_send_cd.clear()


func mode_display(mode: String = "") -> String:
	var m := mode if mode != "" else room_mode()
	if m == MODE_HUNT:
		return "狩獵場"
	return RiftSchedule.mode_name(m)


## 房主開戰加成（真人同房人數）
func battle_player_stats_patch() -> Dictionary:
	if not is_in_room():
		return {}
	if room_status() != "fighting" and not _battle_started_local:
		return {}
	var n := member_count()
	if n <= 1:
		return {}
	return {
		"atk": (n - 1) * COOP_ATK_PER_MEMBER,
		"def": (n - 1) * COOP_DEF_PER_MEMBER,
	}


func apply_stats_to_dict(stats: Dictionary) -> Dictionary:
	var p := battle_player_stats_patch()
	if p.is_empty():
		return stats
	if p.has("atk"):
		stats["atk"] = int(stats.get("atk", 0)) + int(p["atk"])
	if p.has("def"):
		stats["def"] = int(stats.get("def", 0)) + int(p["def"])
	return stats


func status_bbcode(kind: String = "") -> String:
	var k := kind if kind != "" else filter_kind
	var lines: PackedStringArray = []
	if k == "hunt":
		lines.append("[b]狩獵房 · 組隊刷材料[/b]")
		lines.append("房主打 3 波；成員待機，通關共領材料與金。")
	else:
		lines.append("[b]裂縫房 · 組隊挑戰[/b]")
		lines.append("房主權威戰鬥；成員待機，通關後共領獎勵。")
	lines.append("房主權威戰鬥；成員可【同屏觀戰】（Realtime／快輪詢）。")
	lines.append("主線仍單人。")
	lines.append("")
	if not online_ready():
		lines.append("[color=#c96]需關閉純單機並訪客上線，才能開／進真房。[/color]")
		if k == "rift":
			lines.append("離線請用「星途助戰」。")
		else:
			lines.append("離線請用單人狩獵（可帶助戰）。")
		return "\n".join(lines)
	if not is_in_room():
		lines.append("未在房間內。可建立或加入開放房。")
		lines.append("開放房數（快取）：%d" % open_rooms.size())
		if last_created_code != "":
			lines.append("上次建房代碼：%s" % last_created_code)
		return "\n".join(lines)
	lines.append("房號代碼：[b]%s[/b]" % room_code())
	lines.append("類型：%s · 狀態：%s" % [mode_display(), room_status()])
	lines.append("你是：%s · 人數：%d／%d" % ["房主" if _is_host else "成員", member_count(), MAX_PLAYERS])
	lines.append("成員：")
	for m in members:
		var ready := "✓" if bool(m.get("is_ready", false)) else "·"
		var host_mark := "★" if str(m.get("user_id", "")) == str(current_room.get("host_id", "")) else " "
		lines.append("  %s%s %s" % [host_mark, ready, str(m.get("display_name", "?"))])
	var res := str(current_room.get("result", ""))
	if res != "":
		lines.append("結果：%s" % res)
	return "\n".join(lines)


func create_room(mode: String, cb: Callable = Callable()) -> void:
	if not online_ready():
		_fail_cb(cb, "請先上線。")
		return
	if mode != MODE_HUNT and mode not in RiftSchedule.MODES:
		mode = RiftSchedule.featured_mode()
	var code := _gen_code()
	last_created_code = code
	OnlineGate.room_create(mode, code, MAX_PLAYERS, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_fail_cb(cb, str(res.get("msg", "建房失敗")))
			return
		current_room = res.get("room", {})
		if str(current_room.get("code", "")) == "":
			current_room["code"] = code
		_is_host = true
		_in_lobby = true
		_battle_started_local = false
		filter_kind = "hunt" if mode == MODE_HUNT else "rift"
		_poll_once()
		if cb.is_valid():
			cb.call({"ok": true, "msg": "房間已建立。代碼 %s（可給隊友）" % code, "code": code})
		lobby_updated.emit()
	)


func create_hunt_room(cb: Callable = Callable()) -> void:
	create_room(MODE_HUNT, cb)


func join_room_id(rid: String, cb: Callable = Callable()) -> void:
	if not online_ready():
		_fail_cb(cb, "請先上線。")
		return
	OnlineGate.room_join(rid, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_fail_cb(cb, str(res.get("msg", "加入失敗")))
			return
		current_room = res.get("room", {"id": rid})
		_is_host = str(current_room.get("host_id", "")) == OnlineGate.user_id
		_in_lobby = true
		_battle_started_local = false
		if is_hunt_room():
			filter_kind = "hunt"
		else:
			filter_kind = "rift"
		_poll_once()
		if cb.is_valid():
			cb.call({"ok": true, "msg": "已加入房間 %s。" % room_code()})
		lobby_updated.emit()
	)


func join_by_code(code: String, cb: Callable = Callable()) -> void:
	if not online_ready():
		_fail_cb(cb, "請先上線。")
		return
	code = code.strip_edges().to_upper()
	if code.length() < 4:
		_fail_cb(cb, "代碼太短。")
		return
	OnlineGate.room_find_by_code(code, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_fail_cb(cb, str(res.get("msg", "找不到房間")))
			return
		var room: Dictionary = res.get("room", {})
		join_room_id(str(room.get("id", "")), cb)
	)


func refresh_open_rooms(cb: Callable = Callable(), kind: String = "") -> void:
	if kind != "":
		filter_kind = kind
	if not online_ready():
		open_rooms = []
		if cb.is_valid():
			cb.call({"ok": true, "list": []})
		return
	var mode_filter := MODE_HUNT if filter_kind == "hunt" else ""
	## rift：拉全部再過濾掉 hunt
	OnlineGate.room_list_open(func(res: Dictionary):
		var raw: Array = res.get("list", []) if bool(res.get("ok", false)) else []
		var filtered: Array = []
		for row in raw:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var m := str(row.get("mode", ""))
			if filter_kind == "hunt":
				if m == MODE_HUNT:
					filtered.append(row)
			else:
				if m != MODE_HUNT:
					filtered.append(row)
		open_rooms = filtered
		if cb.is_valid():
			cb.call({"ok": true, "list": open_rooms})
		lobby_updated.emit()
	, mode_filter if filter_kind == "hunt" else "")


func set_ready(ready: bool = true, cb: Callable = Callable()) -> void:
	if not is_in_room():
		_fail_cb(cb, "不在房間內。")
		return
	OnlineGate.room_set_ready(room_id(), ready, func(res: Dictionary):
		_poll_once()
		if cb.is_valid():
			cb.call(res)
	)


func leave_room(cb: Callable = Callable()) -> void:
	if not is_in_room():
		leave_silent()
		if cb.is_valid():
			cb.call({"ok": true})
		return
	var rid := room_id()
	OnlineGate.room_leave(rid, func(res: Dictionary):
		leave_silent()
		if cb.is_valid():
			cb.call(res if res is Dictionary else {"ok": true})
		lobby_updated.emit()
	)


## 房主開始：房間 → fighting
func host_start_battle(cb: Callable = Callable()) -> void:
	if not is_in_room() or not _is_host:
		_fail_cb(cb, "只有房主可開戰。")
		return
	if room_status() == "fighting":
		_battle_started_local = true
		if cb.is_valid():
			cb.call({
				"ok": true,
				"mode": room_mode(),
				"hunt": is_hunt_room(),
				"msg": "繼續挑戰",
			})
		return
	OnlineGate.room_set_status(room_id(), "fighting", func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_fail_cb(cb, str(res.get("msg", "無法開戰")))
			return
		current_room["status"] = "fighting"
		_battle_started_local = true
		PartySystem.begin_party_battle()
		if cb.is_valid():
			cb.call({
				"ok": true,
				"mode": room_mode(),
				"hunt": is_hunt_room(),
				"msg": "開戰！人數加成 ×%d" % member_count(),
			})
		room_event.emit("start", {"mode": room_mode(), "hunt": is_hunt_room()})
	)


func host_report_result(won: bool, cb: Callable = Callable()) -> void:
	if not is_in_room():
		if cb.is_valid():
			cb.call({"ok": true, "local_only": true})
		return
	var result := "win" if won else "lose"
	var was_hunt := is_hunt_room()
	OnlineGate.room_report_result(room_id(), result, func(res: Dictionary):
		current_room["result"] = result
		current_room["status"] = "closed" if won else "open"
		_battle_started_local = false
		var bonus := _grant_coop_reward(won, was_hunt)
		if cb.is_valid():
			var out: Dictionary = res.duplicate() if res is Dictionary else {"ok": true}
			out["bonus_msg"] = bonus
			out["won"] = won
			out["hunt"] = was_hunt
			cb.call(out)
		lobby_updated.emit()
	)


func claim_member_reward(cb: Callable = Callable()) -> void:
	if not is_in_room():
		_fail_cb(cb, "不在房間。")
		return
	if str(current_room.get("result", "")) != "win":
		_fail_cb(cb, "尚無勝利結果。")
		return
	var was_hunt := is_hunt_room()
	OnlineGate.room_claim_reward(room_id(), func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_fail_cb(cb, str(res.get("msg", "領獎失敗")))
			return
		var msg := _grant_coop_reward(true, was_hunt)
		if cb.is_valid():
			cb.call({"ok": true, "msg": msg})
	)


func _grant_coop_reward(won: bool, hunt: bool = false) -> String:
	if not won:
		return "共鬥未勝，無額外獎。"
	var n := member_count()
	var gold_n: int
	if hunt:
		gold_n = 50 + (n - 1) * 25
	else:
		gold_n = 80 + (n - 1) * COOP_GOLD_PER_MEMBER
		if not RiftSchedule.current_attempt_rewarded():
			gold_n = int(gold_n * 0.35)
	GameState.add_gold(gold_n)
	var parts: PackedStringArray = ["金 +%d" % gold_n]
	if hunt:
		## 共獵材料
		var hide_n := 1 + (1 if n >= 2 else 0)
		var bone_n := 1 if n >= 2 else 0
		if InventorySystem.add_item("hunt_hide", hide_n):
			parts.append("溢皮×%d" % hide_n)
		if bone_n > 0 and InventorySystem.add_item("hunt_bone", bone_n):
			parts.append("焰骨×%d" % bone_n)
		if n >= 3 and randf() < 0.4 and InventorySystem.add_item("hunt_core", 1):
			parts.append("溢核×1")
		GameState.set_flag("room.hunt_coop_wins", int(GameState.get_flag("room.hunt_coop_wins", 0)) + 1)
	else:
		var dust := 1 if n >= 2 else 0
		if dust > 0:
			GameState.stardust += dust
			parts.append("星屑 +%d" % dust)
		GameState.set_flag("room.coop_wins", int(GameState.get_flag("room.coop_wins", 0)) + 1)
	SaveManager.save_game()
	return "共鬥獎：%s（%d 人）" % [" · ".join(parts), n]


func poll_now() -> void:
	_poll_once()


## ── Realtime 同屏：房主推事件 ──

func should_broadcast() -> bool:
	return is_in_room() and _is_host and (_battle_started_local or room_status() == "fighting") \
		and OnlineGate.is_signed_in()


func broadcast_battle(kind: String, payload: Dictionary, force: bool = false) -> void:
	if not should_broadcast():
		return
	if not force and kind == "snap":
		_broadcast_acc += 0.0  ## 由 tick 控制
	_event_seq += 1
	var rid := room_id()
	var body := payload.duplicate(true)
	body["t"] = Time.get_ticks_msec()
	body["host"] = OnlineGate.display_name
	OnlineGate.room_push_event(rid, kind, body, _event_seq)
	if kind == "snap":
		last_snap = body


func broadcast_snap(player_hp: int, player_max: int, enemy_hp: int, enemy_max: int, enemy_name: String, log_line: String = "") -> void:
	if not should_broadcast():
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if _broadcast_acc > 0.0 and (now - _broadcast_acc) < BROADCAST_MIN_INTERVAL:
		return
	_broadcast_acc = now
	broadcast_battle("snap", {
		"php": player_hp,
		"pmax": player_max,
		"ehp": enemy_hp,
		"emax": enemy_max,
		"ename": enemy_name,
		"log": log_line,
		"mode": room_mode(),
	})


func broadcast_action(action_kind: String, text: String, extra: Dictionary = {}) -> void:
	if not should_broadcast():
		return
	var p := extra.duplicate(true)
	p["action"] = action_kind
	p["text"] = text
	p["mode"] = room_mode()
	broadcast_battle("action", p, true)


func broadcast_start(mode: String) -> void:
	_event_seq = 0
	_last_event_id = 0
	_broadcast_acc = 0.0
	broadcast_battle("battle_start", {
		"mode": mode,
		"host": OnlineGate.display_name,
		"members": member_count(),
	}, true)


func broadcast_end(won: bool) -> void:
	broadcast_battle("end", {
		"won": won,
		"mode": room_mode(),
	}, true)


## ── 成員觀戰 ──

func start_spectate() -> Dictionary:
	return start_coop_control(false)


## 成員同屏操作（可輸入）；pure_watch=true 僅觀戰
func start_coop_control(can_input: bool = true) -> Dictionary:
	if not is_in_room():
		return {"ok": false, "msg": "不在房間內。"}
	if _is_host:
		return {"ok": false, "msg": "房主請直接開戰。"}
	if not OnlineGate.is_signed_in():
		return {"ok": false, "msg": "需上線。"}
	spectating = true
	coop_controlling = can_input
	_last_event_id = 0
	_last_input_id = 0
	last_snap = {}
	if Engine.get_main_loop() is SceneTree:
		var rb: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RealtimeBridge")
		if rb and rb.has_method("subscribe_room_events"):
			rb.call("subscribe_room_events", room_id())
	_poll_events()
	var msg := "同屏操作：J 格擋／連招 · K 戰意 · L 助攻" if can_input else "同屏觀戰"
	return {"ok": true, "msg": msg, "mode": room_mode(), "coop": can_input}


func stop_spectate() -> void:
	spectating = false
	coop_controlling = false
	if Engine.get_main_loop() is SceneTree:
		var rb: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RealtimeBridge")
		if rb and rb.has_method("unsubscribe"):
			rb.call("unsubscribe")


func is_spectating() -> bool:
	return spectating


func is_coop_controlling() -> bool:
	return coop_controlling


## 成員送出操作（節流 + 時間戳供延遲補償）
func send_member_input(kind: String, payload: Dictionary = {}) -> Dictionary:
	if not coop_controlling or not is_in_room():
		return {"ok": false, "msg": "目前無法操作"}
	if not OnlineGate.is_signed_in():
		return {"ok": false, "msg": "未上線"}
	var now := float(Time.get_ticks_msec()) / 1000.0
	var cd := 0.28
	if kind == "assist":
		cd = 1.0
	if kind == "skill":
		cd = 0.65
	if kind in ["parry", "sync", "react"] and sync_window_hot:
		cd = 0.12  ## 連招窗內幾乎無 CD
	var last := float(_input_send_cd.get(kind, 0.0))
	if now - last < cd:
		return {"ok": false, "msg": "冷卻中"}
	_input_send_cd[kind] = now
	var body: Dictionary = payload.duplicate(true)
	body["client_ms"] = Time.get_ticks_msec()
	body["sent_unix"] = Time.get_unix_time_from_system()
	OnlineGate.room_push_input(room_id(), kind, body)
	## 本地預測回饋
	room_event.emit("local_input_sent", {"kind": kind, "predict": true})
	var label := kind
	match kind:
		"sync", "parry", "react":
			label = "格擋／連招"
		"skill":
			label = "戰意"
		"assist":
			label = "助攻"
	return {"ok": true, "msg": "已送出【%s】（預測已顯示）" % label, "kind": kind}


func _poll_inputs() -> void:
	if not is_in_room() or not _is_host:
		return
	OnlineGate.room_fetch_inputs(room_id(), _last_input_id, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			return
		for row in res.get("list", []):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = row
			var iid := int(d.get("id", 0))
			if iid > _last_input_id:
				_last_input_id = iid
			## 忽略房主自己的（房主本地直接操作）
			if str(d.get("user_id", "")) == OnlineGate.user_id:
				continue
			var pay: Variant = d.get("payload", {})
			var pdict: Dictionary = pay if typeof(pay) == TYPE_DICTIONARY else {}
			## 估計 RTT：若有 client sent_unix
			var rtt := estimated_rtt_ms
			if pdict.has("sent_unix"):
				var sent := float(pdict.get("sent_unix", 0.0))
				var now_u := Time.get_unix_time_from_system()
				if sent > 1000000000.0:
					rtt = clampf((now_u - sent) * 1000.0, 20.0, 800.0)
					estimated_rtt_ms = lerpf(estimated_rtt_ms, rtt, 0.3)
			room_event.emit("remote_input", {
				"kind": str(d.get("kind", "")),
				"who": str(d.get("display_name", "旅人")),
				"payload": pdict,
				"id": iid,
				"rtt_ms": estimated_rtt_ms,
			})
	)


func set_sync_window_hot(v: bool) -> void:
	sync_window_hot = v


func realtime_status() -> String:
	if Engine.get_main_loop() is SceneTree:
		var rb: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RealtimeBridge")
		if rb and rb.has_method("status"):
			return str(rb.call("status"))
	return ""


func _poll_events() -> void:
	if not is_in_room():
		return
	OnlineGate.room_fetch_events(room_id(), _last_event_id, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			return
		for row in res.get("list", []):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			_ingest_event_row(row)
	)


func _on_realtime_row(table: String, row: Dictionary) -> void:
	if table != "room_events":
		return
	if str(row.get("room_id", "")) != room_id():
		return
	_ingest_event_row(row)


func _ingest_event_row(row: Dictionary) -> void:
	var eid := int(row.get("id", 0))
	if eid > 0 and eid <= _last_event_id:
		return
	if eid > _last_event_id:
		_last_event_id = eid
	var kind := str(row.get("kind", ""))
	var payload: Variant = row.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	var p: Dictionary = payload
	if kind == "snap":
		last_snap = p
	spectate_event.emit(kind, p)
	room_event.emit(kind, p)
	if kind == "end":
		var won := bool(p.get("won", false))
		spectate_ended.emit(won)


func _poll_once() -> void:
	if not is_in_room():
		return
	var rid := room_id()
	OnlineGate.room_fetch(rid, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			return
		var room: Dictionary = res.get("room", {})
		if not room.is_empty():
			current_room = room
			_is_host = str(room.get("host_id", "")) == OnlineGate.user_id
		members = res.get("members", [])
		if not _is_host and str(current_room.get("status", "")) == "fighting":
			room_event.emit("host_fighting", {})
		if not _is_host and str(current_room.get("result", "")) == "win":
			room_event.emit("host_won", {})
		lobby_updated.emit()
	)


func _gen_code() -> String:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 6:
		s += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return s


func _fail_cb(cb: Callable, msg: String) -> void:
	if cb.is_valid():
		cb.call({"ok": false, "msg": msg})
