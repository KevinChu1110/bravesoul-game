extends RefCounted
## 裂縫房面板。
##
## 從 main.gd 抽出的第二塊。原本 259 行，是最纏的一段：既要畫面板、又要導覽到
## 連線設定／助戰／狩獵房，還要觸發開戰。
##
## 切法：**面板只負責畫面與房間狀態操作；開戰／觀戰留在 main.gd。**
## 開戰會拉起對話、消耗裂縫次數、切戰鬥場景，那是流程控制，不是面板的事。
##
## 宿主（main.gd）介面見 main.gd 的「面板宿主介面」段落。
## 導覽一律 ui_goto()，不要為了單一去處再加宿主方法。
##
## 刻意不用 class_name（見 AGENTS.md「寫測試的規矩」）。

var _host: Node


func _init(host: Node) -> void:
	_host = host


func _goto(target: String) -> Callable:
	return Callable(_host, "ui_goto").bind(target)


func open() -> void:
	RoomSystem.filter_kind = "rift"
	var body: String = RoomSystem.status_bbcode("rift")
	var buttons: Array = []

	## 還沒連線：只給設定與離線助戰
	if not RoomSystem.online_ready():
		buttons.append({"text": "連線設定", "cb": _goto("online")})
		buttons.append({"text": "星途助戰（離線）", "cb": _goto("party")})
		buttons.append({"text": "返回", "cb": _goto("postgame_hub")})
		_host.ui_panel("裂縫房", body, buttons)
		return

	if RoomSystem.is_in_room():
		## 人在狩獵房，先請他回去那邊
		if RoomSystem.is_hunt_room():
			body += "\n\n[color=#c96]你目前在狩獵房。[/color]"
			buttons.append({"text": "前往狩獵房", "cb": _goto("hunt_room")})
			buttons.append({"text": "離開當前房", "cb": leave})
			buttons.append({"text": "返回裂縫", "cb": _goto("postgame_hub")})
			_host.ui_panel("裂縫房", body, buttons)
			return
		buttons.append({"text": "刷新房間", "cb": refresh})
		if RoomSystem.is_host():
			if RoomSystem.room_status() == "open":
				buttons.append({"text": "開戰（房主）", "cb": Callable(_host, "ui_room_host_start")})
			elif RoomSystem.room_status() == "fighting":
				buttons.append({"text": "繼續挑戰", "cb": Callable(_host, "ui_room_host_start")})
		else:
			buttons.append({"text": "標記就緒", "cb": set_ready})
			if RoomSystem.room_status() == "fighting":
				buttons.append({"text": "同屏操作（可輸入）", "cb": Callable(_host, "ui_room_spectate").bind(true)})
				buttons.append({"text": "僅觀戰", "cb": Callable(_host, "ui_room_spectate").bind(false)})
			if str(RoomSystem.current_room.get("result", "")) == "win":
				buttons.append({"text": "領取共鬥獎", "cb": claim})
		var rt := RoomSystem.realtime_status()
		if rt != "":
			body += "\n[color=#aaa]%s[/color]" % rt
		if RoomSystem.is_host() and RoomSystem.estimated_rtt_ms > 0:
			body += "\n輸入延遲估：約 %.0f ms" % RoomSystem.estimated_rtt_ms
		body += "\n操作：J 格擋／連招 · K 戰意 · L 助攻"
		buttons.append({"text": "離開房間", "cb": leave})
		buttons.append({"text": "返回裂縫", "cb": _goto("postgame_hub")})
		_host.ui_panel("裂縫房 · %s" % RoomSystem.room_code(), body, buttons)
		return

	## 不在房裡：列開放房 + 建房
	buttons.append({"text": "刷新開放房", "cb": list_open})
	buttons.append({"text": "用代碼加入…", "cb": open_join_code})
	for mode in RiftSchedule.MODES:
		var m: String = mode
		buttons.append({"text": "建房·%s" % RiftSchedule.mode_name(m), "cb": create.bind(m)})
	buttons.append({"text": "返回", "cb": _goto("postgame_hub")})
	_host.ui_panel("裂縫房", body, buttons)
	RoomSystem.refresh_open_rooms(func(res: Dictionary):
		_show_browser(res.get("list", []))
	, "rift")


func _show_browser(list: Array) -> void:
	if RoomSystem.is_in_room() and RoomSystem.is_rift_room():
		open()
		return
	var body: String = RoomSystem.status_bbcode("rift") + "\n\n[b]開放裂縫房[/b]\n"
	var buttons: Array = []
	var n := 0
	for row in list:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if n >= 8:
			break
		var d: Dictionary = row
		var code := str(d.get("code", ""))
		var mode := str(d.get("mode", "wrath"))
		body += "· 代碼 [b]%s[/b] · %s\n" % [code, RiftSchedule.mode_name(mode)]
		buttons.append({
			"text": "加入 %s（%s）" % [code if code != "" else str(d.get("id", "")).substr(0, 6), RiftSchedule.mode_name(mode)],
			"cb": join.bind(str(d.get("id", ""))),
		})
		n += 1
	if n == 0:
		body += "（暫無開放房，可自建或用代碼加入）\n"
	buttons.append({"text": "用代碼加入…", "cb": open_join_code})
	for mode2 in RiftSchedule.MODES:
		var m2: String = mode2
		buttons.append({"text": "建房·%s" % RiftSchedule.mode_name(m2), "cb": create.bind(m2)})
	buttons.append({"text": "刷新", "cb": list_open})
	buttons.append({"text": "返回", "cb": _goto("postgame_hub")})
	_host.ui_panel("裂縫房", body, buttons)


## 這支要自己畫：帶 LineEdit 的輸入窗，ui_panel() 的 title/body/buttons 表達不了。
func open_join_code() -> void:
	var UiStyle = load("res://scripts/ui/ui_style.gd")
	_host.ui_clear_host()
	_host.ui_reset_fade()
	var layer := Control.new()
	layer.name = "JoinCodeLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.ui_host().add_child(layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.1, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var t := Label.new()
	t.text = "用代碼加入房間"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	root.add_child(t)
	var hint := Label.new()
	hint.text = "輸入房主顯示的 6 字代碼（不分大小寫）"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiStyle.CREAM_DIM)
	root.add_child(hint)
	var le := LineEdit.new()
	le.placeholder_text = "例如 A3K9MP"
	le.max_length = 8
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.add_theme_font_size_override("font_size", 22)
	le.custom_minimum_size = Vector2(0, 40)
	root.add_child(le)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	var btn_ok := Button.new()
	btn_ok.text = "加入"
	btn_ok.custom_minimum_size = Vector2(120, 36)
	row.add_child(btn_ok)
	var btn_back := Button.new()
	btn_back.text = "返回"
	btn_back.custom_minimum_size = Vector2(100, 36)
	row.add_child(btn_back)
	var do_join := func():
		var code := le.text.strip_edges().to_upper()
		if code.length() < 4:
			_host.ui_toast("代碼太短")
			return
		RoomSystem.join_by_code(code, func(res: Dictionary):
			_host.ui_toast(str(res.get("msg", "")))
			if bool(res.get("ok", false)):
				if RoomSystem.is_hunt_room():
					_host.ui_goto("hunt_room")
				else:
					open()
			else:
				open_join_code()
		)
	btn_ok.pressed.connect(do_join)
	le.text_submitted.connect(func(_t): do_join.call())
	btn_back.pressed.connect(func():
		if RoomSystem.filter_kind == "hunt":
			_host.ui_goto("hunt_room")
		else:
			open()
	)
	le.grab_focus()


func create(mode: String) -> void:
	RoomSystem.create_room(mode, func(res: Dictionary):
		_host.ui_toast(str(res.get("msg", "")))
		open()
	)


func join(rid: String) -> void:
	RoomSystem.join_room_id(rid, func(res: Dictionary):
		_host.ui_toast(str(res.get("msg", "")))
		open()
	)


func list_open() -> void:
	RoomSystem.refresh_open_rooms(func(res: Dictionary):
		_show_browser(res.get("list", []))
	, "rift")


func refresh() -> void:
	RoomSystem.poll_now()
	_host.ui_toast("已刷新")
	open()


func set_ready() -> void:
	RoomSystem.set_ready(true, func(res: Dictionary):
		_host.ui_toast(str(res.get("msg", "就緒")))
		open()
	)


func leave() -> void:
	RoomSystem.leave_room(func(_res: Dictionary):
		_host.ui_toast("已離開房間")
		open()
	)


func claim() -> void:
	RoomSystem.claim_member_reward(func(res: Dictionary):
		_host.ui_toast(str(res.get("msg", "")))
		open()
	)
