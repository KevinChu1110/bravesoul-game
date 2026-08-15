extends Control
## 路由器：可走探索 + 對話 + 戰鬥 + 鍛造面板

enum Screen {
	TITLE,
	C0_VILLAGE,
	C0_ROAD,
	BATTLE,
	C1_TOWN,
	C1_FORGE,
	C1_WILD,
	C1_AFTERMATH,
	C2_MIST,
	C3_MONTAGE,
	C3_DOJO,
	C4_FOREST,
	C5_COAST,
	C6_TOWER,
}

@onready var host: Control = %ScreenHost
@onready var hud: Label = %DebugHud

var _battle_scene: PackedScene = preload("res://scenes/battle/battle.tscn")
var _dialogue_scene: PackedScene = preload("res://scenes/ui/dialogue_box.tscn")
const ExploreViewScn = preload("res://scripts/world/explore_view.gd")
const WorldTravel = preload("res://scripts/world/world_travel.gd")
const WorldContent = preload("res://scripts/world/world_content.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const MapleHudScn = preload("res://scripts/ui/maple_hud.gd")
const MapleHotbarScn = preload("res://scripts/ui/maple_hotbar.gd")
const MapleInventoryScn = preload("res://scripts/ui/maple_inventory.gd")
const CutscenePlayerScn = preload("res://scripts/ui/cutscene_player.gd")
const NpcLines = preload("res://scripts/systems/npc_lines.gd")
const MarketPanelScn = preload("res://scripts/ui/panels/market_panel.gd")
var _dialogue: DialogueBox
var _cutscene: Control  ## CutscenePlayer
var _explore: Control  ## ExploreView
var _maple_hud: Control  ## MapleHud
var _hotbar: Control  ## MapleHotbar
var _inv_panel: Control  ## MapleInventory
var _market_ui: RefCounted  ## MarketPanel
var _toast: Label
var _current: Screen = Screen.TITLE
var _battle_mode: String = "wolf"
var _after_dialogue: Callable = Callable()
var _paused: bool = false
var _pause_layer: Control = null
var _debug_hud: bool = false  ## F3 切完整除錯列
var _fade: ColorRect = null
var _last_explore_map: String = "village"
var _last_explore_screen: Screen = Screen.C0_VILLAGE


func _ready() -> void:
	_dialogue = _dialogue_scene.instantiate()
	add_child(_dialogue)
	_dialogue.finished.connect(_on_dialogue_finished)
	_dialogue.choice_selected.connect(_on_choice)
	_cutscene = CutscenePlayerScn.new()
	add_child(_cutscene)
	_maple_hud = MapleHudScn.new()
	_maple_hud.z_index = 20
	add_child(_maple_hud)
	_maple_hud.visible = false
	_hotbar = MapleHotbarScn.new()
	_hotbar.z_index = 25
	add_child(_hotbar)
	_hotbar.visible = false
	if _hotbar.has_signal("slot_clicked"):
		_hotbar.slot_clicked.connect(_on_hotbar_click)
	if _hotbar.has_signal("slot_right_clicked"):
		_hotbar.slot_right_clicked.connect(_on_hotbar_use)
	_inv_panel = MapleInventoryScn.new()
	add_child(_inv_panel)
	_inv_panel.visible = false
	if _inv_panel.has_signal("item_used"):
		_inv_panel.item_used.connect(_on_inv_use_item)
	if _inv_panel.has_signal("assign_hotbar"):
		_inv_panel.assign_hotbar.connect(_on_inv_assign_hotbar)
	_toast = Label.new()
	_toast.z_index = 90
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -100
	_toast.offset_bottom = -70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 14)
	_toast.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1, 1))
	_toast.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.9))
	_toast.add_theme_constant_override("shadow_offset_x", 1)
	_toast.add_theme_constant_override("shadow_offset_y", 1)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	if InventorySystem.has_signal("item_used"):
		InventorySystem.item_used.connect(func(_id, res):
			if res.get("ok", false):
				_show_toast(str(res.get("msg", "")))
				_player_bubble(str(res.get("msg", "")))
		)
	_market_ui = MarketPanelScn.new(self)
	_ensure_fade()
	_go_title()


func _play_cutscene(slides: Array, after: Callable = Callable()) -> void:
	if _paused:
		_close_pause()
	if _explore and is_instance_valid(_explore) and _explore.has_method("set_frozen"):
		_explore.call("set_frozen", true)
	if _dialogue and is_instance_valid(_dialogue):
		_dialogue.visible = false
		_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 清掉標題選單，避免「半透明過場 + 底下選單」疊在一起看起來像卡死
	_clear_host()
	_reset_fade()
	AudioManager.play_ui()
	if _cutscene and _cutscene.has_method("play"):
		_cutscene.call("play", slides, func():
			if _explore and is_instance_valid(_explore) and _explore.has_method("set_frozen"):
				if not (_dialogue and _dialogue.visible):
					_explore.call("set_frozen", false)
			if after.is_valid():
				after.call()
		)
	elif after.is_valid():
		after.call()


func _ensure_fade() -> void:
	if _fade and is_instance_valid(_fade):
		return
	_fade = ColorRect.new()
	_fade.name = "FadeOverlay"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.02, 0.02, 0.04, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.z_index = 80
	add_child(_fade)


func _reset_fade() -> void:
	## 確保選單可點：淡出層不擋滑鼠
	_ensure_fade()
	if _fade:
		_fade.color.a = 0.0
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fade_pulse(mid_cb: Callable = Callable()) -> void:
	## 短轉場：暗 → 換畫面 → 亮
	_ensure_fade()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.14)
	tw.tween_callback(func():
		if mid_cb.is_valid():
			mid_cb.call()
	)
	tw.tween_property(_fade, "color:a", 0.0, 0.2)
	tw.tween_callback(func():
		_reset_fade()
	)


func _process(_dt: float) -> void:
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_debug_hud = not _debug_hud
			_refresh_hud()
			get_viewport().set_input_as_handled()
			return
		## F11：切換全螢幕／視窗
		if event.keycode == KEY_F11:
			if DisplaySettings.mode == "windowed":
				DisplaySettings.set_mode("fullscreen")
			else:
				DisplaySettings.set_mode("windowed")
			_show_toast(DisplaySettings.summary_line())
			get_viewport().set_input_as_handled()
			return
		## I：物品欄
		if event.keycode == KEY_I and _current != Screen.TITLE:
			if _dialogue and _dialogue.visible:
				return
			if _cutscene and _cutscene.visible:
				return
			if _paused:
				return
			_toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		## 1–8 快捷欄
		if _current != Screen.TITLE and not _paused:
			if not (_dialogue and _dialogue.visible) and not (_cutscene and _cutscene.visible):
				if not (_inv_panel and _inv_panel.visible):
					var slot := -1
					match event.keycode:
						KEY_1, KEY_KP_1:
							slot = 0
						KEY_2, KEY_KP_2:
							slot = 1
						KEY_3, KEY_KP_3:
							slot = 2
						KEY_4, KEY_KP_4:
							slot = 3
						KEY_5, KEY_KP_5:
							slot = 4
						KEY_6, KEY_KP_6:
							slot = 5
						KEY_7, KEY_KP_7:
							slot = 6
						KEY_8, KEY_KP_8:
							slot = 7
					if slot >= 0:
						_use_hotbar_slot(slot)
						get_viewport().set_input_as_handled()
						return
	if event.is_action_pressed("ui_cancel"):
		## Esc：先關物品欄 → 暫停／恢復
		if _current == Screen.TITLE:
			return
		if _inv_panel and _inv_panel.visible:
			_inv_panel.call("close")
			get_viewport().set_input_as_handled()
			return
		if _dialogue and _dialogue.visible:
			return
		if _cutscene and _cutscene.visible:
			return
		if _paused:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func _refresh_hud() -> void:
	## 楓之谷風左上狀態板 + 底快捷欄
	var show_chrome := _current != Screen.TITLE and not _paused
	if _inv_panel and _inv_panel.visible:
		show_chrome = true
	if _maple_hud and is_instance_valid(_maple_hud):
		_maple_hud.visible = show_chrome
		if show_chrome and _maple_hud.has_method("refresh"):
			_maple_hud.call("refresh")
	if _hotbar and is_instance_valid(_hotbar):
		_hotbar.visible = show_chrome and not (_dialogue and _dialogue.visible)
		if _hotbar.visible and _hotbar.has_method("refresh"):
			_hotbar.call("refresh")
	if hud == null:
		return
	if _current == Screen.TITLE and not _paused:
		hud.visible = false
		return
	## 底部除錯列
	hud.visible = _debug_hud
	if _debug_hud:
		var extra := ""
		if _explore and is_instance_valid(_explore):
			extra = " · 可走"
		if _paused:
			extra += " · 暫停"
		hud.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35, 0.95))
		hud.add_theme_font_size_override("font_size", 12)
		hud.text = "[F3除錯] HP %d/%d 金%d %s T%d %s%s" % [
			GameState.hp, GameState.max_hp, GameState.gold,
			GameState.weapon_name, GameState.weapon_tier, GameState.chapter, extra
		]


func _open_pause() -> void:
	if _paused:
		return
	_paused = true
	if _explore and is_instance_valid(_explore) and _explore.has_method("set_frozen"):
		_explore.call("set_frozen", true)
	## 戰鬥中暫停 process
	if _current == Screen.BATTLE and host.get_child_count() > 0:
		var b := host.get_child(0)
		if b:
			b.set_process(false)
			b.set_process_unhandled_input(false)
	_build_pause_layer()
	AudioManager.play_ui()
	_refresh_hud()


func _close_pause() -> void:
	if not _paused:
		return
	_paused = false
	if _pause_layer and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
	_pause_layer = null
	if _explore and is_instance_valid(_explore) and _explore.has_method("set_frozen"):
		## 對話進行中保持凍結
		if not (_dialogue and _dialogue.visible):
			_explore.call("set_frozen", false)
	if _current == Screen.BATTLE and host.get_child_count() > 0:
		var b := host.get_child(0)
		if b:
			b.set_process(true)
			b.set_process_unhandled_input(true)
	_refresh_hud()


func _build_pause_layer() -> void:
	if _pause_layer and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
	_pause_layer = Control.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.z_index = 80
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.07, 0.10, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	card.add_child(outer)

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiStyle.header_style())
	outer.add_child(head)
	var title := Label.new()
	var week := "迴響×%d" % GameState.ng_plus if GameState.ng_plus > 0 else "一周目"
	title.text = "選單  ·  %s" % week
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	head.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var sub := Label.new()
	sub.text = "Lv%d · 戰力%d · HP %d／%d\n%s · 金 %d · 星屑 %d" % [
		GameState.level, GameState.power_score(),
		GameState.hp, GameState.effective_max_hp(),
		GameState.weapon_name, GameState.gold, GameState.stardust
	]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", UiStyle.INK_DIM)
	box.add_child(sub)

	_pause_btn(box, "繼續", func():
		_close_pause()
	)
	_pause_btn(box, "顯示設定", func():
		_close_pause()
		_go_display_settings()
	)
	_pause_btn(box, "物品欄 (I)", func():
		_close_pause()
		_toggle_inventory()
	)
	_pause_btn(box, "重設 UI 位置", func():
		UiLayout.reset_all()
		var vp2 := get_viewport().get_visible_rect().size
		if _maple_hud:
			_maple_hud.position = Vector2(8, 8)
		if _hotbar:
			_hotbar.position = Vector2((vp2.x - 430) * 0.5, vp2.y - 68)
		SaveManager.save_game()
		_show_toast("UI 位置已重設")
		_close_pause()
	)
	var claim_n := QuestSystem.claimable_count()
	var daily_tag := "每日獎勵 ★" if QuestSystem.can_claim_daily() else "每日獎勵"
	var quest_tag := "任務／長遠" + (" ★%d" % claim_n if claim_n > 0 else "")
	_pause_btn(box, "存檔", func():
		SaveManager.save_game()
		sub.text = "已存檔 · HP %d／%d · %s" % [GameState.hp, GameState.max_hp, GameState.weapon_name]
		AudioManager.play_ui()
	)
	_pause_btn(box, "旅程進度", func():
		sub.text = _journey_summary()
		sub.custom_minimum_size = Vector2(300, 140)
		AudioManager.play_ui()
	)
	_pause_btn(box, daily_tag, func():
		_close_pause()
		_go_daily_panel()
	)
	_pause_btn(box, quest_tag, func():
		_close_pause()
		_go_quest_panel()
	)
	var ev_pause := EventRuntime.title_button_label()
	if ev_pause != "":
		_pause_btn(box, ev_pause, func():
			_close_pause()
			_go_event_panel()
		)
	_pause_btn(box, "公會／盟約", func():
		_close_pause()
		_go_guild_panel()
	)
	_pause_btn(box, "連線／帳號", func():
		_close_pause()
		_go_online_panel()
	)
	_pause_btn(box, "武器流派（%s）" % GameState.path_display(), func():
		_close_pause()
		_go_path_panel(false)
	)
	_pause_btn(box, "材料行", func():
		_close_pause()
		_go_material_shop()
	)
	_pause_btn(box, "技能／招式", func():
		_close_pause()
		_go_skill_panel()
	)
	_pause_btn(box, "裝備", func():
		_close_pause()
		_go_equip_panel()
	)
	_pause_btn(box, "倉庫", func():
		_close_pause()
		_go_warehouse_panel()
	)
	_pause_btn(box, "冒險日誌", func():
		_close_pause()
		_go_game_log_panel()
	)
	if HuntSystem.is_unlocked():
		_pause_btn(box, "星途獵場", func():
			_close_pause()
			_open_explore("hunting_grounds", Screen.C1_WILD)
		)
	if PartySystem.is_unlocked():
		_pause_btn(box, "星途助戰", func():
			_close_pause()
			_go_party_panel()
		)
	if MarketSystem.is_unlocked():
		_pause_btn(box, "星途市集", func():
			_close_pause()
			_go_market_panel()
		)
	if PartySystem.is_unlocked():
		_pause_btn(box, "裂縫房", func():
			_close_pause()
			_go_room_panel()
		)
	_pause_btn(box, "戰魂／星屑", func():
		_close_pause()
		_go_soul_panel()
	)
	_pause_btn(box, "技能／招式", func():
		_close_pause()
		_go_skill_panel()
	)
	_pause_btn(box, "稱號一覽", func():
		_show_pause_titles(box, sub)
	)
	_pause_btn(box, "匯出備份", func():
		var path := SaveManager.export_backup()
		sub.text = ("已匯出：\n%s" % path) if path != "" else "匯出失敗。"
		AudioManager.play_ui()
	)
	_pause_btn(box, "匯入備份", func():
		var err := SaveManager.import_backup()
		sub.text = "已匯入。建議回標題「繼續」。" if err == OK else "找不到備份（請先匯出）。"
		AudioManager.play_ui()
	)
	_pause_btn(box, "回標題（自動存檔）", func():
		SaveManager.save_game()
		_close_pause()
		_go_title()
	)


func _go_event_panel() -> void:
	## 收攤優先
	var ended: Array = EventRuntime.ended_with_tokens()
	if not ended.is_empty() and EventRuntime.primary_event().is_empty():
		var body0 := "有活動已收攤，剩餘活動幣可換成金幣。\n\n"
		body0 += EventRuntime.calendar_preview_bbcode()
		var buttons0: Array = []
		for e in ended:
			var eid0 := str(e.get("id", ""))
			var nm := str(e.get("name", eid0))
			buttons0.append({"text": "收攤換幣：%s" % nm, "cb": _event_cb_convert.bind(eid0)})
		buttons0.append({"text": "返回", "cb": _hub_back})
		_panel("活動收攤", body0, buttons0)
		return

	var ev: Dictionary = EventRuntime.primary_event()
	if ev.is_empty():
		var body_cal := EventRuntime.calendar_preview_bbcode()
		body_cal += "\n\n" + EventRuntime.daily_board_bbcode()
		var bcal: Array = [
			{"text": "領三件事獎勵", "cb": _event_cb_daily_board},
			{"text": "返回", "cb": _hub_back},
		]
		_panel("歲旅一覽", body_cal, bcal)
		return
	var eid := str(ev.get("id", ""))
	var body := EventRuntime.panel_bbcode(ev)
	var buttons: Array = []
	var left := EventRuntime.daily_left(ev)
	if left > 0:
		buttons.append({"text": "有獎挑戰（剩 %d）" % left, "cb": _event_cb_challenge.bind(eid)})
	else:
		buttons.append({"text": "今日有獎已滿（仍可探索）", "cb": _event_cb_goto.bind(eid)})
	buttons.append({"text": "一鍵領任務", "cb": _event_cb_claim_all.bind(eid)})
	for m in ev.get("missions", []):
		var mid := str(m.get("id", ""))
		if EventRuntime.mission_done(ev, m) and not EventRuntime.mission_claimed(eid, mid):
			var mname := str(m.get("name", mid))
			buttons.append({"text": "領：%s" % mname, "cb": _event_cb_claim_one.bind(eid, mid)})
	var shop: Array = ev.get("shop", [])
	for i in mini(5, shop.size()):
		var it: Dictionary = shop[i]
		var label := "換 %s（%d）" % [str(it.get("name", it.get("id"))), int(it.get("cost", 0))]
		buttons.append({"text": label, "cb": _event_cb_shop.bind(eid, i)})
	buttons.append({"text": "領三件事獎勵", "cb": _event_cb_daily_board})
	if str(ev.get("entry_map", "")) != "":
		buttons.append({"text": "前往活動地圖", "cb": _event_cb_goto.bind(eid)})
	for e2 in EventRuntime.ended_with_tokens():
		var eid2 := str(e2.get("id", ""))
		buttons.append({"text": "收攤：%s" % str(e2.get("name", "")), "cb": _event_cb_convert.bind(eid2)})
	buttons.append({"text": "歲旅一覽", "cb": _event_cb_calendar})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("活動 · %s" % str(ev.get("name", "")), body, buttons)


func _event_cb_challenge(event_id: String) -> void:
	_event_start_challenge(event_id)


func _event_cb_goto(event_id: String) -> void:
	_event_goto_map(EventRuntime.find_event(event_id))


func _event_cb_claim_all(event_id: String) -> void:
	var ra: Dictionary = EventRuntime.claim_all_missions(event_id)
	_play_dialog([{"speaker": "系統", "text": str(ra.get("msg", ""))}], _go_event_panel)


func _event_cb_claim_one(event_id: String, mission_id: String) -> void:
	var r: Dictionary = EventRuntime.claim_mission(event_id, mission_id)
	_play_dialog([{"speaker": "系統", "text": str(r.get("msg", ""))}], _go_event_panel)


func _event_cb_shop(event_id: String, shop_index: int) -> void:
	var r2: Dictionary = EventRuntime.shop_buy(event_id, shop_index)
	_show_toast(str(r2.get("msg", "")))
	_go_event_panel()


func _event_cb_daily_board() -> void:
	var rb: Dictionary = EventRuntime.claim_daily_board_bonus()
	_play_dialog([{"speaker": "系統", "text": str(rb.get("msg", ""))}], _go_event_panel)


func _event_cb_convert(event_id: String) -> void:
	var rc: Dictionary = EventRuntime.convert_leftover_tokens(event_id)
	_play_dialog([{"speaker": "行商", "text": str(rc.get("msg", ""))}], _go_event_panel)


func _event_cb_calendar() -> void:
	_panel("歲旅一覽", EventRuntime.calendar_preview_bbcode(), [
		{"text": "返回活動", "cb": _go_event_panel},
	])


func _event_goto_map(ev: Dictionary) -> void:
	var mid := str(ev.get("entry_map", ""))
	if mid == "":
		_hub_back()
		return
	if not EventRuntime.can_enter_map(ev):
		_play_dialog([{"speaker": "系統", "text": str(ev.get("entry_deny", "尚不能前往。"))}], _go_event_panel)
		return
	_open_explore(mid, Screen.C1_WILD)
	_show_toast("活動地圖：%s" % str(ev.get("name", mid)))


func _event_start_challenge(event_id: String) -> void:
	var ev := EventRuntime.find_event(event_id)
	if not EventRuntime.can_rewarded_run(ev):
		_play_dialog([{"speaker": "系統", "text": "今日有獎次數已用完。"}], _go_event_panel)
		return
	var mode := EventRuntime.challenge_enemy(ev)
	if mode == "" or not WorldContent.is_world_battle(mode):
		mode = "scar_wisp"
	GameState.set_flag("event.pending_run", event_id)
	_play_dialog([
		{"speaker": "旁白", "text": "【%s】挑戰開始。" % str(ev.get("name", "活動"))},
	], func(): _start_battle(mode))


func _event_try_finish_run_after_battle(won: bool) -> bool:
	## 若有待結算活動挑戰，回 true 表示已處理（呼叫端勿再走一般雜魚收尾）
	var pending := str(GameState.get_flag("event.pending_run", ""))
	if pending == "":
		## 在活動地圖打雜魚也可算有獎（可選）
		return false
	GameState.set_flag("event.pending_run", "")
	if not won:
		_play_dialog([{"speaker": "系統", "text": "挑戰失敗。有獎次數未扣。"}], func():
			_hub_back_from_world_battle()
		)
		return true
	var r: Dictionary = EventRuntime.complete_rewarded_run(pending)
	var lines: Array = [{"speaker": "系統", "text": str(r.get("msg", "完成。"))}]
	_play_dialog(lines, func():
		_go_event_panel()
	)
	return true


func _message_place_for_current() -> String:
	var mid := _last_explore_map
	if mid.begins_with("tower"):
		return "tower_camp"
	if mid in ["town", "town_keep", "town_market"]:
		return "town_gate"
	return "crossroads"


func _go_message_stone(from_id: String = "message_stone") -> void:
	var place := _message_place_for_current()
	if from_id == "wall_notice":
		place = "town_gate"
	if not OnlineGate.is_online_enabled() or not OnlineGate.is_signed_in():
		var lore := "石上有舊刻：\n「足迹會交疊。」——星讀\n「別走我的路。」——佚名\n\n（開啟連線並訪客上線後，可讀寫旅人留言。）"
		_panel("留言石", lore, [
			{"text": "連線設定", "cb": _go_online_panel},
			{"text": "返回", "cb": _hub_back},
		])
		return
	OnlineGate.fetch_messages(place, func(res: Dictionary):
		_show_messages_panel(place, res.get("list", []))
	)


func _show_messages_panel(place: String, list: Array) -> void:
	var body := "[b]留言石 · %s[/b]\n星途旅人留下的短句（最多 80 字）\n\n" % place
	if list.is_empty():
		body += "（尚無留言。做第一個足迹吧。）\n"
	else:
		var n := 0
		for row in list:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			body += "· %s\n" % str(row.get("body", ""))
			n += 1
			if n >= 12:
				break
	var buttons: Array = [
		{"text": "留下足迹：還在啊", "cb": _msg_post.bind(place, "還在啊。")},
		{"text": "留下足迹：氣味比預言近", "cb": _msg_post.bind(place, "氣味比預言近。")},
		{"text": "留下足迹：微末也走到了", "cb": _msg_post.bind(place, "微末也走到了。")},
		{"text": "刷新", "cb": func(): _go_message_stone("message_stone")},
		{"text": "返回", "cb": _hub_back},
	]
	_panel("留言石", body, buttons)


func _msg_post(place: String, text: String) -> void:
	OnlineGate.post_message(place, text, func(res: Dictionary):
		var msg := str(res.get("msg", OnlineGate.last_error))
		_play_dialog([{"speaker": "系統", "text": msg}], func(): _go_message_stone("message_stone"))
	)


func _go_candle_altar() -> void:
	var body := "塔下的蠟燭。據說通關的旅人會讓火苗多一寸。\n"
	if GameState.has_flag("game_cleared"):
		body += "\n你已見過晨光。可以點一支。"
	else:
		body += "\n你還沒走到塔的盡頭。仍可靜靜看著。"
	if OnlineGate.offline_only or not OnlineGate.is_configured():
		body += "\n\n（連線後可同步全服燭火。）"
	var buttons: Array = []
	if GameState.has_flag("game_cleared"):
		buttons.append({"text": "點燃（連線同步）", "cb": _candle_light})
	buttons.append({"text": "默默離開", "cb": _hub_back})
	_panel("通關蠟燭", body, buttons)


func _candle_light() -> void:
	if not OnlineGate.is_signed_in():
		_play_dialog([{"speaker": "系統", "text": "請先在連線設定訪客上線，才能同步燭火。"}], _go_candle_altar)
		return
	if GameState.has_flag("online.candle_lit"):
		_play_dialog([{"speaker": "旁白", "text": "你已經點過了。火還在。"}], _go_candle_altar)
		return
	OnlineGate.candle_increment(func(res: Dictionary):
		if bool(res.get("ok", false)) or res.has("total"):
			GameState.set_flag("online.candle_lit", true)
			SaveManager.save_game()
			var total = res.get("total", "?")
			_play_dialog([{"speaker": "旁白", "text": "火苗跳了一下。遠方好像有人同時看見。\n（全服：%s）" % str(total)}], _hub_back)
		else:
			_play_dialog([{"speaker": "系統", "text": str(res.get("msg", "點燈失敗"))}], _go_candle_altar)
	)


func _go_hunt_panel() -> void:
	var body: String = HuntSystem.status_bbcode()
	var buttons: Array = []
	if not HuntSystem.is_unlocked():
		buttons.append({"text": "返回", "cb": _hub_back})
		_panel("星途獵場", body, buttons)
		return
	if HuntSystem.is_run_active():
		buttons.append({"text": "繼續當前波次", "cb": _hunt_continue})
		buttons.append({"text": "放棄狩獵", "cb": _hunt_abandon})
	else:
		if HuntSystem.daily_left() > 0:
			buttons.append({"text": "開始有獎狩獵（剩 %d）" % HuntSystem.daily_left(), "cb": _hunt_start_rewarded})
		buttons.append({"text": "練習狩獵（獎勵少）", "cb": _hunt_start_practice})
	buttons.append({"text": "溢物回收", "cb": _go_hunt_recycle_panel})
	buttons.append({"text": "星途市集", "cb": _go_market_panel})
	buttons.append({"text": "狩獵房（組隊）", "cb": _go_hunt_room_panel})
	if PartySystem.has_party():
		buttons.append({"text": "助戰：已選（單人獵可帶）", "cb": _go_party_panel})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("星途獵場", body, buttons)


func _hunt_start_rewarded() -> void:
	var r: Dictionary = HuntSystem.start_run(false)
	if not bool(r.get("ok", false)):
		_play_dialog([{"speaker": "系統", "text": str(r.get("msg", ""))}], _go_hunt_panel)
		return
	if PartySystem.has_party():
		PartySystem.begin_party_battle()
	var lines: Array = [
		{"speaker": "旁白", "text": str(r.get("msg", "狩獵開始。"))},
		{"speaker": "系統", "text": str(r.get("label", "第一波"))},
	]
	if PartySystem.has_party():
		for pl in PartySystem.intro_lines():
			lines.append(pl)
	_play_dialog(lines, func(): _start_battle(str(r.get("mode", "ash_rat"))))


func _hunt_start_practice() -> void:
	var r: Dictionary = HuntSystem.start_run(true)
	if not bool(r.get("ok", false)):
		_play_dialog([{"speaker": "系統", "text": str(r.get("msg", ""))}], _go_hunt_panel)
		return
	if PartySystem.has_party():
		PartySystem.begin_party_battle()
	var lines: Array = [
		{"speaker": "旁白", "text": str(r.get("msg", "練習開始。"))},
		{"speaker": "系統", "text": str(r.get("label", "第一波"))},
	]
	if PartySystem.has_party():
		for pl in PartySystem.intro_lines():
			lines.append(pl)
	_play_dialog(lines, func(): _start_battle(str(r.get("mode", "ash_rat"))))


func _hunt_continue() -> void:
	if not HuntSystem.is_run_active():
		_go_hunt_panel()
		return
	_play_dialog([
		{"speaker": "系統", "text": HuntSystem.wave_label()},
	], func(): _start_battle(HuntSystem.wave_mode()))


func _hunt_abandon() -> void:
	HuntSystem.abandon_run()
	PartySystem.end_party_battle()
	if RoomSystem.is_in_room() and RoomSystem.is_hunt_room() and RoomSystem.is_host():
		RoomSystem.host_report_result(false, func(_r: Dictionary): pass)
	_play_dialog([{"speaker": "系統", "text": "已放棄本場狩獵。"}], _go_hunt_panel)


func _on_hunt_battle_finished(won: bool) -> void:
	if not won:
		var lost: Dictionary = HuntSystem.on_wave_lost()
		PartySystem.end_party_battle()
		if RoomSystem.is_in_room() and RoomSystem.is_hunt_room() and RoomSystem.is_host():
			RoomSystem.host_report_result(false, func(_r: Dictionary): pass)
		_play_dialog([{"speaker": "系統", "text": str(lost.get("msg", "敗北。"))}], func():
			if RoomSystem.is_in_room() and RoomSystem.is_hunt_room():
				_go_hunt_room_panel()
			else:
				_open_explore("hunting_grounds", Screen.C1_WILD)
		)
		return
	var r: Dictionary = HuntSystem.on_wave_won()
	if not bool(r.get("ok", false)):
		_open_explore("hunting_grounds", Screen.C1_WILD)
		return
	if bool(r.get("finished", false)):
		PartySystem.end_party_battle()
		var lines: Array = [{"speaker": "系統", "text": str(r.get("msg", "完成。"))}]
		if RoomSystem.is_in_room() and RoomSystem.is_hunt_room() and RoomSystem.is_host():
			RoomSystem.host_report_result(true, func(res: Dictionary):
				var bmsg := str(res.get("bonus_msg", ""))
				if bmsg != "":
					lines.append({"speaker": "系統", "text": bmsg})
				_play_dialog(lines, func():
					_go_hunt_room_panel()
				)
			)
			return
		_play_dialog(lines, func():
			_open_explore("hunting_grounds", Screen.C1_WILD)
		)
		return
	## 下一波
	var mid := str(r.get("loot_msg", ""))
	var text := str(r.get("msg", "下一波"))
	if mid != "":
		text += "\n" + mid
	_play_dialog([{"speaker": "系統", "text": text}], func():
		_start_battle(str(r.get("next_mode", "ash_rat")))
	)


func _go_hunt_room_panel() -> void:
	RoomSystem.filter_kind = "hunt"
	var body: String = RoomSystem.status_bbcode("hunt")
	var buttons: Array = []
	if not RoomSystem.online_ready():
		buttons.append({"text": "連線設定", "cb": _go_online_panel})
		buttons.append({"text": "返回獵場", "cb": _go_hunt_panel})
		_panel("狩獵房", body, buttons)
		return
	if RoomSystem.is_in_room():
		if not RoomSystem.is_hunt_room():
			body += "\n\n[color=#c96]你目前在裂縫房。請先離開再進狩獵房。[/color]"
			buttons.append({"text": "前往裂縫房", "cb": _go_room_panel})
			buttons.append({"text": "離開當前房", "cb": _room_leave})
			buttons.append({"text": "返回獵場", "cb": _go_hunt_panel})
			_panel("狩獵房", body, buttons)
			return
		buttons.append({"text": "刷新房間", "cb": _hunt_room_refresh})
		if RoomSystem.is_host():
			if RoomSystem.room_status() == "open" or RoomSystem.room_status() == "fighting":
				if not HuntSystem.is_run_active():
					buttons.append({"text": "開始共獵（房主）", "cb": _hunt_room_host_start})
				else:
					buttons.append({"text": "繼續當前波次", "cb": _hunt_continue})
		else:
			buttons.append({"text": "標記就緒", "cb": _room_ready})
			if RoomSystem.room_status() == "fighting":
				buttons.append({"text": "同屏操作（可輸入）", "cb": _room_spectate})
				buttons.append({"text": "僅觀戰", "cb": _room_spectate_watch})
			if str(RoomSystem.current_room.get("result", "")) == "win":
				buttons.append({"text": "領取共獵獎", "cb": _hunt_room_claim})
		var rt2 := RoomSystem.realtime_status()
		if rt2 != "":
			body += "\n[color=#aaa]%s[/color]" % rt2
		body += "\n操作：J 格擋／連招 · K 戰意 · L 助攻"
		buttons.append({"text": "離開房間", "cb": _hunt_room_leave})
		buttons.append({"text": "返回獵場", "cb": _go_hunt_panel})
		_panel("狩獵房 · %s" % RoomSystem.room_code(), body, buttons)
		return
	buttons.append({"text": "建立狩獵房", "cb": _hunt_room_create})
	buttons.append({"text": "用代碼加入…", "cb": _go_room_join_code_panel})
	buttons.append({"text": "刷新開放狩獵房", "cb": _hunt_room_list})
	buttons.append({"text": "返回獵場", "cb": _go_hunt_panel})
	_panel("狩獵房", body, buttons)
	RoomSystem.refresh_open_rooms(func(res: Dictionary):
		_show_hunt_room_browser(res.get("list", []))
	, "hunt")


func _show_hunt_room_browser(list: Array) -> void:
	if RoomSystem.is_in_room() and RoomSystem.is_hunt_room():
		_go_hunt_room_panel()
		return
	var body: String = RoomSystem.status_bbcode("hunt") + "\n\n[b]開放狩獵房[/b]\n"
	var buttons: Array = []
	var n := 0
	for row in list:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if n >= 8:
			break
		var d: Dictionary = row
		var code := str(d.get("code", ""))
		body += "· 代碼 %s · %s\n" % [code, str(d.get("id", "")).substr(0, 8)]
		buttons.append({
			"text": "加入 %s" % (code if code != "" else str(d.get("id", "")).substr(0, 6)),
			"cb": _hunt_room_join.bind(str(d.get("id", ""))),
		})
		n += 1
	if n == 0:
		body += "（暫無狩獵房，可自建）\n"
	buttons.append({"text": "建立狩獵房", "cb": _hunt_room_create})
	buttons.append({"text": "刷新", "cb": _hunt_room_list})
	buttons.append({"text": "返回獵場", "cb": _go_hunt_panel})
	_panel("狩獵房", body, buttons)


func _hunt_room_create() -> void:
	RoomSystem.create_hunt_room(func(res: Dictionary):
		_show_toast(str(res.get("msg", "")))
		_go_hunt_room_panel()
	)


func _hunt_room_join(rid: String) -> void:
	RoomSystem.join_room_id(rid, func(res: Dictionary):
		_show_toast(str(res.get("msg", "")))
		_go_hunt_room_panel()
	)


func _hunt_room_list() -> void:
	RoomSystem.refresh_open_rooms(func(res: Dictionary):
		_show_hunt_room_browser(res.get("list", []))
	, "hunt")


func _hunt_room_refresh() -> void:
	RoomSystem.poll_now()
	_show_toast("已刷新 · 代碼 %s" % RoomSystem.room_code())
	_go_hunt_room_panel()


func _hunt_room_leave() -> void:
	RoomSystem.leave_room(func(_res: Dictionary):
		_show_toast("已離開狩獵房")
		_go_hunt_room_panel()
	)


func _hunt_room_claim() -> void:
	RoomSystem.claim_member_reward(func(res: Dictionary):
		_show_toast(str(res.get("msg", "")))
		_go_hunt_room_panel()
	)


func _hunt_room_host_start() -> void:
	RoomSystem.host_start_battle(func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_show_toast(str(res.get("msg", "無法開戰")))
			_go_hunt_room_panel()
			return
		var hr: Dictionary = HuntSystem.start_run(false)
		if not bool(hr.get("ok", false)):
			## 可能日 cap 用盡 → 練習
			hr = HuntSystem.start_run(true)
		if not bool(hr.get("ok", false)):
			_show_toast(str(hr.get("msg", "無法開始狩獵")))
			_go_hunt_room_panel()
			return
		PartySystem.begin_party_battle()
		var arr: Array = [
			{"speaker": "系統", "text": str(res.get("msg", "共獵開戰"))},
			{"speaker": "系統", "text": "代碼 %s · %s" % [RoomSystem.room_code(), str(hr.get("label", "第一波"))]},
		]
		if PartySystem.has_party():
			for pl in PartySystem.intro_lines():
				arr.append(pl)
		_play_dialog(arr, func(): _start_battle(str(hr.get("mode", "ash_rat"))))
	)


func _go_hunt_recycle_panel() -> void:
	var body := "[b]溢物回收[/b]\n獵人商人只收狩獵材料（未來市集原型）。\n\n"
	var buttons: Array = []
	for id in ["hunt_hide", "hunt_bone", "hunt_core"]:
		var n: int = InventorySystem.count(id)
		var price: int = HuntSystem.recycle_price(id)
		body += "· %s ×%d（回收 %d 金／個）\n" % [InventorySystem.item_name(id), n, price]
		if n > 0:
			buttons.append({"text": "賣 %s" % InventorySystem.item_name(id), "cb": _hunt_recycle_one.bind(id)})
	if buttons.is_empty():
		body += "\n（袋裡沒有溢皮／焰骨／溢核。）"
	buttons.append({"text": "返回獵場", "cb": _go_hunt_panel})
	buttons.append({"text": "關閉", "cb": _hub_back})
	_panel("溢物回收", body, buttons)


func _hunt_recycle_one(item_id: String) -> void:
	var r: Dictionary = HuntSystem.recycle_one(item_id)
	_show_toast(str(r.get("msg", "")))
	_go_hunt_recycle_panel()


# ─── 星途市集 ───

func _go_market_panel() -> void:
	_market_ui.open()


# ─── 裂縫房 ───

func _go_room_panel() -> void:
	RoomSystem.filter_kind = "rift"
	var body: String = RoomSystem.status_bbcode("rift")
	var buttons: Array = []
	if not RoomSystem.online_ready():
		buttons.append({"text": "連線設定", "cb": _go_online_panel})
		buttons.append({"text": "星途助戰（離線）", "cb": _go_party_panel})
		buttons.append({"text": "返回", "cb": _go_postgame_hub})
		_panel("裂縫房", body, buttons)
		return
	if RoomSystem.is_in_room():
		if RoomSystem.is_hunt_room():
			body += "\n\n[color=#c96]你目前在狩獵房。[/color]"
			buttons.append({"text": "前往狩獵房", "cb": _go_hunt_room_panel})
			buttons.append({"text": "離開當前房", "cb": _room_leave})
			buttons.append({"text": "返回裂縫", "cb": _go_postgame_hub})
			_panel("裂縫房", body, buttons)
			return
		buttons.append({"text": "刷新房間", "cb": _room_refresh})
		if RoomSystem.is_host():
			if RoomSystem.room_status() == "open":
				buttons.append({"text": "開戰（房主）", "cb": _room_host_start})
			elif RoomSystem.room_status() == "fighting":
				buttons.append({"text": "繼續挑戰", "cb": _room_host_start})
		else:
			buttons.append({"text": "標記就緒", "cb": _room_ready})
			if RoomSystem.room_status() == "fighting":
				buttons.append({"text": "同屏操作（可輸入）", "cb": _room_spectate})
				buttons.append({"text": "僅觀戰", "cb": _room_spectate_watch})
			if str(RoomSystem.current_room.get("result", "")) == "win":
				buttons.append({"text": "領取共鬥獎", "cb": _room_claim})
		var rt := RoomSystem.realtime_status()
		if rt != "":
			body += "\n[color=#aaa]%s[/color]" % rt
		if RoomSystem.is_host() and RoomSystem.estimated_rtt_ms > 0:
			body += "\n輸入延遲估：約 %.0f ms" % RoomSystem.estimated_rtt_ms
		body += "\n操作：J 格擋／連招 · K 戰意 · L 助攻"
		buttons.append({"text": "離開房間", "cb": _room_leave})
		buttons.append({"text": "返回裂縫", "cb": _go_postgame_hub})
		_panel("裂縫房 · %s" % RoomSystem.room_code(), body, buttons)
		return
	buttons.append({"text": "刷新開放房", "cb": _room_list_open})
	buttons.append({"text": "用代碼加入…", "cb": _go_room_join_code_panel})
	for mode in RiftSchedule.MODES:
		var m: String = mode
		buttons.append({"text": "建房·%s" % RiftSchedule.mode_name(m), "cb": _room_create.bind(m)})
	buttons.append({"text": "返回", "cb": _go_postgame_hub})
	_panel("裂縫房", body, buttons)
	RoomSystem.refresh_open_rooms(func(res: Dictionary):
		_show_room_browser(res.get("list", []))
	, "rift")


func _show_room_browser(list: Array) -> void:
	if RoomSystem.is_in_room() and RoomSystem.is_rift_room():
		_go_room_panel()
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
			"cb": _room_join.bind(str(d.get("id", ""))),
		})
		n += 1
	if n == 0:
		body += "（暫無開放房，可自建或用代碼加入）\n"
	buttons.append({"text": "用代碼加入…", "cb": _go_room_join_code_panel})
	for mode2 in RiftSchedule.MODES:
		var m2: String = mode2
		buttons.append({"text": "建房·%s" % RiftSchedule.mode_name(m2), "cb": _room_create.bind(m2)})
	buttons.append({"text": "刷新", "cb": _room_list_open})
	buttons.append({"text": "返回", "cb": _go_postgame_hub})
	_panel("裂縫房", body, buttons)


func _go_room_join_code_panel() -> void:
	_clear_host()
	_reset_fade()
	var layer := Control.new()
	layer.name = "JoinCodeLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)
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
			_show_toast("代碼太短")
			return
		RoomSystem.join_by_code(code, func(res: Dictionary):
			_show_toast(str(res.get("msg", "")))
			if bool(res.get("ok", false)):
				if RoomSystem.is_hunt_room():
					_go_hunt_room_panel()
				else:
					_go_room_panel()
			else:
				_go_room_join_code_panel()
		)
	btn_ok.pressed.connect(do_join)
	le.text_submitted.connect(func(_t): do_join.call())
	btn_back.pressed.connect(func():
		if RoomSystem.filter_kind == "hunt":
			_go_hunt_room_panel()
		else:
			_go_room_panel()
	)
	le.grab_focus()


func _room_create(mode: String) -> void:
	RoomSystem.create_room(mode, func(res: Dictionary):
		_show_toast(str(res.get("msg", "")))
		_go_room_panel()
	)


func _room_join(rid: String) -> void:
	RoomSystem.join_room_id(rid, func(res: Dictionary):
		_show_toast(str(res.get("msg", "")))
		_go_room_panel()
	)


func _room_list_open() -> void:
	RoomSystem.refresh_open_rooms(func(res: Dictionary):
		_show_room_browser(res.get("list", []))
	, "rift")


func _room_refresh() -> void:
	RoomSystem.poll_now()
	_show_toast("已刷新")
	_go_room_panel()


func _room_ready() -> void:
	RoomSystem.set_ready(true, func(res: Dictionary):
		_show_toast(str(res.get("msg", "就緒")))
		_go_room_panel()
	)


func _room_leave() -> void:
	RoomSystem.leave_room(func(_res: Dictionary):
		_show_toast("已離開房間")
		_go_room_panel()
	)


func _room_claim() -> void:
	RoomSystem.claim_member_reward(func(res: Dictionary):
		_show_toast(str(res.get("msg", "")))
		_go_room_panel()
	)


func _room_spectate() -> void:
	var r: Dictionary = RoomSystem.start_coop_control(true)
	if not bool(r.get("ok", false)):
		_show_toast(str(r.get("msg", "無法同屏")))
		return
	_show_toast(str(r.get("msg", "同屏操作")))
	_start_spectate_battle(str(r.get("mode", RoomSystem.room_mode())), true)


func _room_spectate_watch() -> void:
	var r: Dictionary = RoomSystem.start_coop_control(false)
	if not bool(r.get("ok", false)):
		_show_toast(str(r.get("msg", "無法觀戰")))
		return
	_show_toast(str(r.get("msg", "觀戰")))
	_start_spectate_battle(str(r.get("mode", RoomSystem.room_mode())), false)


func _room_host_start() -> void:
	if RoomSystem.is_hunt_room():
		_hunt_room_host_start()
		return
	RoomSystem.host_start_battle(func(res: Dictionary):
		if not bool(res.get("ok", false)):
			_show_toast(str(res.get("msg", "無法開戰")))
			_go_room_panel()
			return
		var mode := str(res.get("mode", RoomSystem.room_mode()))
		## 消耗裂縫有獎次數
		RiftSchedule.consume_attempt()
		PartySystem.begin_party_battle()
		var arr: Array = [
			{"speaker": "系統", "text": str(res.get("msg", "開戰"))},
			{"speaker": "系統", "text": "代碼 %s · 房主權威 · 隊友可「同屏觀戰」。" % RoomSystem.room_code()},
		]
		if PartySystem.has_party():
			for pl in PartySystem.intro_lines():
				arr.append(pl)
		_play_dialog(arr, func(): _start_battle(mode))
	)


func _go_online_panel() -> void:
	var body: String = OnlineGate.panel_bbcode()
	body += "\n\n[b]帳號[/b]：Email 註冊／登入（需關純單機並設定後端）"
	var buttons: Array = []
	if OnlineGate.offline_only:
		buttons.append({"text": "關閉純單機（允許連線）", "cb": _online_enable})
	else:
		buttons.append({"text": "開啟純單機（推薦故事模式）", "cb": _online_force_offline})
	buttons.append({"text": "檢測連線健康", "cb": _online_health_check})
	buttons.append({"text": "編輯後端 URL／金鑰…", "cb": _go_online_backend_form})
	if OnlineGate.is_online_enabled() and not OnlineGate.is_signed_in():
		buttons.append({"text": "訪客上線", "cb": _online_sign_in})
		buttons.append({"text": "Email 註冊…", "cb": _go_account_register_panel})
		buttons.append({"text": "Email 登入…", "cb": _go_account_login_panel})
	if OnlineGate.is_signed_in():
		buttons.append({"text": "推送雲存檔", "cb": _online_push_save})
		buttons.append({"text": "拉取雲存檔", "cb": _online_pull_save})
		buttons.append({"text": "上傳殘影（當前域）", "cb": _online_push_presence})
		buttons.append({"text": "登出星途", "cb": _online_sign_out})
	buttons.append({"text": "顯示名：旅人", "cb": _online_set_name})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("連線／帳號", body, buttons)


func _online_health_check() -> void:
	_show_toast("檢測中…")
	OnlineGate.health_check(func(res: Dictionary):
		var msg := str(res.get("msg", OnlineGate.last_health))
		if bool(res.get("ok", false)):
			_play_dialog([{"speaker": "系統", "text": "連線健康：%s" % msg}], _go_online_panel)
		else:
			_play_dialog([{"speaker": "系統", "text": "連線異常：%s" % OnlineGate.humanize_error(msg)}], _go_online_panel)
	)


func _go_online_backend_form() -> void:
	_clear_host()
	_reset_fade()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.1, 0.92)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var title := Label.new()
	title.text = "後端設定（Supabase）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	root.add_child(title)
	var hint := Label.new()
	hint.text = "貼上 Project URL 與 publishable／anon key。不會上傳到別人。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiStyle.CREAM_DIM)
	root.add_child(hint)
	var url_le := LineEdit.new()
	url_le.placeholder_text = "https://xxxx.supabase.co"
	url_le.text = OnlineGate.supabase_url
	url_le.custom_minimum_size.y = 36
	root.add_child(url_le)
	var key_le := LineEdit.new()
	key_le.placeholder_text = "sb_publishable_… 或 eyJ… anon key"
	key_le.text = OnlineGate.supabase_anon_key
	key_le.secret = true
	key_le.custom_minimum_size.y = 36
	root.add_child(key_le)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var save_b := Button.new()
	save_b.text = "儲存並檢測"
	save_b.custom_minimum_size = Vector2(140, 36)
	row.add_child(save_b)
	var back_b := Button.new()
	back_b.text = "返回"
	back_b.custom_minimum_size = Vector2(100, 36)
	row.add_child(back_b)
	save_b.pressed.connect(func():
		OnlineGate.set_backend(url_le.text, key_le.text)
		OnlineGate.set_offline_only(false)
		_show_toast("已儲存，檢測中…")
		OnlineGate.health_check(func(res: Dictionary):
			var msg := str(res.get("msg", ""))
			_play_dialog([{"speaker": "系統", "text": msg if msg != "" else OnlineGate.last_health}], _go_online_panel)
		)
	)
	back_b.pressed.connect(_go_online_panel)
	url_le.grab_focus()


func _go_account_register_panel() -> void:
	_show_account_form(true)


func _go_account_login_panel() -> void:
	_show_account_form(false)


func _show_account_form(is_register: bool) -> void:
	_clear_host()
	_reset_fade()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.1, 0.92)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var title := Label.new()
	title.text = "註冊星途帳號" if is_register else "登入星途帳號"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	root.add_child(title)
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.custom_minimum_size.y = 36
	root.add_child(email)
	var pwd := LineEdit.new()
	pwd.placeholder_text = "密碼（至少 6 字）"
	pwd.secret = true
	pwd.custom_minimum_size.y = 36
	root.add_child(pwd)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var ok := Button.new()
	ok.text = "註冊" if is_register else "登入"
	ok.custom_minimum_size = Vector2(120, 36)
	row.add_child(ok)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(100, 36)
	row.add_child(back)
	var submit := func():
		var e := email.text.strip_edges()
		var p := pwd.text
		if is_register:
			OnlineGate.sign_up_email(e, p, func(res: Dictionary):
				GameLog.account("註冊嘗試：%s" % e)
				_online_on_result(res)
			)
		else:
			OnlineGate.sign_in_email(e, p, func(res: Dictionary):
				GameLog.account("登入嘗試：%s" % e)
				_online_on_result(res)
			)
	ok.pressed.connect(submit)
	pwd.text_submitted.connect(func(_t): submit.call())
	back.pressed.connect(_go_online_panel)
	email.grab_focus()


func _online_enable() -> void:
	OnlineGate.set_offline_only(false)
	_go_online_panel()


func _online_force_offline() -> void:
	OnlineGate.set_offline_only(true)
	OnlineGate.sign_out()
	_go_online_panel()


func _online_sign_in() -> void:
	OnlineGate.sign_in_anonymous(func(res: Dictionary):
		GameLog.account("訪客上線")
		_online_on_result(res)
	)


func _go_equip_panel() -> void:
	## 圖示化裝備面板（部位槽 + 背包格）
	EquipmentSystem._ensure_state()
	_clear_host()
	_reset_fade()
	var layer := Control.new()
	layer.name = "EquipLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.969, 0.965, 0.973, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12 if m != "margin_top" else 10)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "裝備"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(title)

	var b := EquipmentSystem.bonus_totals()
	var sum := Label.new()
	sum.text = "總加成  攻+%d  防+%d  血+%d  ·  暴擊 %.1f%%  暴傷 +%.0f%%" % [
		int(b.atk), int(b.def), int(b.hp),
		GameState.effective_crit(), GameState.effective_crit_dmg(),
	]
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.add_theme_font_size_override("font_size", 12)
	sum.add_theme_color_override("font_color", UiStyle.INK_DIM)
	root.add_child(sum)

	## 三部位槽
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 12)
	root.add_child(slots_row)
	for s in EquipmentSystem.SLOTS:
		slots_row.add_child(_equip_slot_card(s))

	var bag_h := Label.new()
	bag_h.text = "背包（點擊裝備）"
	bag_h.add_theme_font_size_override("font_size", 13)
	bag_h.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(bag_h)

	var bag_grid := GridContainer.new()
	bag_grid.columns = 4
	bag_grid.add_theme_constant_override("h_separation", 8)
	bag_grid.add_theme_constant_override("v_separation", 8)
	root.add_child(bag_grid)
	var n := 0
	for e in GameState.equip_bag:
		if n >= 12:
			break
		bag_grid.add_child(_equip_bag_cell(e))
		n += 1
	if n == 0:
		var empty := Label.new()
		empty.text = "背包尚無裝備。野外掉落或找釘釘鍛造。"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", UiStyle.INK_DIM)
		root.add_child(empty)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var btn_wh := Button.new()
	btn_wh.text = "倉庫"
	UiStyle.style_button(btn_wh, false)
	btn_wh.pressed.connect(func():
		AudioManager.play_ui()
		_go_warehouse_panel()
	)
	actions.add_child(btn_wh)
	var btn_back := Button.new()
	btn_back.text = "返回"
	UiStyle.style_button(btn_back, true)
	btn_back.pressed.connect(func():
		AudioManager.play_ui()
		_hub_back()
	)
	actions.add_child(btn_back)
	_refresh_hud()


func _equip_slot_card(slot: String) -> Control:
	var slot_name := "武器"
	match slot:
		"armor":
			slot_name = "防具"
		"accessory":
			slot_name = "飾品"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(140, 0)
	box.add_theme_constant_override("separation", 4)
	var lab := Label.new()
	lab.text = slot_name
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", UiStyle.INK_DIM)
	box.add_child(lab)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(120, 120)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.94, 0.92, 0.95, 1)
	st.border_color = UiStyle.WOOD
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	cell.add_theme_stylebox_override("panel", st)
	box.add_child(cell)
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(inner)
	var uid := str(GameState.equip_slots.get(slot, ""))
	var inst: Dictionary = {}
	if uid != "" and GameState.equip_worn.has(uid):
		inst = GameState.equip_worn[uid]
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not inst.is_empty():
		var t: Texture2D = SpriteDB.equip_icon_for_inst(inst)
		if t:
			icon.texture = t
	inner.add_child(icon)
	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 11)
	if inst.is_empty():
		name_l.text = "（空）"
		name_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
	else:
		name_l.text = str(inst.get("name", "?"))
		name_l.add_theme_color_override("font_color", UiStyle.INK)
	inner.add_child(name_l)
	if not inst.is_empty():
		var btn := Button.new()
		btn.text = "卸下"
		UiStyle.style_button(btn, false)
		btn.pressed.connect(func():
			AudioManager.play_ui()
			_equip_unequip(slot)
		)
		box.add_child(btn)
	return box


func _equip_bag_cell(inst: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(110, 110)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.95, 0.93, 1)
	st.border_color = Color(0.76, 0.37, 0.45, 0.55)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	cell.add_theme_stylebox_override("panel", st)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var uid := str(inst.get("uid", ""))
	btn.tooltip_text = EquipmentSystem.label(inst)
	btn.pressed.connect(func():
		AudioManager.play_ui()
		_equip_wear(uid)
	)
	cell.add_child(btn)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(col)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Texture2D = SpriteDB.equip_icon_for_inst(inst)
	if t:
		icon.texture = t
	col.add_child(icon)
	var nl := Label.new()
	nl.text = str(inst.get("name", "?"))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.add_theme_font_size_override("font_size", 10)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nl)
	var ql := Label.new()
	ql.text = str(inst.get("quality_label", ""))
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.add_theme_font_size_override("font_size", 10)
	ql.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ql)
	return cell


func _equip_wear(uid: String) -> void:
	var r: Dictionary = EquipmentSystem.equip(uid)
	_show_toast(str(r.get("msg", "")))
	_go_equip_panel()


func _equip_unequip(slot: String) -> void:
	var r: Dictionary = EquipmentSystem.unequip(slot)
	_show_toast(str(r.get("msg", "")))
	_go_equip_panel()


func _equip_debug_drop() -> void:
	var r: Dictionary = EquipmentSystem.try_drop_loot()
	_show_toast(str(r.get("msg", "無")))
	_go_equip_panel()


func _go_warehouse_panel() -> void:
	var body: String = WarehouseSystem.status_bbcode()
	var buttons: Array = []
	## 可存：背包有的材料
	var shown := 0
	for id in ["hunt_hide", "hunt_bone", "hunt_core", "hp_s", "bread", "wolf_fang", "dust_crumb"]:
		if InventorySystem.count(id) > 0 and shown < 6:
			buttons.append({"text": "存 %s" % InventorySystem.item_name(id), "cb": _wh_dep.bind(id)})
			shown += 1
	var wkeys: Array = GameState.warehouse.keys()
	var wi := 0
	for id2 in wkeys:
		if wi >= 6:
			break
		buttons.append({"text": "取 %s" % InventorySystem.item_name(str(id2)), "cb": _wh_wd.bind(str(id2))})
		wi += 1
	for e in GameState.equip_bag:
		if shown >= 10:
			break
		buttons.append({"text": "裝入庫 " + str(e.get("name", "")), "cb": _wh_dep_eq.bind(str(e.get("uid", "")))})
		shown += 1
	for e2 in GameState.warehouse_equip:
		if wi >= 12:
			break
		buttons.append({"text": "裝取出 " + str(e2.get("name", "")), "cb": _wh_wd_eq.bind(str(e2.get("uid", "")))})
		wi += 1
	buttons.append({"text": "裝備", "cb": _go_equip_panel})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("倉庫", body, buttons)


func _wh_dep(id: String) -> void:
	_show_toast(str(WarehouseSystem.deposit_item(id, 1).get("msg", "")))
	_go_warehouse_panel()


func _wh_wd(id: String) -> void:
	_show_toast(str(WarehouseSystem.withdraw_item(id, 1).get("msg", "")))
	_go_warehouse_panel()


func _wh_dep_eq(uid: String) -> void:
	_show_toast(str(WarehouseSystem.deposit_equip(uid).get("msg", "")))
	_go_warehouse_panel()


func _wh_wd_eq(uid: String) -> void:
	_show_toast(str(WarehouseSystem.withdraw_equip(uid).get("msg", "")))
	_go_warehouse_panel()


func _go_game_log_panel() -> void:
	var body: String = GameLog.status_bbcode(28)
	_panel("冒險日誌", body, [
		{"text": "只看戰鬥", "cb": func(): _go_game_log_cat("combat")},
		{"text": "只看經濟", "cb": func(): _go_game_log_cat("economy")},
		{"text": "只看裝備", "cb": func(): _go_game_log_cat("equip")},
		{"text": "返回", "cb": _hub_back},
	])


func _go_game_log_cat(cat: String) -> void:
	var lines: PackedStringArray = ["[b]日誌 · %s[/b]\n" % cat]
	for e in GameLog.recent(25, cat):
		lines.append("· %s" % str(e.get("msg", "")))
	if lines.size() <= 1:
		lines.append("（無）")
	_panel("冒險日誌", "\n".join(lines), [{"text": "全部", "cb": _go_game_log_panel}, {"text": "返回", "cb": _hub_back}])


func _online_push_save() -> void:
	OnlineGate.push_cloud_save(_online_on_result)


func _online_pull_save() -> void:
	OnlineGate.pull_cloud_save(_online_on_result)


func _online_push_presence() -> void:
	var mid := _last_explore_map if _last_explore_map != "" else "town"
	OnlineGate.push_presence(mid)
	_show_toast("已嘗試上傳殘影")
	_go_online_panel()


func _online_sign_out() -> void:
	OnlineGate.sign_out()
	_go_online_panel()


func _online_set_name() -> void:
	OnlineGate.set_display_name("星途旅人")
	_show_toast("顯示名已設為星途旅人")
	_go_online_panel()


func _online_on_result(res: Dictionary) -> void:
	var msg := str(res.get("msg", ""))
	if bool(res.get("error", false)) or bool(res.get("ok", true)) == false:
		msg = str(res.get("msg", OnlineGate.last_error))
	if msg == "":
		msg = OnlineGate.status_line()
	_play_dialog([{"speaker": "系統", "text": msg}], _go_online_panel)


func _go_daily_panel() -> void:
	QuestSystem.refresh_daily()
	var body := "每天登入可領補給。連續簽到獎勵更高。\n"
	body += "連續：%d 天 · 戰力 %d · Lv%d\n\n" % [
		int(GameState.get_flag(QuestSystem.DAILY_STREAK, 0)), GameState.power_score(), GameState.level
	]
	if GameState.ng_plus > 0:
		body += "二周目加成：每日略豐。\n\n"
	body += QuestSystem.list_commissions_bbcode()
	var buttons: Array = []
	if QuestSystem.can_claim_daily():
		buttons.append({"text": "領取今日簽到", "cb": func():
			var r: Dictionary = QuestSystem.claim_daily()
			_play_dialog([{"speaker": "系統", "text": str(r.get("msg", ""))}], _go_daily_panel)
		})
	else:
		buttons.append({"text": "簽到已領", "cb": _go_daily_panel})
	for c in QuestSystem.COMMISSIONS:
		var cid := str(c.get("id", ""))
		if QuestSystem.commission_done(c) and not QuestSystem.commission_claimed(cid):
			var id2 := cid
			buttons.append({"text": "領委託：%s" % c.get("name", cid), "cb": func():
				var r2: Dictionary = QuestSystem.claim_commission(id2)
				_play_dialog([{"speaker": "系統", "text": str(r2.get("msg", ""))}], _go_daily_panel)
			})
	buttons.append({"text": "材料行（琥珀）", "cb": _go_material_shop})
	buttons.append({"text": "長遠任務", "cb": _go_quest_panel})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("每日 · 簽到與委託", body, buttons)


func _go_quest_panel() -> void:
	var body := "長遠任務（完成後可領獎）\n\n" + QuestSystem.list_missions_bbcode()
	var buttons: Array = []
	for m in QuestSystem.MISSIONS:
		var id := str(m.get("id", ""))
		if QuestSystem.mission_done(m) and not QuestSystem.mission_claimed(id):
			var mid := id
			buttons.append({"text": "領獎：%s" % m.get("name", id), "cb": func():
				var r: Dictionary = QuestSystem.claim_mission(mid)
				_play_dialog([{"speaker": "系統", "text": str(r.get("msg", ""))}], _go_quest_panel)
			})
	if buttons.is_empty():
		buttons.append({"text": "（暫無待領任務）", "cb": _go_quest_panel})
	buttons.append({"text": "每日／委託", "cb": _go_daily_panel})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("長遠任務", body, buttons)


func _go_material_shop() -> void:
	## 琥珀材料行：買鍛材／耗材，賣材料
	var body := "琥珀的材料行 · 金幣 %d\n\n" % GameState.gold
	body += "持有：鐵屑%d 星砂%d 橡脂%d 騎士碎鐵%d 狼牙%d\n\n" % [
		InventorySystem.count("iron_scrap"),
		InventorySystem.count("star_ore"),
		InventorySystem.count("oak_resin"),
		InventorySystem.count("knight_shard"),
		InventorySystem.count("wolf_fang"),
	]
	body += "循環：野外掉材料 → 賣金／鍛武器 → 不夠再買 → 再打。"
	var buttons: Array = [
		{"text": "買鐵屑（14金）", "cb": func(): _shop_buy("iron_scrap", 14)},
		{"text": "買星砂礦（22金）", "cb": func(): _shop_buy("star_ore", 22)},
		{"text": "買橡脂（18金）", "cb": func(): _shop_buy("oak_resin", 18)},
		{"text": "買騎士碎鐵（28金）", "cb": func(): _shop_buy("knight_shard", 28)},
		{"text": "買小紅水×1（12金）", "cb": func(): _shop_buy("hp_s", 12)},
		{"text": "買乾糧×1（8金）", "cb": func(): _shop_buy("bread", 8)},
		{"text": "一鍵賣出全部材料", "cb": _shop_sell_all},
		{"text": "回每日／委託", "cb": _go_daily_panel},
		{"text": "關閉", "cb": _hub_back},
	]
	_panel("琥珀 · 材料行", body, buttons)


func _shop_buy(item_id: String, price: int) -> void:
	if GameState.gold < price:
		_play_dialog([{"speaker": "琥珀", "text": "金幣不夠。去打點雜魚或賣材料。"}], _go_material_shop)
		return
	GameState.add_gold(-price)
	InventorySystem.add_item(item_id, 1)
	QuestSystem.track_day("shop", 1)
	SaveManager.save_game()
	_play_dialog([
		{"speaker": "琥珀", "text": "成交。別死外頭——我還想再賺你一次。"},
		{"speaker": "系統", "text": "購入【%s】×1（-%d金）" % [InventorySystem.item_name(item_id), price]},
	], _go_material_shop)


func _shop_sell_all() -> void:
	var r: Dictionary = InventorySystem.sell_all_materials()
	_play_dialog([
		{"speaker": "琥珀" if bool(r.get("ok", false)) else "系統", "text": str(r.get("msg", ""))},
	], _go_material_shop)


func _go_guild_panel() -> void:
	var body := GuildSystem.status_bbcode()
	var buttons: Array = []
	if not GuildSystem.is_joined():
		for g in GuildSystem.GUILDS:
			var gid := str(g.get("id", ""))
			var gname := str(g.get("name", gid))
			buttons.append({"text": "加入：%s" % gname, "cb": func():
				var r: Dictionary = GuildSystem.join(gid)
				_play_dialog([{"speaker": "盟約", "text": str(r.get("msg", ""))}], _go_guild_panel)
			})
	else:
		buttons.append({"text": "下一則佈告", "cb": func():
			var line := GuildSystem.next_board()
			_play_dialog([{"speaker": "佈告欄", "text": line}], _go_guild_panel)
		})
		if GuildSystem.can_shop():
			buttons.append({"text": "公庫補給（貢獻 30）", "cb": func():
				var r: Dictionary = GuildSystem.buy_supply()
				_play_dialog([{"speaker": "公庫", "text": str(r.get("msg", ""))}], _go_guild_panel)
			})
		else:
			buttons.append({"text": "公庫補給（需貢獻 30）", "cb": _go_guild_panel})
	buttons.append({"text": "返回", "cb": _hub_back})
	_panel("公會／盟約", body, buttons)


func _hub_back() -> void:
	## 標題／章節／探索：回到合理畫面
	if GameState.chapter == "title" or _current == Screen.TITLE:
		_go_title()
	else:
		_resume_from_chapter()


func _journey_summary() -> String:
	var checks := [
		["C0 離村", "c0_village_left"],
		["C0 首戰", "c0_first_battle"],
		["C1 鍛造", "c1_forged"],
		["C1 雷歐", "boss.leo_cleared"],
		["C1 小芽", "c1_sprout_done"],
		["C1 舊債", "side.ding_debt_done"],
		["C2 麥穗信", "c2_wheat_letter"],
		["C2 家書", "side.fog_letter_done"],
		["C2 白霧", "boss.white_fog_cleared"],
		["C3 阿波", "boss.abo_cleared"],
		["C4 疾影", "boss.shadowwind_cleared"],
		["C5 石拳", "boss.stonefist_cleared"],
		["岔路浪人", "side.ronin_done"],
		["C6 魔王", "boss.demon_cleared"],
		["通關", "game_cleared"],
	]
	var done := 0
	var lines: PackedStringArray = []
	for c in checks:
		var ok: bool = GameState.has_flag(str(c[1]))
		if ok:
			done += 1
		lines.append(("%s ✓" if ok else "%s ·") % str(c[0]))
	return "進度 %d／%d\n%s\n章節：%s · 金 %d · 星屑 %d" % [
		done, checks.size(), "  ".join(lines), GameState.chapter, GameState.gold, GameState.stardust
	]


func _grant_boss_loot(gold_n: int, dust_n: int, hp_n: int = 0) -> void:
	if gold_n != 0:
		GameState.add_gold(gold_n)
	if dust_n != 0:
		GameState.add_stardust(dust_n)
	if hp_n > 0:
		GameState.max_hp += hp_n
		GameState.hp = GameState.effective_max_hp()
	GuildSystem.add_contrib(20)
	SaveManager.save_game()


func _touch_save_stone(extra: String = "") -> void:
	## 存檔石：存檔 + 回滿血
	GameState.hp = GameState.effective_max_hp()
	SaveManager.save_game()
	var newly: Array[String] = TitleCatalog.evaluate_all()
	var msg := "進度已保存。傷勢也穩了。"
	if extra != "":
		msg += " " + extra
	if not newly.is_empty():
		msg += " 新稱號：%s" % "、".join(newly)
	_play_dialog([{"speaker": "系統", "text": msg}])


func _show_pause_titles(box: VBoxContainer, sub: Label) -> void:
	TitleCatalog.evaluate_all()
	SaveManager.save_game()
	sub.text = "稱號 %d／%d · Esc 或「繼續」返回" % [
		TitleCatalog.unlocked_count(), TitleCatalog.total_count()
	]
	## 清空按鈕列下的說明，改顯示稱號摘要
	var names: String = TitleCatalog.unlocked_names_line()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(300, 80)
	sub.text = "已解鎖：%s\n（完整牆面請回標題「稱號牆」）" % names
	AudioManager.play_ui()


func _pause_btn(parent: VBoxContainer, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(btn, text == "繼續")
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _play_dialog(lines: Array, after: Callable = Callable()) -> void:
	if _paused:
		_close_pause()
	if _explore and is_instance_valid(_explore) and _explore.has_method("set_frozen"):
		_explore.call("set_frozen", true)
	_after_dialogue = after
	AudioManager.play_ui()
	_dialogue.play(lines)


func _on_dialogue_finished() -> void:
	if _explore and is_instance_valid(_explore) and _explore.has_method("set_frozen"):
		_explore.call("set_frozen", false)
	var cb := _after_dialogue
	_after_dialogue = Callable()
	if cb.is_valid():
		cb.call()


func _on_choice(i: int) -> void:
	if _current == Screen.C0_VILLAGE:
		if i == 0 or i == 2:
			GameState.set_flag("c0_care", true)
		else:
			GameState.set_flag("c0_stubborn", true)
	## 小芽贊助 30 金
	if _current == Screen.C1_TOWN and GameState.has_flag("c1_sprout_asked") and not GameState.has_flag("c1_sprout_done"):
		if i == 0 and GameState.gold >= 30 and not GameState.has_flag("item.wood_sword"):
			GameState.gold -= 30
			GameState.stardust += 3
			GameState.set_flag("c1_sprout_done", true)
			TitleCatalog.evaluate_all()
			SaveManager.save_game()


func _clear_host() -> void:
	_explore = null
	for c in host.get_children():
		c.queue_free()


# ─── 面板宿主介面 ───
## 給 scripts/ui/panels/* 用的公開契約。拆 main.gd 時，各面板只准碰這幾支，
## 不要直接呼叫底線開頭的私有方法 —— 那是為了讓面板能一塊一塊搬走而不互相黏死。

func ui_panel(title: String, body: String, buttons: Array) -> void:
	_panel(title, body, buttons)


func ui_toast(msg: String) -> void:
	_show_toast(msg)


func ui_hub_back() -> void:
	_hub_back()


func ui_open_hunt_recycle() -> void:
	_go_hunt_recycle_panel()


func _panel(title: String, body: String, buttons: Array) -> void:
	_clear_host()
	_reset_fade()
	## 進選單時確保沒有殘留過場擋滑鼠
	if _cutscene and is_instance_valid(_cutscene) and _cutscene.visible:
		if _cutscene.has_method("abort"):
			_cutscene.call("abort")
	if _dialogue and is_instance_valid(_dialogue):
		_dialogue.visible = false
		_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 全屏底 + 置中卡片（按鈕永遠在最上層可點）
	var layer := Control.new()
	layer.name = "MenuLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.969, 0.965, 0.973, 1)  ## Artale paper
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	## 可選底圖（標題／章節用）
	var art_path := ""
	if _current == Screen.TITLE:
		art_path = "res://assets/sprites/maps/village_bg.png"
	elif _current == Screen.C1_AFTERMATH:
		art_path = "res://assets/sprites/maps/town_bg.png"
	if art_path != "" and ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture = load(art_path) as Texture2D
		art.modulate = Color(0.55, 0.52, 0.58, 0.55)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(art)
		var veil := ColorRect.new()
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.color = Color(0.04, 0.03, 0.06, 0.55)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)  ## 楓式較窄小窗
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(root)

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	root.add_child(t)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = UiStyle.WOOD
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rule)

	var b := RichTextLabel.new()
	b.bbcode_enabled = true
	b.fit_content = true
	b.scroll_active = true
	b.text = body
	## 限高 + 不擋滑鼠，避免正文把按鈕擠出或吞點擊
	b.custom_minimum_size = Vector2(380, 0)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_color_override("default_color", UiStyle.INK)
	b.add_theme_font_size_override("normal_font_size", 13)
	root.add_child(b)
	## 正文過長時限高，按鈕永遠可見
	if body.length() > 280:
		b.fit_content = false
		b.custom_minimum_size = Vector2(380, 140)
		b.scroll_active = true

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(row)

	for i in buttons.size():
		var item: Dictionary = buttons[i]
		var btn := Button.new()
		btn.text = str(item["text"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 30)
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.disabled = false
		UiStyle.style_button(btn, i == 0)
		## deferred：避免在 pressed 當幀清掉 host 導致「卡死」
		var cb: Callable = item["cb"]
		btn.pressed.connect(func():
			AudioManager.play_ui()
			## 只暫時關掉整列，下一幀回呼；不要留下「灰掉的新的旅途」假卡死
			for c in row.get_children():
				if c is Button:
					(c as Button).disabled = true
			call_deferred("_run_menu_cb", cb)
		)
		row.add_child(btn)
	if row.get_child_count() > 0:
		(row.get_child(0) as Button).grab_focus()
	## 下一幀再確保 fade / 過場不擋
	call_deferred("_reset_fade")


func _run_menu_cb(cb: Callable) -> void:
	_reset_fade()
	if cb.is_valid():
		cb.call()


func _open_explore(map_id: String, screen: Screen) -> void:
	_open_explore_then(map_id, screen, Callable())


func _open_explore_then(map_id: String, screen: Screen, after: Callable) -> void:
	_fade_pulse(func():
		_clear_host()
		_current = screen
		_last_explore_map = map_id
		_last_explore_screen = screen
		_explore = ExploreViewScn.new()
		_explore.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(_explore)
		_explore.setup(map_id)
		_explore.interacted.connect(_on_explore_interact)
		AudioManager.play_bgm_for_map(map_id)
		WorldContent.mark_visit(map_id)
		EventRuntime.mark_explore_daily()
		if OnlineGate.is_signed_in():
			OnlineGate.push_presence(map_id)
		## 舊存檔補起始包
		if GameState.has_flag("tut_done"):
			InventorySystem.grant_starter()
		## 探索引導（僅首次）
		var tips: Array = TutorialSystem.take("explore")
		if not tips.is_empty() and not after.is_valid():
			call_deferred("_play_dialog", tips, Callable())
		if after.is_valid():
			## 場景就緒後再跑教學／後續，避免卡在空 host
			call_deferred("_run_after_explore", after)
		call_deferred("_refresh_hud")
	)


func _run_after_explore(after: Callable) -> void:
	if after.is_valid():
		after.call()


func _toggle_inventory() -> void:
	if _inv_panel == null:
		return
	if _inv_panel.visible:
		_inv_panel.call("close")
	else:
		_inv_panel.call("open")
		AudioManager.play_ui()
	_refresh_hud()


func _use_hotbar_slot(slot: int) -> void:
	var res: Dictionary = InventorySystem.use_hotbar_slot(slot)
	if not bool(res.get("ok", false)):
		var msg := str(res.get("msg", ""))
		if msg != "":
			_show_toast(msg)
		return
	if _hotbar and _hotbar.has_method("pulse_slot"):
		_hotbar.call("pulse_slot", slot)
	SaveManager.save_game()
	_refresh_hud()
	if _inv_panel and _inv_panel.visible and _inv_panel.has_method("refresh"):
		_inv_panel.call("refresh")


func _on_hotbar_click(slot: int) -> void:
	## 左鍵：使用
	_use_hotbar_slot(slot)


func _on_hotbar_use(slot: int) -> void:
	_use_hotbar_slot(slot)


func _on_inv_use_item(item_id: String) -> void:
	var res: Dictionary = InventorySystem.use_item(item_id)
	if not bool(res.get("ok", false)):
		_show_toast(str(res.get("msg", "無法使用")))
	else:
		SaveManager.save_game()
	_refresh_hud()
	if _inv_panel and _inv_panel.has_method("refresh"):
		_inv_panel.call("refresh")


func _on_inv_assign_hotbar(item_id: String) -> void:
	## 放到第一個空位或替換第 1 格
	InventorySystem.ensure_hotbar()
	var placed := false
	for i in GameState.hotbar.size():
		if str(GameState.hotbar[i]) == "" or str(GameState.hotbar[i]) == item_id:
			InventorySystem.set_hotbar(i, item_id)
			placed = true
			_show_toast("已綁定快捷鍵 %d：%s" % [i + 1, InventorySystem.item_name(item_id)])
			break
	if not placed:
		InventorySystem.set_hotbar(0, item_id)
		_show_toast("快捷欄已滿，改綁 1：%s" % InventorySystem.item_name(item_id))
	if _hotbar and _hotbar.has_method("refresh"):
		_hotbar.call("refresh")


func _show_toast(msg: String) -> void:
	if msg == "" or _toast == null:
		return
	_toast.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if _toast:
			_toast.visible = false
			_toast.modulate.a = 1.0
	)


func _player_bubble(text: String) -> void:
	if _explore and is_instance_valid(_explore) and _explore.has_method("show_player_bubble"):
		_explore.call("show_player_bubble", text)


## ── Godogen / proof_capture 用公開入口（勿在正式劇情呼叫）──
func proof_jump_explore(map_id: String = "town") -> void:
	if _paused:
		_close_pause()
	if _inv_panel and _inv_panel.visible and _inv_panel.has_method("close"):
		_inv_panel.call("close")
	if _cutscene and is_instance_valid(_cutscene) and _cutscene.has_method("abort"):
		_cutscene.call("abort")
	if _dialogue and is_instance_valid(_dialogue):
		_dialogue.visible = false
		_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_after_dialogue = Callable()
	_reset_fade()
	## 跳過教學／鎖
	GameState.set_flag("tut_done", true)
	GameState.set_flag("c0_first_battle", true)
	GameState.set_flag("c1_entered_city", true)
	GameState.set_flag("item.rusty_sword", true)
	InventorySystem.grant_starter()
	var screen := Screen.C1_TOWN
	var mid := map_id
	if map_id.begins_with("village") or map_id == "road":
		screen = Screen.C0_VILLAGE if map_id.begins_with("village") else Screen.C0_ROAD
		GameState.set_chapter("c0")
	elif map_id.begins_with("mist"):
		screen = Screen.C2_MIST
		GameState.set_chapter("c2")
		GameState.set_flag("c2_entered", true)
	elif map_id.begins_with("dojo"):
		screen = Screen.C3_DOJO
		GameState.set_chapter("c3")
	elif map_id.begins_with("forest"):
		screen = Screen.C4_FOREST
		GameState.set_chapter("c4")
	elif map_id.begins_with("coast"):
		screen = Screen.C5_COAST
		GameState.set_chapter("c5")
	elif map_id.begins_with("tower"):
		screen = Screen.C6_TOWER
		GameState.set_chapter("c6")
	else:
		GameState.set_chapter("c1")
		if mid == "":
			mid = "town"
	## 立即換探索（不走 fade，證明用）
	_clear_host()
	_current = screen
	_last_explore_map = mid
	_last_explore_screen = screen
	_explore = ExploreViewScn.new()
	_explore.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(_explore)
	_explore.setup(mid)
	_explore.interacted.connect(_on_explore_interact)
	AudioManager.play_bgm_for_map(mid)
	WorldContent.mark_visit(mid)
	EventRuntime.mark_explore_daily()
	if OnlineGate.is_signed_in():
		OnlineGate.push_presence(mid)
	if _explore.has_method("show_player_bubble"):
		_explore.call("show_player_bubble", "PROOF · 探索", 2.5)
	_refresh_hud()


func proof_open_inventory() -> void:
	if _inv_panel == null:
		return
	if _inv_panel.has_method("open"):
		_inv_panel.call("open")
	_refresh_hud()


func proof_close_inventory() -> void:
	if _inv_panel and _inv_panel.has_method("close"):
		_inv_panel.call("close")
	_refresh_hud()


func proof_show_forge() -> void:
	## 確保可開鐵匠
	GameState.set_flag("c1_forged", true)
	GameState.set_flag("c1_entered_city", true)
	if GameState.weapon_tier < 2:
		GameState.weapon_tier = 2
		GameState.weapon_atk = maxi(GameState.weapon_atk, 9)
		GameState.weapon_name = "微末之刃"
	_go_c1_forge()


func proof_show_paths() -> void:
	GameState.set_flag("c1_forged", true)
	_go_path_panel(false)


func proof_show_battle(mode: String = "road_bandit") -> void:
	GameState.set_flag("c1_forged", true)
	GameState.set_flag("c1_entered_city", true)
	if GameState.hp < 10:
		GameState.hp = GameState.effective_max_hp()
	_start_battle(mode)


func proof_show_soul() -> void:
	GameState.set_flag("c1_soul_intro", true)
	GameState.set_flag("c1_entered_city", true)
	if GameState.stardust < 5:
		GameState.add_stardust(5)
	_go_soul_panel()


func _go_title() -> void:
	if _paused:
		_close_pause()
	_reset_fade()
	## 徹底關掉過場／對話，解除擋點擊
	if _cutscene and is_instance_valid(_cutscene):
		if _cutscene.has_method("abort"):
			_cutscene.call("abort")
		else:
			_cutscene.visible = false
			_cutscene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dialogue and is_instance_valid(_dialogue):
		_dialogue.visible = false
		_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_after_dialogue = Callable()
	_current = Screen.TITLE
	GameState.set_chapter("title")
	AudioManager.play_bgm("title")
	var newly: Array[String] = TitleCatalog.evaluate_all()
	if not newly.is_empty():
		SaveManager.save_game()
	var buttons: Array = [
		{"text": Loc.t("title.new_game"), "cb": _new_game},
	]
	if SaveManager.has_save():
		buttons.append({"text": Loc.t("title.continue"), "cb": _continue_game})
	if GameState.has_flag("game_cleared") or GameState.ng_plus > 0:
		buttons.append({"text": Loc.t("title.ng"), "cb": _go_ng_plus_menu})
	buttons.append({"text": Loc.t("title.titles"), "cb": _go_title_wall})
	var ev_label := EventRuntime.title_button_label()
	if ev_label != "":
		buttons.append({"text": ev_label, "cb": _go_event_panel})
	if QuestSystem.can_claim_daily():
		buttons.append({"text": "每日獎勵 ★", "cb": _go_daily_panel})
	else:
		buttons.append({"text": "每日／任務", "cb": _go_quest_panel})
	buttons.append({"text": "公會／盟約", "cb": _go_guild_panel})
	var online_lbl := "連線設定 · 純單機" if OnlineGate.offline_only else "連線設定 · 星途"
	buttons.append({"text": online_lbl, "cb": _go_online_panel})
	buttons.append({"text": "顯示設定 · %s" % DisplaySettings.mode_label(), "cb": _go_display_settings})
	## 語言切換
	var lang_label := "Language: English" if Loc.locale == "zh_TW" else "語言：繁體中文"
	buttons.append({"text": lang_label, "cb": _toggle_locale})
	var ng_line := ""
	if GameState.ng_plus > 0:
		ng_line = "\n[b]二周目 · 黑焰迴響 ×%d[/b]%s" % [
			GameState.ng_plus,
			" · 沾焰" if GameState.stain_flame else "",
		]
	else:
		ng_line = "\n一周目旅途"
	var title_line := "稱號 %d／%d" % [TitleCatalog.unlocked_count(), TitleCatalog.total_count()]
	var body := "[center][i]%s[/i][/center]\n\n" % Loc.t("title.tagline")
	body += Loc.t("title.blurb") + "\n\n"
	body += "[color=#7fd]v0.9 · 每日／任務／公會／活動[/color]\n"
	if EventRuntime.has_active():
		var pev: Dictionary = EventRuntime.primary_event()
		body += "[color=#c96]本期活動：%s（今日有獎剩 %d）[/color]\n" % [
			str(pev.get("name", "")),
			EventRuntime.daily_left(pev),
		]
	body += "[color=#b8a88a]%s%s[/color]\n\n" % [title_line, ng_line]
	body += "[color=#8a8070]%s[/color]" % Loc.t("title.controls")
	_panel("勇者之魂", body, buttons)
	_refresh_hud()
	## 首次啟動引導
	if not TutorialSystem.seen("boot"):
		call_deferred("_boot_tutorial")


func _toggle_locale() -> void:
	if Loc.locale == "zh_TW":
		Loc.set_locale("en")
	else:
		Loc.set_locale("zh_TW")
	AudioManager.play_ui()
	_go_title()


func _go_display_settings() -> void:
	## 顯示：全螢幕／視窗 + 解析度 + 垂直同步
	var body := "[b]顯示設定[/b]\n\n"
	body += DisplaySettings.summary_line() + "\n\n"
	body += "預設為[b]全螢幕[/b]。切到視窗後可用解析度調整大小。\n"
	body += "邏輯畫面固定 16:9；多餘區域為黑邊。\n"
	var buttons: Array = []
	buttons.append({"text": "模式：%s（點擊切換）" % DisplaySettings.mode_label(), "cb": _display_cycle_mode})
	buttons.append({"text": "解析度：%s（下一檔）" % DisplaySettings.res_label(), "cb": _display_cycle_res})
	buttons.append({"text": "解析度：上一檔", "cb": _display_cycle_res_back})
	for r in DisplaySettings.RESOLUTIONS:
		var rid := str(r.get("id", ""))
		var mark := " ✓" if rid == DisplaySettings.res_id else ""
		buttons.append({
			"text": "　%s%s" % [str(r.get("label", rid)), mark],
			"cb": _display_pick_res.bind(rid),
		})
	var vs_label := "垂直同步：開" if DisplaySettings.vsync else "垂直同步：關"
	buttons.append({"text": vs_label, "cb": _display_toggle_vsync})
	buttons.append({"text": "套用並返回", "cb": _display_settings_back})
	_panel("顯示設定", body, buttons)
	_refresh_hud()


func _display_cycle_mode() -> void:
	DisplaySettings.cycle_mode()
	AudioManager.play_ui()
	_go_display_settings()


func _display_cycle_res() -> void:
	DisplaySettings.cycle_resolution(1)
	AudioManager.play_ui()
	_go_display_settings()


func _display_cycle_res_back() -> void:
	DisplaySettings.cycle_resolution(-1)
	AudioManager.play_ui()
	_go_display_settings()


func _display_pick_res(rid: String) -> void:
	DisplaySettings.set_resolution(rid)
	AudioManager.play_ui()
	_go_display_settings()


func _display_toggle_vsync() -> void:
	DisplaySettings.set_vsync(not DisplaySettings.vsync)
	AudioManager.play_ui()
	_go_display_settings()


func _display_settings_back() -> void:
	DisplaySettings.apply()
	AudioManager.play_ui()
	_show_toast(DisplaySettings.summary_line())
	_hub_back()



func _boot_tutorial() -> void:
	var lines: Array = TutorialSystem.take("boot")
	if lines.is_empty():
		return
	_play_dialog(lines)


func _go_title_wall() -> void:
	var newly: Array[String] = TitleCatalog.evaluate_all()
	SaveManager.save_game()
	AudioManager.play_ui()
	var body: String = TitleCatalog.wall_bbcode()
	body += "\n\n已解鎖：%s" % TitleCatalog.unlocked_names_line()
	if not newly.is_empty():
		body = "[color=#fc8]新解鎖：%s[/color]\n\n" % "、".join(newly) + body
	var buttons: Array = [
		{"text": "返回標題", "cb": _go_title},
	]
	if GameState.has_flag("game_cleared"):
		buttons.append({"text": "黑焰裂縫", "cb": _go_postgame_hub})
		buttons.append({"text": "騎士堡", "cb": _go_c1_town})
	_panel("稱號牆", body, buttons)


func _new_game() -> void:
	GameState.reset_new_game()
	SaveManager.save_game()
	_go_c0()


func _go_ng_plus_menu() -> void:
	if not GameState.has_flag("game_cleared") and GameState.ng_plus <= 0:
		_play_dialog([{"speaker": "系統", "text": "尚未通關。先走到晨光。"}], _go_title)
		return
	## 預覽下一層倍率
	var next_lv := maxi(1, GameState.ng_plus + 1)
	var next_m: float = minf(1.30, 1.15 + 0.05 * float(next_lv - 1))
	_panel(
		"黑焰迴響",
		"再走一次——敵 HP／攻擊 ×%.2f（層 %d）。\n機制窗略縮 10%%。\n\n保留：武器、數值、外觀、裂縫紀錄。\n重跑：主線 Boss 進度。\n\n「沾焰」：刃染灰邊，攻擊 +3（可累積外觀）。" % [next_m, next_lv],
		[
			{"text": "再走一次", "cb": func(): _start_ng_plus(false)},
			{"text": "再走一次 · 沾焰", "cb": func(): _start_ng_plus(true)},
			{"text": "返回標題", "cb": _go_title},
		]
	)


func _start_ng_plus(with_stain: bool) -> void:
	GameState.start_ng_plus_run(with_stain)
	## 二周目：給一點盟約與任務進度感
	GuildSystem.add_contrib(25)
	SaveManager.save_game()
	AudioManager.play_bgm("title")
	var stain_s := "刃上多了一層不肯散的灰。" if with_stain else "你仍選了乾淨的刃。"
	var tips: Array = TutorialSystem.take("ng")
	var lines: Array = [
		{"speaker": "旁白", "text": "黑焰退後，又在腳邊留下一圈淺痕——像邀請。"},
		{"speaker": "斷頁", "text": "卷軸可以重抄。脚印，只能再踩一次。"},
		{"speaker": "系統", "text": "【二周目】黑焰迴響 ×%d。%s" % [GameState.ng_plus, stain_s]},
		{"speaker": "系統", "text": "敵強化 ×%.2f · 機制窗略短 · 保留養成與外觀。" % GameState.ng_enemy_mult()},
		{"speaker": "系統", "text": "NPC 台詞與盟約佈告會變化。HUD 顯示迴響層。"},
	]
	for t in tips:
		lines.append(t)
	_play_dialog(lines, _go_c0)


func _continue_game() -> void:
	if SaveManager.load_game() != OK:
		_go_title()
		return
	_apply_saved_ui_layout()
	_resume_from_chapter()


func _apply_saved_ui_layout() -> void:
	## 讀檔後重套 HUD／快捷欄位置（物品欄／小地圖在開啟或進探索時各自套）
	var vp := get_viewport().get_visible_rect().size
	if _maple_hud and is_instance_valid(_maple_hud):
		UiLayout.apply_to(_maple_hud, "hud", Vector2(8, 8))
	if _hotbar and is_instance_valid(_hotbar):
		var hb_fb := Vector2((vp.x - 430) * 0.5, vp.y - 68)
		UiLayout.apply_to(_hotbar, "hotbar", hb_fb)
	if _hotbar and _hotbar.has_method("refresh"):
		_hotbar.call("refresh")


func _resume_from_chapter() -> void:
	match GameState.chapter:
		"c0":
			if GameState.has_flag("c0_first_battle"):
				_go_c1_town()
			elif GameState.has_flag("c0_village_left"):
				_go_c0_road()
			else:
				_go_c0()
		"c1":
			if GameState.has_flag("boss.leo_cleared") and not GameState.has_flag("boss.white_fog_cleared"):
				## 可回城或進 C2
				_go_c1_town()
			elif GameState.has_flag("c1_forged"):
				_go_c1_wild()
			else:
				_go_c1_town()
		"c2":
			if GameState.has_flag("boss.white_fog_cleared"):
				_go_c2_cleared_panel()
			else:
				_go_c2_mist()
		"c3":
			if GameState.has_flag("boss.abo_cleared"):
				_go_c3_cleared_panel()
			else:
				_go_c3_dojo()
		"c4":
			if GameState.has_flag("boss.shadowwind_cleared"):
				_go_c4_cleared_panel()
			else:
				_go_c4_forest()
		"c5":
			if GameState.has_flag("boss.stonefist_cleared"):
				_go_c5_cleared_panel()
			else:
				_go_c5_coast()
		"c6":
			if GameState.has_flag("boss.demon_cleared"):
				_go_postgame_hub()
			else:
				_go_c6_camp()
		"cleared":
			_go_postgame_hub()
		_:
			_go_c0()


# ─── 探索互動分發 ───

func _on_explore_interact(id: String) -> void:
	## 全域路標／子地圖（各章共用）
	if _handle_world_travel(id):
		return
	## 廣域：寶箱／雜魚／秘境小 Boss
	if _handle_world_content(id):
		return
	## 支線掛點（舊債／家書／浪人／絲絨等）
	if _handle_side_content(id):
		return
	var before := _current
	match _current:
		Screen.C0_VILLAGE:
			_interact_village(id)
		Screen.C0_ROAD:
			_interact_road(id)
		Screen.C1_TOWN:
			_interact_town(id)
		Screen.C1_WILD:
			_interact_wild(id)
		Screen.C2_MIST:
			_interact_mist(id)
		Screen.C3_DOJO:
			_interact_dojo(id)
		Screen.C4_FOREST:
			_interact_forest(id)
		Screen.C5_COAST:
			_interact_coast(id)
		Screen.C6_TOWER:
			_interact_tower_camp(id)
		_:
			pass
	## 章節 handler 未消費的新分區物件 → 氛圍台詞（廣域探索）
	if _current == before and not _dialogue.visible:
		_flavor_world_object(id)


func _handle_side_content(id: String) -> bool:
	## 回傳 true 表示已消費互動
	match id:
		"silk", "codex_shelf":
			_side_silk(id)
			return true
		"weapon_rack", "officer_desk":
			if _side_try_pick_broken_blade(id):
				return true
			return false
		"knight_orphan":
			_side_knight_orphan()
			return true
		"ronin":
			_side_ronin()
			return true
		"amber":
			_side_amber()
			return true
		"target_dummy", "training_ring":
			_side_training_spar(id)
			return true
		"guard_dog":
			_play_dialog([{"speaker": "守車犬", "text": "汪。（尾巴一下，像在說：先付金幣。）"}])
			return true
		_:
			return false


func _side_training_spar(id: String) -> void:
	## 演武場可重複練功：經驗 + 招式熟練
	if id == "training_ring" and not GameState.has_flag("c1_forged"):
		_play_dialog([{"speaker": "旁白", "text": "演武台沙上還有舊腳印。先去釘釘把劍養好再練。"}])
		return
	var cost := 0
	if int(GameState.get_flag("meta.train_today", 0)) >= 8:
		_play_dialog([{"speaker": "系統", "text": "今日練功已達上限。去野外或獵場換換空氣。"}])
		return
	_play_dialog([
		{"speaker": "系統", "text": "木靶／演武：要練一回合嗎？（無金幣消耗 · 每日有限）"},
		{
			"speaker": "系統",
			"text": "戰力 %d · Lv%d · 流派 %s" % [GameState.power_score(), GameState.level, GameState.path_display()],
			"choices": ["開練", "離開"],
			"replies": ["腳步沉進沙裡。", "改天。"],
		},
	], func():
		## 選項 0 = 開練：用簡易獎勵模擬（避免每次都進全戰可省時間）
		_side_training_do()
	)


func _side_training_do() -> void:
	## 簡化練功：直接給經驗與熟練（也可改為真開 ash_rat）
	var n := int(GameState.get_flag("meta.train_today", 0))
	GameState.set_flag("meta.train_today", n + 1)
	QuestSystem.track_day("train", 1)
	var base_xp := 10 + GameState.level * 2
	if GameState.path_style == "sword":
		base_xp += 4
	var xr: Dictionary = GameState.add_xp(base_xp)
	SkillSystem.add_mastery("slash", 6)
	if SkillSystem.is_learned("blade_dance"):
		SkillSystem.add_mastery("blade_dance", 5)
	if SkillSystem.is_learned("star_pierce"):
		SkillSystem.add_mastery("star_pierce", 5)
	if SkillSystem.is_learned("iron_guard"):
		SkillSystem.add_mastery("iron_guard", 4)
	## 小幅回血；偶爾掉鐵屑
	GameState.hp = mini(GameState.effective_max_hp(), GameState.hp + 3)
	var mat_s := ""
	if randf() < 0.35:
		InventorySystem.add_item("iron_scrap", 1)
		mat_s = " · 鐵屑×1"
	SaveManager.save_game()
	var msg := "練功結束。經驗 +%d" % int(xr.get("gained", base_xp))
	if int(xr.get("levels", 0)) > 0:
		msg += " · 升級至 Lv%d！" % GameState.level
	msg += " · 招式熟練↑ · 今日 %d／8%s" % [int(GameState.get_flag("meta.train_today", 0)), mat_s]
	_play_dialog([
		{"speaker": "系統", "text": msg},
		{"speaker": "系統", "text": "戰力現為 %d。材料可拿去釘釘鍛武器，或賣給琥珀。" % GameState.power_score()},
	])


func _side_silk(id: String) -> void:
	if id == "codex_shelf":
		var lines: Array = [
			{"speaker": "典籍", "text": "《黑焰三說》抄本：野心為食；至弱至塔；鏡中無我。"},
			{"speaker": "典籍", "text": "邊注（絲絨）：官方刪了『前任至弱者曾守護六域』。"},
		]
		if GameState.has_flag("c2_wheat_letter"):
			lines.append({"speaker": "內心", "text": "信比卷軸真。絲絨說得對。"})
		if not GameState.has_flag("lore.codex_read"):
			lines.append({"speaker": "系統", "text": "讀畢。金幣＋10 · 星屑＋1。"})
			_play_dialog(lines, func():
				GameState.set_flag("lore.codex_read", true)
				GameState.add_gold(10)
				GameState.add_stardust(1)
				SaveManager.save_game()
			)
		else:
			_play_dialog(lines)
		return
	_play_dialog(NpcLines.silk())


func _side_try_pick_broken_blade(id: String) -> bool:
	## 釘釘舊債：演武場武器架撿斷劍
	if not GameState.has_flag("side.ding_debt_asked"):
		if id == "weapon_rack":
			_play_dialog([{"speaker": "旁白", "text": "武器架空了大半。有一把斷劍半埋沙裡——刃口很舊。"}])
			return true
		return false
	if GameState.has_flag("side.ding_debt_done") or GameState.has_flag("item.broken_blade"):
		_play_dialog([{"speaker": "旁白", "text": "這裡已經沒有釘釘要的東西了。"}])
		return true
	_play_dialog([
		{"speaker": "旁白", "text": "沙坑邊的武器架下，一把斷劍露出半截。刃上刻著舊騎士團章。"},
		{"speaker": "內心", "text": "釘釘說的……舊主的鐵。"},
		{"speaker": "系統", "text": "獲得【舊主斷劍】。拿回給釘釘。"},
	], func():
		GameState.set_flag("item.broken_blade", true)
		SaveManager.save_game()
		_player_bubble("撿到斷劍了")
	)
	return true


func _side_knight_orphan() -> void:
	if GameState.has_flag("side.ding_debt_done"):
		_play_dialog([
			{"speaker": "遺孤少年", "text": "鐵匠大叔後來不太罵人了。……還是會罵。但比較輕。"},
		])
		return
	if GameState.has_flag("side.ding_debt_asked"):
		_play_dialog([
			{"speaker": "遺孤少年", "text": "斷劍？在武器架那邊。我不敢碰——怕鐵匠生氣。"},
			{"speaker": "遺孤少年", "text": "我爹以前……也是團裡的。現在只剩沙。"},
		])
		return
	_play_dialog([
		{"speaker": "遺孤少年", "text": "演武場以前很吵。現在只剩風。"},
		{"speaker": "遺孤少年", "text": "灰鬍子說：旗還掛著，人就不能先倒下。"},
	])


func _side_amber() -> void:
	if GameState.has_flag("item.true_letter") and not GameState.has_flag("side.fog_letter_done"):
		_play_dialog([
			{"speaker": "琥珀", "text": "喔？你手上那封……霧隱的印？交給頭領吧，我只收金幣不收心事。"},
			{"speaker": "琥珀", "text": "材料行照開——鍛造材、紅水，現貨。"},
		], _go_material_shop)
		return
	_play_dialog([
		{"speaker": "琥珀", "text": "材料行開張。鐵屑、星砂、橡脂、騎士碎鐵——打怪掉的我收，缺的我賣。"},
		{"speaker": "琥珀", "text": "循環懂吧？打→賣／鍛→不夠再買→再打。兔子也得會算帳。"},
	], _go_material_shop)


func _side_ronin() -> void:
	if GameState.has_flag("side.ronin_done"):
		if GameState.has_flag("side.ronin_spared"):
			if _current == Screen.C6_TOWER or _last_explore_map == "tower_camp":
				_play_dialog([
					{"speaker": "黑焰浪人", "portrait": "road_bandit", "text": "我在這裡守火。上去的人……別學我把焰當柴。"},
					{"speaker": "黑焰浪人", "text": "你若倒下，我會把你拖回來。——只一次。"},
				])
			else:
				_play_dialog(NpcLines.ronin())
		else:
			_play_dialog([{"speaker": "旁白", "text": "地上只剩燒過的靴印。浪人已不在。"}])
		return
	## 未完結：分岔
	if not GameState.has_flag("boss.leo_cleared"):
		_play_dialog([{"speaker": "黑焰浪人", "text": "……還太早。先去打你的獅子。"}])
		return
	GameState.set_flag("side.ronin_met", true)
	var can_persuade := GameState.has_flag("c2_wheat_letter") \
		or GameState.has_flag("c0_wheat_saved") \
		or GameState.has_flag("c1_sprout_done")
	var choices: Array = ["拔劍——解決你", "你走你的，我走我的"]
	var replies: Array = [
		"……好。讓我看看你的『強』有多重。",
		"裝蒜？黑焰不吃這套。",
	]
	if can_persuade:
		choices.append("焰會吃掉你——別再餵它")
		replies.append("……閉嘴。你沒資格——……你有麥稈味。")
	_play_dialog([
		{"speaker": "黑焰浪人", "portrait": "road_bandit", "text": "站住。你也是來『變強』的？"},
		{"speaker": "黑焰浪人", "text": "黑焰教我：心一軟，就被吃乾淨。我不會再軟。"},
		{
			"speaker": "黑焰浪人",
			"text": "怎麼，兔子？要刀還是要滾？",
			"choices": choices,
			"replies": replies,
		},
	], func():
		## choices 回調在 _play_dialog 後需靠 flag 或二次處理；用延遲選項面板更穩
		_side_ronin_choice_panel(can_persuade)
	)


func _side_ronin_choice_panel(can_persuade: bool) -> void:
	var buttons: Array = [
		{"text": "拔劍應戰", "cb": _side_ronin_fight},
		{"text": "轉身離開（稍後再說）", "cb": _side_ronin_leave},
	]
	if can_persuade:
		buttons.insert(1, {"text": "勸他收刃（需：信／稈／小芽）", "cb": _side_ronin_persuade})
	_panel("黑焰浪人 · 分岔", "岔路風很硬。他擋在東向的影子裡。\n\n【擊敗】或【勸降】都會結束這條支線。", buttons)


func _side_ronin_leave() -> void:
	_play_dialog([
		{"speaker": "黑焰浪人", "text": "逃？也好。下次我不會讓路。"},
	], func():
		_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
	)


func _side_ronin_fight() -> void:
	_play_dialog([
		{"speaker": "黑焰浪人", "text": "來。讓焰決定誰該走。"},
	], func(): _start_battle("black_ronin"))


func _side_ronin_persuade() -> void:
	_play_dialog([
		{"speaker": "內心", "text": "我把麥穗的字、小芽的木劍、自己的傷——都攤開。"},
		{"speaker": "黑焰浪人", "text": "……矯情。"},
		{"speaker": "黑焰浪人", "text": "……可焰沒有因此更亮。奇怪。"},
		{"speaker": "黑焰浪人", "text": "滾。我自己的路自己斷。你——去塔。"},
		{"speaker": "系統", "text": "浪人收刃。金幣＋40 · 星屑＋3。稱號進度。"},
	], func():
		GameState.set_flag("side.ronin_spared", true)
		GameState.set_flag("side.ronin_done", true)
		GameState.add_gold(40)
		GameState.add_stardust(3)
		TitleCatalog.evaluate_all()
		SaveManager.save_game()
		_player_bubble("他收刃了")
		_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
	)


func _side_finish_ronin_battle(won: bool) -> void:
	if won:
		_grant_boss_loot(55, 3, 0)
		var xr: Dictionary = GameState.add_xp(70)
		GameState.set_flag("side.ronin_defeated", true)
		GameState.set_flag("side.ronin_done", true)
		GameState.set_flag("meta.skirmish_wins", int(GameState.get_flag("meta.skirmish_wins", 0)) + 1)
		TitleCatalog.evaluate_all()
		SaveManager.save_game()
		var lv_msg := " · 升級！" if int(xr.get("levels", 0)) > 0 else ""
		_play_dialog([
			{"speaker": "黑焰浪人", "text": "……強……又如何……焰還是空的。"},
			{"speaker": "系統", "text": "戰勝黑焰浪人。金 55 · 星屑 3 · 經驗 %d%s。他倒下的地方，靴印不再燒。" % [int(xr.get("gained", 70)), lv_msg]},
		], func():
			_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
		)
	else:
		GameState.hp = maxi(1, int(GameState.max_hp * 0.4))
		SaveManager.save_game()
		_play_dialog([
			{"speaker": "黑焰浪人", "text": "回去練。別用『想變強』當藉口——那是我的台詞。"},
		], func():
			_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
		)


func _side_deliver_true_letter() -> void:
	_play_dialog([
		{"speaker": "行商", "portrait": "caravan_chief", "text": "這印……霧隱？假信我看過一百封。"},
		{"speaker": "行商", "text": "……紙邊有火燎。是真的。我們會送到村外那戶。"},
		{"speaker": "行商", "text": "謝了，兔子。路上少一層假，就少一場刀。"},
		{"speaker": "系統", "text": "交付【真信】。金幣＋45 · 星屑＋3。"},
	], func():
		GameState.set_flag("item.true_letter", false)
		GameState.set_flag("side.fog_letter_done", true)
		GameState.add_gold(45)
		GameState.add_stardust(3)
		TitleCatalog.evaluate_all()
		SaveManager.save_game()
		_player_bubble("真信送達")
	)


func _side_start_ding_debt() -> void:
	if GameState.has_flag("side.ding_debt_done"):
		_play_dialog(NpcLines.ding(), _show_forge_panel)
		return
	if GameState.has_flag("item.broken_blade"):
		_play_dialog([
			{"speaker": "釘釘", "text": "……拿來。"},
			{"speaker": "系統", "text": "釘釘把斷劍放進爐。第三錘很輕，像在對誰道歉。"},
			{"speaker": "釘釘", "text": "舊主的鐵。我當年沒鍛完就跑了。"},
			{"speaker": "釘釘", "text": "現在合上了。你——別學我丟下沒做完的東西。"},
			{"speaker": "系統", "text": "舊債了結。金幣＋50 · 星屑＋3 · 下次升階成功率提升（暫）。"},
		], func():
			GameState.set_flag("item.broken_blade", false)
			GameState.set_flag("side.ding_debt_done", true)
			GameState.set_flag("meta.forge_debt_bonus", true)
			GameState.add_gold(50)
			GameState.add_stardust(3)
			TitleCatalog.evaluate_all()
			SaveManager.save_game()
			_show_forge_panel()
		)
		return
	if not GameState.has_flag("side.ding_debt_asked"):
		_play_dialog([
			{"speaker": "釘釘", "text": "……站住。爐邊有件事。"},
			{"speaker": "釘釘", "text": "演武場武器架下，有一把斷劍。舊騎士團的。"},
			{"speaker": "釘釘", "text": "我欠那鐵一個收場。你若撿回來——我當你付過一次人情。"},
			{"speaker": "系統", "text": "【支線】鐵匠的舊債：去演武場取【舊主斷劍】。"},
		], func():
			GameState.set_flag("side.ding_debt_asked", true)
			SaveManager.save_game()
			_show_forge_panel()
		)
		return
	_play_dialog([
		{"speaker": "釘釘", "text": "斷劍還在演武場。別跟我扯廢話。"},
	], _show_forge_panel)


func _side_start_fog_letter() -> void:
	if GameState.has_flag("side.fog_letter_done"):
		_play_dialog(NpcLines.fog_hide())
		return
	if GameState.has_flag("item.true_letter"):
		_play_dialog(NpcLines.fog_hide())
		return
	if not GameState.has_flag("c2_wheat_letter"):
		_play_dialog(NpcLines.fog_hide())
		return
	## 讀完麥穗信後可接
	if not GameState.has_flag("side.fog_letter_asked"):
		_play_dialog([
			{"speaker": "霧隱", "text": "假信滿天飛。我這裡有一封真的——要送到村外行商驛站。"},
			{"speaker": "霧隱", "text": "假的給霧吃。真的，要人走。"},
			{"speaker": "系統", "text": "【支線】霧中家書：將【真信】交給岔路行商驛站的頭領。"},
		], func():
			GameState.set_flag("side.fog_letter_asked", true)
			GameState.set_flag("item.true_letter", true)
			SaveManager.save_game()
			_player_bubble("收下真信")
		)
		return
	_play_dialog(NpcLines.fog_hide())


func _flavor_world_object(id: String) -> void:
	var flavors := {
		"big_mill": "巨風車的葉片卡死了。風仍過，卻推不動任何東西。",
		"grain_silo": "糧倉空了。灰裡還有半袋焦麥。",
		"miller_hut": "碾坊主不在。桌上茶杯結了薄冰。",
		"wheat_sea": "麥浪在夜裡像黑焰的倒影。",
		"cave_mouth": "洞口呼出冷氣。深處有水滴聲。",
		"glow_moss": "螢光苔微微發綠——像有人故意種在這裡。",
		"deep_dark": "再進去會看不見路。先記在心裡。",
		"stone_gate": "墓園門半開。風從碑間穿過。",
		"grave_a": "無名碑。只有日期，沒有名字。",
		"fresh_earth": "新土。剛埋不久。",
		"bridge_arch": "石拱仍穩。谷底黑得像另一個世界。",
		"toll_ruin": "廢稅亭牆上刻著：「先交心，再過橋。」",
		"inn_sign": "破牌寫著「歇腳」。字被刀劃過。",
		"common_room": "大堂空椅對空椅。壁爐冷透。",
		"column_a": "古驛斷柱。柱身有星曜刻紋。",
		"star_mark": "十四星的簡圖。有人用刀補過最後一顆。",
		"stall_a": "布攤只剩支架。風在空棚裡說話。",
		"beggar": "老人抬眼：「騎士堡的旗……換過幾次了。」",
		"pipe_a": "鐵管嗡嗡響。像城在低語。",
		"slime_pool": "黏液池反著微光。別踩進去。",
		"training_ring": "演武台沙上還有舊腳印——很重、很穩。",
		"lion_statue": "石獅缺了一眼。另一眼望向內殿。",
		"honor_plaque": "「榮譽先於性命。」字被黑焰燻糊半行。",
		"rope_bridge": "繩橋晃。裂谷像要吞掉聲音。",
		"meteor_stone": "隕星石觸手微溫。像還記得天空。",
		"constellation": "地刻星圖。你腳下剛好踩在「弱」的位置。",
		"wish_pool": "淺池映星。許願？……先許平安。",
		"char_soil": "焦裂地燙腳心。黑焰曾在這裡醒來。",
		"whisper_stone": "低語石：……至弱……至塔……",
		"cliff_rail": "霧海在腳下翻。遠方像有六域的輪廓。",
		"fox_statue": "白狐像閉著眼。香灰未冷。",
		"mirror_a": "鏡裡不是你——是你猶豫的那一秒。",
		"true_path": "真影道微微發亮。假出口在偷笑。",
		"zen_pond": "靜心池無波。連風都繞開。",
		"bamboo_wall": "竹牆沙沙。像有人在林後練拳。",
		"peak_platform": "山巔試煉台。雲在腳邊。",
		"bridge_rope": "藤橋在樹冠搖。風耳說：別往下看。",
		"arch_ruin": "古遊俠拱門。石上還有箭痕。",
		"lake_shore": "靜湖倒映樹與天。心一靜，湖也靜。",
		"longship": "長船乾擱。龍骨像巨獸的脊。",
		"tide_pool": "潮池裡有小蟹。與黑焰無關，很好。",
		"hull": "沉船灣的船骸張著口。像要說一個浪的故事。",
		"mural": "封印壁畫：五獸環塔。中央空白——那是你的位置嗎？",
		"memory_orb_a": "記憶球浮出村火。你眨眨眼，它散了。",
		"memory_orb_b": "記憶球：騎士堡的旗第一次升起。",
		"memory_orb_c": "記憶球：聖獸還清明時的眼睛。",
		"throne_shadow": "王座影沒有實體。卻讓人想跪下——你沒有。",
		"wagon_a": "篷車裡有乾糧味與遠方泥土。",
		"map_table": "地圖桌標了六域。塔被畫得最大。",
		"goods_pile": "貨堆用帆布蓋著。行商的規矩：先問價。",
		"codex_shelf": "典籍架上積灰。絲絨的字跡比灰塵新。",
		"knight_orphan": "少年抱著斷木槍。眼睛比槍尖還直。",
		"armor": "空盔甲架。裡面沒有人，卻像還站著班。",
		"hall": "騎士舊廳回音很大。榮譽兩個字被煙燻黃。",
		"throne_hall": "議政廳門半掩。椅子比人多。",
		"keep_well": "內井水深。倒影裡沒有旗。",
		"statue_knight": "無名騎士像缺了半邊臉。另一半仍望著門。",
		"spice_smell": "香料殘跡還在——像有人昨天剛走。",
		"echo_drip": "滴水聲數到七就亂。下水道也不守規矩。",
		"sealed_door": "封死鐵門。牆上有人用指甲刻：別開。",
		"weapon_rack": "武器架空了大半。沙裡可能還埋著舊鐵。",
		"target_dummy": "木靶胸口全是洞。有人練得很兇，然後停了。",
		"banner_stand": "團旗架空著。布去了哪，沒人說。",
		"officer_desk": "隊長桌上壓著未簽名的調防令。日期是三年前。",
		"sand_pit": "沙坑還留著對練的腳印——一大一小。",
		"mask_shop": "面具攤：每一張笑臉背後都是同一張空。",
		"echo_well": "回聲井把你的名字還給你——慢半拍，像在猶豫。",
		"bell_tower": "霧鐘樓沒有鐘舌。風替它敲。",
		"kite_string": "斷線風箏纏在欄上。有人放，有人沒回來收。",
		"incense": "香灰結塊。願還沒散完。",
		"prayer_strip": "願條寫：願霧只騙敵人。字被淚暈過。",
		"secret_panel": "暗板後是空的。有人比你早來過。",
		"star_reader_camp": "星讀帳篷空著。星盤炭筆畫到一半。",
		"night_bloom": "夜開花只在沒人看時開。你看了一眼——它仍開著。",
	}
	if flavors.has(id):
		_play_dialog([{"speaker": "旁白", "text": str(flavors[id])}])
		return
	if _explore and is_instance_valid(_explore) and _explore.has_method("entity_label"):
		var lab: String = str(_explore.call("entity_label", id))
		if lab != "" and not lab.begins_with("往") and not lab.begins_with("回") and not lab.begins_with("通"):
			_play_dialog([{"speaker": "旁白", "text": "你端詳「%s」。風從翠嶺某處吹來。" % lab}])


func _handle_world_content(id: String) -> bool:
	## 秘境小 Boss
	var bosses: Dictionary = WorldContent.minibosses()
	if bosses.has(id):
		var b: Dictionary = bosses[id]
		var need := str(b.get("need_flag", ""))
		if need != "" and not GameState.has_flag(need):
			_play_dialog([{"speaker": "系統", "text": str(b.get("deny", "還不能挑戰。"))}])
			return true
		if GameState.has_flag(str(b.get("flag", ""))):
			_play_dialog([{"speaker": "旁白", "text": "這裡只剩清風。試煉已過。"}])
			return true
		var intro: Array = b.get("intro", [])
		var mode := str(b.get("mode", ""))
		_play_dialog(intro, func(): _start_battle(mode))
		return true

	## 寶箱（單次）
	var chests: Dictionary = WorldContent.chests()
	if chests.has(id):
		var c: Dictionary = chests[id]
		var flag := str(c.get("flag", ""))
		if GameState.has_flag(flag):
			_play_dialog([{"speaker": "旁白", "text": "空了。你已經拿過了。"}])
			return true
		GameState.set_flag(flag, true)
		EventRuntime.mark_explore_daily()
		var g := int(c.get("gold", 0))
		var d := int(c.get("dust", 0))
		_grant_boss_loot(g, d, 0)
		## 寶箱常掉消耗品
		var drop_msg := ""
		if randf() < 0.7:
			InventorySystem.add_item("hp_s", 1)
			drop_msg = " · 小紅水×1"
		elif randf() < 0.5:
			InventorySystem.add_item("bread", 1)
			drop_msg = " · 乾糧×1"
		if randf() < 0.25:
			InventorySystem.add_item("dust_crumb", 1)
			drop_msg += " · 星屑碎×1"
		if Engine.get_main_loop() is SceneTree:
			var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
			if gs and gs.has_method("add_contrib"):
				gs.call("add_contrib", 3)
		SaveManager.save_game()
		_play_dialog([
			{"speaker": "旁白", "text": str(c.get("text", "你找到了財物。"))},
			{"speaker": "系統", "text": "獲得 金 %d · 星屑 %d%s" % [g, d, drop_msg]},
		])
		_player_bubble("撿到東西了！")
		return true

	## 雜魚遭遇
	var sk: Dictionary = WorldContent.skirmishes()
	if sk.has(id):
		var s: Dictionary = sk[id]
		var once := str(s.get("once_flag", ""))
		if once != "" and GameState.has_flag(once):
			_play_dialog([{"speaker": "旁白", "text": "這裡已經平靜了。"}])
			return true
		var mode2 := str(s.get("mode", "ash_rat"))
		var intro_t := str(s.get("intro", "戰鬥！"))
		_play_dialog([{"speaker": "旁白", "text": intro_t}], func():
			if once != "":
				GameState.set_flag(once, true)
			_start_battle(mode2)
		)
		return true
	return false


func _return_to_explore(map_id: String, screen_key: String) -> void:
	_open_explore(map_id, _screen_from_key(screen_key))


func _screen_from_key(key: String) -> Screen:
	match key:
		"C0_VILLAGE":
			return Screen.C0_VILLAGE
		"C0_ROAD":
			return Screen.C0_ROAD
		"C1_TOWN":
			return Screen.C1_TOWN
		"C1_WILD":
			return Screen.C1_WILD
		"C2_MIST":
			return Screen.C2_MIST
		"C3_DOJO":
			return Screen.C3_DOJO
		"C4_FOREST":
			return Screen.C4_FOREST
		"C5_COAST":
			return Screen.C5_COAST
		"C6_TOWER":
			return Screen.C6_TOWER
		_:
			return _current


func _handle_world_travel(id: String) -> bool:
	## 特殊：世界輿圖 / 存檔 / 行商 / BOSS 入口（非純切圖）
	match id:
		"exit_world", "world_map_stone", "sign_board":
			_go_world_map()
			return true
		"fog_gate_deep":
			_c2_try_fog_boss()
			return true
		"falcon_nest_deep":
			_interact_forest("falcon_nest")
			return true
		"boar_cliff_near":
			_interact_coast("boar_cliff")
			return true
		"save_cross", "save_tower", "menu_save", "save_c2", "save_c3", "save_c4", "save_c5":
			_touch_save_stone()
			return true
		"message_stone", "wall_notice":
			_go_message_stone(id)
			return true
		"candle_altar":
			_go_candle_altar()
			return true
		"hunt_board", "hunt_start":
			_go_hunt_panel()
			return true
		"hunt_recycler":
			_go_hunt_recycle_panel()
			return true
		"star_market", "market_board":
			_go_market_panel()
			return true
		"warehouse_keep":
			_play_dialog([
				{"speaker": "倉庫官", "text": "騎士堡管庫的。可堆疊物與裝備都能存。"},
			], _go_warehouse_panel)
			return true
		"save_hunt":
			_touch_save_stone()
			return true
		"merchant", "event_stone":
			## 霧中家書：先交真信
			if id == "merchant" and GameState.has_flag("item.true_letter") and not GameState.has_flag("side.fog_letter_done"):
				_side_deliver_true_letter()
				return true
			if id == "event_stone" or EventRuntime.has_active() or not EventRuntime.ended_with_tokens().is_empty():
				var story: Array = []
				if EventRuntime.has_active():
					var evm: Dictionary = EventRuntime.primary_event()
					for s in evm.get("story", []):
						var spk := "行商" if id == "merchant" else "歲旅石"
						story.append({"speaker": spk, "portrait": "caravan_chief", "text": str(s)})
				else:
					story.append({"speaker": "歲旅石", "text": "石上刻著十二個月的足迹。有的已熄，有的正亮。"})
				_play_dialog(story, _go_event_panel)
				return true
			## 無活動：普通行商
			_play_dialog([
				{"speaker": "行商", "portrait": "caravan_chief", "text": "六域的路我都走過。金幣換消息：塔下最近開了門。"},
				{"speaker": "行商", "portrait": "caravan_chief", "text": "乾糧 15 金。先付再說。"},
			], func():
				if GameState.gold >= 15:
					GameState.add_gold(-15)
					InventorySystem.add_item("bread", 1)
					_show_toast("買下乾糧×1")
					if not GameState.has_flag("inv.map_scrap"):
						InventorySystem.add_item("map_scrap", 1)
						GameState.set_flag("inv.map_scrap", true)
					SaveManager.save_game()
					_refresh_hud()
				else:
					_show_toast("金幣不夠……")
			)
			return true
		"path_mist_c", "path_mist":
			_go_c2_enter()
			return true
		"path_dojo_c", "path_dojo":
			_go_c3_enter()
			return true
		"path_forest_c", "path_forest":
			_go_c4_enter()
			return true
		"path_coast_c", "path_coast":
			_go_c5_enter()
			return true
		"path_tower_c", "path_tower", "path_tower_c5":
			_go_c6_camp()
			return true
		"path_knight", "back_knight":
			_go_c1_town()
			return true
		"path_back_wild", "exit_wild", "exit_wild_inner":
			_go_c1_wild()
			return true
		"exit_town_hint", "dawn_glow":
			if GameState.has_flag("c0_first_battle"):
				_go_c1_town()
				return true
			return false
		"back_town":
			if _current == Screen.C1_WILD:
				_go_c1_town()
			else:
				_open_explore("town", Screen.C1_TOWN)
			return true
		_:
			pass

	## 通用表：WorldTravel.links()
	var links: Dictionary = WorldTravel.links()
	if not links.has(id):
		return false
	var link: Dictionary = links[id]
	var need := str(link.get("need_flag", ""))
	if need != "" and not GameState.has_flag(need):
		var deny := str(link.get("deny", "這條路還不能走。"))
		if deny != "":
			_play_dialog([{"speaker": "系統", "text": deny}])
		return true
	var map_id := str(link.get("map", ""))
	var screen_key := str(link.get("screen", ""))
	if map_id == "":
		return false
	## 進入主城／章節入口時走正式流程（旗標與過場）
	if map_id == "town" and screen_key == "C1_TOWN" and id in ["exit_town_hint", "dawn_glow", "path_knight"]:
		_go_c1_town()
		return true
	_open_explore(map_id, _screen_from_key(screen_key))
	return true


func _go_world_map() -> void:
	var body := "[b]翠嶺大陸 · 六域輿圖（0.9 廣域）[/b]\n\n"
	body += "　　　　遊俠森林（樹冠／靜湖／遺址）\n"
	body += "　　　　　　｜\n"
	body += "維京海岸 ── 法師之塔 ── 騎士堡壘\n"
	body += "（港／洞／沉船）　（門廳／階／回憶）　（市集／下水道／演武）\n"
	body += "　　　　　　｜\n"
	body += "　　　忍者村／霧隱（崖／祠／鏡廊）\n"
	body += "　　　　　　｜\n"
	body += "　　　武鬥道場（內院／竹林／山巔）\n\n"
	body += "秘境：星落平原 · 行商驛站 · 黑焰疤地 · 北山道 · 東塔荒原\n"
	body += "秘境 Boss：疤主 " + ("✓" if GameState.has_flag("boss.scar_lord_cleared") else "·")
	body += " · 鏡影 " + ("✓" if GameState.has_flag("boss.mirror_wraith_cleared") else "·")
	body += " · 船長 " + ("✓" if GameState.has_flag("boss.wreck_captain_cleared") else "·") + "\n"
	if EventRuntime.has_active():
		var pev: Dictionary = EventRuntime.primary_event()
		body += "\n[color=#c96]本期活動：%s · %s %d · 今日有獎剩 %d[/color]\n" % [
			str(pev.get("name", "")),
			str(pev.get("currency_name", "幣")),
			EventRuntime.tokens(str(pev.get("id", ""))),
			EventRuntime.daily_left(pev),
		]
	body += "寶箱 %d／16 · 造訪地圖 %d · 可走分區 %d\n\n" % [
		WorldContent.chest_opened_count(),
		WorldContent.visit_count(),
		WorldTravel.list_map_ids().size(),
	]
	body += "戰力 %d · Lv%d · 流派「%s」· 器階 T%d\n" % [
		GameState.power_score(), GameState.level, GameState.path_display(), GameState.weapon_tier
	]
	body += "經驗 %d／%d\n\n" % [GameState.xp, GameState.xp_to_next()]
	body += "解鎖（0.12 自由路線 · 建議戰力）：\n"
	body += "· 騎士堡 " + ("✓" if GameState.has_flag("c1_entered_city") or GameState.chapter != "c0" else "·") + "\n"
	body += "· 岔路／練功 " + ("✓ 鍛造後" if GameState.has_flag("c1_forged") else "鎖（先鍛造）") + "\n"
	body += "· 霧隱 " + ("✓" if GameState.has_flag("c2_entered") else "建議 18+") + "\n"
	body += "· 道場 " + ("✓" if GameState.has_flag("c3_entered") else "建議 26+") + "\n"
	body += "· 森林 " + ("✓" if GameState.has_flag("c4_entered") else "建議 30+ · 可選序") + "\n"
	body += "· 海岸 " + ("✓" if GameState.has_flag("c5_entered") else "建議 30+ · 可選序") + "\n"
	body += "· 塔 " + ("✓" if GameState.has_flag("c6_camp_cut") or GameState.has_flag("boss.abo_cleared") else "需足夠試煉") + "\n"
	var buttons: Array = [
		{"text": "騎士堡廣場", "cb": _go_c1_town},
		{"text": "城外荒野", "cb": _go_c1_wild},
	]
	if GameState.has_flag("c1_forged") or GameState.has_flag("boss.leo_cleared"):
		buttons.append({"text": "六域岔路", "cb": func(): _open_explore("crossroads", Screen.C1_WILD)})
		buttons.append({"text": "行商驛站", "cb": func(): _open_explore("caravan_camp", Screen.C1_WILD)})
		buttons.append({"text": "星落平原", "cb": func(): _open_explore("starfall_plain", Screen.C1_WILD)})
		buttons.append({"text": "霧隱村", "cb": _go_c2_enter})
		buttons.append({"text": "武鬥道場", "cb": _go_c3_enter})
		buttons.append({"text": "遊俠森林", "cb": _go_c4_enter})
		buttons.append({"text": "維京海岸", "cb": _go_c5_enter})
	if GameState.has_flag("boss.abo_cleared") or GameState.power_score() >= 36:
		buttons.append({"text": "黑焰疤地", "cb": func(): _open_explore("blackflame_scar", Screen.C1_WILD)})
	if GameState.has_flag("boss.abo_cleared") or GameState.has_flag("boss.shadowwind_cleared") \
			or GameState.has_flag("boss.stonefist_cleared") or GameState.power_score() >= 42:
		buttons.append({"text": "塔下營地", "cb": _go_c6_camp})
	if EventRuntime.has_active():
		buttons.append({"text": EventRuntime.title_button_label(), "cb": _go_event_panel})
	if HuntSystem.is_unlocked():
		buttons.append({"text": "星途獵場", "cb": func(): _open_explore("hunting_grounds", Screen.C1_WILD)})
	buttons.append({"text": "武器流派", "cb": _go_path_panel})
	buttons.append({"text": "返回當前", "cb": _hub_back})
	_panel("世界地圖", body, buttons)


func _interact_tower_camp(id: String) -> void:
	match id:
		"duanye":
			_c6_talk_duanye()
		"refugee_fire", "tent_a", "tent_b":
			_play_dialog([{"speaker": "逃難者", "text": "塔門開了……我們不敢上去。你……是那隻兔子嗎？"}])
		"scroll_pile":
			_play_dialog([{"speaker": "卷軸", "text": "「至弱者可至塔頂。卷未寫：若心慕強，焰先至。」"}])
		"tower_gate":
			_play_dialog([{"speaker": "旁白", "text": "塔門敞開。千年來第一次。黑焰在門縫裡呼吸。"}])
		"climb_tower":
			_c6_floor_shadow()
		_:
			pass


func _go_c0() -> void:
	GameState.set_chapter("c0")
	if not GameState.has_flag("c0_intro_cut"):
		GameState.set_flag("c0_intro_cut", true)
		_play_cutscene([
			{
				"bg": "village",
				"speaker": "旁白",
				"text": Loc.t("c0.intro1"),
			},
			{
				"bg": "village",
				"speaker": "旁白",
				"portrait": "麥穗",
				"text": Loc.t("c0.intro2"),
			},
			{
				"bg": "village",
				"speaker": "麥穗",
				"text": Loc.t("c0.intro3"),
			},
			{
				"bg": "village",
				"speaker": "旁白",
				"portrait": "小白",
				"text": Loc.t("c0.intro4"),
			},
		], func():
			SaveManager.save_game()
			_open_explore_then("village", Screen.C0_VILLAGE, _maybe_show_tutorial)
		)
	else:
		_open_explore_then("village", Screen.C0_VILLAGE, _maybe_show_tutorial)


func _maybe_show_tutorial() -> void:
	if GameState.has_flag("tut_done"):
		return
	## 進村後操作教學：短、可點連跳、目標清楚
	_play_dialog([
		{"speaker": "系統", "text": Loc.t("tut.welcome")},
		{"speaker": "系統", "text": Loc.t("tut.move")},
		{"speaker": "系統", "text": Loc.t("tut.interact")},
		{"speaker": "系統", "text": Loc.t("tut.leave")},
		{"speaker": "系統", "text": Loc.t("tut.battle")},
		{"speaker": "系統", "text": Loc.t("tut.parry")},
		{"speaker": "系統", "text": Loc.t("tut.done")},
	], func():
		GameState.set_flag("tut_done", true)
		InventorySystem.grant_starter()
		_show_toast("起始補給：小紅水×3 · 乾糧×2（1–8 使用 · I 背包）")
		SaveManager.save_game()
		_refresh_hud()
		if _explore and is_instance_valid(_explore) and _explore.has_method("show_guide_hint"):
			_explore.call("show_guide_hint", Loc.t("tut.hud_hint"))
	)


func _interact_village(id: String) -> void:
	match id:
		"maisui":
			_play_dialog([
				{"speaker": "麥穗", "text": Loc.t("c0.maisui1")},
				{
					"speaker": "麥穗",
					"text": Loc.t("c0.maisui2"),
					"choices": [
						Loc.t("c0.choice_you"),
						Loc.t("c0.choice_water"),
						Loc.t("c0.choice_help"),
					],
					"replies": [
						Loc.t("c0.reply_you"),
						Loc.t("c0.reply_water"),
						Loc.t("c0.reply_help"),
					],
				},
				{"speaker": "麥穗", "text": Loc.t("c0.maisui3")},
			])
		"sword":
			if GameState.has_flag("item.rusty_sword"):
				_play_dialog([{"speaker": "系統", "text": Loc.t("c0.sword_have")}])
			else:
				_play_dialog([
					{"speaker": "系統", "text": Loc.t("c0.sword1")},
					{"speaker": "系統", "text": Loc.t("c0.sword2")},
					{"speaker": "系統", "text": Loc.t("c0.sword3")},
					{"speaker": "內心", "text": Loc.t("c0.sword_inner")},
				], _c0_sword_done)
		"fire":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.fire")}])
		"hut_a":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.hut_a")}])
		"hut_b":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.hut_b")}])
		"well":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.well")}])
		"ash_pile":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.ash")}])
		"cart":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.cart")}])
		"sign_east":
			_play_dialog([{"speaker": "木牌", "text": Loc.t("flavor.sign_east")}])
		"exit_east":
			_c0_try_leave()
		"shrine_stub":
			_play_dialog([{"speaker": "小祠", "text": "香灰冷了。神也逃了嗎——還是人先走了？"}])
		"field_west", "hut_c", "fence_row":
			_play_dialog([{"speaker": "旁白", "text": "田埂與篱笆都被夜色咬過。世界比村子大——你才剛踏出第一步。"}])
		_:
			pass


func _c0_sword_done() -> void:
	GameState.weapon_name = "鏽劍"
	GameState.weapon_atk = 4
	GameState.weapon_tier = 1
	GameState.set_flag("c0_sword_triple_pull", true)
	GameState.set_flag("item.rusty_sword", true)
	SaveManager.save_game()


func _c0_try_leave() -> void:
	if not GameState.has_flag("item.rusty_sword"):
		_play_dialog([{"speaker": "系統", "text": "兩手空空。至少……撿起那柄劍。"}])
		return
	GameState.has_wheat_stalk = true
	GameState.set_flag("c0_village_left", true)
	var last := "……我會等你。" if GameState.has_flag("c0_care") else "快跑！"
	_play_dialog([
		{"speaker": "麥穗", "text": "（塞進你口袋一枝乾癟的麥穗桿）拿著。不是護身符。——是回家的氣味。"},
		{"speaker": "麥穗", "text": "記住回家的路！"},
		{"speaker": "麥穗", "text": last},
	], _c0_leave_cutscene)


func _c0_leave_cutscene() -> void:
	_play_cutscene([
		{
			"bg": "village",
			"speaker": "旁白",
			"portrait": "麥穗",
			"text": "腳步踩過仍燙的土。身後，爐火與哭聲一起變小。",
		},
		{
			"bg": "road",
			"speaker": "旁白",
			"portrait": "小白",
			"text": "荒路沒有名字。只有風，與遠遠一口像牙齒的石牆。",
		},
		{
			"bg": "road",
			"speaker": "內心",
			"text": "鏽劍很沉。沉得剛好——讓你記得：還活著。",
		},
	], _go_c0_road)


func _go_c0_road() -> void:
	SaveManager.save_game()
	_open_explore("road", Screen.C0_ROAD)


func _interact_road(id: String) -> void:
	match id:
		"wolf":
			_play_dialog([
				{"speaker": "旁白", "text": Loc.t("c0.wolf_spot")},
				{"speaker": "系統", "text": Loc.t("tut.battle")},
			], func(): _start_battle("wolf"))
		"look_back":
			_play_dialog([{"speaker": "內心", "text": Loc.t("flavor.look_back")}])
		"milepost":
			_play_dialog([{"speaker": "里程碑", "text": Loc.t("flavor.milepost")}])
		"bush_a", "bush_b":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.bush")}])
		"road_stone":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.road_stone")}])
		"dawn_glow", "exit_town_hint":
			if GameState.has_flag("c0_first_battle"):
				_play_dialog([
					{"speaker": "內心", "text": Loc.t("flavor.dawn")},
					{"speaker": "系統", "text": "石牆就在前方。"},
				], _go_c1_town)
			else:
				_play_dialog([{"speaker": "內心", "text": Loc.t("flavor.dawn")}])
		"milepost_b", "camp_ash", "bridge":
			_play_dialog([{"speaker": "旁白", "text": "長路向東延伸。翠嶺比地圖上畫的更大。"}])


func _start_battle(mode: String) -> void:
	if _paused:
		_close_pause()
	_reset_fade()
	## 首次戰鬥／格擋教學（對話後再進戰）
	var tut_key := "battle_auto"
	if mode in ["leo", "demon", "abo", "falcon", "boar", "wrath", "tide", "statue", "chrono", "scar_lord", "mirror_wraith", "wreck_captain"]:
		tut_key = "battle_parry"
	if mode == "fog":
		tut_key = "battle_fog"
	var tips: Array = TutorialSystem.take(tut_key)
	if not tips.is_empty():
		_play_dialog(tips, func(): _start_battle_raw(mode))
		return
	_start_battle_raw(mode)


func _start_battle_raw(mode: String) -> void:
	_current = Screen.BATTLE
	_battle_mode = mode
	_clear_host()
	var battle = _battle_scene.instantiate()
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(battle)
	battle.battle_finished.connect(_on_battle_finished)
	battle.setup(mode)
	_refresh_hud()


func _start_spectate_battle(mode: String, coop: bool = true) -> void:
	_current = Screen.BATTLE
	_battle_mode = "spectate:" + mode
	_clear_host()
	var battle = _battle_scene.instantiate()
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(battle)
	battle.battle_finished.connect(_on_spectate_battle_finished)
	if battle.has_method("setup_spectator"):
		battle.setup_spectator(mode, coop)
	else:
		battle.setup(mode)
	_refresh_hud()


func _on_spectate_battle_finished(_won: bool) -> void:
	RoomSystem.stop_spectate()
	SaveManager.save_game()
	_show_toast("觀戰結束")
	if RoomSystem.is_hunt_room():
		_go_hunt_room_panel()
	else:
		_go_room_panel()


func _on_battle_finished(won: bool) -> void:
	## 觀戰不應走到這裡；保險
	if str(_battle_mode).begins_with("spectate:"):
		_on_spectate_battle_finished(won)
		return
	SaveManager.save_game()
	if _battle_mode == "wolf":
		if won:
			_grant_boss_loot(25, 2, 0)
			if GameState.skill_slash_lv < 1:
				GameState.skill_slash_lv = 1
			GameState.set_flag("c0_first_battle", true)
			_play_dialog([
				{"speaker": "旁白", "text": "狼倒下時，紫焰散成灰。它看起來……比想像中瘦。"},
				{"speaker": "內心", "text": "這就是黑焰嗎。連野獸都……"},
				{"speaker": "系統", "text": "學會了【橫斬】。戰利：金 25 · 星屑 2。遠方，石牆在晨光中。"},
			], _c0_to_c1_cutscene)
		else:
			GameState.set_flag("c0_helped_by_stranger", true)
			_play_dialog([
				{"speaker": "系統", "text": "醒來時在路旁。有人用斗篷蓋過你——已不見人影。"},
			], _go_c0_road)
	elif _battle_mode == "leo":
		if won:
			_go_leo_win()
		else:
			_play_dialog([
				{"speaker": "雷歐", "text": "回去握草根吧。"},
				{"speaker": "系統", "text": "你被送回城中。可以再挑戰。"},
			], _go_c1_wild)
	elif _battle_mode == "fog":
		if won:
			_go_fog_win()
		else:
			_play_dialog([
				{"speaker": "白霧", "text": "迷路了呀……再來一次？"},
				{"speaker": "系統", "text": "你被送回霧隱村。記住：等本體發白再打。"},
			], _go_c2_mist)
	elif _battle_mode == "demon":
		if won:
			_go_demon_win()
		else:
			_play_dialog([
				{"speaker": "魔王", "text": "還是太輕了……"},
				{"speaker": "系統", "text": "你倒在塔階。可自塔下再試。"},
			], _go_c6_camp)
	elif _battle_mode == "abo":
		if won:
			_go_abo_win()
		else:
			_play_dialog([
				{"speaker": "阿波", "text": "拳裡還沒有道。再來。"},
				{"speaker": "系統", "text": "你被請出試煉堂。可再挑戰。"},
			], _go_c3_dojo)
	elif _battle_mode == "falcon":
		if won:
			_go_falcon_win()
		else:
			_play_dialog([
				{"speaker": "疾影", "text": "風把你帶走了……再等一次。"},
				{"speaker": "系統", "text": "你被送回樹屋。記住：等停拍再打。"},
			], _go_c4_forest)
	elif _battle_mode == "boar":
		if won:
			_go_boar_win()
		else:
			_play_dialog([
				{"speaker": "石拳", "text": "力氣不夠。站穩再來。"},
				{"speaker": "系統", "text": "你被送回碼頭。記住：對撞剝岩甲。"},
			], _go_c5_coast)
	elif _battle_mode in ["wrath", "tide", "statue", "chrono"]:
		if won:
			if RoomSystem.is_in_room() and RoomSystem.is_host():
				RoomSystem.host_report_result(true, func(res: Dictionary):
					var extra_b := str(res.get("bonus_msg", ""))
					if extra_b != "":
						_show_toast(extra_b)
					_go_rift_win(_battle_mode)
				)
			else:
				_go_rift_win(_battle_mode)
		else:
			PartySystem.end_party_battle()
			if RoomSystem.is_in_room() and RoomSystem.is_host():
				RoomSystem.host_report_result(false, func(_r: Dictionary): pass)
			var tips := {
				"wrath": "灼燒要在滿層前躍出。",
				"tide": "刺胞要在時限內清掉；看相位換普攻／技能。",
				"statue": "只打發光的石像。",
				"chrono": "炸彈要拆；落岩要進安全。",
			}
			_play_dialog([
				{"speaker": "系統", "text": "黑焰把你掀回塔下。%s" % tips.get(_battle_mode, "")},
			], func():
				if RoomSystem.is_in_room():
					_go_room_panel()
				else:
					_go_postgame_hub()
			)
	elif _battle_mode == "black_ronin":
		_side_finish_ronin_battle(won)
	elif WorldContent.is_world_battle(_battle_mode):
		_on_world_battle_finished(won)


func _on_world_battle_finished(won: bool) -> void:
	var mode := _battle_mode
	## 小 Boss
	for _eid in WorldContent.minibosses().keys():
		var b: Dictionary = WorldContent.minibosses()[_eid]
		if str(b.get("mode", "")) != mode:
			continue
		if won:
			GameState.set_flag(str(b.get("flag", "")), true)
			_grant_boss_loot(int(b.get("gold", 80)), int(b.get("dust", 4)), int(b.get("hp", 8)))
			var relic_msg := ""
			var relic: Dictionary = SoulSystem.grant_secret_relic(mode)
			if bool(relic.get("ok", false)):
				relic_msg = str(relic.get("msg", ""))
			InventorySystem.add_item("relic_token", 1)
			InventorySystem.add_item("hp_m", 1)
			if Engine.get_main_loop() is SceneTree:
				var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
				if gs and gs.has_method("add_contrib"):
					gs.call("add_contrib", 15)
			TitleCatalog.evaluate_all()
			SaveManager.save_game()
			var win_lines: Array = b.get("win", []).duplicate()
			if relic_msg != "":
				win_lines.append({"speaker": "系統", "text": relic_msg})
				if not bool(relic.get("duplicate", false)):
					win_lines.append({"speaker": "系統", "text": "可在 Esc → 戰魂 入槽裝備秘境魂器。"})
			win_lines.append({"speaker": "系統", "text": "背包：秘境印記×1 · 中紅水×1"})
			var wmap := str(b.get("win_map", "crossroads"))
			var wsc := str(b.get("win_screen", "C1_WILD"))
			_play_dialog(win_lines, func(): _return_to_explore(wmap, wsc))
		else:
			var lmap := str(b.get("lose_map", "crossroads"))
			var lsc := str(b.get("lose_screen", "C1_WILD"))
			_play_dialog([
				{"speaker": "系統", "text": str(b.get("lose", "你被擊退了。"))},
			], func(): _return_to_explore(lmap, lsc))
		return

	## 狩獵場波次
	if HuntSystem.is_run_active() and WorldContent.is_world_battle(mode):
		_on_hunt_battle_finished(won)
		return
	## 活動有獎挑戰優先
	if _event_try_finish_run_after_battle(won):
		return
	## 雜魚
	var def: Dictionary = WorldContent.enemy_def(mode)
	var ename := str(def.get("name", "敵人"))
	if won:
		var gold_n := 12 + int(def.get("max_hp", 50) / 12)
		var dust_n := 1 if int(def.get("max_hp", 50)) >= 90 else 0
		_grant_boss_loot(gold_n, dust_n, 0)
		var xp_n := 12 + int(def.get("max_hp", 50) / 10)
		if bool(def.get("is_boss", false)):
			xp_n = 80 + int(def.get("max_hp", 100) / 5)
		var xr: Dictionary = GameState.add_xp(xp_n)
		GameState.set_flag("meta.skirmish_wins", int(GameState.get_flag("meta.skirmish_wins", 0)) + 1)
		QuestSystem.track_day("skirmish", 1)
		var loot_s := InventorySystem.apply_drops(InventorySystem.roll_skirmish_loot(mode))
		var eq_s := ""
		if randf() < 0.12:
			var er: Dictionary = EquipmentSystem.try_drop_loot()
			if bool(er.get("ok", false)):
				eq_s = " · " + str(er.get("msg", ""))
		if Engine.get_main_loop() is SceneTree:
			var g2: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
			if g2 and g2.has_method("add_contrib"):
				g2.call("add_contrib", 2)
		GameLog.combat("擊敗 %s · 金 %d" % [ename, gold_n])
		SaveManager.save_game()
		var extra := (" · 星屑 %d" % dust_n) if dust_n > 0 else ""
		extra += " · 經驗 %d" % int(xr.get("gained", xp_n))
		if int(xr.get("levels", 0)) > 0:
			extra += " · 升級！"
		if loot_s != "":
			extra += " · " + loot_s
		extra += eq_s
		_play_dialog([
			{"speaker": "系統", "text": "擊敗%s。金 %d%s。" % [ename, gold_n, extra]},
		], _hub_back_from_world_battle)
	else:
		GameState.hp = maxi(1, int(GameState.max_hp * 0.35))
		SaveManager.save_game()
		_play_dialog([
			{"speaker": "系統", "text": "你掙脫了戰鬥。傷勢不輕——先找存檔石。"},
		], _hub_back_from_world_battle)


func _hub_back_from_world_battle() -> void:
	## 回到開戰前的探索圖
	if _last_explore_map != "":
		_open_explore(_last_explore_map, _last_explore_screen)
	else:
		_go_c1_town()


func _c0_to_c1_cutscene() -> void:
	_play_cutscene([
		{
			"bg": "road",
			"speaker": "旁白",
			"text": "黎明把石牆染成冷灰。旗不揚——卻仍掛著。",
		},
		{
			"bg": "town",
			"speaker": "旁白",
			"portrait": "灰鬚",
			"text": "城門旁站著一個不肯讓路的影子。鬍鬚比門栓還倔。",
		},
		{
			"bg": "town",
			"speaker": "灰鬚",
			"text": "……兔子。帶著煙味的兔子。",
		},
	], _go_c1_town)


func _go_c1_town() -> void:
	GameState.set_chapter("c1")
	if not GameState.has_flag("c1_entered_city"):
		GameState.set_flag("c1_entered_city", true)
		SkillSystem.grant_c1_greybeard()
		if GameState.skill_slash_lv < 1:
			GameState.skill_slash_lv = 1
		## 先播進城，再開探索
		_clear_host()
		_current = Screen.C1_TOWN
		_play_dialog([
			{"speaker": "灰鬚", "text": "停。兔子？"},
			{"speaker": "灰鬚", "text": "這裡不是菜園。回去。"},
			{
				"speaker": "灰鬚",
				"text": "……說吧。幹嘛還杵在門前。",
				"choices": ["村子被燒了。", "我來找能打黑焰的人。", "……讓我進去就好。"],
				"replies": [
					"翠谷？……煙味我聞得出。進來。別哭，沒用。",
					"能打黑焰的人？牆裡沒有這種神仙。只有還肯站崗的傻瓜。",
					"哼。至少話短。進門，別擋道。",
				],
			},
			{"speaker": "灰鬚", "text": "聽著，小東西。牆內也不是天堂。聖獅狂了，騎士團散了。"},
			{"speaker": "灰鬚", "text": "進了就別給我添亂。——劍橫著掃，別跟啄木鳥一樣戳。"},
			{"speaker": "系統", "text": "灰鬚指點了你。【橫斬】更穩了。Esc 可開「技能／招式」。"},
		], func():
			SaveManager.save_game()
			_open_explore("town", Screen.C1_TOWN)
		)
	else:
		_open_explore("town", Screen.C1_TOWN)


func _interact_town(id: String) -> void:
	match id:
		"greybeard":
			_c1_greybeard()
		"ding":
			_go_c1_forge()
		"star":
			_c1_star()
		"silk":
			_side_silk("silk")
		"flag":
			if GameState.has_flag("c1_flag_paw"):
				_play_dialog([{"speaker": "系統", "text": "旗上有炭筆歪扭兔爪。「有人用炭筆畫了兔子。耳朵不太對，勇氣很對。」"}])
			else:
				_play_dialog([{"speaker": "系統", "text": "灰旗低垂。城裡的人都在等一個不可能的奇蹟。"}])
		"sprout":
			_c1_sprout()
		"wall_notice":
			_play_dialog([{"speaker": "告示", "text": Loc.t("flavor.notice")}])
		"market":
			_play_dialog([
				{"speaker": "旁白", "text": Loc.t("flavor.market")},
				{"speaker": "系統", "text": "殘架旁有琥珀的告示：材料行在行商驛站；城內也可問攤位。"},
			], _go_material_shop)
		"forge_sign":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.forge_sign")}])
		"fountain":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.fountain")}])
		"bench":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.bench")}])
		"gate_arch":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.gate_arch")}])
		"exit_wild":
			_go_c1_wild()
		"barracks", "chapel", "stable":
			_play_dialog([{"speaker": "旁白", "text": "外城比想像中廣。騎士域曾是翠嶺的脊樑——現在只剩石與風。"}])
		"menu_save":
			GameState.hp = GameState.effective_max_hp()
			SaveManager.save_game()
			var newly2: Array[String] = TitleCatalog.evaluate_all()
			var extra := ""
			if not newly2.is_empty():
				extra = " 新稱號：%s" % "、".join(newly2)
			_play_dialog([
				{"speaker": "系統", "text": "進度已寫入存檔石。傷勢也穩了。%s" % extra},
				{"speaker": "系統", "text": "（可翻稱號牆）"},
			], _go_title_wall_from_town)
		_:
			pass


func _go_title_wall_from_town() -> void:
	## 從城內看稱號後回廣場
	var newly: Array[String] = TitleCatalog.evaluate_all()
	SaveManager.save_game()
	var body: String = TitleCatalog.wall_bbcode()
	if not newly.is_empty():
		body = "[color=#fc8]新解鎖：%s[/color]\n\n" % "、".join(newly) + body
	_panel(
		"稱號牆 · 騎士堡",
		body,
		[{"text": "回到廣場", "cb": _go_c1_town}]
	)


func _c1_star() -> void:
	if GameState.has_flag("c1_soul_intro"):
		var lines: Array = NpcLines.star()
		if lines.is_empty():
			lines = [{"speaker": "星讀", "text": "足迹會再交疊。星屑夠了就來觀星。"}]
		var tut: Array = TutorialSystem.take("soul")
		for t in tut:
			lines.append(t)
		_play_dialog(lines, _go_soul_panel)
		return
	_play_dialog([
		{"speaker": "星讀", "text": "你身上有煙味，和一點……尚未點名的星光。"},
		{"speaker": "星讀", "text": "路上會撿到星屑。拿來觀星——不是賭博，是讓足迹凝成刃的性格。"},
		{"speaker": "星讀", "text": "（教學）先送你一握星屑……星盤為你亮了一角。"},
		{"speaker": "系統", "text": "獲得星屑 ×5。凝出戰魂「凡·破軍」，已入魂槽。"},
	], func():
		GameState.add_stardust(5)
		SoulSystem.grant_starter_soul()
		GameState.set_flag("c1_soul_intro", true)
		TutorialSystem.mark("soul")
		SaveManager.save_game()
		_go_soul_panel()
	)


func _go_soul_panel() -> void:
	SoulSystem.ensure_slots()
	var body: String = SoulSystem.panel_status_bbcode()
	body += "\n\n足迹偏科會影響觀星星型（如雷歐後破軍權重↑）。"
	var buttons: Array = []
	if SoulSystem.can_ritual():
		buttons.append({"text": "觀星（耗%d星屑）" % SoulSystem.RITUAL_COST, "cb": _soul_do_ritual})
	else:
		buttons.append({"text": "星屑不足（需%d）" % SoulSystem.RITUAL_COST, "cb": _go_soul_panel})
	## 背包入魂：每顆可選槽位
	var bag: Array = SoulSystem.bag_souls()
	var slots: int = SoulSystem.slot_count()
	for i in mini(5, bag.size()):
		var s: Dictionary = bag[i]
		var sid: String = str(s.get("id", ""))
		var label: String = "入魂：%s" % SoulSystem.soul_display(s)
		if slots >= 1:
			## 預設進第一空槽，否則槽1
			var target_slot := 0
			for si in GameState.soul_slots.size():
				if str(GameState.soul_slots[si]) == "":
					target_slot = si
					break
			buttons.append({"text": label, "cb": _soul_equip_cb(sid, target_slot)})
	for i in GameState.soul_slots.size():
		if str(GameState.soul_slots[i]) != "":
			var si: int = i
			buttons.append({"text": "卸下槽%d" % (si + 1), "cb": func():
				SoulSystem.unequip_slot(si)
				SaveManager.save_game()
				_go_soul_panel()
			})
	buttons.append({"text": "嘗試合成（3合1）", "cb": _soul_try_fuse})
	buttons.append({"text": "技能／招式", "cb": _go_skill_panel})
	buttons.append({"text": "回到廣場", "cb": _go_c1_town})
	_panel("星讀 · 觀星台", body, buttons)


func _c1_sprout() -> void:
	## 小芽支線：想要練習木劍
	if GameState.has_flag("c1_sprout_done"):
		if GameState.has_flag("boss.leo_cleared"):
			_play_dialog([
				{"speaker": "小芽", "text": "旗上的兔子是我畫的！……耳朵不太對，勇氣很對！"},
				{"speaker": "小芽", "text": "我每天練木劍。長大要守門——像灰鬍子那樣凶，也像你這樣……不凶。"},
			])
		else:
			_play_dialog([{"speaker": "小芽", "text": "木劍超好揮！謝謝你！……獅子……你真的要去嗎？"}])
		return
	if not GameState.has_flag("c1_sprout_asked"):
		_play_dialog([
			{"speaker": "小芽", "text": "我以後要當騎士！比獅子還大！你那把劍……好沉喔。"},
			{"speaker": "小芽", "text": "可是我沒有劍。木頭的也行……有人願意給我一把嗎？"},
			{"speaker": "系統", "text": "【支線】小芽想要練習木劍。可找釘釘做一把（20 金），或直接給她 30 金讓她去買。"},
		], func():
			GameState.set_flag("c1_sprout_asked", true)
			SaveManager.save_game()
		)
		return
	## 已問過：有木劍 → 送；有 30 金 → 可選贊助；否則提醒
	if GameState.has_flag("item.wood_sword"):
		_play_dialog([
			{"speaker": "小芽", "text": "那是……木劍？！給我嗎？"},
			{"speaker": "小芽", "text": "哇啊啊——！我會每天練！你去打獅子的時候……我在旗下等你回來！"},
			{"speaker": "系統", "text": "交木劍。獲得星屑 ×3、金幣 ×15。"},
		], func():
			GameState.set_flag("item.wood_sword", false)
			GameState.stardust += 3
			GameState.set_flag("c1_sprout_done", true)
			TitleCatalog.evaluate_all()
			SaveManager.save_game()
		)
		return
	if GameState.gold >= 30:
		_play_dialog([
			{
				"speaker": "小芽",
				"text": "你身上叮噹響……是要贊助我買木劍嗎？（30 金）",
				"choices": ["給她 30 金", "先不給"],
				"replies": [
					"謝謝你！！我會每天練！你打獅子的時候，我在旗下等你！",
					"好……我再等。不會纏著你的。",
				],
			},
		])
		return
	_play_dialog([
		{"speaker": "小芽", "text": "木劍……釘釘也許能做（20 金）。或湊三十金直接給我。"},
		{"speaker": "小芽", "text": "我不是貪心！是……想練給大家看。"},
	])


func _c1_greybeard() -> void:
	if GameState.has_flag("c1_forged") and not SkillSystem.is_learned("emergency_heal") and not GameState.has_flag("boss.leo_cleared"):
		_play_dialog([
			{"speaker": "灰鬚", "text": "刃有了。還差一口氣。"},
			{"speaker": "灰鬚", "text": "被咬到別硬撐——吐氣，把血留在身子裡。"},
			{"speaker": "系統", "text": "體悟【緊急恢復】。危急時怒氣會優先回血。"},
		], func():
			SkillSystem.grant_heal_insight()
			SaveManager.save_game()
			_go_skill_panel()
		)
		return
	var lines: Array = NpcLines.greybeard()
	_play_dialog(lines, _go_skill_panel)


func _go_skill_panel() -> void:
	SkillSystem.ensure_skill_map()
	var body: String = SkillSystem.panel_status_bbcode()
	var buttons: Array = []
	## 可習得
	for d in SkillSystem.CATALOG:
		var sid: String = str(d.get("id", ""))
		if SkillSystem.is_learned(sid):
			continue
		if SkillSystem.is_unlocked(sid):
			var nm: String = str(d.get("name", sid))
			buttons.append({"text": "體悟：%s" % nm, "cb": _skill_unlock_cb(sid)})
	## 導師指點（加速熟練）
	for d in SkillSystem.CATALOG:
		var sid2: String = str(d.get("id", ""))
		if SkillSystem.can_tutor(sid2):
			var label: String = "指點 %s（%d金）" % [SkillSystem.display_name(sid2), SkillSystem.TUTOR_COST]
			buttons.append({"text": label, "cb": _skill_tutor_cb(sid2)})
	buttons.append({"text": "戰魂／星屑", "cb": _go_soul_panel})
	buttons.append({"text": "回到廣場", "cb": _go_c1_town})
	_panel("灰鬚 · 旅途養招", body, buttons)


func _skill_unlock_cb(sid: String) -> Callable:
	return func():
		if SkillSystem.try_unlock(sid):
			SaveManager.save_game()
			_play_dialog([
				{"speaker": "灰鬚", "text": "成了。記住手感，別死記招名。"},
				{"speaker": "系統", "text": "習得【%s】" % SkillSystem.display_name(sid)},
			], _go_skill_panel)
		else:
			_play_dialog([{"speaker": "灰鬚", "text": "時機未到。"}], _go_skill_panel)


func _skill_tutor_cb(sid: String) -> Callable:
	return func():
		if not SkillSystem.can_tutor(sid):
			_play_dialog([{"speaker": "灰鬚", "text": "金幣，或你已經頂了。"}], _go_skill_panel)
			return
		var res: Dictionary = SkillSystem.tutor_train(sid)
		SaveManager.save_game()
		var line: String = "熟練推進。%s" % SkillSystem.mastery_progress_line(sid)
		if bool(res.get("leveled", false)):
			line = "體悟！升至 %s" % str(res.get("name", ""))
		_play_dialog([
			{"speaker": "灰鬚", "text": "手腕轉一下。對，這樣。"},
			{"speaker": "系統", "text": line},
		], _go_skill_panel)


func _soul_equip_cb(sid: String, slot: int) -> Callable:
	return func():
		var err: String = SoulSystem.equip_soul(sid, slot)
		if err != "":
			_play_dialog([{"speaker": "星讀", "text": err}], _go_soul_panel)
		else:
			SaveManager.save_game()
			_play_dialog([{"speaker": "系統", "text": "戰魂入槽。刃的性格變了。"}], _go_soul_panel)


func _soul_do_ritual() -> void:
	if not SoulSystem.can_ritual():
		_play_dialog([{"speaker": "星讀", "text": "星屑還不夠點亮一角。"}], _go_soul_panel)
		return
	## 足跡連線簡演出
	var footprint := "星圖暗昧。"
	if GameState.has_flag("boss.leo_cleared"):
		footprint = "騎士域的足迹亮起——勇與攻的線。"
	if GameState.has_flag("boss.white_fog_cleared"):
		footprint += " 霧痕交疊。"
	_play_dialog([
		{"speaker": "星讀", "text": "把星屑撒上星盤。"},
		{"speaker": "系統", "text": footprint},
		{"speaker": "系統", "text": "星屑凝成一點……"},
	], func():
		var soul: Dictionary = SoulSystem.ritual()
		SaveManager.save_game()
		if soul.is_empty():
			_play_dialog([{"speaker": "星讀", "text": "……今夜無星。"}], _go_soul_panel)
			return
		var line: String = "凝出 %s（%s）" % [
			SoulSystem.soul_display(soul), SoulSystem.soul_bonus_line(soul)
		]
		_play_dialog([
			{"speaker": "星讀", "text": "成了。不是運氣——是你走過的路。"},
			{"speaker": "系統", "text": line},
		], _go_soul_panel)
	)


func _soul_try_fuse() -> void:
	## 找第一組可合成的背包魂
	var counts: Dictionary = {}
	for s in SoulSystem.bag_souls():
		var key := "%s|%s|%d" % [s.get("star", ""), s.get("quality", ""), int(s.get("level", 0))]
		if not counts.has(key):
			counts[key] = []
		counts[key].append(s)
	for key in counts.keys():
		var arr: Array = counts[key]
		if arr.size() >= 3:
			var sample: Dictionary = arr[0]
			var lv: int = int(sample.get("level", 0))
			if lv >= 3:
				continue
			var fused: Dictionary = SoulSystem.fuse(
				str(sample.get("star", "")),
				str(sample.get("quality", "")),
				lv
			)
			SaveManager.save_game()
			if not fused.is_empty():
				_play_dialog([
					{"speaker": "星讀", "text": "三顆同軌，併作一層更亮的星。"},
					{"speaker": "系統", "text": "合成 → %s" % SoulSystem.soul_display(fused)},
				], _go_soul_panel)
				return
	_play_dialog([
		{"speaker": "星讀", "text": "要三顆同星、同品、同階，且未入魂。"},
	], _go_soul_panel)


func _go_c1_forge() -> void:
	_current = Screen.C1_FORGE
	var forge_tips: Array = TutorialSystem.take("forge")
	if not forge_tips.is_empty() and GameState.has_flag("c1_forged"):
		_play_dialog(forge_tips, _show_forge_panel)
		return
	if not GameState.has_flag("c1_forged"):
		_play_dialog([
			{"speaker": "釘釘", "text": "門開著不是讓兔子觀光的。"},
			{"speaker": "釘釘", "text": "……這什麼垃圾。挖土的？"},
			{"speaker": "釘釘", "text": "鏽進骨子了。你要走遠路，就別拿骨灰盒當武器。"},
			{"speaker": "系統", "text": "錘擊一。火花。"},
			{"speaker": "系統", "text": "錘擊二。刃上淺淺古紋。"},
			{"speaker": "釘釘", "text": "……你從哪撿的。"},
			{"speaker": "釘釘", "text": "算了。"},
			{"speaker": "系統", "text": "第三錘更輕、更準，像在對什麼道歉。"},
			{"speaker": "釘釘", "text": "叫它「微末之刃」正好。別弄丟。"},
			{"speaker": "釘釘", "text": "我養的是器。星什麼魂，去找愛看天的那個。"},
		], func():
			GameState.weapon_name = "微末之刃"
			GameState.weapon_atk = 9
			GameState.weapon_tier = 2
			GameState.set_flag("c1_forged", true)
			GameState.set_flag("c1_ding_recognized_sword", true)
			## 同步裝備實例（武器線起點）
			if not GameState.has_flag("equip.starter_meager"):
				var inst: Dictionary = EquipmentSystem.roll_instance("meager_edge", "uncommon")
				if not inst.is_empty():
					EquipmentSystem.add_to_bag(inst)
					EquipmentSystem.equip(str(inst.get("uid", "")))
				GameState.set_flag("equip.starter_meager", true)
			InventorySystem.add_item("iron_scrap", 3)
			SaveManager.save_game()
			## 0.12：鍛造後選流派（養成起點）
			if GameState.path_style == "":
				_go_path_panel(true)
			else:
				_show_forge_panel()
		)
	else:
		_show_forge_panel()


func _show_forge_panel() -> void:
	var body := "微末之刃 T%d · 攻擊 +%d\n連敗：%d（3 次釘釘發脾氣）\n金幣：%d（升階 50）" % [
		GameState.weapon_tier, GameState.weapon_atk, GameState.forge_fail_streak, GameState.gold
	]
	if GameState.has_flag("meta.forge_debt_bonus"):
		body += "\n舊債加成：升階更穩（一次人情）。"
	if GameState.has_flag("c1_sprout_asked") and not GameState.has_flag("c1_sprout_done"):
		body += "\n\n小芽想要練習木劍——可在此打一把（20 金）。"
	if GameState.has_flag("side.ding_debt_asked") and not GameState.has_flag("side.ding_debt_done"):
		if GameState.has_flag("item.broken_blade"):
			body += "\n\n【舊債】斷劍已帶回——可交給釘釘。"
		else:
			body += "\n\n【舊債】斷劍在演武場武器架。"
	var buttons: Array = [
		{"text": "升器階", "cb": _try_forge},
	]
	if GameState.has_flag("c1_sprout_asked") and not GameState.has_flag("item.wood_sword") and not GameState.has_flag("c1_sprout_done"):
		buttons.append({"text": "做木劍給小芽（20 金）", "cb": _forge_wood_sword})
	## 舊債支線入口
	if GameState.has_flag("c1_forged") and not GameState.has_flag("side.ding_debt_done"):
		var debt_label := "舊債：交斷劍" if GameState.has_flag("item.broken_blade") else "打聽舊債"
		if GameState.has_flag("side.ding_debt_asked") and not GameState.has_flag("item.broken_blade"):
			debt_label = "舊債進度（斷劍未取）"
		buttons.append({"text": debt_label, "cb": _side_start_ding_debt})
	if GameState.has_flag("c1_forged"):
		buttons.append({"text": "職系武器／護具鍛造", "cb": _go_craft_panel})
		buttons.append({"text": "武器流派（%s）" % GameState.path_display(), "cb": _go_path_panel})
	buttons.append({"text": "回到廣場", "cb": _go_c1_town})
	_panel("鐵匠鋪 · 釘釘", body, buttons)


func _go_craft_panel() -> void:
	if not GameState.has_flag("c1_forged"):
		_play_dialog([{"speaker": "釘釘", "text": "先讓我認你那把鏽鐵。"}], _show_forge_panel)
		return
	var body := "職系武器線 · 材料從野外掉落或琥珀商店買。\n"
	body += "流派契合武器會額外加戰力。金幣 %d\n\n" % GameState.gold
	body += "材料：鐵屑%d 星砂%d 橡脂%d 騎士碎鐵%d\n\n" % [
		InventorySystem.count("iron_scrap"),
		InventorySystem.count("star_ore"),
		InventorySystem.count("oak_resin"),
		InventorySystem.count("knight_shard"),
	]
	var recipes: Array = DataTables.craft_recipes()
	var lines: PackedStringArray = []
	for r in recipes:
		lines.append(EquipmentSystem.recipe_line(r))
	body += "\n".join(lines)
	var buttons: Array = []
	for i in mini(10, recipes.size()):
		var rec: Dictionary = recipes[i]
		var nm := str(EquipmentSystem.base_def(str(rec.get("base_id", ""))).get("name", "?"))
		var idx := i
		buttons.append({"text": "鍛：%s" % nm, "cb": func(): _do_craft(idx)})
	buttons.append({"text": "回鐵匠主選單", "cb": _show_forge_panel})
	_panel("釘釘 · 職系鍛造", body, buttons)


func _do_craft(recipe_index: int) -> void:
	var recipes: Array = DataTables.craft_recipes()
	if recipe_index < 0 or recipe_index >= recipes.size():
		_go_craft_panel()
		return
	var rec: Dictionary = recipes[recipe_index]
	var r: Dictionary = EquipmentSystem.craft(rec)
	_play_dialog([
		{"speaker": "釘釘", "text": "……看火。" if bool(r.get("ok", false)) else "材料不夠就別佔爐。"},
		{"speaker": "系統", "text": str(r.get("msg", ""))},
	], _go_craft_panel)


func _go_path_panel(from_forge: bool = false) -> void:
	var body := "【武器流派】選手感，不是鎖死職業。\n"
	body += "【器／魂／招】另算：鐵匠鍛造 · 星讀觀星 · 技能熟練。\n\n"
	body += "目前：%s · 戰力 %d · Lv%d\n\n" % [
		GameState.path_display(), GameState.power_score(), GameState.level
	]
	body += "劍 弓 法 拳 斧 鎚 槍 火槍 鏢 水晶 — 詳見優缺點（官網「武器流派」頁）。"
	var buttons: Array = []
	for c in DataTables.weapon_class_list():
		var id := str(c.get("id", ""))
		var label := "%s·%s" % [c.get("name", id), c.get("title", "")]
		var cid := id
		buttons.append({"text": label, "cb": func(): _set_path_and_back(cid, from_forge)})
	if from_forge:
		buttons.append({"text": "稍後再選", "cb": _show_forge_panel})
	else:
		buttons.append({"text": "技能／招式", "cb": _go_skill_panel})
		buttons.append({"text": "返回", "cb": _hub_back})
	_panel("武器流派（10）", body, buttons)


func _set_path_and_back(p: String, from_forge: bool) -> void:
	GameState.set_path_style(p)
	for sid in ["star_pierce", "iron_guard", "blade_dance", "emergency_heal", "slash"]:
		SkillSystem.try_unlock(sid)
	var d: Dictionary = DataTables.weapon_class_def(GameState.path_style)
	var tip := str(d.get("play", ""))
	var pros: Array = d.get("pros", [])
	var pro0 := str(pros[0]) if pros.size() > 0 else ""
	SaveManager.save_game()
	_play_dialog([
		{"speaker": "系統", "text": "選定武器流派【%s】。" % GameState.path_display()},
		{"speaker": "系統", "text": "玩法：%s。%s" % [tip, pro0]},
		{"speaker": "系統", "text": "星途觀星仍找星讀（戰魂）；不是職業名。戰力 %d。" % GameState.power_score()},
	], func():
		if from_forge:
			_show_forge_panel()
		else:
			_go_path_panel(false)
	)


func _forge_wood_sword() -> void:
	if GameState.gold < 20:
		_play_dialog([{"speaker": "釘釘", "text": "二十金。沒錢就別來佔爐。"}], _show_forge_panel)
		return
	if GameState.has_flag("item.wood_sword") or GameState.has_flag("c1_sprout_done"):
		_play_dialog([{"speaker": "釘釘", "text": "木劍？你不是拿過了。"}], _show_forge_panel)
		return
	_play_dialog([
		{"speaker": "釘釘", "text": "……木劍？給那個小崽子的？"},
		{"speaker": "釘釘", "text": "哼。三錘。別指望我雕花。"},
		{"speaker": "系統", "text": "獲得【練習木劍】。拿去給小芽。"},
	], func():
		GameState.gold -= 20
		GameState.set_flag("item.wood_sword", true)
		SaveManager.save_game()
		_show_forge_panel()
	)


func _try_forge() -> void:
	if GameState.weapon_tier >= 8:
		_play_dialog([{"speaker": "釘釘", "text": "夠了，先去砍獅子。"}], _show_forge_panel)
		return
	if GameState.gold < 50:
		_play_dialog([{"speaker": "釘釘", "text": "金幣呢？出城晃兩下。"}], _show_forge_panel)
		return
	GameState.add_gold(-50)
	var forge_rate := 0.70
	if GameState.has_flag("meta.forge_debt_bonus"):
		forge_rate = 0.88
	if GameState.path_style in ["hammer", "crystal"]:
		forge_rate = minf(0.95, forge_rate + 0.08)
	## 消耗 1 鐵屑可提高成功率
	var used_scrap := false
	if InventorySystem.has_item("iron_scrap", 1):
		InventorySystem.remove_item("iron_scrap", 1)
		forge_rate = minf(0.96, forge_rate + 0.12)
		used_scrap = true
	var ok := randf() < forge_rate or GameState.forge_fail_streak >= 3
	QuestSystem.track_day("craft", 1)
	if ok:
		GameState.weapon_tier += 1
		GameState.weapon_atk += 2
		GameState.forge_fail_streak = 0
		var scrap_s := "（耗鐵屑穩火）" if used_scrap else ""
		_play_dialog([{"speaker": "釘釘", "text": "成了。T%d。%s" % [GameState.weapon_tier, scrap_s]}], _show_forge_panel)
	else:
		GameState.forge_fail_streak += 1
		if GameState.forge_fail_streak >= 3:
			GameState.forge_fail_streak = 0
			GameState.hp = mini(GameState.max_hp, GameState.hp + 15)
			_play_dialog([
				{"speaker": "釘釘", "text": "（錘砸台面）夠了！鐵都比你有耐心！"},
				{"speaker": "釘釘", "text": "……消氣餅。滾。"},
			], _show_forge_panel)
		else:
			_play_dialog([{"speaker": "釘釘", "text": "失敗。階還在。材料沒了。"}], _show_forge_panel)
	SaveManager.save_game()


func _go_c1_wild() -> void:
	if not GameState.has_flag("c1_forged"):
		_play_dialog([{"speaker": "系統", "text": "鏽劍捲刃了。先去找釘釘。"}])
		return
	if GameState.gold < 100:
		GameState.add_gold(120)
	_open_explore("wild", Screen.C1_WILD)


func _interact_wild(id: String) -> void:
	match id:
		"back_town":
			_go_c1_town()
		"camp", "burnt_field":
			_play_dialog([{"speaker": "旁白", "text": "焦麥田。風裡有黑焰的腥甜。你握緊微末之刃。"}])
		"scarecrow":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.scarecrow")}])
		"rubble":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.rubble")}])
		"trail_mark":
			_play_dialog([{"speaker": "旁白", "text": Loc.t("flavor.trail")}])
		"tower":
			if GameState.has_flag("c1_tower_loot"):
				_play_dialog([{"speaker": "系統", "text": "哨塔空了。只剩風。"}])
			else:
				_play_dialog([
					{"speaker": "系統", "text": "廢棄哨塔裡摸到幾枚舊幣。金幣 ＋40。"},
				], func():
					GameState.add_gold(40)
					GameState.set_flag("c1_tower_loot", true)
					SaveManager.save_game()
				)
		"wild_shrine":
			_play_dialog([
				{"speaker": "小祠", "text": "「守的不是門。是門後那一點光。」"},
				{"speaker": "內心", "text": "……雷歐也該記得這個。"},
			])
		"supply_crate":
			if GameState.has_flag("c1_crate_loot"):
				_play_dialog([{"speaker": "系統", "text": "箱子空了。"}])
			else:
				_play_dialog([
					{"speaker": "系統", "text": "補給箱裡有繃帶與乾糧。回復一些傷勢，金幣 ＋20。"},
				], func():
					GameState.hp = mini(GameState.effective_max_hp(), GameState.hp + 25)
					GameState.add_gold(20)
					GameState.set_flag("c1_crate_loot", true)
					SaveManager.save_game()
				)
		"path_mist":
			_go_c2_enter()
		"leo_gate":
			if GameState.has_flag("boss.leo_cleared"):
				_play_dialog([{"speaker": "系統", "text": "聖獅已醒。內殿安靜下來。東南方霧道已開。"}])
			else:
				_play_dialog([
					{"speaker": "灰鬚", "text": "（若有回音）獅子不聽人話。聽刀。"},
					{"speaker": "灰鬚", "text": "你不是去證明你強。你是去讓它想起——它該守什麼。"},
					{"speaker": "雷歐", "text": "渺小的兔子……也想挑戰騎士之王？"},
					{"speaker": "系統", "text": "王者斬要格擋；場上會出火圈，預告後按 J 躍出。"},
				], func(): _start_battle("leo"))


func _go_leo_win() -> void:
	_grant_boss_loot(80, 4, 10)
	SkillSystem.grant_leo_insight()
	_play_dialog([
		{"speaker": "雷歐", "text": "原來……真正的騎士，是即使渺小也不退縮的勇氣。"},
		{"speaker": "雷歐", "text": "去吧，兔子——堡壘的門，為你而開。"},
		{"speaker": "雷歐", "text": "黑焰要的不是你的命，是你的欲望。別餵它。"},
		{"speaker": "系統", "text": "戰利：金 80 · 星屑 4 · 上限 HP+10。解鎖金鬃。體悟【怒雷】【反戈】。"},
	], _c1_leo_aftermath_cut)


func _c1_leo_aftermath_cut() -> void:
	_play_cutscene([
		{
			"bg": "wild",
			"speaker": "旁白",
			"portrait": "雷歐",
			"text": "聖獅臥下。內殿的塵第一次安靜得像有人在禱告。",
		},
		{
			"bg": "town",
			"speaker": "旁白",
			"portrait": "灰鬚",
			"text": "鏡頭只拍灰鬚的背影。門栓，被一隻不肯年輕的手拉開。",
		},
		{
			"bg": "town",
			"speaker": "灰鬚",
			"text": "……門為你開。去吧，小子。",
		},
		{
			"bg": "town",
			"speaker": "旁白",
			"portrait": "小芽",
			"text": "廣場旗揚起歪扭兔爪印。東南方，霧正升起。",
		},
	], _go_aftermath)


func _go_aftermath() -> void:
	_current = Screen.C1_AFTERMATH
	GameState.set_flag("c1_gate_open_back", true)
	GameState.set_flag("c1_flag_paw", true)
	GameState.set_flag("cosmetic.gold_mane", true)
	GameState.set_flag("boss.leo_cleared", true)
	SaveManager.save_game()
	AudioManager.play_bgm("town")
	_panel(
		"雷歐之後",
		"堡壘的門已開。\n廣場旗上有歪扭兔爪印——小芽說「差不多是你」。\n\n絲絨說：東南方霧起——忍者村。\n\n體悟【怒雷】【反戈】· 外觀契機：金鬃。",
		[
			{"text": "前往霧隱村（C2）", "cb": _go_c2_enter},
			{"text": "回到廣場", "cb": _go_c1_town},
			{"text": "出城荒野（霧道）", "cb": _go_c1_wild},
			{"text": "存檔回標題", "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── C2 霧與真 ───

func _go_c2_enter() -> void:
	if not _try_soft_enter_region("mist"):
		return
	if not GameState.has_flag("boss.leo_cleared") and not GameState.has_flag("c2_soft_warn"):
		GameState.set_flag("c2_soft_warn", true)
		_play_dialog([
			{"speaker": "系統", "text": "你尚未戰勝雷歐也能進霧——白霧仍很難。建議先鍛造、練等，或挑戰內殿。"},
		], func(): _go_c2_enter_body())
		return
	_go_c2_enter_body()


func _go_c2_enter_body() -> void:
	GameState.set_chapter("c2")
	if not GameState.has_flag("c2_entered"):
		GameState.set_flag("c2_entered", true)
		_play_cutscene([
			{
				"bg": "town",
				"speaker": "旁白",
				"portrait": "小白",
				"text": "東南方的霧，像有人把世界的邊縫撕開一角。",
			},
			{
				"bg": "mist_village",
				"speaker": "旁白",
				"portrait": "霧隱",
				"text": "村口沒有門——只有霧。真假同色，腳下也是。",
			},
			{
				"bg": "mist_village",
				"speaker": "霧隱",
				"text": "……兔子。你的眼睛，借我用用。",
			},
		], func():
			_play_dialog([
				{"speaker": "霧隱", "text": "霧裡真假同色。你的眼睛，借我用用。"},
				{"speaker": "霧隱", "text": "先住一晚。走夜路的人，會先斷在自己心裡。"},
				{"speaker": "系統", "text": "客棧營火處……似乎有東西在等你。"},
			], _go_c2_mist)
		)
	else:
		_go_c2_mist()


func _go_c2_mist() -> void:
	SaveManager.save_game()
	_open_explore("mist_village", Screen.C2_MIST)


func _interact_mist(id: String) -> void:
	match id:
		"fog_hide":
			_side_start_fog_letter()
		"inn":
			_c2_inn_letter()
		"lantern":
			_play_dialog([{"speaker": "旁白", "text": "霧燈只照三步。再遠的路，要靠自己的眼睛。"}])
		"well_fog":
			_play_dialog([{"speaker": "旁白", "text": "井裡不是水——是更濃的霧。有人說掉下去會夢見自己。"}])
		"laundry":
			_play_dialog([{"speaker": "旁白", "text": "衣裳濕著，卻沒有人影。霧會替人晾衣服嗎？"}])
		"cat_shadow":
			_play_dialog([
				{"speaker": "影貓", "text": "……喵？"},
				{"speaker": "內心", "text": "是真貓，還是霧學的叫聲？"},
			])
		"shrine":
			_play_dialog([
				{"speaker": "霧祠", "text": "「真者一瞬。假者千層。」"},
				{"speaker": "內心", "text": "一瞬就夠。我只要那一瞬。"},
			])
		"train":
			if not GameState.has_flag("c2_wheat_letter"):
				_play_dialog([{"speaker": "系統", "text": "心神不寧。先回客棧。"}])
			else:
				_play_dialog([
					{"speaker": "霧隱", "text": "（訓練）影子會騙人。真身會亮一下。記住那一下。"},
					{"speaker": "系統", "text": "提示：戰鬥中本體發白＝看破；Tab 或 1/2/3 切目標。"},
				])
		"fog_gate":
			_c2_try_fog_boss()
		"save_c2":
			_touch_save_stone()
		"back_knight":
			_go_c1_town()
		"path_dojo":
			_go_c3_enter()
		_:
			pass


func _c2_inn_letter() -> void:
	if GameState.has_flag("c2_wheat_letter"):
		_play_dialog([
			{"speaker": "系統", "text": "信還在日誌裡。"},
			{"speaker": "日誌", "text": "「我還在。不是因為預言，是因為你還沒回來。」——麥穗"},
		])
		return
	## N8 延遲的信（必做）
	var open_line := "稈／行囊縫裡……有一張薄紙。字跡被捏過。"
	if GameState.wheat_stalk_broken or GameState.has_wheat_stalk:
		open_line = "麥穗的稈裡捲著一張薄紙。字跡被捏過。"
	else:
		open_line = "霧隱將一封遲到的信放到桌上：「有人託人一站一站轉來。慢了。」"
	_play_dialog([
		{"speaker": "系統", "text": open_line},
		{"speaker": "信", "text": "我還在。"},
		{"speaker": "信", "text": "不是因為預言，"},
		{"speaker": "信", "text": "是因為你還沒回來。"},
		{"speaker": "信", "text": "——麥穗"},
		{"speaker": "內心", "text": "……還在。那我就還能走。"},
		{"speaker": "日誌", "text": "麥穗的字。比預言輕，比劍重。"},
	], func():
		GameState.set_flag("c2_wheat_letter", true)
		SaveManager.save_game()
	)


func _c2_try_fog_boss() -> void:
	if not GameState.has_flag("c2_wheat_letter"):
		_play_dialog([{"speaker": "霧隱", "text": "心裡還欠一封信。先回客棧。"}])
		return
	if GameState.has_flag("boss.white_fog_cleared"):
		_play_dialog([{"speaker": "系統", "text": "幻廊已靜。可回村或繼續旅程。"}])
		return
	_play_dialog([
		{"speaker": "白霧", "text": "嘻嘻～真的假的，你分得清嗎？"},
		{"speaker": "系統", "text": "多目標：Tab 鎖本體。本體發白才能打。打幻影會反噬並寒意減速。"},
	], func(): _start_battle("fog"))


func _go_fog_win() -> void:
	_grant_boss_loot(70, 4, 8)
	_play_dialog([
		{"speaker": "白霧", "text": "看破了呀……真沒意思。"},
		{"speaker": "白霧", "text": "霧散了，路就在你眼前——走吧。"},
		{"speaker": "系統", "text": "戰利：金 70 · 星屑 4 · HP+8。解鎖霧影。山上傳來鐘聲……"},
	], _c2_fog_clear_cut)


func _c2_fog_clear_cut() -> void:
	_play_cutscene([
		{
			"bg": "mist_village",
			"speaker": "旁白",
			"portrait": "霧隱",
			"text": "霧退成薄紗。村影第一次站穩腳跟。",
		},
		{
			"bg": "mist_village",
			"speaker": "內心",
			"text": "麥穗的字還在：我還在。那我就還能走。",
		},
		{
			"bg": "dojo",
			"speaker": "旁白",
			"portrait": "阿茶",
			"text": "遠山鐘響。茶煙升起——武鬥道場在召喚。",
		},
	], _go_c2_cleared_panel)


func _go_c2_cleared_panel() -> void:
	GameState.set_flag("cosmetic.mist_fur", true)
	GameState.set_flag("boss.white_fog_cleared", true)
	SaveManager.save_game()
	AudioManager.play_bgm("mist")
	_panel(
		"C2 完成 · 霧與真",
		"你看破了白霧。\n麥穗的字還在心上：我還在。\n\n遠山鐘響——武鬥道場在召喚。",
		[
			{"text": "前往道場（C3）", "cb": _go_c3_enter},
			{"text": "回霧隱村", "cb": _go_c2_mist},
			{"text": "回騎士堡", "cb": _go_c1_town},
			{"text": "存檔回標題", "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── C3 武鬥道場 ───

func _region_power_ok(need: int) -> bool:
	return GameState.power_score() >= need or GameState.level >= maxi(1, need / 4)


func _try_soft_enter_region(region: String) -> bool:
	## 0.12 自由路線：戰力／等級／任一相關旗 可進；不足則警告可硬闖
	## 回傳 false = 完全不可進
	var power := GameState.power_score()
	match region:
		"mist":
			if GameState.has_flag("boss.leo_cleared") or GameState.has_flag("c1_forged"):
				return true
			_play_dialog([{"speaker": "系統", "text": "霧還太遠。先在騎士堡把劍養起來。"}])
			return false
		"dojo":
			if GameState.has_flag("boss.white_fog_cleared") or GameState.has_flag("boss.leo_cleared") or power >= 26:
				return true
			_play_dialog([{"speaker": "系統", "text": "道場氣壓重。建議戰力 26+（你 %d），或先走霧隱／升等練功。" % power}])
			return false
		"forest":
			if GameState.has_flag("boss.abo_cleared") or GameState.has_flag("boss.leo_cleared") or power >= 30:
				return true
			_play_dialog([{"speaker": "系統", "text": "林風很急。建議戰力 30+（你 %d）。可先道場／獵場練。" % power}])
			return false
		"coast":
			if GameState.has_flag("boss.abo_cleared") or GameState.has_flag("boss.leo_cleared") or power >= 30:
				return true
			_play_dialog([{"speaker": "系統", "text": "岸浪重。建議戰力 30+（你 %d）。" % power}])
			return false
		_:
			return true


func _go_c3_enter() -> void:
	if not _try_soft_enter_region("dojo"):
		return
	if not GameState.has_flag("boss.white_fog_cleared") and not GameState.has_flag("c3_soft_warn"):
		GameState.set_flag("c3_soft_warn", true)
		_play_dialog([
			{"speaker": "系統", "text": "你尚未看破白霧也能上山——阿波不會因此手下留情。戰力 %d。" % GameState.power_score()},
			{"speaker": "系統", "text": "不夠就回城鍛造、觀星、演武場練功、星途獵場。"},
		], func(): _go_c3_enter_body())
		return
	_go_c3_enter_body()


func _go_c3_enter_body() -> void:
	GameState.set_chapter("c3")
	if not GameState.has_flag("c3_entered"):
		GameState.set_flag("c3_entered", true)
		_play_cutscene([
			{
				"bg": "mist_village",
				"speaker": "旁白",
				"text": "山道把霧踩在腳下。鐘聲一層一層，從雲裡落下。",
			},
			{
				"bg": "dojo",
				"speaker": "旁白",
				"portrait": "阿茶",
				"text": "山門。茶煙。木魚聲很慢——像有人在等你喘口氣。",
			},
			{
				"bg": "dojo",
				"speaker": "阿茶",
				"text": "客從霧裡來？宗師在試煉堂……他不先出手，他先問。",
			},
		], func():
			_play_dialog([
				{"speaker": "阿茶", "text": "客從霧裡來？宗師在試煉堂……他不先出手，他先問。"},
				{"speaker": "系統", "text": "道場可走。試煉堂挑戰阿波。"},
			], _go_c3_dojo)
		)
	else:
		_go_c3_dojo()


func _go_c3_dojo() -> void:
	SaveManager.save_game()
	_open_explore("dojo", Screen.C3_DOJO)


func _interact_dojo(id: String) -> void:
	match id:
		"acha":
			_play_dialog(NpcLines.acha())
		"gate_bell":
			_play_dialog([{"speaker": "旁白", "text": "鐘響一聲。山谷把回音還給你：為何而戰？"}])
		"training_dummy":
			if GameState.has_flag("c3_dummy_hit"):
				_play_dialog([{"speaker": "系統", "text": "木人樁上已有新拳印。你的。"}])
			else:
				_play_dialog([
					{"speaker": "系統", "text": "你朝木人樁連打三下。木屑飛起。"},
					{"speaker": "內心", "text": "一下一下……殼會鬆。"},
				], func():
					GameState.set_flag("c3_dummy_hit", true)
					GameState.stardust += 1
					SaveManager.save_game()
				)
		"scroll_wall":
			_play_dialog([
				{"speaker": "拳譜", "text": "「破勢在勤，不在怒。」"},
				{"speaker": "拳譜", "text": "「怒滿則拳散。散則勢破。」"},
			])
		"stone_garden":
			_play_dialog([{"speaker": "旁白", "text": "石子排成拳形。有人每天挪一顆——挪到心靜為止。"}])
		"tea":
			_play_dialog([
				{"speaker": "阿茶", "text": "喝一口吧。苦盡才回甘——像你的路。"},
			], func():
				GameState.hp = mini(GameState.max_hp, GameState.hp + 20)
				SaveManager.save_game()
			)
		"trial_hall":
			_c3_try_abo()
		"save_c3":
			_touch_save_stone()
		"back_mist":
			_go_c2_mist()
		"path_forest":
			_go_c4_enter()
		"path_tower":
			_go_c3_cleared_panel()
		_:
			pass


func _c3_try_abo() -> void:
	if GameState.has_flag("boss.abo_cleared"):
		_play_dialog([{"speaker": "系統", "text": "試煉堂空了。阿波坐在門檻上喝茶。"}])
		return
	_play_dialog([
		{"speaker": "阿波", "text": "小兔子。來打我的架勢。"},
		{"speaker": "阿波", "text": "打不穿的時候，別急——一下一下，把殼撞鬆。"},
		{"speaker": "系統", "text": "灌破防條破架勢；破防中可重創，他也會出重拳——要格擋。"},
	], func(): _start_battle("abo"))


func _go_abo_win() -> void:
	_grant_boss_loot(90, 5, 10)
	var extra := ""
	if GameState.has_flag("c3_abo_perfect"):
		extra = "你的拳裡，有道了——架勢被你連破兩次。"
	else:
		extra = "你的拳裡，開始有道了。"
	_play_dialog([
		{"speaker": "阿波", "text": extra},
		{"speaker": "阿波", "text": "（指尖在你眉心一點）最後的試煉在塔頂——去吧，別回頭。"},
		{"speaker": "阿茶", "text": "（茶香）路上……記得回家的氣味。"},
		{"speaker": "系統", "text": "戰利：金 90 · 星屑 5 · HP+10。解鎖玉魄。向塔之路開啟。"},
	], _c3_abo_clear_cut)


func _c3_abo_clear_cut() -> void:
	_play_cutscene([
		{
			"bg": "dojo",
			"speaker": "旁白",
			"portrait": "阿波",
			"text": "試煉堂的塵落定。拳印在木地板上，像誰寫下的「道」。",
		},
		{
			"bg": "dojo",
			"speaker": "阿茶",
			"text": "茶還熱著。他……終於肯看你一眼了。",
		},
		{
			"bg": "tower",
			"speaker": "旁白",
			"portrait": "小白",
			"text": "西林有風，東岸有石——塔尖仍掛著不肯散的黑焰。",
		},
	], _go_c3_cleared_panel)


func _go_c3_cleared_panel() -> void:
	GameState.set_flag("boss.abo_cleared", true)
	GameState.set_flag("c3_montage_done", true)
	GameState.set_flag("cosmetic.jade_fur", true)
	SaveManager.save_game()
	AudioManager.play_bgm("dojo")
	_panel(
		"C3 完成 · 拳中有道",
		"阿波認可了你。\n鐘聲落盡。\n\n西林有風在等——疾影；東岸有石在吼——石拳。\n亦可直上法師之塔（最短通關）。",
		[
			{"text": "遊俠森林（C4·疾影）", "cb": _go_c4_enter},
			{"text": "維京海岸（C5·石拳）", "cb": _go_c5_enter},
			{"text": "直上塔下營地（C6）", "cb": _go_c6_camp},
			{"text": "回道場走走", "cb": _go_c3_dojo},
			{"text": "存檔回標題", "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── C4 遊俠森林 · 疾影 ───

func _go_c4_enter() -> void:
	if not _try_soft_enter_region("forest"):
		return
	GameState.set_chapter("c4")
	if not GameState.has_flag("c4_entered"):
		GameState.set_flag("c4_entered", true)
		_play_cutscene([
			{
				"bg": "dojo",
				"speaker": "旁白",
				"text": "西林的風比鐘聲更急。葉縫裡有人笑，像在等你追。",
			},
			{
				"bg": "forest",
				"speaker": "旁白",
				"portrait": "風耳",
				"text": "樹影交錯。風箏線斷在半空——線頭還在顫。",
			},
			{
				"bg": "forest",
				"speaker": "風耳",
				"text": "站住。追風的人，最後都會迷路。",
			},
		], func():
			_play_dialog([
				{"speaker": "風耳", "text": "你若要見疾影——先學會等。風停的那一下，才是真的。"},
				{"speaker": "系統", "text": "遊俠森林可走。疾影巢在東。"},
			], _go_c4_forest)
		)
	else:
		_go_c4_forest()


func _go_c4_forest() -> void:
	SaveManager.save_game()
	_open_explore("forest", Screen.C4_FOREST)


func _interact_forest(id: String) -> void:
	match id:
		"wind_ear":
			_play_dialog(NpcLines.wind_ear_idle())
		"treehouse":
			_play_dialog([
				{"speaker": "旁白", "text": "樹屋用藤索連著。風箏線纏在欄杆上，線頭還在顫。"},
				{"speaker": "孩童", "text": "（遠遠）我的風箏……被風帶走了！"},
			])
		"kite_stuck":
			if GameState.has_flag("c4_kite_freed"):
				_play_dialog([{"speaker": "系統", "text": "風箏已還給孩子。線捲得整整齊齊。"}])
			else:
				_play_dialog([
					{"speaker": "旁白", "text": "風箏卡在枝桠。你小心地扯下線。"},
					{"speaker": "孩童", "text": "謝謝你！……風還會回來，但線在就好。"},
					{"speaker": "系統", "text": "獲得星屑 ×2。"},
				], func():
					GameState.stardust += 2
					GameState.set_flag("c4_kite_freed", true)
					SaveManager.save_game()
				)
		"stream":
			_play_dialog([{"speaker": "旁白", "text": "溪水很清。水面映出葉影——沒有紫縫。難得。"}])
		"owl_post":
			_play_dialog([
				{"speaker": "貓頭鷹", "text": "……"},
				{"speaker": "內心", "text": "牠在看風，不是看我。"},
			])
		"arrow_path":
			if GameState.has_flag("c4_arrow_tip"):
				_play_dialog([{"speaker": "系統", "text": "箭道安靜。偶爾仍有風切掠過草尖。"}])
			else:
				_play_dialog([
					{"speaker": "旁白", "text": "箭道地面一道淺痕——風曾割過這裡。"},
					{"speaker": "系統", "text": "戰鬥中會有風切預告。預告後按 J 閃出風道。"},
				], func():
					GameState.set_flag("c4_arrow_tip", true)
					SaveManager.save_game()
				)
		"watch_tower":
			_play_dialog([
				{"speaker": "碑文", "text": "「疾影守風。風守行路之人。」"},
				{"speaker": "碑文", "text": "「若風狂了——等它記得，自己也曾為誰停過。」"},
				{"speaker": "內心", "text": "等……不是弱，是看清楚。"},
			])
		"herb_slope":
			if GameState.has_flag("c4_herb_loot"):
				_play_dialog([{"speaker": "系統", "text": "藥草坡的露水已經收過。"}])
			else:
				_play_dialog([
					{"speaker": "系統", "text": "採到幾把帶風味的藥草。換了些金幣。"},
				], func():
					GameState.add_gold(45)
					GameState.set_flag("c4_herb_loot", true)
					SaveManager.save_game()
				)
		"falcon_nest":
			_c4_try_falcon()
		"save_c4":
			_touch_save_stone()
		"back_dojo":
			_go_c3_dojo()
		"path_coast":
			_go_c5_enter()
		_:
			pass


func _c4_try_falcon() -> void:
	if GameState.has_flag("boss.shadowwind_cleared"):
		_play_dialog([{"speaker": "系統", "text": "巢空了。只剩風，和一撮銀羽。"}])
		return
	_play_dialog([
		{"speaker": "疾影", "text": "……你的眼睛，跟得上我嗎？"},
		{"speaker": "疾影", "text": "追，會迷路。等，才見我。"},
		{"speaker": "系統", "text": "真身停拍才全額傷害；風切預告後按 J。"},
	], func(): _start_battle("falcon"))


func _go_falcon_win() -> void:
	_grant_boss_loot(85, 4, 8)
	_play_dialog([
		{"speaker": "疾影", "text": "你追上了風……有趣的傢伙。"},
		{"speaker": "疾影", "text": "銀羽給你。不是獎賞——是記得：有人肯為你停。"},
		{"speaker": "風耳", "text": "（遠處）……走吧。海岸還在吼。"},
		{"speaker": "系統", "text": "戰利：金 85 · 星屑 4 · HP+8。解鎖疾風。"},
	], _c4_falcon_clear_cut)


func _c4_falcon_clear_cut() -> void:
	_play_cutscene([
		{
			"bg": "forest",
			"speaker": "旁白",
			"portrait": "疾影",
			"text": "銀羽在光裡轉。風第一次，為誰停了半拍。",
		},
		{
			"bg": "coast",
			"speaker": "旁白",
			"portrait": "石拳",
			"text": "東岸有浪在吼——力氣，還要找方向。",
		},
	], _go_c4_cleared_panel)


func _go_c4_cleared_panel() -> void:
	GameState.set_flag("boss.shadowwind_cleared", true)
	GameState.set_flag("cosmetic.gale_fur", true)
	SaveManager.save_game()
	AudioManager.play_bgm("forest")
	_panel(
		"C4 完成 · 風之試煉",
		"你等來了疾影的停拍。\n林旗揚起，銀羽在光裡轉。\n\n東岸石拳仍在吼——或直上塔。",
		[
			{"text": "維京海岸（C5）", "cb": _go_c5_enter},
			{"text": "塔下營地（C6）", "cb": _go_c6_camp},
			{"text": "回森林走走", "cb": _go_c4_forest},
			{"text": "回道場", "cb": _go_c3_dojo},
			{"text": "存檔回標題", "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── C5 維京海岸 · 石拳 ───

func _go_c5_enter() -> void:
	if not _try_soft_enter_region("coast"):
		return
	## 0.12：海岸／森林可與道場並行，不必固定順序
	GameState.set_chapter("c5")
	if not GameState.has_flag("c5_entered"):
		GameState.set_flag("c5_entered", true)
		_play_cutscene([
			{
				"bg": "forest",
				"speaker": "旁白",
				"text": "林盡是鹽。風裡有鐵與浪。",
			},
			{
				"bg": "coast",
				"speaker": "旁白",
				"portrait": "石拳",
				"text": "浪打空岸。碼頭木樁上插著斧，斧柄還在抖。",
			},
			{
				"bg": "coast",
				"speaker": "潮吼",
				"portrait": "潮吼",
				"text": "哦？兔子？來比腕力——不，來聽浪。",
			},
		], func():
			_play_dialog([
				{"speaker": "潮吼", "text": "石拳不是為了砸碎你。它忘了力氣該往哪放。"},
				{"speaker": "系統", "text": "海岸可走。石拳崖在東。"},
			], _go_c5_coast)
		)
	else:
		_go_c5_coast()


func _go_c5_coast() -> void:
	SaveManager.save_game()
	_open_explore("coast", Screen.C5_COAST)


func _interact_coast(id: String) -> void:
	match id:
		"tide_roar":
			_play_dialog(NpcLines.tide_roar_idle())
		"dock":
			_play_dialog([
				{"speaker": "旁白", "text": "碼頭鎮幾乎空了。漁網乾在架上，像沒人敢出海。"},
				{"speaker": "系統", "text": "有人用炭在板上寫：力氣若沒有方向，只是浪打空岸。"},
			])
		"boat_wreck":
			_play_dialog([{"speaker": "旁白", "text": "破船骸裡還有半袋鹽。鹽是乾的——浪沒有把它們帶走，是人先走了。"}])
		"net_rack":
			_play_dialog([{"speaker": "旁白", "text": "漁網結滿鹽晶。像誰把浪編織起來，又忘了收。"}])
		"runestone":
			_play_dialog([
				{"speaker": "符文石", "text": "「力為護，不為炫。」"},
				{"speaker": "內心", "text": "……和潮吼說的一樣。"},
			])
		"forge_c5":
			if GameState.has_flag("c5_forge_tip"):
				_play_dialog([{"speaker": "潮吼", "text": "（回音）斧意在刃上，不在嗓門。"}])
			else:
				_play_dialog([
					{"speaker": "潮吼", "text": "岸邊這爐還熱。釘釘那小子……不，你的刃夠用。"},
					{"speaker": "潮吼", "text": "記住：最後一擊，是為了護，不是為了炫。"},
					{"speaker": "系統", "text": "潮吼塞給你一袋岸礦。金幣＋60。"},
				], func():
					GameState.add_gold(60)
					GameState.set_flag("c5_forge_tip", true)
					SaveManager.save_game()
				)
		"cliff_path":
			_play_dialog([
				{"speaker": "旁白", "text": "峭壁道上落石痕新舊交錯。地面曾亮過安全圈的燒痕。"},
				{"speaker": "系統", "text": "戰鬥中落岩會預告。預告後按 J 進安全區。"},
			])
		"boar_cliff":
			_c5_try_boar()
		"save_c5":
			_touch_save_stone()
		"back_forest":
			if GameState.has_flag("c4_entered") or GameState.has_flag("boss.shadowwind_cleared"):
				_go_c4_forest()
			else:
				_go_c3_dojo()
		"path_tower_c5":
			_go_c5_cleared_panel()
		_:
			pass


func _c5_try_boar() -> void:
	if GameState.has_flag("boss.stonefist_cleared"):
		_play_dialog([{"speaker": "系統", "text": "崖上安靜。只剩浪聲，像鼓掌。"}])
		return
	_play_dialog([
		{"speaker": "石拳", "text": "哦？還站著？那就接下這一拳——"},
		{"speaker": "石拳", "text": "力氣……該砸向誰？我早忘了。"},
		{"speaker": "系統", "text": "衝鋒時按 J 對撞剝岩甲；落岩時按 J 進安全。"},
	], func(): _start_battle("boar"))


func _go_boar_win() -> void:
	_grant_boss_loot(95, 5, 10)
	_play_dialog([
		{"speaker": "石拳", "text": "哈哈哈！站到最後的是你！"},
		{"speaker": "石拳", "text": "……力氣，是用來護岸的。多謝提醒。"},
		{"speaker": "潮吼", "text": "（大笑）好兔子！去塔吧！"},
		{"speaker": "系統", "text": "戰利：金 95 · 星屑 5 · HP+10。解鎖炎心。"},
	], _c5_boar_clear_cut)


func _c5_boar_clear_cut() -> void:
	_play_cutscene([
		{
			"bg": "coast",
			"speaker": "旁白",
			"portrait": "石拳",
			"text": "浪聲如鼓。岩甲碎在沙上，像誰終於放下拳頭。",
		},
		{
			"bg": "tower",
			"speaker": "旁白",
			"portrait": "小白",
			"text": "五柱中四柱已醒。塔門——千年來第一次，為你開了一縫。",
		},
	], _go_c5_cleared_panel)


func _go_c5_cleared_panel() -> void:
	GameState.set_flag("boss.stonefist_cleared", true)
	GameState.set_flag("cosmetic.ember_fur", true)
	SaveManager.save_game()
	AudioManager.play_bgm("coast")
	_panel(
		"C5 完成 · 岸上最後一擊",
		"石拳記起了力氣的方向。\n岸旗燃起，浪聲如鼓。\n\n五柱中四柱已醒——塔門在等。",
		[
			{"text": "前往塔下營地（C6）", "cb": _go_c6_camp},
			{"text": "回海岸走走", "cb": _go_c5_coast},
			{"text": "回森林", "cb": _go_c4_forest},
			{"text": "存檔回標題", "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


func _go_c3_montage() -> void:
	## 保留捷徑：跳過道場直接開塔（開發／重玩用）
	_current = Screen.C3_MONTAGE
	_play_dialog([
		{"speaker": "旁白", "text": "山門。茶煙。一頭熊貓不發一掌，只問：你，為何而戰？"},
		{"speaker": "內心", "text": "因為還有人在等。因為我還沒回去。"},
		{"speaker": "旁白", "text": "鐘響。道，暫記一筆。路，繼續向塔。"},
	], func():
		GameState.set_flag("c3_montage_done", true)
		GameState.set_flag("boss.abo_cleared", true)
		SaveManager.save_game()
		_go_c3_cleared_panel()
	)


# ─── C6 通天黑塔 ───

func _go_c6_camp() -> void:
	if not GameState.has_flag("boss.abo_cleared") and not GameState.has_flag("c3_montage_done"):
		if GameState.has_flag("boss.white_fog_cleared"):
			_play_dialog([{"speaker": "系統", "text": "山鐘未響。先上道場。"}], _go_c3_enter)
			return
		_play_dialog([{"speaker": "系統", "text": "路還未開。先走完眼前的試煉。"}])
		return
	if not GameState.has_flag("c3_montage_done"):
		GameState.set_flag("c3_montage_done", true)
	if not GameState.has_flag("c6_camp_cut"):
		GameState.set_flag("c6_camp_cut", true)
		_play_cutscene([
			{
				"bg": "tower",
				"speaker": "旁白",
				"portrait": "小白",
				"text": "塔影把世界壓成一條縫。逃難者的火堆在縫邊抖。",
			},
			{
				"bg": "tower",
				"speaker": "旁白",
				"portrait": "斷頁",
				"text": "有人在抄卷——字跡比手還抖。塔門……開了。千年來第一次。",
			},
			{
				"bg": "tower",
				"speaker": "斷頁",
				"text": "兔子。你比預言輕……也比預言先到。",
			},
		], _show_c6_camp_panel)
	else:
		_show_c6_camp_panel()


func _show_c6_camp_panel() -> void:
	GameState.set_chapter("c6")
	_current = Screen.C6_TOWER
	SaveManager.save_game()
	## 可走塔下營地大地圖
	_open_explore("tower_camp", Screen.C6_TOWER)


func _c6_talk_duanye() -> void:
	var lines: Array = [
		{"speaker": "斷頁", "text": "塔門……開了。千年來第一次。"},
		{"speaker": "斷頁", "text": "你若上去，卷軸只能寫到這裡。其餘——你自己走完。"},
		{"speaker": "斷頁", "text": "預言寫至弱。我信的不是預言。是你走到這裡的腳印。"},
	]
	if GameState.has_flag("c2_wheat_letter"):
		lines.append({"speaker": "斷頁", "text": "……信比卷軸真。記得回家的氣味。"})
	if GameState.has_flag("c1_sprout_done"):
		lines.append({"speaker": "斷頁", "text": "城裡有個孩子在練木劍。世界還肯長出明天。"})
	if GameState.has_flag("side.ding_debt_done"):
		lines.append({"speaker": "斷頁", "text": "鐵匠把舊債錘進爐了。人情也是一種封印。"})
	if GameState.has_flag("side.fog_letter_done"):
		lines.append({"speaker": "斷頁", "text": "真信比假卷軸稀。你送達過一封——我記在頁邊。"})
	if GameState.has_flag("side.ronin_spared"):
		lines.append({"speaker": "斷頁", "text": "營火邊多了一個收刃的人。他不說話，但火更穩。"})
	elif GameState.has_flag("side.ronin_defeated"):
		lines.append({"speaker": "斷頁", "text": "岔路的燒痕淡了。有人用強解決了強——也行。"})
	if GameState.has_flag("boss.shadowwind_cleared") and GameState.has_flag("boss.stonefist_cleared"):
		lines.append({"speaker": "斷頁", "text": "風與石都醒了。塔頂……會記得你。"})
	_play_dialog(lines)


func _c6_floor_shadow() -> void:
	_play_dialog([
		{"speaker": "旁白", "text": "影之廊。牆上有人低語。"},
		{"speaker": "幻聲", "text": "變強就能救所有人。吞下焰，世界會安靜。"},
		{"speaker": "內心", "text": "……不。那不是安靜，是熄滅。"},
		{"speaker": "系統", "text": "你穿過影之廊，未拔劍。"},
	], _c6_floor_blade)


func _c6_floor_blade() -> void:
	var lines: Array = [
		{"speaker": "旁白", "text": "器之廳。壁畫上一柄古劍，紋路與微末之刃相同。"},
		{"speaker": "內心", "text": "紋……一樣。"},
		{"speaker": "日誌", "text": "古刃銘：微末。持之者，再未歸村。"},
	]
	if GameState.has_flag("c1_ding_recognized_sword"):
		lines.append({"speaker": "內心", "text": "釘釘當時停住的兩秒……他認得葬過一次的鐵。"})
	lines.append({"speaker": "系統", "text": "劍微微發熱。名之廳在上方。"})
	_play_dialog(lines, _c6_truth_hall)


func _c6_truth_hall() -> void:
	_play_dialog([
		{"speaker": "旁白", "text": "名之廳。黑焰如靜海。中央一道將散未散的影。"},
		{"speaker": "？？？", "text": "你走到這裡了。和我一樣輕。一樣……不該慕強。"},
		{
			"speaker": "？？？",
			"text": "……你想問什麼？",
			"choices": ["你是誰？", "你是魔王？", "（沉默）"],
			"replies": [
				"名字早就燒光了。他們後來只叫我——魔王。",
				"魔王是他們給的稱號。以前……我也只是個很輕的人。",
				"……沉默也好。言語省一點，心就慢一點死。",
			],
		},
		{"speaker": "？？？", "text": "封印要塌時，我吞下黑焰，用野心當柴，把塔再撐了一千年。"},
		{"speaker": "？？？", "text": "至弱者可以到塔頂。卷上沒寫的是——若至弱也開始慕強，心會先死。"},
		{"speaker": "？？？", "text": "那柄劍……也是我的。或者說，是「我們這種人」的。"},
		{"speaker": "？？？", "text": "鐵匠若沉默，是因為他認得出葬過一次的鐵。"},
		{"speaker": "？？？", "text": "現在輪到你。來吧。證明你有另一條路——或者，像我一樣，把世界扛在錯誤的力氣上。"},
	], func():
		GameState.set_flag("c6_truth_revealed", true)
		SaveManager.save_game()
		_panel(
			"決戰之前",
			"真相已揭開。\n魔王曾是第一位至弱者。\n\n黑焰外殼正在合攏……",
			[
				{"text": "迎戰魔王", "cb": func(): _start_battle("demon")},
			]
		)
	)


func _go_demon_win() -> void:
	_grant_boss_loot(150, 8, 0)
	GameState.hp = GameState.effective_max_hp()
	_play_dialog([
		{"speaker": "魔王", "text": "不可能……被一隻……兔子……"},
		{"speaker": "前任", "text": "……不。是應該的。"},
		{"speaker": "前任", "text": "下次……別走我的路。"},
		{"speaker": "前任", "text": "劍還你。或者——交給下一個跟我們一樣輕的人。"},
		{"speaker": "系統", "text": "戰利：金 150 · 星屑 8。五道星光升起。解鎖：星辰兔。"},
	], _c6_ending_cut)


func _c6_ending_cut() -> void:
	_play_cutscene([
		{
			"bg": "tower",
			"speaker": "旁白",
			"portrait": "魔王",
			"text": "黑焰外殼裂開。裡面不是神——是一個也曾渺小的背影。",
		},
		{
			"bg": "tower",
			"speaker": "旁白",
			"portrait": "小白",
			"text": "五道星光升起。塔尖第一次，像為誰讓路。",
		},
		{
			"bg": "village",
			"speaker": "旁白",
			"portrait": "麥穗",
			"text": "遠方，有人還在等。氣味比預言近。",
		},
	], _go_ending)


func _go_ending() -> void:
	GameState.set_flag("boss.demon_cleared", true)
	GameState.set_flag("cosmetic.star_rabbit", true)
	GameState.set_flag("game_cleared", true)
	GameState.set_flag("postgame.rift_unlocked", true)
	if GameState.ng_plus > 0:
		GameState.set_flag("title.echo_walker", true)
		GameState.set_flag("ng_plus_cleared_%d" % GameState.ng_plus, true)
		if GameState.stain_flame:
			GameState.set_flag("cosmetic.ash_edge", true)
	GameState.set_chapter("cleared")
	var new_titles: Array[String] = TitleCatalog.evaluate_all()
	SaveManager.save_game()
	## 通關蠟燭（有連線才同步；失敗不擋結局）
	if OnlineGate.is_signed_in() and not GameState.has_flag("online.candle_lit"):
		OnlineGate.candle_increment(func(res: Dictionary):
			if bool(res.get("ok", false)) or res.has("total"):
				GameState.set_flag("online.candle_lit", true)
				SaveManager.save_game()
		)
	AudioManager.play_bgm("ending")
	var maisui_line := "「還在啊。」"
	if GameState.wheat_stalk_broken or GameState.has_flag("c0_wheat_saved"):
		maisui_line = "「還在啊。早說了是氣味。」"
	var ding_line := ""
	if GameState.has_flag("c1_ding_recognized_sword"):
		ding_line = "\n釘釘：「鐵還在就好。——別再讓我認第二次葬過的鐵。」"
	var star_line := ""
	if GameState.has_flag("c6_refuse_all"):
		star_line = "\n星讀：「你的拒絕，比任何戰魂都亮。」"
	var ng_line := ""
	if GameState.ng_plus > 0:
		ng_line = "\n\n[b]黑焰迴響 ×%d 通關。[/b] 稱號：迴響行者。" % GameState.ng_plus
		if GameState.stain_flame:
			ng_line += " 沾焰灰邊仍在。"
	var title_pop := ""
	if not new_titles.is_empty():
		title_pop = "\n\n新稱號：%s" % "、".join(new_titles)
	_panel(
		"終章 · 晨光",
		"黑焰潰散的那一刻，法師之塔自塔頂裂開。\n五方聖獸卸下重擔，化作星辰。\n\n而那隻曾經連劍都拔了三次才拔起的兔子，站在晨光裡——\n不是因為變得多強，是因為從未把心餵給焰。\n\n麥穗：%s%s%s%s%s\n\n[b]通關。[/b] 塔外，黑焰裂縫仍在顫。" % [maisui_line, ding_line, star_line, ng_line, title_pop],
		[
			{"text": "黑焰裂縫（通關後）", "cb": _go_postgame_hub},
			{"text": "稱號牆", "cb": _go_title_wall},
			{"text": "黑焰迴響（再走一次）", "cb": _go_ng_plus_menu},
			{"text": "再逛逛（騎士堡）", "cb": _go_c1_town},
			{"text": "回標題", "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── 通關後 · 黑焰裂縫 ───

func _go_postgame_hub() -> void:
	## 通關後中樞：裂縫 + 獵場 + 助戰
	if not GameState.has_flag("game_cleared"):
		_play_dialog([{"speaker": "系統", "text": "裂縫尚未溢出。先走完塔頂的試煉。"}])
		return
	GameState.set_flag("postgame.rift_unlocked", true)
	GameState.set_chapter("cleared")
	RiftSchedule.refresh_day()
	SaveManager.save_game()
	AudioManager.play_bgm("tower")
	var body: String = RiftSchedule.hub_status_text()
	body += "\n\n★＝本週焦點。有獎次數用盡後仍可練習。"
	if PartySystem.has_party():
		var pnames: PackedStringArray = []
		for pc in PartySystem.selected_companions():
			pnames.append(str(pc.get("name", "")))
		body += "\n助戰：" + "、".join(pnames)
	var feat: String = RiftSchedule.featured_mode()
	var buttons: Array = [
		{"text": "本週焦點·%s" % RiftSchedule.featured_name(), "cb": func(): _go_rift_intro(feat)},
	]
	for m in RiftSchedule.MODES:
		if m == feat:
			continue
		var mode_s: String = m
		buttons.append({
			"text": RiftSchedule.button_label(mode_s),
			"cb": func(): _go_rift_intro(mode_s),
		})
	buttons.append_array([
		{"text": "裂縫房（真多人）", "cb": _go_room_panel},
		{"text": "星途助戰（離線）", "cb": _go_party_panel},
		{"text": "星途市集", "cb": _go_market_panel},
		{"text": "星途獵場", "cb": func(): _open_explore("hunting_grounds", Screen.C1_WILD)},
		{"text": "塔下營地", "cb": _go_c6_camp},
		{"text": "騎士堡", "cb": _go_c1_town},
		{"text": "存檔回標題", "cb": func(): SaveManager.save_game(); _go_title()},
	])
	buttons.insert(0, {"text": "黑焰迴響（NG+）", "cb": _go_ng_plus_menu})
	buttons.insert(1, {"text": "稱號牆", "cb": _go_title_wall})
	TitleCatalog.evaluate_all()
	_panel("通關後 · 黑焰裂縫", body, buttons)


func _go_party_panel() -> void:
	var body: String = PartySystem.status_bbcode()
	var buttons: Array = []
	if not PartySystem.is_unlocked():
		buttons.append({"text": "返回", "cb": _go_postgame_hub})
		_panel("星途助戰", body, buttons)
		return
	for c in PartySystem.roster_for_ui():
		var cid := str(c.get("id", ""))
		var mark := "✓ " if bool(c.get("picked", false)) else ""
		var label := "%s%s · 攻+%d 防+%d" % [mark, c.get("name", cid), int(c.get("atk", 0)), int(c.get("def", 0))]
		buttons.append({"text": label, "cb": _party_toggle.bind(cid)})
	if PartySystem.has_party():
		buttons.append({"text": "清空助戰", "cb": _party_clear})
	buttons.append({"text": "返回裂縫", "cb": _go_postgame_hub})
	_panel("星途助戰", body, buttons)


func _party_toggle(cid: String) -> void:
	var r: Dictionary = PartySystem.toggle_companion(cid)
	_show_toast(str(r.get("msg", "")))
	_go_party_panel()


func _party_clear() -> void:
	PartySystem.clear_selected()
	_show_toast("已改為單人出戰。")
	_go_party_panel()


func _go_rift_intro(mode: String) -> void:
	RiftSchedule.refresh_day()
	var rewarded: bool = RiftSchedule.daily_left() > 0
	var attempt_note: String
	if rewarded:
		attempt_note = "消耗 1 次今日有獎（剩餘將為 %d）。" % (RiftSchedule.daily_left() - 1)
		if RiftSchedule.is_featured(mode):
			attempt_note += " 本週焦點：金幣×1.5。"
	else:
		attempt_note = "今日有獎已用盡——此為練習局（金幣大減、無經驗）。"
	var lines := {
		"wrath": [
			{"speaker": "旁白", "text": "裂縫口。焰在無臉的輪廓裡顫。"},
			{"speaker": "系統", "text": "密火圈。漏閃疊灼燒——滿三層會爆。躍出可減層。"},
		],
		"tide": [
			{"speaker": "旁白", "text": "海水氣味的黑焰。刺胞鼓起又癟。"},
			{"speaker": "系統", "text": "限時清三隻刺胞；本體輪流「普攻減半／技傷減半」。"},
		],
		"statue": [
			{"speaker": "旁白", "text": "三尊石像輪流亮起一隻眼。"},
			{"speaker": "系統", "text": "只打發光的那尊。全滅後本體出現。落岩按 J。"},
		],
		"chrono": [
			{"speaker": "旁白", "text": "地上的焰結成倒數的環。"},
			{"speaker": "系統", "text": "炸彈窗按 J 拆除；落岩時進安全區。"},
		],
	}
	var arr: Array = lines.get(mode, [{"speaker": "系統", "text": "裂縫張開。"}]).duplicate()
	arr.append({"speaker": "系統", "text": attempt_note})
	if PartySystem.has_party():
		for pl in PartySystem.intro_lines():
			arr.append(pl)
	_play_dialog(arr, func():
		RiftSchedule.consume_attempt()
		PartySystem.begin_party_battle()
		SaveManager.save_game()
		_start_battle(mode)
	)


func _go_rift_win(mode: String) -> void:
	GameState.hp = GameState.max_hp
	var wins := int(GameState.get_flag("postgame.rift_wins", 0))
	var mult: Dictionary = RiftSchedule.reward_mult(mode)
	var extra := ""
	if bool(mult.get("practice", false)):
		extra = "\n（練習局：獎勵已縮減）"
	elif bool(mult.get("featured", false)):
		extra = "\n（本週焦點加成已套用）"
	if GameState.has_flag("title.rift_walker"):
		extra += "\n（裂縫行者）焰裡也有你的節奏。"
	## grant_win_bonus 已在 battle_view 結算時呼叫；此處只收尾
	PartySystem.end_party_battle()
	_play_dialog([
		{"speaker": "無臉", "text": "…………"},
		{"speaker": "系統", "text": "「%s」暫熄。勝場：%d。%s" % [
			RiftSchedule.mode_name(mode), wins, extra
		]},
	], func():
		RiftSchedule.clear_attempt_flag()
		if RoomSystem.is_in_room():
			_go_room_panel()
		else:
			_go_postgame_hub()
	)
