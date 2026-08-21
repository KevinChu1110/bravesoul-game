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

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

@onready var host: Control = %ScreenHost
@onready var hud: Label = %DebugHud

var _battle_scene: PackedScene = preload("res://scenes/battle/battle.tscn")
var _dialogue_scene: PackedScene = preload("res://scenes/ui/dialogue_box.tscn")
const ExploreViewScn = preload("res://scripts/world/explore_view.gd")
const WorldTravel = preload("res://scripts/world/world_travel.gd")
const WorldContent = preload("res://scripts/world/world_content.gd")
const RegionCatalog = preload("res://scripts/world/region_catalog.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const MapleHudScn = preload("res://scripts/ui/maple_hud.gd")
const MapleHotbarScn = preload("res://scripts/ui/maple_hotbar.gd")
const MapleInventoryScn = preload("res://scripts/ui/maple_inventory.gd")
const CutscenePlayerScn = preload("res://scripts/ui/cutscene_player.gd")
const NpcLines = preload("res://scripts/systems/npc_lines.gd")
const EquipPanelScn = preload("res://scripts/ui/panels/equip_panel.gd")
const SaveSlotsPanelScn = preload("res://scripts/ui/panels/save_slots_panel.gd")
var _dialogue: DialogueBox
var _cutscene: Control  ## CutscenePlayer
var _explore: Control  ## ExploreView
## 戰鬥結束後探索場景重建時補播的姿態
var _pending_explore_pose: String = ""
var _pending_explore_pose_dur: float = 0.45
var _maple_hud: Control  ## MapleHud
var _hotbar: Control  ## MapleHotbar
var _inv_panel: Control  ## MapleInventory
var _equip_ui: RefCounted  ## EquipPanel
var _saves_ui: RefCounted  ## SaveSlotsPanel
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



## 玩家看得到的中文字面值一律包這支。ContentLoc 以「原文」當 key，譯文放在
## data/i18n/content/<locale>/ui.json。
##
## 一定要包在**字面值**上、格式化之前：
##     _t("稱號 %d／%d") % [a, b]      ✓
##     _t("稱號 %d／%d" % [a, b])      ✗  代完了就查不到表
## 所以譯文的 %s／%d 佔位符數量與順序必須跟原文一致，check_content_loc.py 會擋。
func _t(s: String) -> String:
	return ContentLoc.text("ui", s)


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
	_equip_ui = EquipPanelScn.new(self)
	_saves_ui = SaveSlotsPanelScn.new(self)
	_saves_ui.on_loaded = func() -> void:
		_apply_saved_ui_layout()
		_resume_from_chapter()
	_saves_ui.on_close = _go_title
	_ensure_fade()
	_go_title()


## 幫每張過場配一張專屬插畫：<scene_id>_1、<scene_id>_2⋯
##
## 插畫還沒畫的段落會安靜退回原本的地圖底圖，所以可以一段一段補——
## 補到哪裡就好看到哪裡，不用等十四段全畫完才敢上。
## 檔名規則跟 tools/import_cutscene.py stills --name <scene_id> 的輸出一致，
## 所以產完直接丟進 assets/sprites/cutscenes 就會亮起來。
func _cutscene_art(scene_id: String, slides: Array) -> Array:
	for i in slides.size():
		var s: Dictionary = slides[i]
		if not s.has("art"):
			s["art"] = "%s_%d" % [scene_id, i + 1]
	return slides


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
		## 1–8 快捷欄（鍵盤數字列；手把暫不綁以免誤觸格擋／選單）
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
	## 物品欄：I 或手把 Select／Back
	if event.is_action_pressed("inventory") and _current != Screen.TITLE:
		if _dialogue and _dialogue.visible:
			return
		if _cutscene and _cutscene.visible:
			return
		if _paused:
			return
		_toggle_inventory()
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
	## 戰鬥中不顯示探索用的左上狀態板。
	##
	## 它固定在 (10,10)、228x118，而戰鬥畫面自己的玩家血條／戰意條從 x=28、y=16 開始
	## —— 兩塊直接疊在一起，畫面上會有兩條血條。而且那張卡片在戰鬥中能提供的
	## 只有等級／金幣／戰力，打到一半沒有人要看；真正要盯的 HP、戰意、敵人血量、
	## 格擋倒數，戰鬥畫面本來就都有。
	## 快捷欄留著 —— 戰鬥中要用道具（見 InventorySystem.hp_authority）。
	var show_status_card := show_chrome and _current != Screen.BATTLE
	if _inv_panel and _inv_panel.visible:
		show_status_card = true
	if _maple_hud and is_instance_valid(_maple_hud):
		_maple_hud.visible = show_status_card
		if show_status_card and _maple_hud.has_method("refresh"):
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
			extra = _t(" · 可走")
		if _paused:
			extra += _t(" · 暫停")
		hud.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35, 0.95))
		hud.add_theme_font_size_override("font_size", 12)
		hud.text = _t("[F3除錯] HP %d/%d 金%d %s T%d %s%s") % [
			GameState.hp, GameState.max_hp, GameState.gold,
			GameState.weapon_display(), GameState.weapon_tier, GameState.chapter, extra
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
	var week := Loc.t("pause.echo", {"n": GameState.ng_plus}) if GameState.ng_plus > 0 else Loc.t("pause.week1")
	title.text = "%s  ·  %s" % [Loc.t("pause.title"), week]
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
	sub.text = Loc.t("pause.stats", {
		"lv": GameState.level, "pow": GameState.power_score(),
		"hp": GameState.hp, "max": GameState.effective_max_hp(),
		"weapon": GameState.weapon_display(), "gold": GameState.gold, "dust": GameState.stardust,
	})
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", UiStyle.INK_DIM)
	box.add_child(sub)

	var pad_hint := Label.new()
	pad_hint.text = Loc.t("ctrl.gamepad_hint")
	pad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad_hint.add_theme_font_size_override("font_size", 11)
	pad_hint.add_theme_color_override("font_color", UiStyle.INK_DIM)
	box.add_child(pad_hint)

	_pause_btn(box, Loc.t("pause.continue"), func():
		_close_pause()
	, true)
	_pause_btn(box, Loc.t("pause.display"), func():
		_close_pause()
		_go_display_settings()
	)
	_pause_btn(box, Loc.t("pause.inventory"), func():
		_close_pause()
		_toggle_inventory()
	)
	_pause_btn(box, Loc.t("pause.reset_ui"), func():
		UiLayout.reset_all()
		var vp2 := get_viewport().get_visible_rect().size
		if _maple_hud:
			_maple_hud.position = Vector2(8, 8)
		if _hotbar:
			_hotbar.position = Vector2((vp2.x - 430) * 0.5, vp2.y - 68)
		SaveManager.save_game()
		_show_toast(Loc.t("pause.reset_ui_toast"))
		_close_pause()
	)
	var claim_n := QuestSystem.claimable_count()
	var star_n := QuestSystem.starpath_reward_count()
	var star_tag := Loc.t("pause.starpath_star", {"n": star_n}) if star_n > 0 else Loc.t("pause.starpath")
	var daily_tag := Loc.t("pause.daily_star") if QuestSystem.can_claim_daily() else Loc.t("pause.daily")
	var quest_tag := Loc.t("pause.quests_star", {"n": claim_n}) if claim_n > 0 else Loc.t("pause.quests")
	_pause_btn(box, Loc.t("pause.save"), func():
		SaveManager.save_game()
		sub.text = Loc.t("pause.saved", {
			"hp": GameState.hp, "max": GameState.max_hp, "weapon": GameState.weapon_display(),
		})
		AudioManager.play_ui()
	)
	_pause_btn(box, Loc.t("pause.journey"), func():
		sub.text = _journey_summary()
		sub.custom_minimum_size = Vector2(300, 140)
		AudioManager.play_ui()
	)
	## 今日村莊：日課總入口（簽到／委託／競技場／獵場）
	_pause_btn(box, star_tag, func():
		_close_pause()
		_go_starpath_panel()
	)
	var codex_n := 0
	if StoryCodex:
		StoryCodex.try_unlock_all()
		codex_n = StoryCodex.unlocked_count()
	_pause_btn(box, Loc.t("pause.codex", {"n": codex_n, "max": StoryCodex.total_count() if StoryCodex else 0}), func():
		_close_pause()
		_go_story_codex_panel()
	)
	_pause_btn(box, daily_tag, func():
		_close_pause()
		_go_daily_panel()
	)
	_pause_btn(box, quest_tag, func():
		_close_pause()
		_go_quest_panel()
	)
	_pause_btn(box, Loc.t("pause.guild"), func():
		_close_pause()
		_go_guild_panel()
	)
	_pause_btn(box, Loc.t("pause.online"), func():
		_close_pause()
		_go_online_panel()
	)
	_pause_btn(box, Loc.t("pause.path", {"path": GameState.path_display()}), func():
		_close_pause()
		_go_path_panel(false)
	)
	_pause_btn(box, Loc.t("pause.materials"), func():
		_close_pause()
		_go_material_shop()
	)
	_pause_btn(box, Loc.t("pause.skills"), func():
		_close_pause()
		_go_skill_panel()
	)
	_pause_btn(box, Loc.t("pause.equip"), func():
		_close_pause()
		_go_equip_panel()
	)
	_pause_btn(box, Loc.t("pause.log"), func():
		_close_pause()
		_go_game_log_panel()
	)
	if HuntSystem.is_unlocked():
		_pause_btn(box, Loc.t("pause.hunt"), func():
			_close_pause()
			_open_explore("hunting_grounds", Screen.C1_WILD)
		)
	if ArenaSystem.is_unlocked():
		_pause_btn(box, Loc.t("pause.arena"), func():
			_close_pause()
			_go_arena_panel()
		)
	_pause_btn(box, Loc.t("pause.soul"), func():
		_close_pause()
		_go_soul_panel()
	)
	_pause_btn(box, Loc.t("pause.gems"), func():
		_close_pause()
		_go_gem_panel()
	)
	_pause_btn(box, Loc.t("pause.regions"), func():
		_close_pause()
		_go_region_panel()
	)
	_pause_btn(box, Loc.t("pause.visit"), func():
		_close_pause()
		_go_visit_panel()
	)
	_pause_btn(box, Loc.t("pause.titles"), func():
		_show_pause_titles(box, sub)
	)
	_pause_btn(box, Loc.t("pause.export"), func():
		var path := SaveManager.export_backup()
		sub.text = Loc.t("pause.export_ok", {"path": path}) if path != "" else Loc.t("pause.export_fail")
		AudioManager.play_ui()
	)
	## 匯入會直接覆蓋當前存檔，所以要按兩次。
	## 旁邊的「旅途紀錄」刪除格子就是兩段式（save_slots_panel），
	## 同一份資料在這裡卻能一鍵蓋掉，兩處標準不一致。
	## 而且這顆就緊貼著「匯出備份」，手滑的代價是整趟進度。
	var import_armed := [false]
	_pause_btn(box, Loc.t("pause.import"), func():
		if not import_armed[0]:
			import_armed[0] = true
			sub.text = _t("匯入會覆蓋目前的進度。要繼續就再按一次。")
			AudioManager.play_ui()
			return
		import_armed[0] = false
		var err := SaveManager.import_backup()
		sub.text = Loc.t("pause.import_ok") if err == OK else Loc.t("pause.import_fail")
		AudioManager.play_ui()
	)
	_pause_btn(box, Loc.t("pause.title_return"), func():
		SaveManager.save_game()
		_close_pause()
		_go_title()
	)


func _message_place_for_current() -> String:
	var mid := _last_explore_map
	if mid.begins_with("tower"):
		return "tower_camp"
	if mid.begins_with("town") or mid == "barracks_yard":
		return "town_gate"
	if mid.begins_with("village"):
		return "village_well"
	if mid.begins_with("mist"):
		return "mist_gate"
	if mid.begins_with("road"):
		return "road_inn"
	return "crossroads"


func _local_msg_key(place: String) -> String:
	return "lore.msgs.%s" % place


func _local_msgs(place: String) -> Array:
	var raw: Variant = GameState.get_flag(_local_msg_key(place), [])
	if raw is Array:
		return raw
	if typeof(raw) == TYPE_STRING and str(raw) != "":
		var parsed = JSON.parse_string(str(raw))
		if parsed is Array:
			return parsed
	return []


func _local_msg_add(place: String, text: String) -> void:
	var arr: Array = _local_msgs(place)
	arr.push_front({"body": text, "local": true})
	while arr.size() > 20:
		arr.pop_back()
	GameState.set_flag(_local_msg_key(place), arr)
	SaveManager.save_game()


func _go_message_stone(from_id: String = "message_stone") -> void:
	var place := _message_place_for_current()
	if from_id == "wall_notice":
		place = "town_gate"
	if from_id == "road_note":
		place = "road_inn"
	## 上線：拉雲端；離線：本地足跡＋舊刻（仍可留字，有 FB 牆感覺）
	if OnlineGate.is_online_enabled() and OnlineGate.is_signed_in():
		OnlineGate.fetch_messages(place, func(res: Dictionary):
			var cloud: Array = res.get("list", [])
			## 雲端為主，本地補在後面（尚未同步的）
			var merged: Array = cloud.duplicate()
			for row in _local_msgs(place):
				merged.append(row)
			_show_messages_panel(place, merged, true)
		)
		return
	var lore_rows: Array = [
		{"body": _t("「足跡會交疊。」——星讀")},
		{"body": _t("「別走我的路。」——佚名")},
		{"body": _t("「微末也有火。」——過客")},
	]
	for row in _local_msgs(place):
		lore_rows.append(row)
	_show_messages_panel(place, lore_rows, false)


func _show_messages_panel(place: String, list: Array, online: bool) -> void:
	var body := _t("[b]留言石[/b]\n星途旅人留下的短句（最多 80 字）\n")
	if online:
		body += _t("（已連線 · 雲端足跡）\n\n")
	else:
		body += _t("（本地足跡 · 上線後可同步雲端）\n\n")
	if list.is_empty():
		body += _t("（尚無留言。做第一個足跡吧。）\n")
	else:
		var n := 0
		for row in list:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var line := str(row.get("body", ""))
			if bool(row.get("local", false)):
				line = _t("〔本地〕") + line
			body += "· %s\n" % line
			n += 1
			if n >= 14:
				break
	var buttons: Array = [
		{"text": _t("留下足跡：還在啊"), "cb": _msg_post.bind(place, _t("還在啊。"), online)},
		{"text": _t("留下足跡：氣味比預言近"), "cb": _msg_post.bind(place, _t("氣味比預言近。"), online)},
		{"text": _t("留下足跡：微末也走到了"), "cb": _msg_post.bind(place, _t("微末也走到了。"), online)},
		{"text": _t("留下足跡：今日村莊"), "cb": _msg_post.bind(place, _t("今日村莊，還亮著。"), online)},
		{"text": Loc.t("btn.refresh"), "cb": func(): _go_message_stone("message_stone")},
	]
	if not online:
		buttons.append({"text": _t("連線設定"), "cb": _go_online_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.message_stone"), body, buttons)


func _msg_post(place: String, text: String, online: bool = true) -> void:
	if online and OnlineGate.is_signed_in():
		OnlineGate.post_message(place, text, func(res: Dictionary):
			var msg := str(res.get("msg", OnlineGate.last_error))
			## 同時寫本地備份
			_local_msg_add(place, text)
			_play_dialog([{"speaker": _t("系統"), "text": msg}], func(): _go_message_stone("message_stone"))
		)
		return
	_local_msg_add(place, text)
	_play_dialog([
		{"speaker": _t("系統"), "text": _t("足跡留在石上了。（本地）上線後可同步給其他旅人。")},
	], func(): _go_message_stone("message_stone"))


func _go_candle_altar(skip_fetch: bool = false) -> void:
	var body := _t("塔下的蠟燭。據說通關的旅人會讓火苗多一寸。\n\n")
	body += "[b]%s[/b]\n" % OnlineGate.candle_line(false)
	if GameState.has_flag("game_cleared"):
		body += _t("\n你已見過晨光。可以點一支。")
	else:
		body += _t("\n你還沒走到塔的盡頭。仍可靜靜看著。")
	if OnlineGate.offline_only or not OnlineGate.is_configured():
		body += _t("\n\n（連線後可同步全服燭火。）")
	var buttons: Array = []
	if GameState.has_flag("game_cleared"):
		buttons.append({"text": _t("點燃（連線同步）"), "cb": _candle_light})
	buttons.append({"text": _t("重新讀取燭火"), "cb": _candle_refresh_panel})
	buttons.append({"text": _t("默默離開"), "cb": _hub_back})
	_panel(Loc.t("panel.candle"), body, buttons)
	## 進場軟拉最新數字，回來後重畫一次（skip 避免迴圈）
	if not skip_fetch and OnlineGate.is_online_enabled():
		OnlineGate.fetch_candle_total(func(res: Dictionary):
			if bool(res.get("ok", false)) and int(res.get("total", -1)) >= 0:
				_go_candle_altar(true)
		)


func _candle_refresh_panel() -> void:
	OnlineGate.fetch_candle_total(func(res: Dictionary):
		if bool(res.get("ok", false)):
			_show_toast(_t("燭火：%d") % int(res.get("total", 0)))
		else:
			_show_toast(str(res.get("msg", _t("讀取失敗"))))
		_go_candle_altar()
	, true)


func _candle_light() -> void:
	if not OnlineGate.is_signed_in():
		_play_dialog(DialogLines.lines("hub.candle_need_online"), _go_candle_altar)
		return
	if GameState.has_flag("online.candle_lit"):
		_play_dialog(DialogLines.lines("hub.candle_already_lit"), _go_candle_altar)
		return
	OnlineGate.candle_increment(func(res: Dictionary):
		if bool(res.get("ok", false)) or res.has("total"):
			GameState.set_flag("online.candle_lit", true)
			SaveManager.save_game()
			var total = res.get("total", "?")
			_play_dialog(DialogLines.lines("hub.candle_lit", {"total": str(total)}), _hub_back)
		else:
			_play_dialog([{"speaker": _t("系統"), "text": str(res.get("msg", _t("點燈失敗")))}], _go_candle_altar)
	)


func _go_hunt_panel() -> void:
	var body: String = HuntSystem.status_bbcode()
	var buttons: Array = []
	if not HuntSystem.is_unlocked():
		buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
		_panel(Loc.t("panel.hunt"), body, buttons)
		return
	if HuntSystem.is_run_active():
		buttons.append({"text": _t("繼續當前波次"), "cb": _hunt_continue})
		buttons.append({"text": _t("放棄狩獵"), "cb": _hunt_abandon})
	else:
		if HuntSystem.daily_left() > 0:
			buttons.append({"text": _t("開始有獎狩獵（剩 %d）") % HuntSystem.daily_left(), "cb": _hunt_start_rewarded})
		buttons.append({"text": _t("練習狩獵（獎勵少）"), "cb": _hunt_start_practice})
	buttons.append({"text": _t("溢物回收"), "cb": _go_hunt_recycle_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.hunt"), body, buttons)


func _hunt_start_rewarded() -> void:
	var er: Dictionary = EnergySystem.try_spend_run("hunt")
	if not bool(er.get("ok", false)):
		_play_dialog([{"speaker": _t("系統"), "text": str(er.get("msg", ""))}], _go_hunt_panel)
		return
	var r: Dictionary = HuntSystem.start_run(false)
	if not bool(r.get("ok", false)):
		EnergySystem.grant(int(er.get("cost", 1)))
		_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_hunt_panel)
		return
	var lines: Array = [
		{"speaker": _t("旁白"), "text": str(r.get("msg", _t("狩獵開始。")))},
		{"speaker": _t("系統"), "text": str(r.get("label", _t("第一波")))},
	]
	_play_dialog(lines, func(): _start_battle(str(r.get("mode", "ash_rat"))))


func _hunt_start_practice() -> void:
	var er: Dictionary = EnergySystem.try_spend_run("hunt")
	if not bool(er.get("ok", false)):
		_play_dialog([{"speaker": _t("系統"), "text": str(er.get("msg", ""))}], _go_hunt_panel)
		return
	var r: Dictionary = HuntSystem.start_run(true)
	if not bool(r.get("ok", false)):
		EnergySystem.grant(int(er.get("cost", 1)))
		_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_hunt_panel)
		return
	var lines: Array = [
		{"speaker": _t("旁白"), "text": str(r.get("msg", _t("練習開始。")))},
		{"speaker": _t("系統"), "text": str(r.get("label", _t("第一波")))},
	]
	_play_dialog(lines, func(): _start_battle(str(r.get("mode", "ash_rat"))))


func _hunt_continue() -> void:
	if not HuntSystem.is_run_active():
		_go_hunt_panel()
		return
	_play_dialog([
		{"speaker": _t("系統"), "text": HuntSystem.wave_label()},
	], func(): _start_battle(HuntSystem.wave_mode()))


func _hunt_abandon() -> void:
	HuntSystem.abandon_run()
	_play_dialog(DialogLines.lines("hub.hunt_abandoned"), _go_hunt_panel)


func _on_hunt_battle_finished(won: bool) -> void:
	if not won:
		var lost: Dictionary = HuntSystem.on_wave_lost()
		_play_dialog([{"speaker": _t("系統"), "text": str(lost.get("msg", _t("敗北。")))}], func():
			_open_explore("hunting_grounds", Screen.C1_WILD)
		)
		return
	var r: Dictionary = HuntSystem.on_wave_won()
	if not bool(r.get("ok", false)):
		_open_explore("hunting_grounds", Screen.C1_WILD)
		return
	if bool(r.get("finished", false)):
		_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", _t("完成。"))) + _hunt_xp_line(r)}], func():
			_open_explore("hunting_grounds", Screen.C1_WILD)
		)
		return
	## 下一波
	var mid := str(r.get("loot_msg", ""))
	var text := str(r.get("msg", _t("下一波"))) + _hunt_xp_line(r)
	if mid != "":
		text += "\n" + mid
	_play_dialog([{"speaker": _t("系統"), "text": text}], func():
		_start_battle(str(r.get("next_mode", "ash_rat")))
	)


func _go_arena_panel() -> void:
	var body: String = ArenaSystem.status_bbcode()
	var buttons: Array = []
	if not ArenaSystem.is_unlocked():
		buttons.append({"text": Loc.t("btn.back"), "cb": _go_starpath_panel})
		_panel(Loc.t("panel.arena"), body, buttons)
		return
	if ArenaSystem.is_run_active():
		buttons.append({"text": _t("繼續試煉"), "cb": _arena_continue})
		buttons.append({"text": _t("放棄本輪"), "cb": _arena_abandon})
	else:
		if ArenaSystem.daily_left() > 0:
			buttons.append({"text": _t("開始有獎試煉（剩 %d）") % ArenaSystem.daily_left(), "cb": _arena_start_rewarded})
		buttons.append({"text": _t("練習試煉"), "cb": _arena_start_practice})
	buttons.append({"text": _t("查看排行"), "cb": _arena_show_leaderboard})
	buttons.append({"text": Loc.t("btn.back"), "cb": _go_starpath_panel})
	_panel(Loc.t("panel.arena"), body, buttons)


func _arena_start_rewarded() -> void:
	var er: Dictionary = EnergySystem.try_spend_run("arena")
	if not bool(er.get("ok", false)):
		_play_dialog([{"speaker": _t("系統"), "text": str(er.get("msg", ""))}], _go_arena_panel)
		return
	var r: Dictionary = ArenaSystem.start_run(false)
	if not bool(r.get("ok", false)):
		EnergySystem.grant(int(er.get("cost", 1)))  ## 開場失敗退能量
		_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_arena_panel)
		return
	_play_dialog([
		{"speaker": _t("系統"), "text": str(r.get("msg", ""))},
		{"speaker": _t("系統"), "text": str(r.get("label", ""))},
	], func(): _start_battle(str(r.get("mode", "ash_rat"))))


func _arena_start_practice() -> void:
	var er: Dictionary = EnergySystem.try_spend_run("arena")
	if not bool(er.get("ok", false)):
		_play_dialog([{"speaker": _t("系統"), "text": str(er.get("msg", ""))}], _go_arena_panel)
		return
	var r: Dictionary = ArenaSystem.start_run(true)
	if not bool(r.get("ok", false)):
		EnergySystem.grant(int(er.get("cost", 1)))
		_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_arena_panel)
		return
	_play_dialog([
		{"speaker": _t("系統"), "text": str(r.get("msg", ""))},
		{"speaker": _t("系統"), "text": str(r.get("label", ""))},
	], func(): _start_battle(str(r.get("mode", "ash_rat"))))


func _arena_continue() -> void:
	if not ArenaSystem.is_run_active():
		_go_arena_panel()
		return
	_play_dialog([
		{"speaker": _t("系統"), "text": ArenaSystem.wave_label()},
	], func(): _start_battle(ArenaSystem.wave_mode()))


func _arena_abandon() -> void:
	ArenaSystem.abandon_run()
	_play_dialog([{"speaker": _t("系統"), "text": _t("已放棄本輪試煉。")}], _go_arena_panel)


func _on_arena_battle_finished(won: bool) -> void:
	if not won:
		var lost: Dictionary = ArenaSystem.on_wave_lost()
		_play_dialog([{"speaker": _t("系統"), "text": str(lost.get("msg", _t("敗北。")))}], _go_arena_panel)
		return
	var r: Dictionary = ArenaSystem.on_wave_won(GameState.hp)
	if not bool(r.get("ok", false)):
		_go_arena_panel()
		return
	if bool(r.get("finished", false)):
		_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", _t("完成。"))) + _hunt_xp_line(r)}], _go_arena_panel)
		return
	var text := str(r.get("msg", _t("下一試"))) + _hunt_xp_line(r)
	_play_dialog([{"speaker": _t("系統"), "text": text}], func():
		_start_battle(str(r.get("next_mode", "ash_rat")))
	)


func _arena_show_leaderboard() -> void:
	var body := _t("[b]角鬥排行[/b]\n個人最佳：%d\n\n") % ArenaSystem.best_score()
	if OnlineGate.is_signed_in():
		body += _t("讀取雲端榜中…\n")
		_panel(Loc.t("panel.arena"), body, [{"text": _t("返回"), "cb": _go_arena_panel}])
		OnlineGate.leaderboard_fetch(ArenaSystem.LEADERBOARD_BOARD, func(res: Dictionary):
			var lines: PackedStringArray = []
			lines.append(_t("[b]角鬥排行 · 前 10[/b]"))
			lines.append(_t("你的最佳：%d\n") % ArenaSystem.best_score())
			var list: Array = res.get("list", []) if bool(res.get("ok", true)) else []
			## OnlineGate _ok 包裝可能不同；相容 raw list
			if list.is_empty() and res.has("data"):
				list = res.get("data", [])
			var i := 0
			for row in list:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				i += 1
				if i > 10:
					break
				lines.append("%d. %s — %d" % [
					i,
					str(row.get("display_name", row.get("user_id", "?"))),
					int(row.get("score", 0)),
				])
			if i == 0:
				lines.append(_t("（尚無紀錄，或連線失敗）"))
			_panel(Loc.t("panel.arena"), "\n".join(lines), [{"text": _t("返回"), "cb": _go_arena_panel}])
		)
	else:
		body += _t("登入連線帳號後可上傳並查看雲端榜。\n（Esc → 連線設定）")
		_panel(Loc.t("panel.arena"), body, [{"text": _t("返回"), "cb": _go_arena_panel}])


## 波次經驗要講出來。不講的話玩家看不出獵場跟野外的差別在哪，
## 只會覺得「打完什麼都沒有」—— 這正是它以前真的什麼都沒給的時候給人的印象。
func _hunt_xp_line(r: Dictionary) -> String:
	var n := int(r.get("xp", 0))
	if n <= 0:
		return ""
	return _t(" · 經驗 %d%s") % [n, _t("（升級！）") if bool(r.get("level_up", false)) else ""]


func _go_hunt_recycle_panel() -> void:
	var body := _t("[b]溢物回收[/b]\n獵人商人只收狩獵材料。\n\n")
	var buttons: Array = []
	for id in ["hunt_hide", "hunt_bone", "hunt_core"]:
		var n: int = InventorySystem.count(id)
		var price: int = HuntSystem.recycle_price(id)
		body += _t("· %s ×%d（回收 %d 金／個）\n") % [InventorySystem.item_name(id), n, price]
		if n > 0:
			buttons.append({"text": _t("賣 %s") % InventorySystem.item_name(id), "cb": _hunt_recycle_one.bind(id)})
	if buttons.is_empty():
		body += _t("\n（袋裡沒有溢皮／焰骨／溢核。）")
	buttons.append({"text": _t("返回獵場"), "cb": _go_hunt_panel})
	buttons.append({"text": Loc.t("btn.close"), "cb": _hub_back})
	_panel(Loc.t("panel.recycle"), body, buttons)


func _hunt_recycle_one(item_id: String) -> void:
	var r: Dictionary = HuntSystem.recycle_one(item_id)
	_show_toast(str(r.get("msg", "")))
	_go_hunt_recycle_panel()



func _go_online_panel() -> void:
	var body: String = OnlineGate.panel_bbcode()
	body += _t("\n\n[b]帳號[/b]：訪客／Email／Google／Discord／Facebook／X")
	body += _t("\n（OAuth 開瀏覽器 → 官網回跳 → 遊戲本機收 token。需在 Supabase 開啟 Provider。）")
	var buttons: Array = []
	if OnlineGate.offline_only:
		buttons.append({"text": _t("關閉純單機（允許連線）"), "cb": _online_enable})
	else:
		buttons.append({"text": _t("開啟純單機（推薦故事模式）"), "cb": _online_force_offline})
	buttons.append({"text": _t("檢測連線健康"), "cb": _online_health_check})
	buttons.append({"text": _t("編輯後端 URL／金鑰…"), "cb": _go_online_backend_form})
	if OnlineGate.is_online_enabled() and not OnlineGate.is_signed_in():
		buttons.append({"text": _t("訪客上線"), "cb": _online_sign_in})
		buttons.append({"text": _t("用 Google 登入"), "cb": _online_oauth.bind("google")})
		buttons.append({"text": _t("用 Discord 登入"), "cb": _online_oauth.bind("discord")})
		buttons.append({"text": _t("用 Facebook 登入"), "cb": _online_oauth.bind("facebook")})
		buttons.append({"text": _t("用 X 登入"), "cb": _online_oauth.bind("twitter")})
		buttons.append({"text": _t("Email 註冊…"), "cb": _go_account_register_panel})
		buttons.append({"text": _t("Email 登入…"), "cb": _go_account_login_panel})
	if OnlineGate.is_signed_in():
		## 雲端只有一份，落地時就寫在目前這一格上。玩家按下去之前要知道會壓到哪。
		body += _t("\n[color=#c96]雲端只留一份紀錄。拉下來會蓋掉目前的第 %d 格；") % SaveManager.current_slot
		body += _t("想留著那一格就先去旅途紀錄換一格再拉。[/color]")
		buttons.append({"text": _t("推送雲存檔（送出第 %d 格）") % SaveManager.current_slot, "cb": _online_push_save})
		buttons.append({"text": _t("拉取雲存檔（蓋掉第 %d 格）") % SaveManager.current_slot, "cb": _online_pull_save})
		buttons.append({"text": _t("上傳殘影（當前域）"), "cb": _online_push_presence})
		buttons.append({"text": _t("登出星途"), "cb": _online_sign_out})
	buttons.append({"text": _t("體驗回報…"), "cb": _go_telemetry_consent})
	buttons.append({"text": _t("顯示名：旅人"), "cb": _online_set_name})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.online"), body, buttons)


func _online_health_check() -> void:
	_show_toast(_t("檢測中…"))
	OnlineGate.health_check(func(res: Dictionary):
		var msg := str(res.get("msg", OnlineGate.last_health))
		if bool(res.get("ok", false)):
			_play_dialog(DialogLines.lines("hub.online_health_ok", {"msg": msg}), _go_online_panel)
		else:
			_play_dialog(DialogLines.lines("hub.online_health_fail", {"msg": OnlineGate.humanize_error(msg)}), _go_online_panel)
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
	title.text = _t("後端設定（Supabase）")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	root.add_child(title)
	var hint := Label.new()
	hint.text = _t("貼上 Project URL 與 publishable／anon key。不會上傳到別人。")
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
	key_le.placeholder_text = _t("sb_publishable_… 或 eyJ… anon key")
	key_le.text = OnlineGate.supabase_anon_key
	key_le.secret = true
	key_le.custom_minimum_size.y = 36
	root.add_child(key_le)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var save_b := Button.new()
	save_b.text = _t("儲存並檢測")
	save_b.custom_minimum_size = Vector2(140, 36)
	row.add_child(save_b)
	var back_b := Button.new()
	back_b.text = _t("返回")
	back_b.custom_minimum_size = Vector2(100, 36)
	row.add_child(back_b)
	save_b.pressed.connect(func():
		OnlineGate.set_backend(url_le.text, key_le.text)
		OnlineGate.set_offline_only(false)
		_show_toast(_t("已儲存，檢測中…"))
		OnlineGate.health_check(func(res: Dictionary):
			var msg := str(res.get("msg", ""))
			_play_dialog([{"speaker": _t("系統"), "text": msg if msg != "" else OnlineGate.last_health}], _go_online_panel)
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
	title.text = _t("註冊星途帳號") if is_register else _t("登入星途帳號")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	root.add_child(title)
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.custom_minimum_size.y = 36
	root.add_child(email)
	var pwd := LineEdit.new()
	pwd.placeholder_text = _t("密碼（至少 6 字）")
	pwd.secret = true
	pwd.custom_minimum_size.y = 36
	root.add_child(pwd)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var ok := Button.new()
	ok.text = _t("註冊") if is_register else _t("登入")
	ok.custom_minimum_size = Vector2(120, 36)
	row.add_child(ok)
	var back := Button.new()
	back.text = _t("返回")
	back.custom_minimum_size = Vector2(100, 36)
	row.add_child(back)
	var submit := func():
		var e := email.text.strip_edges()
		var p := pwd.text
		if is_register:
			OnlineGate.sign_up_email(e, p, func(res: Dictionary):
				GameLog.account(_t("註冊嘗試：%s") % e)
				_online_on_result(res)
			)
		else:
			OnlineGate.sign_in_email(e, p, func(res: Dictionary):
				GameLog.account(_t("登入嘗試：%s") % e)
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
		GameLog.account(_t("訪客上線"))
		_online_on_result(res)
	)


func _online_oauth(provider: String) -> void:
	_show_toast(_t("正在開啟瀏覽器（%s）…") % OnlineGate.oauth_provider_label(provider))
	OnlineGate.sign_in_oauth(provider, func(res: Dictionary):
		if bool(res.get("ok", false)):
			GameLog.account(_t("%s 登入") % OnlineGate.oauth_provider_label(provider))
			_show_toast(_t("登入成功"))
		_online_on_result(res)
	)


## 面板本體在 scripts/ui/panels/{equip,warehouse}_panel.gd。
## （原本這裡還有 _equip_debug_drop()，全專案零呼叫者，搬家時刪除。）

func _go_equip_panel() -> void:
	_equip_ui.open()


## 面板文字全部來自 Telemetry，改文案只改那一支，不要在這裡另寫一份。
func _go_telemetry_consent() -> void:
	var body := Telemetry.consent_prompt_bbcode() + "\n\n" + Telemetry.status_line()
	var buttons: Array = []
	if Telemetry.has_consent():
		buttons.append({"text": _t("不要回報"), "cb": func() -> void:
			Telemetry.set_consent(false)
			_show_toast(_t("已關閉"))
			_go_telemetry_consent()
		})
	else:
		buttons.append({"text": _t("好，幫忙回報"), "cb": func() -> void:
			Telemetry.set_consent(true)
			_show_toast(_t("謝謝"))
			_go_telemetry_consent()
		})
	buttons.append({"text": Loc.t("btn.back"), "cb": _go_online_panel})
	_panel(Loc.t("panel.telemetry"), body, buttons)


func _go_save_slots_panel() -> void:
	_saves_ui.open()


func _go_game_log_panel() -> void:
	var body: String = GameLog.status_bbcode(28)
	_panel(Loc.t("panel.log"), body, [
		{"text": Loc.t("btn.log_combat"), "cb": func(): _go_game_log_cat("combat")},
		{"text": Loc.t("btn.log_economy"), "cb": func(): _go_game_log_cat("economy")},
		{"text": Loc.t("btn.log_equip"), "cb": func(): _go_game_log_cat("equip")},
		{"text": Loc.t("btn.back"), "cb": _hub_back},
	])


## 分類代號 → 玩家看得懂的字。按鈕上寫的是「只看戰鬥」，
## 點進去標題卻變成「日誌 · combat」—— 同一件事兩種說法，而且其中一種是給程式看的。
## const 裡不能呼叫函式，所以譯文查在讀的時候做，不是宣告的時候。
const LOG_CAT_NAMES := {
	"combat": "戰鬥",
	"economy": "經濟",
	"equip": "裝備",
	"system": "系統",
}


func _log_cat_name(cat: String) -> String:
	return _t(str(LOG_CAT_NAMES.get(cat, cat)))


func _go_game_log_cat(cat: String) -> void:
	var cat_name := _log_cat_name(cat)
	var lines: PackedStringArray = [_t("[b]日誌 · %s[/b]\n") % cat_name]
	for e in GameLog.recent(25, cat):
		lines.append("· %s" % str(e.get("msg", "")))
	if lines.size() <= 1:
		lines.append(_t("（無）"))
	_panel(Loc.t("panel.log"), "\n".join(lines), [{"text": Loc.t("btn.all"), "cb": _go_game_log_panel}, {"text": Loc.t("btn.back"), "cb": _hub_back}])


func _online_push_save() -> void:
	OnlineGate.push_cloud_save(_online_on_result)


func _online_pull_save() -> void:
	OnlineGate.pull_cloud_save(_online_on_result)


func _online_push_presence() -> void:
	var mid := _last_explore_map if _last_explore_map != "" else "town"
	OnlineGate.push_presence(mid)
	_show_toast(_t("已嘗試上傳殘影"))
	_go_online_panel()


func _online_sign_out() -> void:
	OnlineGate.sign_out()
	_go_online_panel()


func _online_set_name() -> void:
	OnlineGate.set_display_name(_t("星途旅人"))
	_show_toast(_t("顯示名已設為星途旅人"))
	_go_online_panel()


func _online_on_result(res: Dictionary) -> void:
	var msg := str(res.get("msg", ""))
	if bool(res.get("error", false)) or bool(res.get("ok", true)) == false:
		msg = str(res.get("msg", OnlineGate.last_error))
	if msg == "":
		msg = OnlineGate.status_line()
	_play_dialog([{"speaker": _t("系統"), "text": msg}], _go_online_panel)


func _go_starpath_panel() -> void:
	## 今日村莊儀表板：一天要開遊戲時先看這裡
	QuestSystem.refresh_daily()
	OnlineGate.refresh_candle_soft()
	var body := QuestSystem.starpath_summary_bbcode()
	body += "\n\n[color=#fc9]%s[/color]" % OnlineGate.candle_line(false)
	body += _t("\n戰力 %d · Lv%d") % [GameState.power_score(), GameState.level]
	var buttons: Array = []
	if QuestSystem.can_claim_daily():
		buttons.append({"text": _t("★ 領取今日簽到"), "cb": func():
			var r: Dictionary = QuestSystem.claim_daily()
			_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_starpath_panel)
		})
	for c in QuestSystem.commissions():
		var cid := str(c.get("id", ""))
		if QuestSystem.commission_done(c) and not QuestSystem.commission_claimed(cid):
			var id2 := cid
			buttons.append({"text": _t("★ 領委託：%s") % c.get("name", cid), "cb": func():
				var r2: Dictionary = QuestSystem.claim_commission(id2)
				_play_dialog([{"speaker": _t("系統"), "text": str(r2.get("msg", ""))}], _go_starpath_panel)
			})
	buttons.append({"text": _t("今日委託明細"), "cb": _go_daily_panel})
	if ArenaSystem.is_unlocked():
		var a_left := ArenaSystem.daily_left()
		var a_lab := _t("演武場（剩 %d）") % a_left if a_left > 0 else _t("演武場（練習）")
		buttons.append({"text": a_lab, "cb": _go_arena_panel})
	if HuntSystem.is_unlocked():
		var h_left := HuntSystem.daily_left()
		var h_lab := _t("野外獵場（剩 %d）") % h_left if h_left > 0 else _t("野外獵場（練習）")
		buttons.append({"text": h_lab, "cb": func(): _open_explore("hunting_grounds", Screen.C1_WILD)})
	buttons.append({"text": _t("旅人留言石"), "cb": func(): _go_message_stone("message_stone")})
	buttons.append({"text": _t("通關燭火"), "cb": _go_candle_altar})
	buttons.append({"text": _t("長遠任務"), "cb": _go_quest_panel})
	if _current == Screen.TITLE:
		buttons.append({"text": Loc.t("btn.back"), "cb": _go_title})
	else:
		buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.starpath"), body, buttons)
	## 拉到數字後若面板還在，可再刷一次標題列感覺——此處用 toast 太吵，靜默即可


func _go_daily_panel() -> void:
	QuestSystem.refresh_daily()
	var body := _t("每天登入可領補給。連續簽到獎勵更高。\n")
	body += _t("連續：%d 天 · 戰力 %d · Lv%d\n") % [
		int(GameState.get_flag(QuestSystem.DAILY_STREAK, 0)), GameState.power_score(), GameState.level
	]
	body += _t("%s\n\n") % QuestSystem.streak_milestone_hint()
	if GameState.ng_plus > 0:
		body += _t("二周目加成：每日略豐。\n\n")
	body += QuestSystem.list_commissions_bbcode()
	var buttons: Array = []
	if QuestSystem.can_claim_daily():
		buttons.append({"text": _t("領取今日簽到"), "cb": func():
			var r: Dictionary = QuestSystem.claim_daily()
			_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_daily_panel)
		})
	else:
		buttons.append({"text": _t("簽到已領"), "cb": _go_daily_panel})
	for c in QuestSystem.commissions():
		var cid := str(c.get("id", ""))
		if QuestSystem.commission_done(c) and not QuestSystem.commission_claimed(cid):
			var id2 := cid
			buttons.append({"text": _t("領委託：%s") % c.get("name", cid), "cb": func():
				var r2: Dictionary = QuestSystem.claim_commission(id2)
				_play_dialog([{"speaker": _t("系統"), "text": str(r2.get("msg", ""))}], _go_daily_panel)
			})
	buttons.append({"text": _t("材料行（琥珀）"), "cb": _go_material_shop})
	buttons.append({"text": _t("長遠任務"), "cb": _go_quest_panel})
	buttons.append({"text": _t("今日村莊"), "cb": _go_starpath_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.daily"), body, buttons)


func _go_quest_panel() -> void:
	var body := _t("長遠任務（完成後可領獎）\n\n") + QuestSystem.list_missions_bbcode()
	var buttons: Array = []
	for m in QuestSystem.missions():
		var id := str(m.get("id", ""))
		if QuestSystem.mission_done(m) and not QuestSystem.mission_claimed(id):
			var mid := id
			buttons.append({"text": _t("領獎：%s") % m.get("name", id), "cb": func():
				var r: Dictionary = QuestSystem.claim_mission(mid)
				_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_quest_panel)
			})
	if buttons.is_empty():
		buttons.append({"text": _t("（暫無待領任務）"), "cb": _go_quest_panel})
	buttons.append({"text": _t("每日／委託"), "cb": _go_daily_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.quests"), body, buttons)


func _go_material_shop() -> void:
	## 琥珀材料行：買鍛材／耗材，賣材料
	var body := _t("琥珀的材料行 · 金幣 %d\n\n") % GameState.gold
	body += _t("持有：鐵屑%d 星砂%d 橡脂%d 騎士碎鐵%d 狼牙%d\n\n") % [
		InventorySystem.count("iron_scrap"),
		InventorySystem.count("star_ore"),
		InventorySystem.count("oak_resin"),
		InventorySystem.count("knight_shard"),
		InventorySystem.count("wolf_fang"),
	]
	body += _t("循環：野外掉材料 → 賣金／鍛武器 → 不夠再買 → 再打。")
	var buttons: Array = [
		{"text": _t("買鐵屑（14金）"), "cb": func(): _shop_buy("iron_scrap", 14)},
		{"text": _t("買星砂礦（22金）"), "cb": func(): _shop_buy("star_ore", 22)},
		{"text": _t("買橡脂（18金）"), "cb": func(): _shop_buy("oak_resin", 18)},
		{"text": _t("買騎士碎鐵（28金）"), "cb": func(): _shop_buy("knight_shard", 28)},
		{"text": _t("買小紅水×1（12金）"), "cb": func(): _shop_buy("hp_s", 12)},
		{"text": _t("買乾糧×1（8金）"), "cb": func(): _shop_buy("bread", 8)},
		{"text": _t("一鍵賣出全部材料"), "cb": _shop_sell_all},
		{"text": _t("回每日／委託"), "cb": _go_daily_panel},
		{"text": Loc.t("btn.close"), "cb": _hub_back},
	]
	_panel(Loc.t("panel.shop"), body, buttons)


func _shop_buy(item_id: String, price: int) -> void:
	if GameState.gold < price:
		_play_dialog(DialogLines.lines("shop.not_enough_gold"), _go_material_shop)
		return
	GameState.add_gold(-price)
	InventorySystem.add_item(item_id, 1)
	QuestSystem.track_day("shop", 1)
	SaveManager.save_game()
	_play_dialog(DialogLines.lines("shop.bought", {"item": InventorySystem.item_name(item_id), "price": price}), _go_material_shop)


func _shop_sell_all() -> void:
	var r: Dictionary = InventorySystem.sell_all_materials()
	_play_dialog([
		{"speaker": _t("琥珀") if bool(r.get("ok", false)) else _t("系統"), "text": str(r.get("msg", ""))},
	], _go_material_shop)


func _go_guild_panel() -> void:
	var body := GuildSystem.status_bbcode()
	var buttons: Array = []
	if not GuildSystem.is_joined():
		for g in GuildSystem.guilds():
			var gid := str(g.get("id", ""))
			var gname := str(g.get("name", gid))
			## 加入之後沒有退出的路（GuildSystem 只有 join()），
			## 而面板文案一個字都沒提這是一次性選擇。至少先問一次。
			buttons.append({"text": _t("加入：%s") % gname, "cb": func():
				_play_dialog([
					{
						"speaker": _t("盟約"),
						"text": _t("入了「%s」就不能改投別家了。確定嗎？") % gname,
						"choices": [_t("確定加入"), _t("再想想")],
						"replies": [_t("名字落在盟約上。"), _t("盟約收了回去。")],
					},
				], func():
					if _last_choice != 0:
						_go_guild_panel()
						return
					var r: Dictionary = GuildSystem.join(gid)
					_play_dialog([{"speaker": _t("盟約"), "text": str(r.get("msg", ""))}], _go_guild_panel)
				, "guild_join")
			})
	else:
		buttons.append({"text": _t("下一則佈告"), "cb": func():
			var line := GuildSystem.next_board()
			_play_dialog([{"speaker": _t("佈告欄"), "text": line}], _go_guild_panel)
		})
		if GuildSystem.can_shop():
			buttons.append({"text": _t("公庫補給（貢獻 30）"), "cb": func():
				var r: Dictionary = GuildSystem.buy_supply()
				_play_dialog([{"speaker": _t("公庫"), "text": str(r.get("msg", ""))}], _go_guild_panel)
			})
		else:
			buttons.append({"text": _t("公庫補給（需貢獻 30）"), "cb": _go_guild_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.guild"), body, buttons)


func _hub_back() -> void:
	## 標題／章節／探索：回到合理畫面
	if GameState.chapter == "title" or _current == Screen.TITLE:
		_go_title()
		return
	## 原本一律走 _resume_from_chapter()，那支只認 GameState.chapter，
	## 不認玩家剛剛站在哪張圖 —— 在野外獵場開個裝備面板再返回，
	## 人會出現在城外荒野。所有非章節主線的子地圖（獵場、下城市集、下水道、
	## 各章次場景）都會這樣被傳走。
	## 記得上一張探索圖就送回那裡；只有真的沒有紀錄時才退回章節預設。
	if _last_explore_map != "":
		_open_explore(_last_explore_map, _last_explore_screen)
		return
	_resume_from_chapter()


func _go_story_codex_panel() -> void:
	if StoryCodex == null:
		_show_toast(_t("手札尚未就緒。"))
		return
	var newly: Array = StoryCodex.try_unlock_all()
	if not newly.is_empty():
		var names: PackedStringArray = []
		for id in newly:
			names.append(StoryCodex.display_title(str(id)))
		_show_toast(_t("手札更新：%s") % "、".join(names))
	var body := StoryCodex.panel_list_bbcode()
	var buttons: Array = []
	for id in StoryCodex.unlocked_ids():
		var sid := str(id)
		buttons.append({
			"text": StoryCodex.display_title(sid),
			"cb": func(): _go_story_codex_entry(sid),
		})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.codex"), body, buttons)


func _go_story_codex_entry(id: String) -> void:
	var body := StoryCodex.entry_bbcode(id) if StoryCodex else ""
	_panel(
		StoryCodex.display_title(id) if StoryCodex else id,
		body,
		[{"text": Loc.t("btn.back"), "cb": _go_story_codex_panel}]
	)


func _notify_codex_unlocks() -> void:
	if StoryCodex == null:
		return
	var newly: Array = StoryCodex.try_unlock_all()
	if newly.is_empty():
		return
	var names: PackedStringArray = []
	for id in newly:
		names.append(StoryCodex.display_title(str(id)))
	_show_toast(_t("翠嶺手札：%s") % "、".join(names))


func _journey_summary() -> String:
	var checks := [
		[_t("C0 離村"), "c0_village_left"],
		[_t("C0 首戰"), "c0_first_battle"],
		[_t("C1 鍛造"), "c1_forged"],
		[_t("C1 雷歐"), "boss.leo_cleared"],
		[_t("C1 小芽"), "c1_sprout_done"],
		[_t("C1 舊債"), "side.ding_debt_done"],
		[_t("C2 麥穗信"), "c2_wheat_letter"],
		[_t("C2 家書"), "side.fog_letter_done"],
		[_t("C2 白霧"), "boss.white_fog_cleared"],
		[_t("C3 阿波"), "boss.abo_cleared"],
		[_t("C4 疾影"), "boss.shadowwind_cleared"],
		[_t("C5 石拳"), "boss.stonefist_cleared"],
		[_t("岔路浪人"), "side.ronin_done"],
		[_t("長明燈"), "side.lantern_done"],
		[_t("橋下巢"), "side.nest_care_done"],
		[_t("星池願"), "side.star_wish_done"],
		[_t("霧祠香"), "side.fog_incense_done"],
		[_t("客棧爐"), "side.hearth_lit"],
		[_t("C6 魔王"), "boss.demon_cleared"],
		[_t("通關"), "game_cleared"],
	]
	var done := 0
	var lines: PackedStringArray = []
	for c in checks:
		var ok: bool = GameState.has_flag(str(c[1]))
		if ok:
			done += 1
		lines.append(("%s ✓" if ok else "%s ·") % str(c[0]))
	return _t("進度 %d／%d\n%s\n章節：%s · 金 %d · 星屑 %d") % [
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
	_grant_part_break_loot()
	GuildSystem.add_contrib(20)
	SaveManager.save_game()


## 破部位掉落：僅打贏進袋（原作報酬；變兇部位可能掉雙份）
func _grant_part_break_loot() -> void:
	var BattleSimT := preload("res://scripts/battle/battle_sim.gd")
	var loot: Array = BattleSimT.last_victory_part_loot.duplicate()
	BattleSimT.last_victory_part_loot = []
	if loot.is_empty():
		return
	var counts: Dictionary = {}
	for mid in loot:
		var id := str(mid)
		if id == "":
			continue
		counts[id] = int(counts.get(id, 0)) + 1
	var bits: PackedStringArray = []
	for id in counts.keys():
		var n: int = int(counts[id])
		InventorySystem.add_item(id, n)
		bits.append("%s×%d" % [InventorySystem.item_name(id), n])
	if not bits.is_empty():
		ui_toast(_t("部位殘片：%s") % " · ".join(bits))


## 支線發獎樣板 → SideMilestones.apply（旗／金／星屑／稱號／存檔）。
## 保留 main 薄包裝，讓 test_side_rewards 仍可對主場景呼叫。
func _grant_side_reward(r: Dictionary) -> void:
	var bubble := SideMilestones.apply(r)
	if bubble != "":
		_player_bubble(bubble)


func _touch_save_stone(extra: String = "") -> void:
	## 存檔石：存檔 + 回滿血
	GameState.hp = GameState.effective_max_hp()
	SaveManager.save_game()
	var newly: Array[String] = TitleCatalog.evaluate_all()
	var msg := _t("進度已保存。傷勢也穩了。")
	if extra != "":
		msg += " " + extra
	if not newly.is_empty():
		msg += _t(" 新稱號：%s") % "、".join(newly)
	_play_dialog([{"speaker": _t("系統"), "text": msg}])


func _show_pause_titles(box: VBoxContainer, sub: Label) -> void:
	TitleCatalog.evaluate_all()
	SaveManager.save_game()
	sub.text = _t("稱號 %d／%d · Esc 或「繼續」返回") % [
		TitleCatalog.unlocked_count(), TitleCatalog.total_count()
	]
	## 清空按鈕列下的說明，改顯示稱號摘要
	var names: String = TitleCatalog.unlocked_names_line()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(300, 80)
	sub.text = _t("已解鎖：%s\n（完整牆面請回標題「稱號牆」）") % names
	AudioManager.play_ui()


## primary 要用參數傳，不能靠比對按鈕文字 —— 本來寫的是 text == "繼續"，
## 那在英日韓西任何一個語言都不會成立，主要按鈕的樣式直接消失。
func _pause_btn(parent: VBoxContainer, text: String, cb: Callable, primary := false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(btn, primary)
	btn.pressed.connect(cb)
	parent.add_child(btn)


## 這一段帶選項的對話屬於誰。空字串＝沒有人在等選項。
##
## 為什麼需要：`_on_choice` 是全域的，原本只靠「目前在哪個畫面 + 選了第幾項」認人。
## 演武場練功選單的畫面鍵剛好也是 C1_TOWN、第一項剛好也是 index 0，
## 於是玩家點「開練」會觸發小芽支線的贊助分支 —— 扣 30 金、支線靜默結案，
## 而玩家以為自己只是去練功。兩段不相干的對話共用一個處理器，只能靠上下文分開。
var _choice_ctx: String = ""


func _play_dialog(lines: Array, after: Callable = Callable(), choice_ctx: String = "") -> void:
	_choice_ctx = choice_ctx
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
	## 拜訪獎勵選完後回拜訪面板
	if _choice_ctx == "visit_reward":
		var msg := str(GameState.get_flag("visit.last_result_msg", ""))
		_choice_ctx = ""
		var cb0 := _after_dialogue
		_after_dialogue = Callable()
		if msg != "":
			_play_dialog([{"speaker": _t("系統"), "text": msg}], _go_visit_panel)
		else:
			_go_visit_panel()
		return
	var cb := _after_dialogue
	_after_dialogue = Callable()
	if cb.is_valid():
		cb.call()


## 最近一次選項的 index。after 回呼要靠它分辨玩家選了什麼。
var _last_choice: int = -1


func _on_choice(i: int) -> void:
	_last_choice = i
	if _current == Screen.C0_VILLAGE:
		if i == 0 or i == 2:
			GameState.set_flag("c0_care", true)
		else:
			GameState.set_flag("c0_stubborn", true)
	## 小芽贊助 30 金（只認小芽那一段對話）
	if _choice_ctx == "sprout_sponsor":
		if i == 0 and GameState.gold >= 30 and not GameState.has_flag("item.wood_sword"):
			GameState.gold -= 30
			GameState.stardust += 3
			GameState.set_flag("c1_sprout_done", true)
			TitleCatalog.evaluate_all()
			SaveManager.save_game()
	## 好友挑戰：0=金幣 1=經驗
	if _choice_ctx == "visit_reward":
		var prefer_gold := i == 0
		var vr: Dictionary = VisitSystem.on_challenge_won(prefer_gold)
		## 對話結束後再跳面板（finished 會清 ctx；這裡先把結果存起來）
		GameState.set_flag("visit.last_result_msg", str(vr.get("msg", "")))


func _clear_host() -> void:
	_explore = null
	for c in host.get_children():
		c.queue_free()


# ─── 面板宿主介面 ───
## 給 scripts/ui/panels/* 用的公開契約。拆 main.gd 時，各面板只准碰這幾支，
## 不要直接呼叫底線開頭的私有方法 —— 那是為了讓面板能一塊一塊搬走而不互相黏死。
##
## 導覽一律走 ui_goto(target)，不要一個去處加一支方法。面板只說「我要去哪」，
## main.gd 才是唯一知道「怎麼去」的地方；這樣再搬幾塊面板，這個介面也不會膨脹。

## ui_goto 認得的去處。test_panels.gd 會逐一驗證都還接得到東西。
const UI_GOTO_TARGETS: Array[String] = [
	"hub", "postgame_hub", "online", "hunt_recycle", "equip", "saves",
]


func ui_panel(title: String, body: String, buttons: Array) -> void:
	_panel(title, body, buttons)


func ui_toast(msg: String) -> void:
	_show_toast(msg)


## 回傳是否認得這個去處 —— 讓 test_panels.gd 能逐一驗 UI_GOTO_TARGETS 都還接得到，
## 打錯字或某支入口被改名時會當場紅燈，而不是等玩家點到才發現按鈕沒反應。
func ui_goto(target: String) -> bool:
	match target:
		"hub": _hub_back()
		"postgame_hub": _go_postgame_hub()
		"online": _go_online_panel()
		"hunt_recycle": _go_hunt_recycle_panel()
		"equip": _go_equip_panel()
		"saves": _go_save_slots_panel()
		_:
			push_error(_t("ui_goto: 未知去處 '%s'") % target)
			return false
	return true


## 少數面板要自己畫，才需要直接拿 host。一般面板請用 ui_panel()，不要碰這三支。
func ui_host() -> Control:
	return host


func ui_clear_host() -> void:
	_clear_host()


func ui_reset_fade() -> void:
	_reset_fade()


func ui_refresh_hud() -> void:
	_refresh_hud()


## 戰鬥還在進行中嗎。
##
## 「host 底下有 Battle 節點」不夠 —— 戰鬥結束後那個節點還在，
## 而勝利收尾本來就要開面板（裂縫勝利 → 通關後中樞）。要看的是它打完了沒。
func _battle_is_live() -> bool:
	if host == null:
		return false
	for c in host.get_children():
		if c.has_method("setup") and c.get("sim") != null:
			return not bool(c.get("_ended"))
	return false


func _panel(title: String, body: String, buttons: Array, extras: Dictionary = {}) -> void:
	## 戰鬥進行中不准開面板。
	##
	## _panel() 第一件事就是 _clear_host()，而戰鬥節點就掛在 host 底下 ——
	## 打到一半按 Esc 點「顯示設定」，整場戰鬥當場被釋放，Boss 剩一滴血也一樣，
	## 沒有任何確認。而 _current 還停在 BATTLE，狀態機根本不知道戰鬥不見了。
	## Esc 是標題頁自己教的按鍵，暫停選單看起來就像可以隨便逛。
	##
	## 擋在這裡而不是逐顆按鈕擋：_clear_host() 才是真正吃掉戰鬥的地方，
	## 擋在源頭，之後新增的入口也不必記得再擋一次。
	if _battle_is_live():
		_show_toast(_t("戰鬥中不能開這個。先打完，或按「逃離」。"))
		return
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

	if bool(extras.get("soul_hang", false)):
		var hang := _make_soul_hang()
		if hang:
			root.add_child(hang)

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

	## 按鈕列要能捲動。
	##
	## 原本是直接把 VBox 掛進卡片，按鈕多的時候卡片就長過螢幕；CenterContainer
	## 置中之後上下都被切掉，「返回」被推出畫面外，Esc 只會疊暫停選單，
	## 唯一出路是回標題 —— 玩家的進度沒了。684px 的可用高度只放得下 10 顆。
	##
	## 可用高 = 視窗高 － 卡片其它東西（標題、分隔線、正文、間距、邊距）。
	## 需要多高**不要用猜的**：這裡原本寫死「一顆按鈕 30px」，
	## 而 UiStyle.style_button() 之後會把 custom_minimum_size 蓋成 36 ——
	## 於是每個面板的捲動區都比內容矮，最後一顆（幾乎都是「返回」）被切掉一半。
	## 按鈕多的面板玩家還會想到去捲，只有兩顆按鈕的面板不會，只覺得「返回不見了」。
	## 改成按鈕建好之後直接問 VBox 要多高，不再有第二個數字要維護。
	var btn_gap := 6.0
	## 卡片固定開銷：標題 26 + 分隔線 2 + 三段間距 36 + 上下邊距 18 + 保險 24，
	## 另外留 40 給上下留白 —— 不留的話卡片會頂到螢幕邊，看起來像被切掉。
	var chrome_h := 146.0
	var body_h := 140.0 if body.length() > 280 else minf(140.0, ceilf(float(body.length()) / 26.0) * 20.0)
	var avail_h := maxf(150.0, float(get_viewport_rect().size.y) - chrome_h - body_h)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scroll)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", int(btn_gap))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.add_child(row)

	for i in buttons.size():
		var item: Dictionary = buttons[i]
		var btn := Button.new()
		btn.text = str(item["text"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	## 按鈕都建好了，直接問實際需要多高（含 style_button 蓋上去的高度）
	var need_h := row.get_combined_minimum_size().y
	scroll.custom_minimum_size = Vector2(0, minf(need_h, avail_h))
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
		if OnlineGate.is_signed_in():
			OnlineGate.push_presence(map_id)
		OnlineGate.refresh_candle_soft()
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
		call_deferred("_flush_pending_explore_pose")
		call_deferred("_refresh_hud")
	)


func _flush_pending_explore_pose() -> void:
	if _pending_explore_pose == "":
		return
	var p := _pending_explore_pose
	var d := _pending_explore_pose_dur
	_pending_explore_pose = ""
	if _explore and is_instance_valid(_explore) and _explore.has_method("play_action_pose"):
		_explore.call("play_action_pose", p, d)


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
		_show_toast(str(res.get("msg", _t("無法使用"))))
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
			_show_toast(_t("已綁定快捷鍵 %d：%s") % [i + 1, InventorySystem.item_name(item_id)])
			break
	if not placed:
		InventorySystem.set_hotbar(0, item_id)
		_show_toast(_t("快捷欄已滿，改綁 1：%s") % InventorySystem.item_name(item_id))
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
	if OnlineGate.is_signed_in():
		OnlineGate.push_presence(mid)
	if _explore.has_method("show_player_bubble"):
		_explore.call("show_player_bubble", _t("PROOF · 探索"), 2.5)
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
	## 截圖不要被引導／標題卡擋住
	for k in ["boot", "explore", "battle_auto", "battle_parry", "battle_fog", "forge", "paths", "soul", "fort", "flag_hint", "ng"]:
		TutorialSystem.mark(k)
	GameState.set_flag("tut_done", true)
	_after_dialogue = Callable()
	if _dialogue and is_instance_valid(_dialogue):
		_dialogue.visible = false
		_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameState.hp < 10:
		GameState.hp = GameState.effective_max_hp()
	## 確保戰鬥武器疊層有東西可畫（流派／裝備 → SpriteDB）
	if GameState.path_style == "":
		GameState.set_path_style("sword")
	if str(GameState.equip_slots.get("weapon", "")) == "" and not GameState.has_flag("equip.starter_meager"):
		var inst: Dictionary = EquipmentSystem.roll_instance("meager_edge", "uncommon")
		if not inst.is_empty():
			EquipmentSystem.add_to_bag(inst)
			EquipmentSystem.equip(str(inst.get("uid", "")))
			GameState.set_flag("equip.starter_meager", true)
	if GameState.weapon_name == "" or GameState.weapon_name == "空手":
		GameState.weapon_name = "微末之刃"
		GameState.weapon_atk = maxi(GameState.weapon_atk, 9)
		GameState.weapon_tier = maxi(GameState.weapon_tier, 2)
	## 直接進戰，略過 _start_battle 可能再插的教學
	_start_battle_raw(mode)


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
		## 今日村莊：先讀檔再開儀表板（避免在空白狀態領獎）
		buttons.append({"text": Loc.t("title.starpath"), "cb": _continue_then_starpath})
	## 紀錄面板的門檻比「繼續」低一階：格子裡有壞掉的檔時「繼續」給不出來，
	## 但玩家要進得去才刪得掉那一格。
	if SaveManager.has_any_slot():
		buttons.append({"text": _t("旅途紀錄"), "cb": _go_save_slots_panel})
	if GameState.has_flag("game_cleared") or GameState.ng_plus > 0:
		buttons.append({"text": Loc.t("title.ng"), "cb": _go_ng_plus_menu})
	buttons.append({"text": Loc.t("title.titles"), "cb": _go_title_wall})
	## 簽到／委託本體仍在旅途內（暫停→今日村莊）；標題只提供「讀檔後進儀表板」捷徑。
	var online_lbl := _t("連線設定 · 純單機") if OnlineGate.offline_only else _t("連線設定 · 星途")
	buttons.append({"text": online_lbl, "cb": _go_online_panel})
	buttons.append({"text": _t("顯示設定 · %s") % DisplaySettings.mode_label(), "cb": _go_display_settings})
	## 語言切換：按一次換下一個語言，按鈕上寫「下一個是誰」。
	##
	## 完成度是算出來的，不是寫死的 —— 劇情台詞還沒全譯，
	## 標 100% 會讓玩家切過去以為遊戲壞了。算出來的數字至少不會說謊。
	var nxt_i: int = (Loc.locale_index() + 1) % Loc.LOCALES.size()
	var nxt_code := str(Loc.LOCALES[nxt_i]["code"])
	var nxt_name := str(Loc.LOCALES[nxt_i]["label"])
	var cov := Loc.coverage(nxt_code)
	var lang_label := "%s → %s" % [Loc.locale_label(), nxt_name]
	if cov < 0.995:
		lang_label += "（%d%%）" % int(round(cov * 100.0))
	buttons.append({"text": lang_label, "cb": _toggle_locale})
	var ng_line := ""
	if GameState.ng_plus > 0:
		ng_line = _t("\n[b]二周目 · 黑焰迴響 ×%d[/b]%s") % [
			GameState.ng_plus,
			_t(" · 沾焰") if GameState.stain_flame else "",
		]
	else:
		ng_line = _t("\n一周目旅途")
	var title_line := _t("稱號 %d／%d") % [TitleCatalog.unlocked_count(), TitleCatalog.total_count()]
	var body := "[center][i]%s[/i][/center]\n\n" % Loc.t("title.tagline")
	body += Loc.t("title.blurb") + "\n\n"
	body += _t("[color=#7fd]v0.17 · 今日村莊／演武場／每日輪替[/color]\n")
	body += "[color=#fc9]%s[/color]\n" % OnlineGate.candle_line(false)
	body += "[color=#b8a88a]%s%s[/color]\n\n" % [title_line, ng_line]
	body += "[color=#8a8070]%s[/color]" % Loc.t("title.controls")
	_panel(_t("勇者之魂"), body, buttons)
	_refresh_hud()
	## 軟拉全服燭火（不擋 UI）
	OnlineGate.refresh_candle_soft()
	## 首次啟動引導
	if not TutorialSystem.seen("boot"):
		call_deferred("_boot_tutorial")


func _toggle_locale() -> void:
	Loc.cycle_locale()
	## 台詞是另一套資料，切語言之後要重載 —— 不然畫面語言變了、對白還是舊的
	DialogLines.reload()
	NpcLines.reload()
	AudioManager.play_ui()
	_go_title()


func _go_display_settings() -> void:
	## 顯示：全螢幕／視窗 + 解析度 + 垂直同步
	var body := "[b]%s[/b]\n\n" % Loc.t("display.title")
	body += DisplaySettings.summary_line() + "\n\n"
	body += Loc.t("display.blurb") + "\n"
	## 解析度只有視窗模式吃得到。不講的話，玩家在全螢幕下點了一排解析度、
	## 每個都打勾、每個都跳提示，卻什麼都沒變。
	if not DisplaySettings.res_is_effective():
		body += "[color=#c96]%s[/color]\n" % Loc.t("display.res_needs_window")
	body += Loc.t("ctrl.gamepad_hint") + "\n"
	var buttons: Array = []
	buttons.append({"text": Loc.t("display.mode", {"mode": DisplaySettings.mode_label()}), "cb": _display_cycle_mode})
	buttons.append({"text": Loc.t("display.res_next", {"res": DisplaySettings.res_label()}), "cb": _display_cycle_res})
	buttons.append({"text": Loc.t("display.res_prev"), "cb": _display_cycle_res_back})
	for r in DisplaySettings.RESOLUTIONS:
		var rid := str(r.get("id", ""))
		var mark := " ✓" if rid == DisplaySettings.res_id else ""
		buttons.append({
			"text": "　%s%s" % [str(r.get("label", rid)), mark],
			"cb": _display_pick_res.bind(rid),
		})
	var vs_label := Loc.t("display.vsync_on") if DisplaySettings.vsync else Loc.t("display.vsync_off")
	buttons.append({"text": vs_label, "cb": _display_toggle_vsync})
	buttons.append({"text": Loc.t("display.apply"), "cb": _display_settings_back})
	_panel(Loc.t("display.title"), body, buttons)
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
	body += _t("\n\n已解鎖：%s") % TitleCatalog.unlocked_names_line()
	if not newly.is_empty():
		body = _t("[color=#fc8]新解鎖：%s[/color]\n\n") % "、".join(newly) + body
	var buttons: Array = [
		{"text": _t("返回標題"), "cb": _go_title},
	]
	if GameState.has_flag("game_cleared"):
		buttons.append({"text": _t("黑焰裂縫"), "cb": _go_postgame_hub})
		buttons.append({"text": _t("騎士堡"), "cb": _go_c1_town})
	_panel(Loc.t("panel.titles"), body, buttons)


func _new_game() -> void:
	## 開新旅途一律落在空格：不這麼做會直接蓋掉開機時指向的「上次玩的那一格」
	var empty := SaveManager.first_empty_slot()
	if empty <= 0:
		## 四格都住人了。挑一格默默蓋掉是最糟的做法——玩家按下去之前不知道要付出什麼。
		## 把紀錄攤開讓他自己決定刪哪一格，刪完那一格就會冒出「新的旅途」。
		_show_toast(_t("四格都有紀錄了，先挑一格清掉。"))
		_go_save_slots_panel()
		return
	SaveManager.current_slot = empty
	GameState.reset_new_game()
	SaveManager.save_game()
	_go_c0()


func _go_ng_plus_menu() -> void:
	if not GameState.has_flag("game_cleared") and GameState.ng_plus <= 0:
		_play_dialog(DialogLines.lines("hub.ng_plus_not_yet"), _go_title)
		return
	## 預覽下一層倍率
	var next_lv := maxi(1, GameState.ng_plus + 1)
	var next_m: float = minf(1.30, 1.15 + 0.05 * float(next_lv - 1))
	_panel(
		_t("黑焰迴響"),
		_t("再走一次——敵人的血與攻擊 ×%.2f（第 %d 層）。\n格擋與閃避的時機也會短一點。\n\n帶著走：武器、養成、外觀、裂縫紀錄。\n重來的是：主線的 Boss。\n\n「沾焰」：刃口染上灰邊，攻擊 +3，而且會愈積愈深。") % [next_m, next_lv],
		[
			{"text": _t("再走一次"), "cb": func(): _start_ng_plus(false)},
			{"text": _t("再走一次 · 沾焰"), "cb": func(): _start_ng_plus(true)},
			{"text": _t("返回標題"), "cb": _go_title},
		]
	)


func _start_ng_plus(with_stain: bool) -> void:
	GameState.start_ng_plus_run(with_stain)
	## 二周目：給一點盟約與任務進度感
	GuildSystem.add_contrib(25)
	SaveManager.save_game()
	AudioManager.play_bgm("title")
	var stain_s := _t("刃上多了一層不肯散的灰。") if with_stain else _t("你仍選了乾淨的刃。")
	var tips: Array = TutorialSystem.take("ng")
	var lines: Array = [
		{"speaker": _t("旁白"), "text": _t("黑焰退後，又在腳邊留下一圈淺痕——像邀請。")},
		{"speaker": _t("斷頁"), "text": _t("卷軸可以重抄。脚印，只能再踩一次。")},
		{"speaker": _t("系統"), "text": _t("【二周目】黑焰迴響 ×%d。%s") % [GameState.ng_plus, stain_s]},
		{"speaker": _t("系統"), "text": _t("敵人強了 ×%.2f，出手的空檔也窄了些。養成和外觀都帶著走。") % GameState.ng_enemy_mult()},
		{"speaker": _t("系統"), "text": _t("NPC 會說不一樣的話，佈告也跟著換。畫面上會標著迴響到第幾層。")},
	]
	for t in tips:
		lines.append(t)
	_play_dialog(lines, _go_c0)


func _continue_game() -> void:
	if SaveManager.load_game() != OK:
		## 悶著彈回標題的話，玩家只會覺得按鈕壞了。
		## 導去紀錄面板：哪一格出事、還剩哪幾格，那裡看得到也處理得掉。
		_show_toast(_t("那一格讀不起來，先看看紀錄。"))
		_go_save_slots_panel()
		return
	_apply_saved_ui_layout()
	_resume_from_chapter()


## 標題「今日村莊」：先載入存檔再開儀表板（狀態才是真的）
func _continue_then_starpath() -> void:
	if SaveManager.load_game() != OK:
		_show_toast(_t("那一格讀不起來，先看看紀錄。"))
		_go_save_slots_panel()
		return
	_apply_saved_ui_layout()
	_resume_from_chapter()
	call_deferred("_go_starpath_panel")


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
	## 戰鬥／拔劍類互動：探索也播攻擊姿
	if id in ["wolf", "leo", "fog_boss", "abo", "falcon", "boar", "sword", "black_ronin"] \
			or str(id).begins_with("mb_") or str(id).begins_with("hunt_"):
		_explore_play_pose("attack", 0.42)
	elif id in ["maisui", "ding", "greybeard", "silk", "sprout", "star", "gem_clerk"]:
		_explore_play_pose("telegraph", 0.28)
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
			_play_dialog(NpcLines.for_npc("knight_orphan"))
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
			_play_dialog(DialogLines.lines("side.guard_dog"))
			return true
		## 日常小事支線（地圖互動物件）
		"lantern_post":
			_side_lantern_post()
			return true
		"nest_under":
			_side_nest_care()
			return true
		"wish_pool":
			_side_star_wish()
			return true
		"incense":
			_side_fog_incense()
			return true
		"hearth":
			_side_hearth()
			return true
		## 生活感短台詞（現有地圖物件）
		"road_note":
			_play_dialog(DialogLines.lines("world.road_note"))
			return true
		"grave_b":
			_play_dialog(DialogLines.lines("world.grave_b"))
			return true
		"scare_field":
			_play_dialog(DialogLines.lines("world.scare_field"))
			return true
		"camp_ash":
			_play_dialog(DialogLines.lines("world.camp_ash_road"))
			return true
		_:
			return false


func _side_training_spar(id: String) -> void:
	## 演武場可重複練功：經驗 + 招式熟練
	if id == "training_ring" and not GameState.has_flag("c1_forged"):
		_play_dialog(DialogLines.lines("side.training_need_weapon"))
		return
	var cost := 0
	if int(GameState.get_flag("meta.train_today", 0)) >= 8:
		_play_dialog(DialogLines.lines("side.training_daily_cap"))
		return
	_play_dialog([
		{"speaker": _t("系統"), "text": _t("要練一回合嗎？不用花錢，但一天有次數。")},
		{
			"speaker": _t("系統"),
			"text": _t("戰力 %d · Lv%d · 流派 %s") % [GameState.power_score(), GameState.level, GameState.path_display()],
			"choices": [_t("開練"), _t("離開")],
			"replies": [_t("腳步沉進沙裡。"), _t("改天。")],
		},
	], func():
		## 原本這裡無條件就練 —— 選「離開」照樣扣掉一次每日額度、照樣給經驗。
		## 選項要真的有分別，玩家才有得選。
		if _choice_ctx == "training" and _last_choice == 0:
			_side_training_do()
	, "training")


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
		mat_s = _t(" · 鐵屑×1")
	SaveManager.save_game()
	var msg := _t("練功結束。經驗 +%d") % int(xr.get("gained", base_xp))
	if int(xr.get("levels", 0)) > 0:
		msg += _t(" · 升級至 Lv%d！") % GameState.level
	msg += _t(" · 招式熟練↑ · 今日 %d／8%s") % [int(GameState.get_flag("meta.train_today", 0)), mat_s]
	_play_dialog(DialogLines.lines("side.training_result", {"msg": msg, "power": GameState.power_score()}))


func _side_silk(id: String) -> void:
	if id == "codex_shelf":
		var lines: Array = [
			{"speaker": _t("典籍"), "text": _t("《黑焰三說》抄本：野心為食；至弱至塔；鏡中無我。")},
			{"speaker": _t("典籍"), "text": _t("邊注（絲絨）：官方刪了『前任至弱者曾守護六域』。")},
		]
		if GameState.has_flag("c2_wheat_letter"):
			lines.append({"speaker": _t("內心"), "text": _t("信比卷軸真。絲絨說得對。")})
		if not GameState.has_flag("lore.codex_read"):
			lines.append({"speaker": _t("系統"), "text": _t("讀畢。金幣＋10 · 星屑＋1。")})
			_play_dialog(lines, func(): _grant_side_reward(SideMilestones.reward("codex")))
		else:
			_play_dialog(lines)
		return
	_play_dialog(NpcLines.for_npc("silk"))


func _side_try_pick_broken_blade(id: String) -> bool:
	## 釘釘舊債：演武場武器架撿斷劍
	if not GameState.has_flag("side.ding_debt_asked"):
		if id == "weapon_rack":
			_play_dialog(DialogLines.lines("side.weapon_rack_untasked"))
			return true
		return false
	if GameState.has_flag("side.ding_debt_done") or GameState.has_flag("item.broken_blade"):
		_play_dialog(DialogLines.lines("side.broken_blade_gone"))
		return true
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("沙坑邊的武器架下，一把斷劍露出半截。刃上刻著舊騎士團章。")},
		{"speaker": _t("內心"), "text": _t("釘釘說的……舊主的鐵。")},
		{"speaker": _t("系統"), "text": _t("獲得【舊主斷劍】。拿回給釘釘。")},
	], func(): _grant_side_reward(SideMilestones.reward("broken_blade")))
	return true


func _side_amber() -> void:
	if GameState.has_flag("item.true_letter") and not GameState.has_flag("side.fog_letter_done"):
		_play_dialog(DialogLines.lines("side.amber_has_letter"), _go_material_shop)
		return
	_play_dialog(DialogLines.lines("side.amber_shop_open"), _go_material_shop)


func _side_ronin() -> void:
	if GameState.has_flag("side.ronin_done"):
		if GameState.has_flag("side.ronin_spared"):
			if _current == Screen.C6_TOWER or _last_explore_map == "tower_camp":
				_play_dialog(DialogLines.lines("side.ronin_guard_fire"))
			else:
				_play_dialog(NpcLines.for_npc("ronin"))
		else:
			_play_dialog(DialogLines.lines("side.ronin_gone"))
		return
	## 未完結：分岔
	if not GameState.has_flag("boss.leo_cleared"):
		_play_dialog(DialogLines.lines("side.ronin_too_early"))
		return
	GameState.set_flag("side.ronin_met", true)
	var can_persuade := GameState.has_flag("c2_wheat_letter") \
		or GameState.has_flag("c0_wheat_saved") \
		or GameState.has_flag("c1_sprout_done")
	var choices: Array = [_t("拔劍——解決你"), _t("你走你的，我走我的")]
	var replies: Array = [
		_t("……好。讓我看看你的『強』有多重。"),
		_t("裝蒜？黑焰不吃這套。"),
	]
	if can_persuade:
		choices.append(_t("焰會吃掉你——別再餵它"))
		replies.append(_t("……閉嘴。你沒資格——……你有麥稈味。"))
	_play_dialog([
		{"speaker": _t("黑焰浪人"), "portrait": "road_bandit", "text": _t("站住。你也是來『變強』的？")},
		{"speaker": _t("黑焰浪人"), "text": _t("黑焰教我：心一軟，就被吃乾淨。我不會再軟。")},
		{
			"speaker": _t("黑焰浪人"),
			"text": _t("怎麼，團裡最弱的？要刀還是要滾？"),
			"choices": choices,
			"replies": replies,
		},
	], func():
		## choices 回調在 _play_dialog 後需靠 flag 或二次處理；用延遲選項面板更穩
		_side_ronin_choice_panel(can_persuade)
	)


func _side_ronin_choice_panel(can_persuade: bool) -> void:
	var buttons: Array = [
		{"text": _t("拔劍應戰"), "cb": _side_ronin_fight},
		{"text": _t("轉身離開（稍後再說）"), "cb": _side_ronin_leave},
	]
	if can_persuade:
		buttons.insert(1, {"text": _t("勸他收刃（需：信／稈／小芽）"), "cb": _side_ronin_persuade})
	_panel(_t("黑焰浪人 · 分岔"), _t("岔路風很硬。他擋在東向的影子裡。\n\n【擊敗】或【勸降】都會結束這條支線。"), buttons)


func _side_ronin_leave() -> void:
	_play_dialog([
		{"speaker": _t("黑焰浪人"), "text": _t("逃？也好。下次我不會讓路。")},
	], func():
		_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
	)


func _side_ronin_fight() -> void:
	_play_dialog([
		{"speaker": _t("黑焰浪人"), "text": _t("來。讓焰決定誰該走。")},
	], func(): _start_battle("black_ronin"))


func _side_ronin_persuade() -> void:
	_play_dialog([
		{"speaker": _t("內心"), "text": _t("我把麥穗的字、小芽的木劍、自己的傷——都攤開。")},
		{"speaker": _t("黑焰浪人"), "text": _t("……矯情。")},
		{"speaker": _t("黑焰浪人"), "text": _t("……可焰沒有因此更亮。奇怪。")},
		{"speaker": _t("黑焰浪人"), "text": _t("滾。我自己的路自己斷。你——去塔。")},
		{"speaker": _t("系統"), "text": _t("浪人收了刃。金 40、星屑 3。稱號也往前走了一格。")},
	], func():
		_grant_side_reward(SideMilestones.reward("ronin_persuade"))
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
		var lv_msg := _t(" · 升級！") if int(xr.get("levels", 0)) > 0 else ""
		_play_dialog(DialogLines.lines("side.ronin_defeated", {"xp": int(xr.get("gained", 70)), "level_up": lv_msg}), func():
			_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
		)
	else:
		GameState.hp = maxi(1, int(GameState.max_hp * 0.4))
		SaveManager.save_game()
		_play_dialog([
			{"speaker": _t("黑焰浪人"), "text": _t("回去練。別用『想變強』當藉口——那是我的台詞。")},
		], func():
			_open_explore(_last_explore_map if _last_explore_map != "" else "crossroads", _last_explore_screen)
		)


func _side_deliver_true_letter() -> void:
	_play_dialog([
		{"speaker": _t("行商"), "portrait": "caravan_chief", "text": _t("這印……霧隱？假信我看過一百封。")},
		{"speaker": _t("行商"), "text": _t("……紙邊有火燎。是真的。我們會送到村外那戶。")},
		{"speaker": _t("行商"), "text": _t("謝了。路上少一層假，就少一場刀。")},
		{"speaker": _t("系統"), "text": _t("交付【真信】。金幣＋45 · 星屑＋3。")},
	], func(): _grant_side_reward(SideMilestones.reward("fog_letter_deliver")))


func _side_start_ding_debt() -> void:
	if GameState.has_flag("side.ding_debt_done"):
		_play_dialog(NpcLines.for_npc("ding"), _show_forge_panel)
		return
	if GameState.has_flag("item.broken_blade"):
		_play_dialog([
			{"speaker": _t("釘釘"), "text": _t("……拿來。")},
			{"speaker": _t("系統"), "text": _t("釘釘把斷劍放進爐。第三錘很輕，像在對誰道歉。")},
			{"speaker": _t("釘釘"), "text": _t("舊主的鐵。我當年沒鍛完就跑了。")},
			{"speaker": _t("釘釘"), "text": _t("現在合上了。你——別學我丟下沒做完的東西。")},
			{"speaker": _t("系統"), "text": _t("舊債了結。金幣＋50 · 星屑＋3 · 下次升階成功率提升（暫）。")},
		], func():
			_grant_side_reward(SideMilestones.reward("ding_debt_done"))
			_show_forge_panel()
		)
		return
	if not GameState.has_flag("side.ding_debt_asked"):
		_play_dialog([
			{"speaker": _t("釘釘"), "text": _t("……站住。爐邊有件事。")},
			{"speaker": _t("釘釘"), "text": _t("演武場武器架下，有一把斷劍。舊騎士團的。")},
			{"speaker": _t("釘釘"), "text": _t("我欠那鐵一個收場。你若撿回來——我當你付過一次人情。")},
			{"speaker": _t("系統"), "text": _t("【支線】鐵匠的舊債：去演武場取【舊主斷劍】。")},
		], func():
			_grant_side_reward(SideMilestones.reward("ding_debt_asked"))
			_show_forge_panel()
		)
		return
	_play_dialog(DialogLines.lines("side.ding_debt_remind"), _show_forge_panel)


func _side_lantern_post() -> void:
	## 村後墓園 · 長明燈
	if GameState.has_flag("side.lantern_done"):
		_play_dialog([
			{"speaker": _t("旁白"), "text": _t("長明燈還亮著。火很小，卻夠照見碑上的字。")},
			{"speaker": _t("內心"), "text": _t("誰寫過「誰有火，點一下」——你點了。")},
		])
		return
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("長明燈滅了。燈罩裡還有半截燈芯，像等人點。")},
		{"speaker": _t("內心"), "text": _t("……就一下。")},
		{"speaker": _t("旁白"), "text": _t("你借營火與星屑碎的餘溫，把燈重新點亮。墓園影短了一截。")},
		{"speaker": _t("系統"), "text": _t("【支線】長明一火完成。金 20 · 星屑 1 · 經驗 15 · 鐵屑×1。")},
	], func():
		_grant_side_reward(SideMilestones.reward("lantern"))
	)


func _side_nest_care() -> void:
	## 荒路大橋 · 橋下鳥巢
	if GameState.has_flag("side.nest_care_done"):
		_play_dialog([
			{"speaker": _t("旁白"), "text": _t("鳥巢安靜。幾根新羽，沒有被掏過的痕跡。")},
		])
		return
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("橋下鳥巢軟軟的。裡面沒有蛋，只有碎殼與乾草。")},
		{"speaker": _t("內心"), "text": _t("留言板寫過：別掏蛋。那就……補一點乾糧屑。")},
		{"speaker": _t("旁白"), "text": _t("你撒下少許乾糧碎。巢緣被風掀起，又落回去，像點了頭。")},
		{"speaker": _t("系統"), "text": _t("【支線】橋下軟羽完成。金 15 · 星屑 1 · 經驗 12 · 橡脂×1。")},
	], func():
		_grant_side_reward(SideMilestones.reward("nest_care"))
	)


func _side_star_wish() -> void:
	## 星落平原 · 許願淺池
	if GameState.has_flag("side.star_wish_done"):
		_play_dialog([
			{"speaker": _t("旁白"), "text": _t("淺池仍映星。你的願已經沉在水底，不必再說一遍。")},
		])
		return
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("淺池映著十四星。水面涼，心卻熱了一下。")},
		{"speaker": _t("內心"), "text": _t("願……平安。願麥穗還在。願自己走到塔，還記得路回去。")},
		{"speaker": _t("旁白"), "text": _t("水紋一圈。星沒有回答，但池邊開了一朵夜開花。")},
		{"speaker": _t("系統"), "text": _t("【支線】星池一願完成。金 25 · 星屑 2 · 經驗 20 · 星砂×1。稱號「許願兔」。")},
	], func():
		_grant_side_reward(SideMilestones.reward("star_wish"))
	)


func _side_fog_incense() -> void:
	## 霧祠 · 香爐
	if GameState.has_flag("side.fog_incense_done"):
		_play_dialog([
			{"speaker": _t("旁白"), "text": _t("香灰還熱。白狐像仍閉著眼，願還在散。")},
		])
		return
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("香爐灰結了塊。旁有未燃的細香——霧隱人留下的規矩。")},
		{"speaker": _t("內心"), "text": _t("上香不求強。只求霧只騙敵人。")},
		{"speaker": _t("旁白"), "text": _t("一炷煙直上，在霧裡拐了個彎，像笑了一下。")},
		{"speaker": _t("系統"), "text": _t("【支線】霧祠一炷完成。金 25 · 星屑 2 · 經驗 18 · 騎士碎鐵×1。")},
	], func():
		_grant_side_reward(SideMilestones.reward("fog_incense"))
	)


func _side_hearth() -> void:
	## 路旁客棧 · 壁爐
	if GameState.has_flag("side.hearth_lit"):
		_play_dialog([
			{"speaker": _t("旁白"), "text": _t("壁爐還有餘溫。空椅對空椅，但火在，就不算全空。")},
		])
		return
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("熄滅壁爐積滿灰。爐邊還有半袋乾柴——像有人打算回來卻沒回來。")},
		{"speaker": _t("內心"), "text": _t("替下一個人點著。我也是過路的。")},
		{"speaker": _t("旁白"), "text": _t("火舌爬上柴。大堂影子暖了一圈。「歇腳」兩個字好像沒那麼破了。")},
		{"speaker": _t("系統"), "text": _t("【支線】歇腳餘溫完成。金 18 · 星屑 1 · 經驗 14 · 乾糧×1。")},
	], func():
		_grant_side_reward(SideMilestones.reward("hearth"))
	)


func _side_start_fog_letter() -> void:
	if GameState.has_flag("side.fog_letter_done"):
		_play_dialog(NpcLines.for_npc("fog_hide"))
		return
	if GameState.has_flag("item.true_letter"):
		_play_dialog(NpcLines.for_npc("fog_hide"))
		return
	if not GameState.has_flag("c2_wheat_letter"):
		_play_dialog(NpcLines.for_npc("fog_hide"))
		return
	## 讀完麥穗信後可接
	if not GameState.has_flag("side.fog_letter_asked"):
		_play_dialog([
			{"speaker": _t("霧隱"), "text": _t("假信滿天飛。我這裡有一封真的——要送到村外行商驛站。")},
			{"speaker": _t("霧隱"), "text": _t("假的給霧吃。真的，要人走。")},
			{"speaker": _t("系統"), "text": _t("【支線】霧中家書：將【真信】交給岔路行商驛站的頭領。")},
		], func(): _grant_side_reward(SideMilestones.reward("fog_letter_asked")))
		return
	_play_dialog(NpcLines.for_npc("fog_hide"))


func _flavor_world_object(id: String) -> void:
	var flavors := {
		"big_mill": _t("巨風車的葉片卡死了。風仍過，卻推不動任何東西。"),
		"grain_silo": _t("糧倉空了。灰裡還有半袋焦麥。"),
		"miller_hut": _t("碾坊主不在。桌上茶杯結了薄冰。"),
		"wheat_sea": _t("麥浪在夜裡像黑焰的倒影。"),
		"cave_mouth": _t("洞口呼出冷氣。深處有水滴聲。"),
		"glow_moss": _t("螢光苔微微發綠——像有人故意種在這裡。"),
		"deep_dark": _t("再進去會看不見路。先記在心裡。"),
		"stone_gate": _t("墓園門半開。風從碑間穿過。"),
		"grave_a": _t("無名碑。只有日期，沒有名字。"),
		"fresh_earth": _t("新土。剛埋不久。"),
		## grave_b／scare_field／camp_ash／road_note／長明燈等改走支線或生活台詞 handler
		"bridge_arch": _t("石拱仍穩。谷底黑得像另一個世界。"),
		"toll_ruin": _t("廢稅亭牆上刻著：「先交心，再過橋。」"),
		"inn_sign": _t("破牌寫著「歇腳」。字被刀劃過。"),
		"common_room": _t("大堂空椅對空椅。壁爐冷透。"),
		"column_a": _t("古驛斷柱。柱身有星曜刻紋。"),
		"star_mark": _t("十四星的簡圖。有人用刀補過最後一顆。"),
		"stall_a": _t("布攤只剩支架。風在空棚裡說話。"),
		"beggar": _t("老人抬眼：「騎士堡的旗……換過幾次了。」"),
		"pipe_a": _t("鐵管嗡嗡響。像城在低語。"),
		"slime_pool": _t("黏液池反著微光。別踩進去。"),
		"training_ring": _t("演武台沙上還有舊腳印——很重、很穩。"),
		"lion_statue": _t("石獅缺了一眼。另一眼望向內殿。"),
		"honor_plaque": _t("「榮譽先於性命。」字被黑焰燻糊半行。"),
		"rope_bridge": _t("繩橋晃。裂谷像要吞掉聲音。"),
		"meteor_stone": _t("隕星石觸手微溫。像還記得天空。"),
		"constellation": _t("地刻星圖。你腳下剛好踩在「弱」的位置。"),
		"char_soil": _t("焦裂地燙腳心。黑焰曾在這裡醒來。"),
		"whisper_stone": _t("低語石：……至弱……至塔……"),
		"cliff_rail": _t("霧海在腳下翻。遠方像有六域的輪廓。"),
		"fox_statue": _t("白狐像閉著眼。香灰未冷。"),
		"mirror_a": _t("鏡裡不是你——是你猶豫的那一秒。"),
		"true_path": _t("真影道微微發亮。假出口在偷笑。"),
		"zen_pond": _t("靜心池無波。連風都繞開。"),
		"bamboo_wall": _t("竹牆沙沙。像有人在林後練拳。"),
		"peak_platform": _t("山巔試煉台。雲在腳邊。"),
		"bridge_rope": _t("藤橋在樹冠搖。風耳說：別往下看。"),
		"arch_ruin": _t("古遊俠拱門。石上還有箭痕。"),
		"lake_shore": _t("靜湖倒映樹與天。心一靜，湖也靜。"),
		"longship": _t("長船乾擱。龍骨像巨獸的脊。"),
		"tide_pool": _t("潮池裡有小蟹。與黑焰無關，很好。"),
		"hull": _t("沉船灣的船骸張著口。像要說一個浪的故事。"),
		"mural": _t("封印壁畫：五獸環塔。中央空白——那是你的位置嗎？"),
		"memory_orb_a": _t("記憶球浮出村火。你眨眨眼，它散了。"),
		"memory_orb_b": _t("記憶球：騎士堡的旗第一次升起。"),
		"memory_orb_c": _t("記憶球：聖獸還清明時的眼睛。"),
		"throne_shadow": _t("王座影沒有實體。卻讓人想跪下——你沒有。"),
		"wagon_a": _t("篷車裡有乾糧味與遠方泥土。"),
		"map_table": _t("地圖桌標了六域。塔被畫得最大。"),
		"goods_pile": _t("貨堆用帆布蓋著。行商的規矩：先問價。"),
		"codex_shelf": _t("典籍架上積灰。絲絨的字跡比灰塵新。"),
		"knight_orphan": _t("少年抱著斷木槍。眼睛比槍尖還直。"),
		"armor": _t("空盔甲架。裡面沒有人，卻像還站著班。"),
		"hall": _t("騎士舊廳回音很大。榮譽兩個字被煙燻黃。"),
		"throne_hall": _t("議政廳門半掩。椅子比人多。"),
		"keep_well": _t("內井水深。倒影裡沒有旗。"),
		"statue_knight": _t("無名騎士像缺了半邊臉。另一半仍望著門。"),
		"spice_smell": _t("香料殘跡還在——像有人昨天剛走。"),
		"echo_drip": _t("滴水聲數到七就亂。下水道也不守規矩。"),
		"sealed_door": _t("封死鐵門。牆上有人用指甲刻：別開。"),
		"weapon_rack": _t("武器架空了大半。沙裡可能還埋著舊鐵。"),
		"target_dummy": _t("木靶胸口全是洞。有人練得很兇，然後停了。"),
		"banner_stand": _t("團旗架空著。布去了哪，沒人說。"),
		"officer_desk": _t("隊長桌上壓著未簽名的調防令。日期是三年前。"),
		"sand_pit": _t("沙坑還留著對練的腳印——一大一小。"),
		"mask_shop": _t("面具攤：每一張笑臉背後都是同一張空。"),
		"echo_well": _t("回聲井把你的名字還給你——慢半拍，像在猶豫。"),
		"bell_tower": _t("霧鐘樓沒有鐘舌。風替它敲。"),
		"kite_string": _t("斷線風箏纏在欄上。有人放，有人沒回來收。"),
		"prayer_strip": _t("願條寫：願霧只騙敵人。字被淚暈過。"),
		"secret_panel": _t("暗板後是空的。有人比你早來過。"),
		"star_reader_camp": _t("星讀帳篷空著。星盤炭筆畫到一半。"),
		"night_bloom": _t("夜開花只在沒人看時開。你看了一眼——它仍開著。"),
	}
	if flavors.has(id):
		_play_dialog([{"speaker": _t("旁白"), "text": str(flavors[id])}])
		return
	if _explore and is_instance_valid(_explore) and _explore.has_method("entity_label"):
		var lab: String = str(_explore.call("entity_label", id))
		if lab != "" and not lab.begins_with(_t("往")) and not lab.begins_with(_t("回")) and not lab.begins_with(_t("通")):
			_play_dialog(DialogLines.lines("world.inspect_object", {"label": lab}))


func _handle_world_content(id: String) -> bool:
	## 秘境小 Boss
	var bosses: Dictionary = WorldContent.minibosses()
	if bosses.has(id):
		var b: Dictionary = bosses[id]
		var need := str(b.get("need_flag", ""))
		if need != "" and not GameState.has_flag(need):
			_play_dialog([{"speaker": _t("系統"), "text": str(b.get("deny", _t("還不能挑戰。")))}])
			return true
		if GameState.has_flag(str(b.get("flag", ""))):
			## 三王各有戰後回訪台詞；字面 key 給 DialogLines 黃金樣本用
			match id:
				"scar_boss":
					_play_dialog(DialogLines.lines("world.scar_cleared"))
				"mirror_boss":
					_play_dialog(DialogLines.lines("world.mirror_cleared"))
				"wreck_boss":
					_play_dialog(DialogLines.lines("world.wreck_cleared"))
				_:
					_play_dialog(DialogLines.lines("world.miniboss_cleared"))
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
			_play_dialog(DialogLines.lines("world.chest_empty"))
			return true
		GameState.set_flag(flag, true)
		var g := int(c.get("gold", 0))
		var d := int(c.get("dust", 0))
		_grant_boss_loot(g, d, 0)
		## 寶箱常掉消耗品
		var drop_msg := ""
		if randf() < 0.7:
			InventorySystem.add_item("hp_s", 1)
			drop_msg = _t(" · 小紅水×1")
		elif randf() < 0.5:
			InventorySystem.add_item("bread", 1)
			drop_msg = _t(" · 乾糧×1")
		if randf() < 0.25:
			InventorySystem.add_item("dust_crumb", 1)
			drop_msg += _t(" · 星屑碎×1")
		if Engine.get_main_loop() is SceneTree:
			var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
			if gs and gs.has_method("add_contrib"):
				gs.call("add_contrib", 3)
		SaveManager.save_game()
		_play_dialog(DialogLines.lines("world.chest_open", {
			"found": str(c.get("text", _t("你找到了財物。"))),
			"gold": g,
			"dust": d,
			"drop": drop_msg,
		}))
		_player_bubble(_t("撿到東西了！"))
		return true

	## 雜魚遭遇
	var sk: Dictionary = WorldContent.skirmishes()
	if sk.has(id):
		var s: Dictionary = sk[id]
		var once := str(s.get("once_flag", ""))
		if once != "" and GameState.has_flag(once):
			_play_dialog(DialogLines.lines("world.skirmish_cleared"))
			return true
		var mode2 := str(s.get("mode", "ash_rat"))
		var intro_t := str(s.get("intro", _t("戰鬥！")))
		_play_dialog([{"speaker": _t("旁白"), "text": intro_t}], func():
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
		"message_stone", "wall_notice", "road_note":
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
		"save_hunt":
			_touch_save_stone()
			return true
		"merchant":
			## 霧中家書：先交真信
			if GameState.has_flag("item.true_letter") and not GameState.has_flag("side.fog_letter_done"):
				_side_deliver_true_letter()
				return true
			_play_dialog([
				{"speaker": _t("行商"), "portrait": "caravan_chief", "text": _t("六域的路我都走過。金幣換消息：塔下最近開了門。")},
				{"speaker": _t("行商"), "portrait": "caravan_chief", "text": _t("乾糧 15 金。先付再說。")},
			], func():
				if GameState.gold >= 15:
					GameState.add_gold(-15)
					InventorySystem.add_item("bread", 1)
					_show_toast(_t("買下乾糧×1"))
					if not GameState.has_flag("inv.map_scrap"):
						InventorySystem.add_item("map_scrap", 1)
						GameState.set_flag("inv.map_scrap", true)
					SaveManager.save_game()
					_refresh_hud()
				else:
					_show_toast(_t("金幣不夠……"))
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
		var deny := str(link.get("deny", _t("這條路還不能走。")))
		if deny != "":
			_play_dialog([{"speaker": _t("系統"), "text": deny}])
		return true
	var map_id := str(link.get("map", ""))
	var screen_key := str(link.get("screen", ""))
	if map_id == "":
		return false
	if map_id in ["town_forge", "town_soul", "town_gem", "town_tutor"]:
		if not GameState.has_flag("c1_four_shops_seen"):
			GameState.set_flag("c1_four_shops_seen", true)
	## 進入主城／章節入口時走正式流程（旗標與過場）
	if map_id == "town" and screen_key == "C1_TOWN" and id in ["exit_town_hint", "dawn_glow", "path_knight"]:
		_go_c1_town()
		return true
	_open_explore(map_id, _screen_from_key(screen_key))
	return true


func _go_world_map() -> void:
	var body := _t("[b]翠嶺大陸 · 六域輿圖（0.9 廣域）[/b]\n\n")
	body += _t("　　　　遊俠森林（樹冠／靜湖／遺址）\n")
	body += "　　　　　　｜\n"
	body += _t("維京海岸 ── 法師之塔 ── 騎士堡壘\n")
	body += _t("（港／洞／沉船）　（門廳／階／回憶）　（四店／市集／演武）\n")
	body += "　　　　　　｜\n"
	body += _t("　　　忍者村／霧隱（崖／祠／鏡廊）\n")
	body += "　　　　　　｜\n"
	body += _t("　　　武鬥道場（內院／竹林／山巔）\n\n")
	body += _t("秘境：星落平原 · 行商驛站 · 黑焰疤地 · 北山道 · 東塔荒原\n")
	body += _t("秘境 Boss：疤主 ") + ("✓" if GameState.has_flag("boss.scar_lord_cleared") else "·")
	body += _t(" · 鏡影 ") + ("✓" if GameState.has_flag("boss.mirror_wraith_cleared") else "·")
	body += _t(" · 船長 ") + ("✓" if GameState.has_flag("boss.wreck_captain_cleared") else "·") + "\n"
	body += _t("寶箱 %d／16 · 造訪地圖 %d · 可走分區 %d\n\n") % [
		WorldContent.chest_opened_count(),
		WorldContent.visit_count(),
		WorldTravel.list_map_ids().size(),
	]
	body += _t("戰力 %d · Lv%d · 流派「%s」· 器階 T%d\n") % [
		GameState.power_score(), GameState.level, GameState.path_display(), GameState.weapon_tier
	]
	body += _t("經驗 %d／%d\n\n") % [GameState.xp, GameState.xp_to_next()]
	body += _t("解鎖（0.12 自由路線 · 建議戰力）：\n")
	body += _t("· 騎士堡 ") + ("✓" if GameState.has_flag("c1_entered_city") or GameState.chapter != "c0" else "·") + "\n"
	body += _t("· 岔路／練功 ") + (_t("✓ 鍛造後") if GameState.has_flag("c1_forged") else _t("鎖（先鍛造）")) + "\n"
	body += _t("· 霧隱 ") + ("✓" if GameState.has_flag("c2_entered") else _t("建議 18+")) + "\n"
	body += _t("· 道場 ") + ("✓" if GameState.has_flag("c3_entered") else _t("建議 26+")) + "\n"
	body += _t("· 森林 ") + ("✓" if GameState.has_flag("c4_entered") else _t("建議 30+ · 可選序")) + "\n"
	body += _t("· 海岸 ") + ("✓" if GameState.has_flag("c5_entered") else _t("建議 30+ · 可選序")) + "\n"
	body += _t("· 塔 ") + ("✓" if GameState.has_flag("c6_camp_cut") or GameState.has_flag("boss.abo_cleared") else _t("需足夠試煉")) + "\n"
	var buttons: Array = [
		{"text": _t("騎士堡廣場"), "cb": _go_c1_town},
		{"text": _t("城外荒野"), "cb": _go_c1_wild},
	]
	if GameState.has_flag("c1_forged") or GameState.has_flag("boss.leo_cleared"):
		buttons.append({"text": _t("六域岔路"), "cb": func(): _open_explore("crossroads", Screen.C1_WILD)})
		buttons.append({"text": _t("行商驛站"), "cb": func(): _open_explore("caravan_camp", Screen.C1_WILD)})
		buttons.append({"text": _t("星落平原"), "cb": func(): _open_explore("starfall_plain", Screen.C1_WILD)})
		buttons.append({"text": _t("霧隱村"), "cb": _go_c2_enter})
		buttons.append({"text": _t("武鬥道場"), "cb": _go_c3_enter})
		buttons.append({"text": _t("遊俠森林"), "cb": _go_c4_enter})
		buttons.append({"text": _t("維京海岸"), "cb": _go_c5_enter})
	if GameState.has_flag("boss.abo_cleared") or GameState.power_score() >= 36:
		buttons.append({"text": _t("黑焰疤地"), "cb": func(): _open_explore("blackflame_scar", Screen.C1_WILD)})
	if GameState.has_flag("boss.abo_cleared") or GameState.has_flag("boss.shadowwind_cleared") \
			or GameState.has_flag("boss.stonefist_cleared") or GameState.power_score() >= 42:
		buttons.append({"text": _t("塔下營地"), "cb": _go_c6_camp})
	if HuntSystem.is_unlocked():
		buttons.append({"text": _t("野外獵場"), "cb": func(): _open_explore("hunting_grounds", Screen.C1_WILD)})
	if ArenaSystem.is_unlocked():
		buttons.append({"text": _t("演武場"), "cb": _go_arena_panel})
	buttons.append({"text": _t("武器流派"), "cb": _go_path_panel})
	buttons.append({"text": _t("返回當前"), "cb": _hub_back})
	_panel(Loc.t("panel.world_map"), body, buttons)


func _interact_tower_camp(id: String) -> void:
	match id:
		"duanye":
			_c6_talk_duanye()
		"refugee_fire", "tent_a", "tent_b":
			_play_dialog(DialogLines.lines("c6.refugee"))
		"scroll_pile":
			_play_dialog(DialogLines.lines("c6.scroll_pile"))
		"tower_gate":
			_play_dialog(DialogLines.lines("c6.tower_gate"))
		"climb_tower":
			_c6_floor_shadow()
		_:
			pass


func _go_c0() -> void:
	GameState.set_chapter("c0")
	if not GameState.has_flag("c0_intro_cut"):
		GameState.set_flag("c0_intro_cut", true)
		_notify_codex_unlocks()
		_play_cutscene(_cutscene_art("c0_open", [
			{
				"bg": "village",
				"speaker": _t("旁白"),
				"text": Loc.t("c0.intro1"),
			},
			{
				"bg": "village",
				"speaker": _t("旁白"),
				"portrait": _t("麥穗"),
				"text": Loc.t("c0.intro2"),
			},
			{
				"bg": "village",
				"speaker": _t("麥穗"),
				"text": Loc.t("c0.intro3"),
			},
			{
				"bg": "village",
				"speaker": _t("旁白"),
				"portrait": _t("小白"),
				"text": Loc.t("c0.intro4"),
			},
		]), func():
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
		{"speaker": _t("系統"), "text": Loc.t("tut.welcome")},
		{"speaker": _t("系統"), "text": Loc.t("tut.move")},
		{"speaker": _t("系統"), "text": Loc.t("tut.interact")},
		{"speaker": _t("系統"), "text": Loc.t("tut.leave")},
		{"speaker": _t("系統"), "text": Loc.t("tut.battle")},
		{"speaker": _t("系統"), "text": Loc.t("tut.parry")},
		{"speaker": _t("系統"), "text": Loc.t("tut.done")},
	], func():
		GameState.set_flag("tut_done", true)
		InventorySystem.grant_starter()
		_show_toast(_t("起始補給：小紅水×3 · 乾糧×2（1–8 使用 · I 背包）"))
		SaveManager.save_game()
		_refresh_hud()
		if _explore and is_instance_valid(_explore) and _explore.has_method("show_guide_hint"):
			_explore.call("show_guide_hint", Loc.t("tut.hud_hint"))
	)


func _interact_village(id: String) -> void:
	match id:
		"maisui":
			_play_dialog([
				{"speaker": _t("麥穗"), "text": Loc.t("c0.maisui1")},
				{
					"speaker": _t("麥穗"),
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
				{"speaker": _t("麥穗"), "text": Loc.t("c0.maisui3")},
			])
		"sword":
			if GameState.has_flag("item.rusty_sword"):
				_play_dialog([{"speaker": _t("系統"), "text": Loc.t("c0.sword_have")}])
			else:
				_play_dialog([
					{"speaker": _t("系統"), "text": Loc.t("c0.sword1")},
					{"speaker": _t("系統"), "text": Loc.t("c0.sword2")},
					{"speaker": _t("系統"), "text": Loc.t("c0.sword3")},
					{"speaker": _t("內心"), "text": Loc.t("c0.sword_inner")},
				], _c0_sword_done)
		"fire":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.fire")}])
		"hut_a":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.hut_a")}])
		"hut_b":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.hut_b")}])
		"well":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.well")}])
		"ash_pile":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.ash")}])
		"cart":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.cart")}])
		"sign_east":
			_play_dialog([{"speaker": _t("木牌"), "text": Loc.t("flavor.sign_east")}])
		"exit_east":
			_c0_try_leave()
		"shrine_stub":
			_play_dialog(DialogLines.lines("c0.shrine_stub"))
		"field_west", "hut_c", "fence_row":
			_play_dialog(DialogLines.lines("c0.field_west"))
		_:
			pass


func _c0_sword_done() -> void:
	GameState.weapon_name = "鏽劍"
	GameState.weapon_atk = 4
	GameState.weapon_tier = 1
	GameState.set_flag("c0_sword_triple_pull", true)
	GameState.set_flag("item.rusty_sword", true)
	SaveManager.save_game()
	_notify_codex_unlocks()


func _c0_try_leave() -> void:
	if not GameState.has_flag("item.rusty_sword"):
		_play_dialog(DialogLines.lines("c0.leave_without_sword"))
		return
	GameState.has_wheat_stalk = true
	GameState.set_flag("c0_village_left", true)
	_notify_codex_unlocks()
	var last := _t("……我會等你。") if GameState.has_flag("c0_care") else _t("快跑！")
	_play_dialog([
		{"speaker": _t("麥穗"), "text": _t("（塞進你口袋一枝乾癟的麥穗桿）拿著。不是護身符。——是回家的氣味。")},
		{"speaker": _t("麥穗"), "text": _t("記住回家的路！")},
		{"speaker": _t("麥穗"), "text": last},
	], _c0_leave_cutscene)


func _c0_leave_cutscene() -> void:
	_play_cutscene(_cutscene_art("c0_leave", [
		{
			"bg": "village",
			"speaker": _t("旁白"),
			"portrait": _t("麥穗"),
			"text": _t("腳步踩過仍燙的土。身後，爐火與哭聲一起變小。"),
		},
		{
			"bg": "road",
			"speaker": _t("旁白"),
			"portrait": _t("小白"),
			"text": _t("荒路沒有名字。只有風，與遠遠一口像牙齒的石牆。"),
		},
		{
			"bg": "road",
			"speaker": _t("內心"),
			"text": _t("鏽劍很沉。沉得剛好——讓你記得：還活著。"),
		},
	]), _go_c0_road)


func _go_c0_road() -> void:
	SaveManager.save_game()
	_open_explore("road", Screen.C0_ROAD)


func _interact_road(id: String) -> void:
	match id:
		"wolf":
			_play_dialog([
				{"speaker": _t("旁白"), "text": Loc.t("c0.wolf_spot")},
				{"speaker": _t("系統"), "text": Loc.t("tut.battle")},
			], func(): _start_battle("wolf"))
		"look_back":
			_play_dialog([{"speaker": _t("內心"), "text": Loc.t("flavor.look_back")}])
		"milepost":
			_play_dialog([{"speaker": _t("里程碑"), "text": Loc.t("flavor.milepost")}])
		"bush_a", "bush_b":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.bush")}])
		"road_stone":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.road_stone")}])
		"dawn_glow", "exit_town_hint":
			if GameState.has_flag("c0_first_battle"):
				_play_dialog([
					{"speaker": _t("內心"), "text": Loc.t("flavor.dawn")},
					{"speaker": _t("系統"), "text": _t("石牆就在前方。")},
				], _go_c1_town)
			else:
				_play_dialog([{"speaker": _t("內心"), "text": Loc.t("flavor.dawn")}])
		"milepost_b", "camp_ash", "bridge":
			_play_dialog(DialogLines.lines("c0.road_east"))


func _explore_play_pose(pose: String, duration: float = 0.4) -> void:
	if pose == "" or pose == "idle":
		_pending_explore_pose = ""
		return
	if _explore and is_instance_valid(_explore) and _explore.has_method("play_action_pose"):
		_explore.call("play_action_pose", pose, duration)
		_pending_explore_pose = ""
	else:
		## 戰鬥中探索已被清掉：等下次 _open_explore 再播
		_pending_explore_pose = pose
		_pending_explore_pose_dur = duration


func _start_battle(mode: String) -> void:
	if _paused:
		_close_pause()
	_reset_fade()
	## 探索→戰鬥：先閃攻擊姿，再進戰（與戰鬥 poses 一致）
	_explore_play_pose("attack", 0.35)
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
	## 拜訪挑戰不耗能量；其餘走能量制
	var visit_pending := VisitSystem.pending_id() != ""
	if not visit_pending:
		var er: Dictionary = EnergySystem.try_spend_for_battle(mode)
		if not bool(er.get("ok", false)):
			_play_dialog([{"speaker": _t("系統"), "text": str(er.get("msg", ""))}], func():
				if _last_explore_map != "":
					_open_explore(_last_explore_map, _last_explore_screen)
				else:
					_go_starpath_panel()
			)
			return
		elif int(er.get("cost", 0)) > 0:
			ui_toast(EnergySystem.status_line())
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


func _on_battle_finished(won: bool) -> void:
	SaveManager.save_game()
	## 回探索時補一拍勝負姿（場景重建後下一幀也可能已換圖，仍盡力播）
	if won:
		_explore_play_pose("skill", 0.55)
	else:
		_explore_play_pose("hit", 0.5)
	## 好友挑戰優先收尾
	if VisitSystem.pending_id() != "":
		_on_visit_battle_finished(won)
		return
	if _battle_mode == "wolf":
		if won:
			_grant_boss_loot(25, 2, 0)
			if GameState.skill_slash_lv < 1:
				GameState.skill_slash_lv = 1
			GameState.set_flag("c0_first_battle", true)
			_notify_codex_unlocks()
			_play_dialog(DialogLines.lines("battle.wolf_win"), _c0_to_c1_cutscene)
		else:
			GameState.set_flag("c0_helped_by_stranger", true)
			_play_dialog(DialogLines.lines("battle.wolf_lose"), _go_c0_road)
	elif _battle_mode == "leo":
		if won:
			_go_leo_win()
		else:
			_play_dialog(DialogLines.lines("battle.leo_lose"), _go_c1_wild)
	elif _battle_mode == "fog":
		if won:
			_go_fog_win()
		else:
			_play_dialog(DialogLines.lines("battle.fog_lose"), _go_c2_mist)
	elif _battle_mode == "demon":
		if won:
			_go_demon_win()
		else:
			_play_dialog(DialogLines.lines("battle.demon_lose"), _go_c6_camp)
	elif _battle_mode == "abo":
		if won:
			_go_abo_win()
		else:
			_play_dialog(DialogLines.lines("battle.abo_lose"), _go_c3_dojo)
	elif _battle_mode == "falcon":
		if won:
			_go_falcon_win()
		else:
			_play_dialog(DialogLines.lines("battle.falcon_lose"), _go_c4_forest)
	elif _battle_mode == "boar":
		if won:
			_go_boar_win()
		else:
			_play_dialog(DialogLines.lines("battle.boar_lose"), _go_c5_coast)
	elif _battle_mode in ["wrath", "tide", "statue", "chrono"]:
		if won:
			_go_rift_win(_battle_mode)
		else:
			var tips := {
				"wrath": _t("灼燒要在滿層前躍出。"),
				"tide": _t("刺胞要在時間內解決。看牠當下的樣子，決定用普攻還是技能。"),
				"statue": _t("只打發光的石像。"),
				"chrono": _t("炸彈要拆；落岩要進安全。"),
			}
			_play_dialog(DialogLines.lines("battle.rift_lose", {"tip": tips.get(_battle_mode, "")}), _go_postgame_hub)
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
				win_lines.append({"speaker": _t("系統"), "text": relic_msg})
				if not bool(relic.get("duplicate", false)):
					win_lines.append({"speaker": _t("系統"), "text": _t("秘境魂器要裝上才有用。按 Esc 開選單，進「戰魂」放進槽裡。")})
			win_lines.append({"speaker": _t("系統"), "text": _t("背包：秘境印記×1 · 中紅水×1")})
			var wmap := str(b.get("win_map", "crossroads"))
			var wsc := str(b.get("win_screen", "C1_WILD"))
			_play_dialog(win_lines, func(): _return_to_explore(wmap, wsc))
		else:
			var lmap := str(b.get("lose_map", "crossroads"))
			var lsc := str(b.get("lose_screen", "C1_WILD"))
			_play_dialog([
				{"speaker": _t("系統"), "text": str(b.get("lose", _t("你被擊退了。")))},
			], func(): _return_to_explore(lmap, lsc))
		return

	## 競技場波次（優先於獵場）
	if ArenaSystem.is_run_active() and WorldContent.is_world_battle(mode):
		_on_arena_battle_finished(won)
		return
	## 狩獵場波次
	if HuntSystem.is_run_active() and WorldContent.is_world_battle(mode):
		_on_hunt_battle_finished(won)
		return
	## 雜魚
	var def: Dictionary = WorldContent.enemy_def(mode)
	var ename := str(def.get("name", _t("敵人")))
	if won:
		## 雜魚金幣（經濟 0.15）：略降基準，重複刷有軟上限。
		## 公式 8+hp/15 → 灰燼鼠約 11、疤地焰靈約 16（舊 12+hp/12 → 16～22）。
		## 軟上限：勝場≥25 ×0.8、≥40 ×0.6，最低 5 —— 刷金不再碾過鍛造 sink。
		var gold_n := 8 + int(def.get("max_hp", 50) / 15)
		var sk_wins := int(GameState.get_flag("meta.skirmish_wins", 0))
		if sk_wins >= 40:
			gold_n = maxi(5, int(gold_n * 0.6))
		elif sk_wins >= 25:
			gold_n = maxi(6, int(gold_n * 0.8))
		var dust_n := 1 if int(def.get("max_hp", 50)) >= 90 else 0
		_grant_boss_loot(gold_n, dust_n, 0)
		var xp_n := Formulas.field_xp(int(def.get("max_hp", 50)), sk_wins)
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
		GameLog.combat(_t("擊敗 %s · 金 %d") % [ename, gold_n])
		SaveManager.save_game()
		var extra := (_t(" · 星屑 %d") % dust_n) if dust_n > 0 else ""
		extra += _t(" · 經驗 %d") % int(xr.get("gained", xp_n))
		if int(xr.get("levels", 0)) > 0:
			extra += _t(" · 升級！")
		if sk_wins == 24:
			extra += _t(" · 野外經驗開始變薄。回村演武比較厚。")
		if loot_s != "":
			extra += " · " + loot_s
		extra += eq_s
		_play_dialog(DialogLines.lines("battle.world_win", {"enemy": ename, "gold": gold_n, "extra": extra}), _hub_back_from_world_battle)
	else:
		GameState.hp = maxi(1, int(GameState.max_hp * 0.35))
		SaveManager.save_game()
		_play_dialog(DialogLines.lines("battle.world_flee"), _hub_back_from_world_battle)


func _hub_back_from_world_battle() -> void:
	## 回到開戰前的探索圖
	if _last_explore_map != "":
		_open_explore(_last_explore_map, _last_explore_screen)
	else:
		_go_c1_town()


func _c0_to_c1_cutscene() -> void:
	_play_cutscene(_cutscene_art("c1_arrive", [
		{
			"bg": "road",
			"speaker": _t("旁白"),
			"text": _t("黎明把石牆染成冷灰。旗不揚——卻仍掛著。"),
		},
		{
			"bg": "town",
			"speaker": _t("旁白"),
			"portrait": _t("灰鬚"),
			"text": _t("城門旁站著一個不肯讓路的影子。鬍鬚比門栓還倔。"),
		},
		{
			"bg": "town",
			"speaker": _t("灰鬚"),
			"text": _t("……傭兵團的？煙味。最弱那掛。"),
		},
	]), _go_c1_town)


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
			{"speaker": _t("灰鬚"), "text": _t("停。傭兵團的？……看腳步就知道。最弱那掛的。")},
			{"speaker": _t("灰鬚"), "text": _t("這裡不是菜園，也不是團裡發餉的地方。回去。")},
			{
				"speaker": _t("灰鬚"),
				"text": _t("……說吧。幹嘛還杵在門前。"),
				"choices": [_t("村子被燒了。——上面只叫我來看一眼。"), _t("我來找能打黑焰的人。團裡沒人肯來。"), _t("……讓我進去就好。活著回報就行。")],
				"replies": [
					_t("翠谷？……煙味我聞得出。進來。別哭，沒用。"),
					_t("能打黑焰的人？牆裡沒有這種神仙。只有還肯站崗的傻瓜。"),
					_t("哼。至少話短。進門，別擋道。"),
				],
			},
			{"speaker": _t("灰鬚"), "text": _t("聽著，新人。牆內也不是天堂。聖獅狂了，騎士團散了。")},
			{"speaker": _t("灰鬚"), "text": _t("進了就別給我添亂。——劍橫著掃，別跟啄木鳥一樣戳。")},
			{"speaker": _t("系統"), "text": _t("灰鬚指點了你。【橫斬】更穩了。Esc 可開「技能／招式」。")},
		], func():
			SaveManager.save_game()
			## 第一次進堡：器／魂／招短教學（可 dismiss）
			_open_explore_then("town", Screen.C1_TOWN, func():
				var fort_tips: Array = TutorialSystem.take("fort")
				if not fort_tips.is_empty():
					_play_dialog(fort_tips)
			)
		)
	else:
		## 雷歐後回城：旗幟錨點備援提示（一次）
		if GameState.has_flag("c1_flag_paw") and not TutorialSystem.seen("flag_hint"):
			_open_explore_then("town", Screen.C1_TOWN, func():
				var fh: Array = TutorialSystem.take("flag_hint")
				if not fh.is_empty():
					_play_dialog(fh)
			)
		else:
			_open_explore("town", Screen.C1_TOWN)


func _interact_town(id: String) -> void:
	if _interact_shop_interior(id):
		return
	match id:
		"greybeard":
			_enter_plaza_shop("tutor")
		"ding":
			_enter_plaza_shop("forge")
		"star":
			_enter_plaza_shop("soul")
		"silk":
			_side_silk("silk")
		"flag":
			if GameState.has_flag("c1_flag_paw"):
				_play_dialog(DialogLines.lines("c1.flag_paw"))
			else:
				_play_dialog(DialogLines.lines("c1.flag_grey"))
		"sprout":
			_c1_sprout()
		"wall_notice":
			_play_dialog([{"speaker": _t("告示"), "text": Loc.t("flavor.notice")}])
		"market":
			_play_dialog([
				{"speaker": _t("旁白"), "text": Loc.t("flavor.market")},
				{"speaker": _t("系統"), "text": _t("殘架旁有琥珀的告示：材料行在行商驛站；城內也可問攤位。")},
			], _go_material_shop)
		"fountain":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.fountain")}])
		"bench":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.bench")}])
		"gate_arch":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.gate_arch")}])
		"exit_wild":
			_go_c1_wild()
		"barracks", "chapel", "stable":
			_play_dialog(DialogLines.lines("c1.outer_ward"))
		"menu_save":
			GameState.hp = GameState.effective_max_hp()
			SaveManager.save_game()
			var newly2: Array[String] = TitleCatalog.evaluate_all()
			var extra := ""
			if not newly2.is_empty():
				extra = _t(" 新稱號：%s") % "、".join(newly2)
			_play_dialog(DialogLines.lines("c1.save_stone", {"extra": extra}), _go_title_wall_from_town)
		_:
			pass


func _go_title_wall_from_town() -> void:
	## 從城內看稱號後回廣場
	var newly: Array[String] = TitleCatalog.evaluate_all()
	SaveManager.save_game()
	var body: String = TitleCatalog.wall_bbcode()
	if not newly.is_empty():
		body = _t("[color=#fc8]新解鎖：%s[/color]\n\n") % "、".join(newly) + body
	_panel(
		_t("稱號牆 · 騎士堡"),
		body,
		[{"text": _t("回到廣場"), "cb": _go_c1_town}]
	)


func _c1_star() -> void:
	if GameState.has_flag("c1_soul_intro"):
		var lines: Array = NpcLines.for_npc("star")
		if lines.is_empty():
			lines = [{"speaker": _t("星讀"), "text": _t("足跡會再交疊。星屑夠了就來抽魂。")}]
		var tut: Array = TutorialSystem.take("soul")
		for t in tut:
			lines.append(t)
		_play_dialog(lines, _go_soul_panel)
		return
	_play_dialog([
		{"speaker": _t("星讀"), "text": _t("你身上有煙味，和一點……尚未點名的星光。")},
		{"speaker": _t("星讀"), "text": _t("路上會撿到星屑。拿來抽魂，走過的路會凝成刃的性格。")},
		{"speaker": _t("星讀"), "text": _t("先送你一握星屑。星盤為你亮了一角。")},
		{"speaker": _t("系統"), "text": _t("獲得星屑 ×5。凝出戰魂「凡·破軍」，已入魂槽。")},
	], func():
		GameState.add_stardust(5)
		SoulSystem.grant_starter_soul()
		GameState.set_flag("c1_soul_intro", true)
		TutorialSystem.mark("soul")
		SaveManager.save_game()
		_go_soul_panel()
	)



func _screen_from_region_key(key: String) -> Screen:
	match key:
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
			return Screen.C1_TOWN


func _go_region_panel() -> void:
	var body := RegionCatalog.status_bbcode()
	body += "\n" + EnergySystem.status_line()
	var buttons: Array = []
	for s in RegionCatalog.flat_open_stages():
		var st := str(s.get("state", "open"))
		var mark := "✅" if st == "cleared" else "▶"
		var label := "%s %s" % [mark, str(s.get("name", ""))]
		var goto: Dictionary = s.get("goto", {})
		var map_id := str(goto.get("map", "town"))
		var sc := _screen_from_region_key(str(goto.get("screen", "C1_TOWN")))
		buttons.append({"text": label, "cb": _region_goto_cb(map_id, sc)})
	buttons.append({"text": Loc.t("btn.back"), "cb": _go_starpath_panel})
	_panel(_t("四地區關卡"), body, buttons)


func _region_goto_cb(map_id: String, screen: Screen) -> Callable:
	return func():
		_open_explore(map_id, screen)


func _go_visit_panel() -> void:
	if OnlineGate.is_signed_in():
		OnlineGate.push_pvp_snapshot()
		OnlineGate.fetch_pvp_snapshots(func(res: Dictionary):
			var list: Array = res.get("list", []) if typeof(res.get("list", [])) == TYPE_ARRAY else []
			VisitSystem.ingest_remote(list)
			_render_visit_panel()
		)
	_render_visit_panel()


func _render_visit_panel() -> void:
	var body := VisitSystem.status_bbcode()
	body += "\n" + EnergySystem.status_line()
	var buttons: Array = []
	for trow in VisitSystem.list_targets():
		var tid := str(trow.get("id", ""))
		var done := bool(trow.get("done", false))
		var nm := str(trow.get("name", tid))
		var lab := (_t("今日已戰・%s") % nm) if done else (_t("挑戰好友・%s") % nm)
		var pwr: int = int(trow.get("power", 0))
		if pwr > 0:
			lab += _t("  戰力 %d") % pwr
		if done:
			buttons.append({"text": lab, "cb": _go_visit_panel})
		else:
			buttons.append({"text": lab, "cb": _visit_challenge_cb(tid)})
	if VisitSystem.can_open_chest():
		buttons.append({"text": _t("打開友誼寶箱（3 鑰匙）"), "cb": _visit_open_chest})
	else:
		buttons.append({"text": _t("友誼寶箱（需 3 鑰匙）"), "cb": _go_visit_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _go_starpath_panel})
	_panel(_t("好友挑戰"), body, buttons)


func _visit_challenge_cb(tid: String) -> Callable:
	return func():
		var r: Dictionary = VisitSystem.begin_challenge(tid)
		if not bool(r.get("ok", false)):
			_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_visit_panel)
			return
		_play_dialog([
			{"speaker": _t("系統"), "text": str(r.get("msg", ""))},
			{"speaker": _t("系統"), "text": _t("殘影戰力 %d。打的是人影留下的打法，不是即時對戰。勝利後可選金幣或經驗。不耗能量。") % int(r.get("power", 0))},
		], func(): _start_battle(str(r.get("mode", "pvp_snap"))))


func _visit_open_chest() -> void:
	var r: Dictionary = VisitSystem.open_chest()
	_play_dialog([{"speaker": _t("系統"), "text": str(r.get("msg", ""))}], _go_visit_panel)


func _on_visit_battle_finished(won: bool) -> void:
	if not won:
		var lost: Dictionary = VisitSystem.on_challenge_lost()
		_play_dialog([{"speaker": _t("系統"), "text": str(lost.get("msg", ""))}], _go_visit_panel)
		return
	_play_dialog([
		{
			"speaker": _t("系統"),
			"text": _t("好友挑戰勝利！選擇獎勵："),
			"choices": [_t("要金幣"), _t("要經驗")],
			"replies": [_t("選擇金幣。"), _t("選擇經驗。")],
		},
	], Callable(), "visit_reward")


func _go_soul_panel() -> void:
	SoulSystem.ensure_slots()
	SoulSystem.ensure_daily_free()
	## 聚魂殿用較靜的村曲，避免還停在戰鬥 BGM
	if AudioManager and AudioManager.has_method("play_bgm"):
		AudioManager.play_bgm("village")
	var body: String = SoulSystem.panel_status_bbcode()
	body += "\n\n" + Loc.t("soul.hint")
	body += "\n" + EnergySystem.status_line()
	var buttons: Array = []
	if SoulSystem.can_ritual():
		var cost_g: int = SoulSystem.ritual_cost_gold()
		var label: String
		if cost_g <= 0:
			label = Loc.t("soul.ritual_free")
		else:
			label = Loc.t("soul.ritual_gold", {"n": cost_g})
		buttons.append({"text": label, "cb": _soul_do_ritual})
		if SoulSystem.can_ritual_batch(10):
			var est: int = SoulSystem.ritual_batch_gold_estimate(10)
			buttons.append({
				"text": Loc.t("soul.ritual_x10", {"n": est}),
				"cb": _soul_do_ritual_x10,
			})
	else:
		buttons.append({
			"text": Loc.t("soul.gold_short", {"n": SoulSystem.vessel_cost()}),
			"cb": _go_soul_panel,
		})
	## 背包入魂：先進對比槽位，不默默塞第一空槽
	var bag: Array = SoulSystem.bag_souls()
	for i in mini(5, bag.size()):
		var s: Dictionary = bag[i]
		var sid: String = str(s.get("id", ""))
		var label: String = Loc.t("soul.equip", {"name": SoulSystem.soul_display(s)})
		buttons.append({"text": label, "cb": _soul_embed_pick_cb(sid)})
	for i in GameState.soul_slots.size():
		if str(GameState.soul_slots[i]) != "":
			var si: int = i
			buttons.append({"text": Loc.t("soul.unequip", {"n": si + 1}), "cb": func():
				SoulSystem.unequip_slot(si)
				SaveManager.save_game()
				_go_soul_panel()
			})
	buttons.append({"text": Loc.t("soul.fuse"), "cb": _soul_try_fuse})
	buttons.append({"text": Loc.t("pause.gems"), "cb": _go_gem_panel})
	buttons.append({"text": Loc.t("common.skills"), "cb": _go_skill_panel})
	buttons.append({"text": Loc.t("forge.back_square"), "cb": _go_c1_town})
	_panel(Loc.t("soul.panel_title"), body, buttons, {"soul_hang": true})


func _go_gem_panel() -> void:
	var body: String = GemSystem.status_bbcode()
	body += "\n\n" + GemSystem.panel_actions_hint()
	var buttons: Array = []
	if GemSystem.unlocked():
		## 熔爐解鎖
		if GemSystem.furnace_can_unlock_gold():
			buttons.append({
				"text": _t("點燃熔爐（%d 金 · 第二產線）") % GemSystem.FURNACE_GOLD,
				"cb": func():
					var ur: Dictionary = GemSystem.unlock_furnace("gold")
					_show_toast(str(ur.get("msg", "")))
					_go_gem_panel()
			})
		if GemSystem.furnace_can_unlock_medal():
			buttons.append({
				"text": _t("點燃熔爐（%d 勳章）") % GemSystem.FURNACE_MEDALS,
				"cb": func():
					var um: Dictionary = GemSystem.unlock_furnace("medal")
					_show_toast(str(um.get("msg", "")))
					_go_gem_panel()
			})
		## 熔煉：3 碎片 → 1 級
		for c in GemSystem.COLORS:
			if GemSystem.can_smelt(c):
				var cc: String = c
				buttons.append({
					"text": _t("熔煉 %s（3 碎片→1級）") % GemSystem.color_label(cc),
					"cb": func():
						var sr: Dictionary = GemSystem.smelt(cc)
						_show_toast(str(sr.get("msg", "")))
						_go_gem_panel()
				})
		## 合成：每色每級若可合成給一顆按鈕（最多列幾組）
		var fuse_n := 0
		for c in GemSystem.COLORS:
			for lv in range(1, GemSystem.MAX_LEVEL):
				if GemSystem.can_fuse(c, lv) and fuse_n < 6:
					var cc2: String = c
					var ll: int = lv
					buttons.append({
						"text": _t("合成 %s %d→%d") % [GemSystem.color_label(cc2), ll, ll + 1],
						"cb": func():
							var r: Dictionary = GemSystem.fuse(cc2, ll)
							_show_toast(str(r.get("msg", "")))
							_go_gem_panel()
					})
					fuse_n += 1
		## 鑲嵌：背包前幾顆寶石 × 已穿武器／防具
		var worn_targets: Array = []
		for slot in ["weapon", "armor"]:
			var uid := str(GameState.equip_slots.get(slot, ""))
			if uid != "" and GameState.equip_worn.has(uid):
				worn_targets.append({"uid": uid, "name": str(GameState.equip_worn[uid].get("name", slot))})
		var bag_n := 0
		for g in GameState.gem_bag:
			if bag_n >= 4:
				break
			var gid := str(g.get("id", ""))
			var glabel := GemSystem.gem_label(g)
			for t in worn_targets:
				var uid2: String = str(t.get("uid", ""))
				var tname: String = str(t.get("name", ""))
				buttons.append({
					"text": _t("鑲嵌 %s → %s") % [glabel, tname],
					"cb": func():
						var r2: Dictionary = GemSystem.socket(uid2, gid)
						_show_toast(str(r2.get("msg", "")))
						_go_gem_panel()
				})
			bag_n += 1
	buttons.append({"text": Loc.t("pause.soul"), "cb": _go_soul_panel})
	buttons.append({"text": Loc.t("pause.equip"), "cb": _go_equip_panel})
	buttons.append({"text": Loc.t("btn.back"), "cb": _hub_back})
	_panel(Loc.t("panel.gems"), body, buttons)


func _c1_sprout() -> void:
	## 小芽支線：想要練習木劍
	if GameState.has_flag("c1_sprout_done"):
		if GameState.has_flag("boss.leo_cleared"):
			_play_dialog(DialogLines.lines("c1.sprout_after_leo"))
		else:
			_play_dialog(DialogLines.lines("c1.sprout_thanks"))
		return
	if not GameState.has_flag("c1_sprout_asked"):
		_play_dialog([
			{"speaker": _t("小芽"), "text": _t("我以後要當騎士！比獅子還大！你那把劍好沉喔，我搬不動。")},
			{"speaker": _t("小芽"), "text": _t("可是我沒有劍。木頭的也可以！有沒有人要給我一把？")},
			{"speaker": _t("系統"), "text": _t("【支線】小芽想要練習木劍。可找釘釘做一把（20 金），或直接給她 30 金讓她去買。")},
		], func():
			GameState.set_flag("c1_sprout_asked", true)
			SaveManager.save_game()
		)
		return
	## 已問過：有木劍 → 送；有 30 金 → 可選贊助；否則提醒
	if GameState.has_flag("item.wood_sword"):
		_play_dialog([
			{"speaker": _t("小芽"), "text": _t("那是木劍？！給我的嗎？！")},
			{"speaker": _t("小芽"), "text": _t("哇啊啊！我會每天練！你去打獅子那天，我在旗下等你回來！")},
			{"speaker": _t("系統"), "text": _t("交木劍。獲得星屑 ×3、金幣 ×15。")},
		], func():
			GameState.set_flag("item.wood_sword", false)
			GameState.stardust += 3
			## 台詞承諾 15 金，原本只給星屑。木劍本身花 20 金打，
			## 玩家是照「20 換 15＋3 星屑」在算帳的。
			GameState.add_gold(15)
			GameState.set_flag("c1_sprout_done", true)
			TitleCatalog.evaluate_all()
			SaveManager.save_game()
		)
		return
	if GameState.gold >= 30:
		_play_dialog([
			{
				"speaker": _t("小芽"),
				"text": _t("你身上叮噹響……是要贊助我買木劍嗎？（30 金）"),
				"choices": [_t("給她 30 金"), _t("先不給")],
				"replies": [
					_t("謝謝你！！我會每天練！你打獅子的時候，我在旗下等你！"),
					_t("好……我再等。不會纏著你的。"),
				],
			},
		], Callable(), "sprout_sponsor")
		return
	_play_dialog(DialogLines.lines("c1.sprout_wish"))


## 原作村內四大店：走進室內圖，店裡才開面板（Esc 選單仍可用）
func _plaza_shop_map(kind: String) -> String:
	match kind:
		"forge":
			return "town_forge"
		"soul":
			return "town_soul"
		"gem":
			return "town_gem"
		"tutor":
			return "town_tutor"
		_:
			return ""


func _enter_plaza_shop(kind: String) -> void:
	var dest := _plaza_shop_map(kind)
	if dest == "":
		return
	var first := not GameState.has_flag("c1_four_shops_seen")
	if first:
		GameState.set_flag("c1_four_shops_seen", true)
		_play_dialog([
			{"speaker": _t("旁白"), "text": _t("廣場四店：鐵匠鋪、聚魂殿、手藝工坊、武術館。走進才算來過。")},
		], func(): _open_explore(dest, Screen.C1_TOWN))
		return
	_open_explore(dest, Screen.C1_TOWN)


func _interact_shop_interior(id: String) -> bool:
	match _last_explore_map:
		"town_forge":
			match id:
				"ding":
					_go_c1_forge()
					return true
				"anvil":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("鐵砧還燙。釘釘不看頭銜，看鐵。")}])
					return true
				"forge_hearth":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("爐心拍在臉上。失敗不掉階——他手藝沒那麼丟人。")}])
					return true
				"bellows":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("風箱餘息。重鍛時他曾在這裡停錘兩秒。")}])
					return true
				"scrap_bin":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("廢鐵桶裡有捲刃。他養的是器，不是骨灰盒。")}])
					return true
		"town_soul":
			match id:
				"star":
					_c1_star()
					return true
				"astrolabe":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("星盤偏了一角，像在等傭兵團最弱的那個。")}])
					return true
				"gourd_shelf":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("葫蘆綠到橙。抽魂＝聚魂。星屑只是路上的光。")}])
					return true
				"star_mat":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("墊上還有上一個人的膝印。足跡會交疊。")}])
					return true
		"town_gem":
			match id:
				"gem_clerk":
					_play_dialog([
						{"speaker": _t("工坊師傅"), "text": _t("紅黃藍。三合一流派；碎片熔煉。鑲上就成——只換，不失敗。")},
					], _go_gem_panel)
					return true
				"gem_case", "cold_furnace", "shard_box":
					_go_gem_panel()
					return true
		"town_tutor":
			match id:
				"greybeard":
					_c1_greybeard()
					return true
				"training_dummy":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("木人樁身上全是橫痕。啄木鳥式的戳，一刀都沒留下。")}])
					return true
				"weapon_wall":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("牆上的劍都橫放。招跟手上那把走，換錯欄出不了招。")}])
					return true
				"floor_mat":
					_play_dialog([{"speaker": _t("旁白"), "text": _t("練武墊磨薄了。傭兵第一課：活著比漂亮重要。")}])
					return true
		_:
			pass
	return false


func _c1_greybeard() -> void:
	if GameState.has_flag("c1_forged") and not SkillSystem.is_learned("emergency_heal") and not GameState.has_flag("boss.leo_cleared"):
		_play_dialog([
			{"speaker": _t("灰鬚"), "text": _t("刃有了。還差一口氣。")},
			{"speaker": _t("灰鬚"), "text": _t("被咬到別硬撐——吐氣，把血留在身子裡。")},
			{"speaker": _t("系統"), "text": _t("體悟【緊急恢復】。危急時怒氣會優先回血。")},
		], func():
			SkillSystem.grant_heal_insight()
			SaveManager.save_game()
			_go_skill_panel()
		)
		return
	var lines: Array = NpcLines.for_npc("greybeard")
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
			buttons.append({"text": _t("體悟：%s") % nm, "cb": _skill_unlock_cb(sid)})
	## 導師指點（加速熟練）
	for d in SkillSystem.CATALOG:
		var sid2: String = str(d.get("id", ""))
		if SkillSystem.can_tutor(sid2):
			var label: String = _t("指點 %s（%d金）") % [SkillSystem.display_name(sid2), SkillSystem.TUTOR_COST]
			buttons.append({"text": label, "cb": _skill_tutor_cb(sid2)})
	buttons.append({"text": Loc.t("pause.soul"), "cb": _go_soul_panel})
	buttons.append({"text": _t("回到廣場"), "cb": _go_c1_town})
	_panel(Loc.t("panel.tutor"), body, buttons)


func _skill_unlock_cb(sid: String) -> Callable:
	return func():
		if SkillSystem.try_unlock(sid):
			SaveManager.save_game()
			_play_dialog(DialogLines.lines("skill.learned", {"skill": SkillSystem.display_name(sid)}), _go_skill_panel)
		else:
			_play_dialog(DialogLines.lines("skill.not_yet"), _go_skill_panel)


func _skill_tutor_cb(sid: String) -> Callable:
	return func():
		if not SkillSystem.can_tutor(sid):
			_play_dialog(DialogLines.lines("skill.tutor_deny"), _go_skill_panel)
			return
		var res: Dictionary = SkillSystem.tutor_train(sid)
		SaveManager.save_game()
		var line: String = _t("熟練推進。%s") % SkillSystem.mastery_progress_line(sid)
		if bool(res.get("leveled", false)):
			line = _t("體悟！升至 %s") % str(res.get("name", ""))
		_play_dialog([
			{"speaker": _t("灰鬚"), "text": _t("手腕轉一下。對，這樣。")},
			{"speaker": _t("系統"), "text": line},
		], _go_skill_panel)


func _soul_embed_pick_cb(sid: String) -> Callable:
	return func():
		_go_soul_embed_panel(sid)


func _go_soul_embed_panel(sid: String) -> void:
	SoulSystem.ensure_slots()
	var incoming: Dictionary = SoulSystem.find_soul(sid)
	if incoming.is_empty():
		_play_dialog([{"speaker": _t("星讀"), "text": _t("找不到這顆戰魂。")}], _go_soul_panel)
		return
	if SoulSystem.slot_count() <= 0:
		_play_dialog([
			{"speaker": _t("星讀"), "text": _t("器階不足，尚無魂槽。先找釘釘養器。")},
		], _go_soul_panel)
		return
	var body: String = _t("[b]入魂：%s[/b]\n%s\n選空槽或替換。數字是相對該槽的增減。") % [
		SoulSystem.soul_display(incoming), SoulSystem.soul_bonus_line(incoming)
	]
	var buttons: Array = []
	for i in GameState.soul_slots.size():
		var cmp: Dictionary = SoulSystem.compare_embed(sid, i)
		buttons.append({"text": str(cmp.get("line", "")), "cb": _soul_equip_cb(sid, i)})
	buttons.append({"text": Loc.t("btn.back"), "cb": _go_soul_panel})
	_panel(_t("入魂 · 選槽"), body, buttons, {"soul_hang": true})


func _soul_after_draw(sid: String) -> void:
	var buttons: Array = [
		{"text": _t("前往嵌魂"), "cb": func(): _go_soul_embed_panel(sid)},
		{"text": _t("稍後再說"), "cb": _go_soul_panel},
	]
	_panel(_t("點亮完成"), _t("戰魂已入袋。要現在嵌進器槽嗎？"), buttons, {"soul_hang": true})


func _soul_equip_cb(sid: String, slot: int) -> Callable:
	return func():
		var err: String = SoulSystem.equip_soul(sid, slot)
		if err != "":
			_play_dialog([{"speaker": _t("星讀"), "text": err}], _go_soul_panel)
		else:
			SaveManager.save_game()
			_play_dialog(DialogLines.lines("soul.equipped"), _go_soul_panel)


func _make_soul_hang() -> Control:
	## 聚魂面板掛圖：當下葫蘆＋十四星（已抽過的亮、神品質偏金）
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vt: Texture2D = SpriteDB.soul_vessel(str(GameState.soul_vessel))
	if vt:
		var gourd := TextureRect.new()
		gourd.texture = vt
		gourd.custom_minimum_size = Vector2(56, 72)
		gourd.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gourd.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gourd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(gourd)
	var shen_tex: Texture2D = SpriteDB.soul_shen()
	var owned: Dictionary = {}
	var has_shen := false
	for s in GameState.souls:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var star_id := str(s.get("star", ""))
		owned[star_id] = true
		if str(s.get("quality", "")) == "神":
			has_shen = true
	if has_shen and shen_tex:
		var wreath := TextureRect.new()
		wreath.texture = shen_tex
		wreath.custom_minimum_size = Vector2(48, 48)
		wreath.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wreath.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wreath.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(wreath)
	box.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var any_star := false
	for st in SoulSystem.STARS:
		var sid := str(st.get("id", ""))
		var star_tex: Texture2D = SpriteDB.soul_star(sid)
		if star_tex == null:
			continue
		any_star = true
		var cell := TextureRect.new()
		cell.texture = star_tex
		cell.custom_minimum_size = Vector2(32, 32)
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if owned.has(sid):
			cell.modulate = Color(1.1, 1.05, 0.9)
		else:
			cell.modulate = Color(0.38, 0.38, 0.42, 0.55)
		grid.add_child(cell)
	if any_star:
		box.add_child(grid)
	if top.get_child_count() == 0 and not any_star:
		return null
	return box


func _soul_preview_tex(tex: Texture2D) -> TextureRect:
	var old := host.get_node_or_null("SoulHangPreview")
	if old:
		old.queue_free()
	if tex == null:
		return null
	var wrap := CenterContainer.new()
	wrap.name = "SoulHangPreview"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.name = "Glow"
	tr.texture = tex
	tr.custom_minimum_size = Vector2(180, 200)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(tr)
	host.add_child(wrap)
	wrap.z_index = 8
	return tr


func _vessel_glow_color(vessel: String) -> Color:
	match vessel:
		"綠葫蘆":
			return Color(0.45, 1.0, 0.55)
		"藍葫蘆":
			return Color(0.4, 0.65, 1.15)
		"紫葫蘆":
			return Color(0.85, 0.5, 1.15)
		"橙葫蘆":
			return Color(1.15, 0.65, 0.25)
		_:
			return Color(1, 1, 1)


func _soul_play_lightup(vessel: String, result: Texture2D, then: Callable) -> void:
	var gourd := SpriteDB.soul_vessel(vessel)
	var tr := _soul_preview_tex(gourd if gourd else result)
	if tr == null:
		if then.is_valid():
			then.call()
		return
	var col := _vessel_glow_color(vessel)
	tr.modulate = Color(0.35, 0.35, 0.4)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(tr, "modulate", col, 0.28)
	tw.tween_property(tr, "modulate", Color(1.25, 1.2, 0.95), 0.18)
	tw.tween_callback(func():
		if result:
			tr.texture = result
		tr.modulate = col
	)
	tw.tween_property(tr, "modulate", Color.WHITE, 0.35)
	tw.tween_callback(func():
		if then.is_valid():
			then.call()
	)


func _vessel_glow_line(vessel: String) -> String:
	match vessel:
		"綠葫蘆":
			return _t("💚 綠光從蒂部滲出……樸素的葫蘆醒了。")
		"藍葫蘆":
			return _t("💙 藍紋沿著葫蘆腰線爬升……更深一階。")
		"紫葫蘆":
			return _t("💜 紫霧在葫蘆內打轉……稀世近了。")
		"橙葫蘆":
			return _t("🧡 橙焰燃滿葫蘆——頂階！再抽同色便會摔回綠。")
		_:
			return _t("魂器顫動……")


func _soul_do_ritual() -> void:
	if not SoulSystem.can_ritual():
		_play_dialog([
			{"speaker": _t("星讀"), "text": _t("金幣不夠點亮魂器。去做委託、演武，或等明日免費一次。")},
		], _go_soul_panel)
		return
	## 原作「點亮」：依目前葫蘆色階演出 → 抽魂 → 跳階結果
	AudioManager.play("ui", 1.08, -6.0)
	var vessel_now := str(GameState.soul_vessel)
	_soul_preview_tex(SpriteDB.soul_vessel(vessel_now))
	ui_toast(_t("點亮：%s") % vessel_now)
	var footprint: String = SoulSystem.ritual_footprint_line()
	var ladder := SoulSystem.vessel_ladder_bbcode()
	_play_dialog([
		{"speaker": _t("星讀"), "text": _t("把手放上葫蘆。聚魂——也就是你們說的抽魂。")},
		{"speaker": _t("系統"), "text": _t("魂器階梯：%s") % ladder},
		{"speaker": _t("系統"), "text": _vessel_glow_line(vessel_now)},
		{"speaker": _t("系統"), "text": footprint},
		{"speaker": _t("系統"), "text": _t("點亮——抽魂！")},
	], func():
		var before_v := str(GameState.soul_vessel)
		var soul: Dictionary = SoulSystem.ritual()
		SaveManager.save_game()
		if soul.is_empty():
			_play_dialog([{"speaker": _t("星讀"), "text": _t("……今夜無星。")}], _go_soul_panel)
			return
		var after_v := str(GameState.soul_vessel)
		var q := str(soul.get("quality", ""))
		var result_tex: Texture2D = SpriteDB.soul_star(str(soul.get("star", "")))
		if q == "神":
			var sh := SpriteDB.soul_shen()
			if sh:
				result_tex = sh
		if result_tex == null:
			result_tex = SpriteDB.soul_vessel(after_v)
		var line: String = _t("凝出 %s（%s）") % [
			SoulSystem.soul_display(soul), SoulSystem.soul_bonus_line(soul)
		]
		var vessel_line := _t("魂器仍為 %s。") % after_v
		if after_v != before_v:
			if after_v == "綠葫蘆" and before_v != "綠葫蘆":
				vessel_line = _t("同色頂階！魂器由 %s 摔回綠葫蘆，重新攀升。") % before_v
			else:
				vessel_line = _t("魂器升階：%s → %s｜%s") % [before_v, after_v, _vessel_glow_line(after_v)]
		ui_toast(_t("入魂候補：%s") % SoulSystem.soul_display(soul))
		AudioManager.play("interact", 1.0, -4.0)
		var sid_done := str(soul.get("id", ""))
		_soul_play_lightup(before_v, result_tex, func():
			_play_dialog([
				{"speaker": _t("星讀"), "text": _t("好。看葫蘆現在停在哪一階。")},
				{"speaker": _t("系統"), "text": line},
				{"speaker": _t("系統"), "text": vessel_line},
				{"speaker": _t("系統"), "text": _t("現階：%s") % SoulSystem.vessel_ladder_bbcode()},
			], func(): _soul_after_draw(sid_done))
		)
	)


func _soul_do_ritual_x10() -> void:
	if not SoulSystem.can_ritual_batch(10):
		_play_dialog([
			{"speaker": _t("星讀"), "text": _t("金幣不夠連抽十次。先抽一顆，或去做委託、演武。")},
		], _go_soul_panel)
		return
	AudioManager.play("ui", 1.08, -6.0)
	var vessel_now := str(GameState.soul_vessel)
	_soul_preview_tex(SpriteDB.soul_vessel(vessel_now))
	ui_toast(_t("點亮×10：%s") % vessel_now)
	_play_dialog([
		{"speaker": _t("星讀"), "text": _t("十次。把手放穩。聚魂會連著跳。")},
		{"speaker": _t("系統"), "text": _vessel_glow_line(vessel_now)},
		{"speaker": _t("系統"), "text": _t("點亮——抽魂×10！")},
	], func():
		var before_v := str(GameState.soul_vessel)
		var souls: Array = SoulSystem.ritual_batch(10)
		SaveManager.save_game()
		if souls.is_empty():
			_play_dialog([{"speaker": _t("星讀"), "text": _t("……今夜無星。")}], _go_soul_panel)
			return
		var after_v := str(GameState.soul_vessel)
		var best: Dictionary = souls[0]
		for s in souls:
			if str(s.get("quality", "")) == "神":
				best = s
				break
		var best_tex: Texture2D = SpriteDB.soul_star(str(best.get("star", "")))
		if str(best.get("quality", "")) == "神":
			var sh2 := SpriteDB.soul_shen()
			if sh2:
				best_tex = sh2
		if best_tex == null:
			best_tex = SpriteDB.soul_vessel(after_v)
		var names: Array[String] = []
		for s2 in souls:
			names.append(SoulSystem.soul_display(s2))
		var shown := "、".join(PackedStringArray(names.slice(0, mini(4, names.size()))))
		if names.size() > 4:
			shown += _t("…共 %d 顆") % names.size()
		var vessel_line := _t("魂器仍為 %s。") % after_v
		if after_v != before_v:
			if after_v == "綠葫蘆" and before_v != "綠葫蘆":
				vessel_line = _t("同色頂階！魂器由 %s 摔回綠葫蘆，重新攀升。") % before_v
			else:
				vessel_line = _t("魂器：%s → %s") % [before_v, after_v]
		ui_toast(_t("抽魂×%d") % souls.size())
		var sid_best := str(best.get("id", ""))
		_soul_play_lightup(before_v, best_tex, func():
			_play_dialog([
				{"speaker": _t("星讀"), "text": _t("十次聚魂完了。看最好的那顆。")},
				{"speaker": _t("系統"), "text": _t("凝出：%s") % shown},
				{"speaker": _t("系統"), "text": vessel_line},
				{"speaker": _t("系統"), "text": _t("現階：%s") % SoulSystem.vessel_ladder_bbcode()},
			], func(): _soul_after_draw(sid_best))
		)
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
				_play_dialog(DialogLines.lines("soul.fused", {"soul": SoulSystem.soul_display(fused)}), _go_soul_panel)
				return
	_play_dialog(DialogLines.lines("soul.fuse_requirement"), _go_soul_panel)


func _go_c1_forge() -> void:
	_current = Screen.C1_FORGE
	var forge_tips: Array = TutorialSystem.take("forge")
	if not forge_tips.is_empty() and GameState.has_flag("c1_forged"):
		_play_dialog(forge_tips, _show_forge_panel)
		return
	if not GameState.has_flag("c1_forged"):
		_play_dialog([
			{"speaker": _t("釘釘"), "text": _t("門開著不是讓菜鳥觀光的。——傭兵團又把最弱的送來了？")},
			{"speaker": _t("釘釘"), "text": _t("……這什麼垃圾。挖土的？團裡發的？")},
			{"speaker": _t("釘釘"), "text": _t("鏽進骨子了。你要走遠路，就別拿骨灰盒當武器。")},
			{"speaker": _t("系統"), "text": _t("錘擊一。火花。")},
			{"speaker": _t("系統"), "text": _t("錘擊二。刃上淺淺古紋。")},
			{"speaker": _t("釘釘"), "text": _t("……你從哪撿的。")},
			{"speaker": _t("釘釘"), "text": _t("算了。")},
			{"speaker": _t("系統"), "text": _t("第三錘更輕、更準，像在對什麼道歉。")},
			{"speaker": _t("釘釘"), "text": _t("叫它「微末之刃」正好。別弄丟。")},
			{"speaker": _t("釘釘"), "text": _t("我養的是器。星什麼魂，去找愛看天的那個。")},
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
	var at_max := GameState.weapon_tier >= FORGE_MAX_TIER
	var body := Loc.t("forge.status", {
		"tier": GameState.weapon_tier, "max": FORGE_MAX_TIER, "atk": GameState.weapon_atk,
		"fail": GameState.forge_fail_streak, "gold": GameState.gold,
	})
	if at_max:
		body += "\n" + Loc.t("forge.at_max")
	else:
		body += "\n" + Loc.t("forge.next", {
			"cost": forge_cost(), "rate": int(forge_rate_base() * 100.0),
		})
	## 魂槽是跟著器階開的，讓玩家看得到下一格在哪裡
	var slots: int = SoulSystem.slot_count()
	var next_slot := 0
	for need in SoulSystem.SLOT_TIERS:
		if GameState.weapon_tier < need:
			next_slot = need
			break
	body += "\n" + Loc.t("forge.soul_slots", {"cur": slots, "max": SoulSystem.SLOT_TIERS.size()})
	if next_slot > 0:
		body += Loc.t("forge.next_slot", {"n": next_slot})
	if GameState.has_flag("meta.forge_debt_bonus"):
		body += _t("\n舊債加成：升階更穩（一次人情）。")
	if GameState.has_flag("c1_sprout_asked") and not GameState.has_flag("c1_sprout_done"):
		body += _t("\n\n小芽想要練習木劍——可在此打一把（20 金）。")
	if GameState.has_flag("side.ding_debt_asked") and not GameState.has_flag("side.ding_debt_done"):
		if GameState.has_flag("item.broken_blade"):
			body += _t("\n\n【舊債】斷劍已帶回——可交給釘釘。")
		else:
			body += _t("\n\n【舊債】斷劍在演武場武器架。")
	var buttons: Array = [
		{"text": Loc.t("forge.upgrade"), "cb": _try_forge},
	]
	if GameState.has_flag("c1_sprout_asked") and not GameState.has_flag("item.wood_sword") and not GameState.has_flag("c1_sprout_done"):
		buttons.append({"text": _t("做木劍給小芽（20 金）"), "cb": _forge_wood_sword})
	## 舊債支線入口
	if GameState.has_flag("c1_forged") and not GameState.has_flag("side.ding_debt_done"):
		var debt_label := _t("舊債：交斷劍") if GameState.has_flag("item.broken_blade") else _t("打聽舊債")
		if GameState.has_flag("side.ding_debt_asked") and not GameState.has_flag("item.broken_blade"):
			debt_label = _t("舊債進度（斷劍未取）")
		buttons.append({"text": debt_label, "cb": _side_start_ding_debt})
	if GameState.has_flag("c1_forged"):
		buttons.append({"text": Loc.t("forge.craft_class"), "cb": _go_craft_panel})
		buttons.append({"text": Loc.t("pause.path", {"path": GameState.path_display()}), "cb": _go_path_panel})
	buttons.append({"text": Loc.t("forge.back_square"), "cb": _go_c1_town})
	_panel(Loc.t("forge.panel_title"), body, buttons)


func _go_craft_panel() -> void:
	if not GameState.has_flag("c1_forged"):
		_play_dialog(DialogLines.lines("forge.need_rusty_first"), _show_forge_panel)
		return
	var body := Loc.t("forge.craft_intro", {
		"gold": GameState.gold,
		"iron": InventorySystem.count("iron_scrap"),
		"star": InventorySystem.count("star_ore"),
		"oak": InventorySystem.count("oak_resin"),
		"knight": InventorySystem.count("knight_shard"),
	})
	var recipes: Array = DataTables.craft_recipes()
	var lines: PackedStringArray = []
	for r in recipes:
		lines.append(EquipmentSystem.recipe_line(r))
	body += "\n".join(lines)
	## 26 個配方全部列得出來。
	##
	## 原本只做前 10 個（說明區卻把 26 個全列給玩家看），做不出來的 16 個裡
	## 包含**全部的防具與飾品**，以及鎚流派的三把鎚 —— 選了鎚的玩家
	## 一把自己的武器都打不出來，而裝備面板還寫著「野外掉落或找釘釘鍛造」。
	##
	## 當初封 10 個大概是因為面板放不下；現在按鈕列會捲動了，不必再砍。
	## 自己流派的排前面，不用在 26 顆裡面找。
	var my_line := GameState.path_style
	var order: Array = []
	for i in recipes.size():
		var rr: Dictionary = recipes[i]
		var bl := str(EquipmentSystem.base_def(str(rr.get("base_id", ""))).get("line", ""))
		order.append({"i": i, "own": bl != "" and bl == my_line})
	order.sort_custom(func(a2, b2): return bool(a2["own"]) and not bool(b2["own"]))
	var buttons: Array = []
	for o in order:
		var idx: int = int(o["i"])
		var rec: Dictionary = recipes[idx]
		var nm := str(EquipmentSystem.base_def(str(rec.get("base_id", ""))).get("name", "?"))
		buttons.append({"text": Loc.t("forge.craft_btn", {"name": nm}), "cb": func(): _do_craft(idx)})
	buttons.append({"text": Loc.t("forge.back_menu"), "cb": _show_forge_panel})
	_panel(Loc.t("forge.craft_title"), body, buttons)


func _do_craft(recipe_index: int) -> void:
	var recipes: Array = DataTables.craft_recipes()
	if recipe_index < 0 or recipe_index >= recipes.size():
		_go_craft_panel()
		return
	var rec: Dictionary = recipes[recipe_index]
	var r: Dictionary = EquipmentSystem.craft(rec)
	_play_dialog([
		{"speaker": _t("釘釘"), "text": _t("……看火。") if bool(r.get("ok", false)) else _t("材料不夠就別佔爐。")},
		{"speaker": _t("系統"), "text": str(r.get("msg", ""))},
	], _go_craft_panel)


func _go_path_panel(from_forge: bool = false) -> void:
	## 首次：短教學「流派≠三重養成」再進面板
	var path_tips: Array = TutorialSystem.take("paths")
	if not path_tips.is_empty():
		_play_dialog(path_tips, func(): _go_path_panel_ui(from_forge))
		return
	_go_path_panel_ui(from_forge)


func _go_path_panel_ui(from_forge: bool = false) -> void:
	var body := Loc.t("path.intro", {
		"path": GameState.path_display(),
		"pow": GameState.power_score(),
		"lv": GameState.level,
	})
	var buttons: Array = []
	for c in DataTables.weapon_class_list():
		var id := str(c.get("id", ""))
		var label := "%s·%s" % [c.get("name", id), c.get("title", "")]
		var cid := id
		buttons.append({"text": label, "cb": func(): _set_path_and_back(cid, from_forge)})
	if from_forge:
		buttons.append({"text": Loc.t("path.later"), "cb": _show_forge_panel})
	else:
		buttons.append({"text": Loc.t("common.skills"), "cb": _go_skill_panel})
		buttons.append({"text": Loc.t("common.back"), "cb": _hub_back})
	_panel(Loc.t("path.panel_title"), body, buttons)


func _set_path_and_back(p: String, from_forge: bool) -> void:
	GameState.set_path_style(p)
	## 發招 + starter 武器 → PathLoadout
	PathLoadout.apply_path_choice(GameState.path_style)
	var d: Dictionary = DataTables.weapon_class_def(GameState.path_style)
	var tip := str(d.get("play", ""))
	var pros: Array = d.get("pros", [])
	var pro0 := str(pros[0]) if pros.size() > 0 else ""
	SaveManager.save_game()
	_play_dialog(DialogLines.lines("forge.path_chosen", {
		"path": GameState.path_display(),
		"play": tip,
		"pro": pro0,
		"power": GameState.power_score(),
	}), func():
		if from_forge:
			_show_forge_panel()
		else:
			_go_path_panel(false)
	)


func _forge_wood_sword() -> void:
	if GameState.gold < 20:
		_play_dialog(DialogLines.lines("forge.wood_sword_no_gold"), _show_forge_panel)
		return
	if GameState.has_flag("item.wood_sword") or GameState.has_flag("c1_sprout_done"):
		_play_dialog(DialogLines.lines("forge.wood_sword_owned"), _show_forge_panel)
		return
	_play_dialog([
		{"speaker": _t("釘釘"), "text": _t("……木劍？給那個小崽子的？")},
		{"speaker": _t("釘釘"), "text": _t("哼。三錘。別指望我雕花。")},
		{"speaker": _t("系統"), "text": _t("獲得【練習木劍】。拿去給小芽。")},
	], func():
		GameState.gold -= 20
		GameState.set_flag("item.wood_sword", true)
		SaveManager.save_game()
		_show_forge_panel()
	)


## 鍛造的階數上限。設計是 T1～T15（PROGRESSION 2.2），三個月切片先做到 T8，
## 而魂槽門檻寫的是 T1／T6／T11 —— 於是第三個魂槽永遠開不了。
## 開到 T11 讓那個承諾兌現得了，也讓金幣在後期還有地方去。
const FORGE_MAX_TIER := 11

## 升階價 = 這個數 × 目前階數。
##
## 原本每一階都是固定 50 金：T2 打到封頂總共約 430 金，比一趟野外來回還便宜。
## 而全遊戲有 24 個收入點、5 個支出點，實測一趟通關收入 10328、支出 1480 ——
## 金幣是單向累積的，中期之後永遠花不完，於是「賺錢」對三條養成柱都失去意義。
## 改成隨階漲價之後，T2→T11 約要 3500 金，後期的每一場戰鬥又開始有理由打。
const FORGE_COST_PER_TIER := 40


func forge_cost() -> int:
	return FORGE_COST_PER_TIER * maxi(1, GameState.weapon_tier)


## 成功率隨階下降（PROGRESSION 2.2 寫了但沒實作，之前是固定 0.70）。
## 連敗 3 次保底成功那條還在，所以最壞情況仍然是四次一定升。
func forge_rate_base() -> float:
	return maxf(0.45, 0.80 - 0.03 * float(GameState.weapon_tier - 1))


func _try_forge() -> void:
	if GameState.weapon_tier >= FORGE_MAX_TIER:
		_play_dialog(DialogLines.lines("forge.tier_max"), _show_forge_panel)
		return
	var cost := forge_cost()
	if GameState.gold < cost:
		_play_dialog(DialogLines.lines("forge.no_gold"), _show_forge_panel)
		return
	GameState.add_gold(-cost)
	var forge_rate := forge_rate_base()
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
		var scrap_s := _t("（耗鐵屑穩火）") if used_scrap else ""
		if AudioManager.has_method("play_craft_success"):
			AudioManager.play_craft_success()
		_play_dialog(DialogLines.lines("forge.success", {"tier": GameState.weapon_tier, "scrap": scrap_s}), _show_forge_panel)
	else:
		GameState.forge_fail_streak += 1
		if GameState.forge_fail_streak >= 3:
			## W4 釘釘摔錘（連敗 3 次 · 主線可截圖記憶點）
			GameState.forge_fail_streak = 0
			GameState.hp = mini(GameState.max_hp, GameState.hp + 15)
			AudioManager.play("break", 0.92, -2.0)
			ui_toast(_t("釘釘摔錘了"))
			GameLog.system(_t("釘釘摔錘 · 消氣餅"))
			_play_dialog(DialogLines.lines("forge.pity_break"), _show_forge_panel)
		else:
			_play_dialog(DialogLines.lines("forge.failed"), _show_forge_panel)
	SaveManager.save_game()


func _go_c1_wild() -> void:
	if not GameState.has_flag("c1_forged"):
		_play_dialog(DialogLines.lines("c1.wild_need_forge"))
		return
	## 起步安全網：第一次進荒野時若身上不夠打一把器，補一筆。
	## 原本沒有旗標，於是每次金幣低於 100 走進荒野就 +120 —— 那是個無限水龍頭，
	## 玩家永遠不會缺錢，經濟的下限直接消失。
	## 補到 120，而不是「不足就 +120」。
	##
	## 原本是「金幣 < 100 就加 120」，於是在荒野入口身上有 100~189 金的玩家
	## 反而比什麼都不撿的玩家窮 —— 什麼都不撿 70+120=190，
	## 撿了一個 40 金寶箱變成 110、拿不到補助。安全網懲罰了會探索的人，
	## 而且完全看不見。改成「補到 120」：撿得多的一定不會比較少。
	if not GameState.has_flag("meta.wild_stipend"):
		GameState.set_flag("meta.wild_stipend", true)
		if GameState.gold < 120:
			GameState.add_gold(120 - GameState.gold)
	_open_explore("wild", Screen.C1_WILD)


func _interact_wild(id: String) -> void:
	match id:
		"back_town":
			_go_c1_town()
		"camp", "burnt_field":
			_play_dialog(DialogLines.lines("c1.burnt_field"))
		"scarecrow":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.scarecrow")}])
		"rubble":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.rubble")}])
		"trail_mark":
			_play_dialog([{"speaker": _t("旁白"), "text": Loc.t("flavor.trail")}])
		"tower":
			if GameState.has_flag("c1_tower_loot"):
				_play_dialog(DialogLines.lines("c1.tower_empty"))
			else:
				_play_dialog([
					{"speaker": _t("系統"), "text": _t("廢棄哨塔裡摸到幾枚舊幣。金幣 ＋40。")},
				], func():
					GameState.add_gold(40)
					GameState.set_flag("c1_tower_loot", true)
					SaveManager.save_game()
				)
		"wild_shrine":
			_play_dialog(DialogLines.lines("c1.wild_shrine"))
		"supply_crate":
			if GameState.has_flag("c1_crate_loot"):
				_play_dialog(DialogLines.lines("c1.crate_empty"))
			else:
				_play_dialog([
					{"speaker": _t("系統"), "text": _t("補給箱裡有繃帶與乾糧。回復一些傷勢，金幣 ＋20。")},
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
				_play_dialog(DialogLines.lines("c1.leo_gate_cleared"))
			else:
				_play_dialog([
					{"speaker": _t("灰鬚"), "text": _t("（若有回音）獅子不聽人話。聽刀。")},
					{"speaker": _t("灰鬚"), "text": _t("你不是去證明你強。你是去讓它想起——它該守什麼。")},
					{"speaker": _t("雷歐"), "text": _t("傭兵團把最弱的送來了？也想挑戰騎士之王？")},
					{"speaker": _t("系統"), "text": _t("王者斬一定要擋。地上冒出火圈時會先亮一下，那時按 J 跳開。")},
				], func(): _start_battle("leo"))


func _go_leo_win() -> void:
	_grant_boss_loot(80, 4, 10)
	SkillSystem.grant_leo_insight()
	_play_dialog(DialogLines.lines("c1.leo_win"), _c1_leo_aftermath_cut)


func _c1_leo_aftermath_cut() -> void:
	_play_cutscene(_cutscene_art("c1_leo_after", [
		{
			"bg": "wild",
			"speaker": _t("旁白"),
			"portrait": _t("雷歐"),
			"text": _t("聖獅臥下。內殿的塵第一次安靜得像有人在禱告。"),
		},
		{
			"bg": "town",
			"speaker": _t("旁白"),
			"portrait": _t("灰鬚"),
			"text": _t("鏡頭只拍灰鬚的背影。門栓，被一隻不肯年輕的手拉開。"),
		},
		{
			"bg": "town",
			"speaker": _t("灰鬚"),
			"text": _t("……門為你開。去吧，小子。"),
		},
		{
			"bg": "town",
			"speaker": _t("旁白"),
			"portrait": _t("小芽"),
			"text": _t("廣場旗揚起歪扭兔爪印。東南方，霧正升起。"),
		},
	]), _go_aftermath)


func _go_aftermath() -> void:
	_current = Screen.C1_AFTERMATH
	GameState.set_flag("c1_gate_open_back", true)
	GameState.set_flag("c1_flag_paw", true)
	GameState.set_flag("cosmetic.gold_mane", true)
	GameState.set_flag("boss.leo_cleared", true)
	SaveManager.save_game()
	AudioManager.play_bgm("town")
	_panel(
		_t("雷歐之後"),
		_t("堡壘的門已開。\n廣場旗上有歪扭爪印——小芽說「差不多是你」。\n\n絲絨說：東南方霧起——忍者村。團裡的「看一眼」還沒寫完。\n\n體悟【怒雷】【反戈】· 外觀契機：金鬃。"),
		[
			{"text": _t("前往霧隱村（C2）"), "cb": _go_c2_enter},
			{"text": _t("回到廣場"), "cb": _go_c1_town},
			{"text": _t("出城荒野（霧道）"), "cb": _go_c1_wild},
			{"text": _t("存檔回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── C2 霧與真 ───

func _go_c2_enter() -> void:
	if not _try_soft_enter_region("mist"):
		return
	if not GameState.has_flag("boss.leo_cleared") and not GameState.has_flag("c2_soft_warn"):
		GameState.set_flag("c2_soft_warn", true)
		_play_dialog([
			{"speaker": _t("系統"), "text": _t("還沒打贏雷歐也能進霧，只是白霧會很硬。要不要先去鍛造、練練身手，或回內殿再試一次？")},
		], func(): _go_c2_enter_body())
		return
	_go_c2_enter_body()


func _go_c2_enter_body() -> void:
	GameState.set_chapter("c2")
	if not GameState.has_flag("c2_entered"):
		GameState.set_flag("c2_entered", true)
		_play_cutscene(_cutscene_art("c2_enter", [
			{
				"bg": "town",
				"speaker": _t("旁白"),
				"portrait": _t("小白"),
				"text": _t("東南方的霧，像有人把世界的邊縫撕開一角。"),
			},
			{
				"bg": "mist_village",
				"speaker": _t("旁白"),
				"portrait": _t("霧隱"),
				"text": _t("村口沒有門——只有霧。真假同色，腳下也是。"),
			},
			{
				"bg": "mist_village",
				"speaker": _t("霧隱"),
				"text": _t("……傭兵團最弱的？眼睛，借我用用。"),
			},
		]), func():
			## N8 延遲的信：進村後主線強制先讀，不可漏
			_play_dialog(DialogLines.lines("c2.arrive"), _c2_force_letter_then_mist)
		)
	else:
		_go_c2_mist()


func _c2_force_letter_then_mist() -> void:
	if StoryAnchors.has_wheat_letter():
		_go_c2_mist()
		return
	_c2_play_wheat_letter(func():
		_go_c2_mist()
	)


func _go_c2_mist() -> void:
	SaveManager.save_game()
	## 備援：舊存檔／捷徑進村尚未讀信 → 直接播 N8，不靠玩家記得找客棧
	if not StoryAnchors.has_wheat_letter():
		_open_explore_then("mist_village", Screen.C2_MIST, func():
			_c2_play_wheat_letter(Callable())
		)
	else:
		_open_explore("mist_village", Screen.C2_MIST)


func _interact_mist(id: String) -> void:
	match id:
		"fog_hide":
			_side_start_fog_letter()
		"inn":
			_c2_inn_letter()
		"lantern":
			_play_dialog(DialogLines.lines("c2.lantern"))
		"well_fog":
			_play_dialog(DialogLines.lines("c2.well_fog"))
		"laundry":
			_play_dialog(DialogLines.lines("c2.laundry"))
		"cat_shadow":
			_play_dialog(DialogLines.lines("c2.cat_shadow"))
		"shrine":
			_play_dialog(DialogLines.lines("c2.shrine"))
		"train":
			if not GameState.has_flag("c2_wheat_letter"):
				_play_dialog(DialogLines.lines("c2.train_need_letter"))
			else:
				_play_dialog(DialogLines.lines("c2.train_tip"))
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
	if StoryAnchors.has_wheat_letter():
		_play_dialog(DialogLines.lines("c2.letter_reread"))
		return
	_c2_play_wheat_letter(Callable())


## N8 延遲的信正文 → StoryAnchors.wheat_letter_lines（進村強制／客棧共用）
func _c2_play_wheat_letter(after: Callable = Callable()) -> void:
	_play_dialog(StoryAnchors.wheat_letter_lines(), func():
		StoryAnchors.mark_wheat_letter_read()
		SaveManager.save_game()
		ui_toast(_t("日誌：麥穗的字"))
		GameLog.system(_t("讀到麥穗的信——我還在"))
		AudioManager.play("reveal", 1.0, -4.0)
		if after.is_valid():
			after.call()
	)


func _c2_try_fog_boss() -> void:
	if not GameState.has_flag("c2_wheat_letter"):
		_play_dialog(DialogLines.lines("c2.fog_need_letter"))
		return
	if GameState.has_flag("boss.white_fog_cleared"):
		_play_dialog(DialogLines.lines("c2.fog_cleared"))
		return
	_play_dialog([
		{"speaker": _t("白霧"), "text": _t("嘻嘻～真的假的，你分得清嗎？")},
		{"speaker": _t("系統"), "text": _t("用 Tab 鎖住本體，等牠發白再出手。砍到幻影會被反咬，還會被寒意拖慢。")},
	], func(): _start_battle("fog"))


func _go_fog_win() -> void:
	_grant_boss_loot(70, 4, 8)
	_play_dialog(DialogLines.lines("c2.fog_win"), _c2_fog_clear_cut)


func _c2_fog_clear_cut() -> void:
	_play_cutscene(_cutscene_art("c2_fog_clear", [
		{
			"bg": "mist_village",
			"speaker": _t("旁白"),
			"portrait": _t("霧隱"),
			"text": _t("霧退成薄紗。村影第一次站穩腳跟。"),
		},
		{
			"bg": "mist_village",
			"speaker": _t("內心"),
			"text": _t("麥穗的字還在：我還在。那我就還能走。"),
		},
		{
			"bg": "dojo",
			"speaker": _t("旁白"),
			"portrait": _t("阿茶"),
			"text": _t("遠山鐘響。茶煙升起——武鬥道場在召喚。"),
		},
	]), _go_c2_cleared_panel)


func _go_c2_cleared_panel() -> void:
	GameState.set_flag("cosmetic.mist_fur", true)
	GameState.set_flag("boss.white_fog_cleared", true)
	SaveManager.save_game()
	AudioManager.play_bgm("mist")
	_panel(
		_t("C2 完成 · 霧與真"),
		_t("你看破了白霧。\n麥穗的字還在心上：我還在。\n\n遠山鐘響——武鬥道場在召喚。"),
		[
			{"text": _t("前往道場（C3）"), "cb": _go_c3_enter},
			{"text": _t("回霧隱村"), "cb": _go_c2_mist},
			{"text": _t("回騎士堡"), "cb": _go_c1_town},
			{"text": _t("存檔回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
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
			_play_dialog(DialogLines.lines("region.mist_locked"))
			return false
		"dojo":
			if GameState.has_flag("boss.white_fog_cleared") or GameState.has_flag("boss.leo_cleared") or power >= 26:
				return true
			_play_dialog(DialogLines.lines("region.dojo_warn", {"power": power}))
			return false
		"forest":
			if GameState.has_flag("boss.abo_cleared") or GameState.has_flag("boss.leo_cleared") or power >= 30:
				return true
			_play_dialog(DialogLines.lines("region.forest_warn", {"power": power}))
			return false
		"coast":
			if GameState.has_flag("boss.abo_cleared") or GameState.has_flag("boss.leo_cleared") or power >= 30:
				return true
			_play_dialog(DialogLines.lines("region.coast_warn", {"power": power}))
			return false
		_:
			return true


func _go_c3_enter() -> void:
	if not _try_soft_enter_region("dojo"):
		return
	if not GameState.has_flag("boss.white_fog_cleared") and not GameState.has_flag("c3_soft_warn"):
		GameState.set_flag("c3_soft_warn", true)
		_play_dialog(DialogLines.lines("c3.soft_warn", {"power": GameState.power_score()}), func(): _go_c3_enter_body())
		return
	_go_c3_enter_body()


func _go_c3_enter_body() -> void:
	GameState.set_chapter("c3")
	if not GameState.has_flag("c3_entered"):
		GameState.set_flag("c3_entered", true)
		_play_cutscene(_cutscene_art("c3_enter", [
			{
				"bg": "mist_village",
				"speaker": _t("旁白"),
				"text": _t("山道把霧踩在腳下。鐘聲一層一層，從雲裡落下。"),
			},
			{
				"bg": "dojo",
				"speaker": _t("旁白"),
				"portrait": _t("阿茶"),
				"text": _t("山門。茶煙。木魚聲很慢——像有人在等你喘口氣。"),
			},
			{
				"bg": "dojo",
				"speaker": _t("阿茶"),
				"text": _t("客從霧裡來？傭兵團的……最弱那個？宗師在試煉堂。他不先出手，他先問。"),
			},
		]), func():
			_play_dialog(DialogLines.lines("c3.arrive"), _go_c3_dojo)
		)
	else:
		_go_c3_dojo()


func _go_c3_dojo() -> void:
	SaveManager.save_game()
	_open_explore("dojo", Screen.C3_DOJO)


func _interact_dojo(id: String) -> void:
	match id:
		"acha":
			_play_dialog(NpcLines.for_npc("acha"))
		"gate_bell":
			_play_dialog(DialogLines.lines("c3.gate_bell"))
		"training_dummy":
			if GameState.has_flag("c3_dummy_hit"):
				_play_dialog(DialogLines.lines("c3.dummy_done"))
			else:
				_play_dialog([
					{"speaker": _t("系統"), "text": _t("你朝木人樁連打三下。木屑飛起。")},
					{"speaker": _t("內心"), "text": _t("一下一下……殼會鬆。")},
				], func():
					GameState.set_flag("c3_dummy_hit", true)
					GameState.stardust += 1
					SaveManager.save_game()
				)
		"scroll_wall":
			_play_dialog(DialogLines.lines("c3.scroll_wall"))
		"stone_garden":
			_play_dialog(DialogLines.lines("c3.stone_garden"))
		"tea":
			_play_dialog([
				{"speaker": _t("阿茶"), "text": _t("喝一口吧。今天火候壓得低，回甘慢。")},
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
		_play_dialog(DialogLines.lines("c3.abo_cleared"))
		return
	_play_dialog([
		{"speaker": _t("阿波"), "text": _t("傭兵團最弱的。來打我的架勢。")},
		{"speaker": _t("阿波"), "text": _t("打不穿的時候，別急——一下一下，把殼撞鬆。頭銜撞不開。")},
		{"speaker": _t("系統"), "text": _t("先把他的架勢打散，散開的那陣子傷害吃得滿。但他也會出重拳，記得擋。")},
	], func(): _start_battle("abo"))


func _go_abo_win() -> void:
	_grant_boss_loot(90, 5, 10)
	var extra := ""
	if GameState.has_flag("c3_abo_perfect"):
		extra = _t("你的拳裡，有道了——架勢被你連破兩次。")
	else:
		extra = _t("你的拳裡，開始有道了。")
	_play_dialog([
		{"speaker": _t("阿波"), "text": extra},
		{"speaker": _t("阿波"), "text": _t("（指尖在你眉心一點）最後的試煉在塔頂——去吧，別回頭。團裡若問，就說：你答過為何而戰。")},
		{"speaker": _t("阿茶"), "text": _t("（茶香）路上要是聞到這個味道，就是走對了。")},
		{"speaker": _t("系統"), "text": _t("金 90、星屑 5，體力上限多 10。毛裡泛出玉光。往塔的路開了。")},
	], _c3_abo_clear_cut)


func _c3_abo_clear_cut() -> void:
	_play_cutscene(_cutscene_art("c3_abo_clear", [
		{
			"bg": "dojo",
			"speaker": _t("旁白"),
			"portrait": _t("阿波"),
			"text": _t("試煉堂的塵落定。拳印在木地板上，像誰寫下的「道」。"),
		},
		{
			"bg": "dojo",
			"speaker": _t("阿茶"),
			"text": _t("茶還熱著。他……終於肯看你一眼了。"),
		},
		{
			"bg": "tower",
			"speaker": _t("旁白"),
			"portrait": _t("小白"),
			"text": _t("西林有風，東岸有石——塔尖仍掛著不肯散的黑焰。"),
		},
	]), _go_c3_cleared_panel)


func _go_c3_cleared_panel() -> void:
	GameState.set_flag("boss.abo_cleared", true)
	GameState.set_flag("c3_montage_done", true)
	GameState.set_flag("cosmetic.jade_fur", true)
	SaveManager.save_game()
	AudioManager.play_bgm("dojo")
	_panel(
		_t("C3 完成 · 拳中有道"),
		_t("阿波認可了你——不問頭銜，問為何而戰。\n鐘聲落盡。\n\n西林有風在等——疾影；東岸有石在吼——石拳。\n亦可直上法師之塔（最短通關）。"),
		[
			{"text": _t("遊俠森林（C4·疾影）"), "cb": _go_c4_enter},
			{"text": _t("維京海岸（C5·石拳）"), "cb": _go_c5_enter},
			{"text": _t("直上塔下營地（C6）"), "cb": _go_c6_camp},
			{"text": _t("回道場走走"), "cb": _go_c3_dojo},
			{"text": _t("存檔回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── C4 遊俠森林 · 疾影 ───

func _go_c4_enter() -> void:
	if not _try_soft_enter_region("forest"):
		return
	GameState.set_chapter("c4")
	if not GameState.has_flag("c4_entered"):
		GameState.set_flag("c4_entered", true)
		_play_cutscene(_cutscene_art("c4_enter", [
			{
				"bg": "dojo",
				"speaker": _t("旁白"),
				"text": _t("西林的風比鐘聲更急。團裡最弱的那個，被風先看見。"),
			},
			{
				"bg": "forest",
				"speaker": _t("旁白"),
				"portrait": _t("風耳"),
				"text": _t("樹影交錯。風箏線斷在半空——線頭還在顫。"),
			},
			{
				"bg": "forest",
				"speaker": _t("風耳"),
				"text": _t("站住。追風的人，最後都會迷路。傭兵團的？腳步比風慢。——正好。"),
			},
		]), func():
			_play_dialog(DialogLines.lines("c4.arrive"), _go_c4_forest)
		)
	else:
		_go_c4_forest()


func _go_c4_forest() -> void:
	SaveManager.save_game()
	_open_explore("forest", Screen.C4_FOREST)


func _interact_forest(id: String) -> void:
	match id:
		"wind_ear":
			_play_dialog(NpcLines.for_npc("wind_ear_idle"))
		"treehouse":
			_play_dialog(DialogLines.lines("c4.treehouse"))
		"kite_stuck":
			if GameState.has_flag("c4_kite_freed"):
				_play_dialog(DialogLines.lines("c4.kite_freed"))
			else:
				_play_dialog([
					{"speaker": _t("旁白"), "text": _t("風箏卡在枝桠。你小心地扯下線。")},
					{"speaker": _t("孩童"), "text": _t("謝謝你！……風還會回來，但線在就好。")},
					{"speaker": _t("系統"), "text": _t("獲得星屑 ×2。")},
				], func():
					GameState.stardust += 2
					GameState.set_flag("c4_kite_freed", true)
					SaveManager.save_game()
				)
		"stream":
			_play_dialog(DialogLines.lines("c4.stream"))
		"owl_post":
			_play_dialog(DialogLines.lines("c4.owl_post"))
		"arrow_path":
			if GameState.has_flag("c4_arrow_tip"):
				_play_dialog(DialogLines.lines("c4.arrow_path_done"))
			else:
				_play_dialog([
					{"speaker": _t("旁白"), "text": _t("箭道地面一道淺痕——風曾割過這裡。")},
					{"speaker": _t("系統"), "text": _t("風要切過來之前會先響一聲。聽到就按 J 讓開。")},
				], func():
					GameState.set_flag("c4_arrow_tip", true)
					SaveManager.save_game()
				)
		"watch_tower":
			_play_dialog(DialogLines.lines("c4.watch_tower"))
		"herb_slope":
			if GameState.has_flag("c4_herb_loot"):
				_play_dialog(DialogLines.lines("c4.herb_looted"))
			else:
				_play_dialog([
					{"speaker": _t("系統"), "text": _t("採到幾把帶風味的藥草。換了些金幣。")},
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
		_play_dialog(DialogLines.lines("c4.falcon_cleared"))
		return
	_play_dialog([
		{"speaker": _t("疾影"), "text": _t("……傭兵團把最慢的送來了？眼睛，跟得上我嗎？")},
		{"speaker": _t("疾影"), "text": _t("追，會迷路。等，才見我。頭銜追不上風。")},
		{"speaker": _t("系統"), "text": _t("牠停下來的那一拍才吃滿傷害。風聲響起就按 J。")},
	], func(): _start_battle("falcon"))


func _go_falcon_win() -> void:
	_grant_boss_loot(85, 4, 8)
	_play_dialog(DialogLines.lines("c4.falcon_win"), _c4_falcon_clear_cut)


func _c4_falcon_clear_cut() -> void:
	_play_cutscene(_cutscene_art("c4_falcon_clear", [
		{
			"bg": "forest",
			"speaker": _t("旁白"),
			"portrait": _t("疾影"),
			"text": _t("銀羽在光裡轉。風第一次，為傭兵團最弱的那個停了半拍。"),
		},
		{
			"bg": "coast",
			"speaker": _t("旁白"),
			"portrait": _t("石拳"),
			"text": _t("東岸有浪在吼——力氣，還要找方向。團裡沒規定你非去不可。"),
		},
	]), _go_c4_cleared_panel)


func _go_c4_cleared_panel() -> void:
	GameState.set_flag("boss.shadowwind_cleared", true)
	GameState.set_flag("cosmetic.gale_fur", true)
	SaveManager.save_game()
	AudioManager.play_bgm("forest")
	_panel(
		_t("C4 完成 · 風之試煉"),
		_t("你等來了疾影的停拍——不是追上風，是風肯為新人停半拍。\n林旗揚起，銀羽在光裡轉。\n\n東岸石拳仍在吼——或直上塔。團裡若問，就說：你等過風。"),
		[
			{"text": _t("維京海岸（C5）"), "cb": _go_c5_enter},
			{"text": _t("塔下營地（C6）"), "cb": _go_c6_camp},
			{"text": _t("回森林走走"), "cb": _go_c4_forest},
			{"text": _t("回道場"), "cb": _go_c3_dojo},
			{"text": _t("存檔回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
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
		_play_cutscene(_cutscene_art("c5_enter", [
			{
				"bg": "forest",
				"speaker": _t("旁白"),
				"text": _t("林盡是鹽。團裡最弱的那個，被浪先打濕。"),
			},
			{
				"bg": "coast",
				"speaker": _t("旁白"),
				"portrait": _t("石拳"),
				"text": _t("浪打空岸。碼頭木樁上插著斧，斧柄還在抖。"),
			},
			{
				"bg": "coast",
				"speaker": _t("潮吼"),
				"portrait": _t("潮吼"),
				"text": _t("傭兵團的？岸上不比腕力——比你敢不敢迎上去。"),
			},
		]), func():
			_play_dialog(DialogLines.lines("c5.arrive"), _go_c5_coast)
		)
	else:
		_go_c5_coast()


func _go_c5_coast() -> void:
	SaveManager.save_game()
	_open_explore("coast", Screen.C5_COAST)


func _interact_coast(id: String) -> void:
	match id:
		"tide_roar":
			_play_dialog(NpcLines.for_npc("tide_roar_idle"))
		"dock":
			_play_dialog(DialogLines.lines("c5.dock"))
		"boat_wreck":
			_play_dialog(DialogLines.lines("c5.boat_wreck"))
		"net_rack":
			_play_dialog(DialogLines.lines("c5.net_rack"))
		"runestone":
			_play_dialog(DialogLines.lines("c5.runestone"))
		"forge_c5":
			if GameState.has_flag("c5_forge_tip"):
				_play_dialog(DialogLines.lines("c5.forge_tip_done"))
			else:
				_play_dialog([
					{"speaker": _t("潮吼"), "text": _t("岸邊這爐還熱。釘釘那小子……不，你的刃夠用。")},
					{"speaker": _t("潮吼"), "text": _t("記住：最後一擊，是為了護，不是為了炫。")},
					{"speaker": _t("系統"), "text": _t("潮吼塞給你一袋岸礦。金幣＋60。")},
				], func():
					GameState.add_gold(60)
					GameState.set_flag("c5_forge_tip", true)
					SaveManager.save_game()
				)
		"cliff_path":
			_play_dialog(DialogLines.lines("c5.cliff_path"))
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
		_play_dialog(DialogLines.lines("c5.boar_cleared"))
		return
	_play_dialog([
		{"speaker": _t("石拳"), "text": _t("傭兵團把最弱的送來了？還站著？那就接下這一拳——")},
		{"speaker": _t("石拳"), "text": _t("力氣該砸向誰？頭銜砸不開岸。")},
		{"speaker": _t("系統"), "text": _t("他衝過來時按 J 硬碰，岩甲會一層層裂開。落石時一樣按 J 找掩護。")},
	], func(): _start_battle("boar"))


func _go_boar_win() -> void:
	_grant_boss_loot(95, 5, 10)
	_play_dialog(DialogLines.lines("c5.boar_win"), _c5_boar_clear_cut)


func _c5_boar_clear_cut() -> void:
	_play_cutscene(_cutscene_art("c5_boar_clear", [
		{
			"bg": "coast",
			"speaker": _t("旁白"),
			"portrait": _t("石拳"),
			"text": _t("浪聲如鼓。岩甲碎在沙上，像誰終於放下拳頭。"),
		},
		{
			"bg": "tower",
			"speaker": _t("旁白"),
			"portrait": _t("小白"),
			"text": _t("五柱中四柱已醒。塔門開了一縫——不是為預言，是為還肯站著的人。"),
		},
	]), _go_c5_cleared_panel)


func _go_c5_cleared_panel() -> void:
	GameState.set_flag("boss.stonefist_cleared", true)
	GameState.set_flag("cosmetic.ember_fur", true)
	SaveManager.save_game()
	AudioManager.play_bgm("coast")
	_panel(
		_t("C5 完成 · 岸上最後一擊"),
		_t("石拳記起了力氣的方向——不是砸人，是護岸。團裡最弱的那個，迎上去了。\n岸旗燃起，浪聲如鼓。\n\n五柱中四柱已醒——塔門在等。團裡若問，就說：你把力氣對準了。"),
		[
			{"text": _t("前往塔下營地（C6）"), "cb": _go_c6_camp},
			{"text": _t("回海岸走走"), "cb": _go_c5_coast},
			{"text": _t("回森林"), "cb": _go_c4_forest},
			{"text": _t("存檔回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


func _go_c3_montage() -> void:
	## 保留捷徑：跳過道場直接開塔（開發／重玩用）
	_current = Screen.C3_MONTAGE
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("山門。茶煙。一頭熊貓不發一掌，只問：你，為何而戰？")},
		{"speaker": _t("內心"), "text": _t("因為還有人在等。因為我還沒回去。")},
		{"speaker": _t("旁白"), "text": _t("鐘響。道，暫記一筆。路，繼續向塔。")},
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
			_play_dialog(DialogLines.lines("c6.bell_not_rung"), _go_c3_enter)
			return
		_play_dialog(DialogLines.lines("c6.path_not_open"))
		return
	if not GameState.has_flag("c3_montage_done"):
		GameState.set_flag("c3_montage_done", true)
	if not GameState.has_flag("c6_camp_cut"):
		GameState.set_flag("c6_camp_cut", true)
		_play_cutscene(_cutscene_art("c6_camp", [
			{
				"bg": "tower",
				"speaker": _t("旁白"),
				"portrait": _t("小白"),
				"text": _t("塔影把世界壓成一條縫。逃難者的火堆在縫邊抖。"),
			},
			{
				"bg": "tower",
				"speaker": _t("旁白"),
				"portrait": _t("斷頁"),
				"text": _t("有人在抄卷——字跡比手還抖。塔門……開了。千年來第一次。"),
			},
			{
				"bg": "tower",
				"speaker": _t("斷頁"),
				"text": _t("傭兵團把最弱的送到塔下了。卷軸寫至弱——我信的是你走到這裡的腳印。"),
			},
		]), _show_c6_camp_panel)
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
		{"speaker": _t("斷頁"), "text": _t("塔門……開了。千年來第一次。")},
		{"speaker": _t("斷頁"), "text": _t("你若上去，卷軸只能寫到這裡。其餘——你自己走完。")},
		{"speaker": _t("斷頁"), "text": _t("預言寫至弱。我信的不是預言。是你走到這裡的腳印。")},
	]
	if GameState.has_flag("c2_wheat_letter"):
		lines.append({"speaker": _t("斷頁"), "text": _t("……信比卷軸真。記得回家的氣味。")})
	if GameState.has_flag("c1_sprout_done"):
		lines.append({"speaker": _t("斷頁"), "text": _t("城裡有個孩子在練木劍。世界還肯長出明天。")})
	if GameState.has_flag("side.ding_debt_done"):
		lines.append({"speaker": _t("斷頁"), "text": _t("鐵匠把舊債錘進爐了。人情也是一種封印。")})
	if GameState.has_flag("side.fog_letter_done"):
		lines.append({"speaker": _t("斷頁"), "text": _t("真信比假卷軸稀。你送達過一封——我記在頁邊。")})
	if GameState.has_flag("side.ronin_spared"):
		lines.append({"speaker": _t("斷頁"), "text": _t("營火邊多了一個收刃的人。他不說話，但火更穩。")})
	elif GameState.has_flag("side.ronin_defeated"):
		lines.append({"speaker": _t("斷頁"), "text": _t("岔路的燒痕淡了。有人用強解決了強——也行。")})
	if GameState.has_flag("boss.shadowwind_cleared") and GameState.has_flag("boss.stonefist_cleared"):
		lines.append({"speaker": _t("斷頁"), "text": _t("風與石都醒了。塔頂……會記得你。")})
	_play_dialog(lines)


func _c6_floor_shadow() -> void:
	_play_dialog(DialogLines.lines("c6.floor_shadow"), _c6_floor_blade)


func _c6_floor_blade() -> void:
	var lines: Array = [
		{"speaker": _t("旁白"), "text": _t("器之廳。壁畫上一柄古劍，紋路與微末之刃相同。")},
		{"speaker": _t("內心"), "text": _t("紋……一樣。")},
		{"speaker": _t("日誌"), "text": _t("古刃銘：微末。持之者，再未歸村。")},
	]
	if GameState.has_flag("c1_ding_recognized_sword"):
		lines.append({"speaker": _t("內心"), "text": _t("釘釘當時停住的兩秒……他認得葬過一次的鐵。")})
	lines.append({"speaker": _t("系統"), "text": _t("劍微微發熱。名之廳在上方。")})
	_play_dialog(lines, _c6_truth_hall)


func _c6_truth_hall() -> void:
	_play_dialog([
		{"speaker": _t("旁白"), "text": _t("名之廳。黑焰如靜海。中央一道將散未散的影。")},
		{"speaker": "？？？", "text": _t("你走到這裡了。和我一樣輕。一樣……不該慕強。")},
		{
			"speaker": "？？？",
			"text": _t("……你想問什麼？"),
			"choices": [_t("你是誰？"), _t("你是魔王？"), _t("（沉默）")],
			"replies": [
				_t("名字早就燒光了。他們後來只叫我——魔王。"),
				_t("魔王是他們給的稱號。以前……我也只是個很輕的人。"),
				_t("……沉默也好。言語省一點，心就慢一點死。"),
			],
		},
		{"speaker": "？？？", "text": _t("封印要塌時，我吞下黑焰，用野心當柴，把塔再撐了一千年。")},
		{"speaker": "？？？", "text": _t("至弱者可以到塔頂。卷上沒寫的是——若至弱也開始慕強，心會先死。")},
		{"speaker": "？？？", "text": _t("那柄劍……也是我的。或者說，是「我們這種人」的。")},
		{"speaker": "？？？", "text": _t("鐵匠若沉默，是因為他認得出葬過一次的鐵。")},
		{"speaker": "？？？", "text": _t("現在輪到你。來吧。證明你有另一條路——或者，像我一樣，把世界扛在錯誤的力氣上。")},
	], func():
		GameState.set_flag("c6_truth_revealed", true)
		SaveManager.save_game()
		_panel(
			_t("決戰之前"),
			_t("真相已揭開。\n魔王曾是第一位至弱者。\n\n黑焰外殼正在合攏……"),
			[
				{"text": _t("迎戰魔王"), "cb": func(): _start_battle("demon")},
			]
		)
	)


func _go_demon_win() -> void:
	_grant_boss_loot(150, 8, 0)
	GameState.hp = GameState.effective_max_hp()
	_play_dialog(DialogLines.lines("c6.demon_win"), _c6_ending_cut)


func _c6_ending_cut() -> void:
	_play_cutscene(_cutscene_art("c6_ending", [
		{
			"bg": "tower",
			"speaker": _t("旁白"),
			"portrait": _t("魔王"),
			"text": _t("黑焰外殼裂開。裡面不是神——是一個也曾渺小的背影。"),
		},
		{
			"bg": "tower",
			"speaker": _t("旁白"),
			"portrait": _t("小白"),
			"text": _t("五道星光升起。塔尖第一次，像為誰讓路。"),
		},
		{
			"bg": "village",
			"speaker": _t("旁白"),
			"portrait": _t("麥穗"),
			"text": _t("遠方，有人還在等。氣味比卷軸近。"),
		},
	]), _go_ending)


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
	## 通關燭火（有連線才同步；失敗不擋結局）
	if OnlineGate.is_signed_in() and not GameState.has_flag("online.candle_lit"):
		OnlineGate.candle_increment(func(res: Dictionary):
			if bool(res.get("ok", false)) or res.has("total"):
				GameState.set_flag("online.candle_lit", true)
				SaveManager.save_game()
		)
	else:
		OnlineGate.refresh_candle_soft()
	AudioManager.play_bgm("ending")
	var maisui_line := _t("「還在啊。」")
	if GameState.wheat_stalk_broken or GameState.has_flag("c0_wheat_saved"):
		maisui_line = _t("「還在啊。早說了是氣味。」")
	var ding_line := ""
	if GameState.has_flag("c1_ding_recognized_sword"):
		ding_line = _t("\n釘釘：「鐵還在就好。——別再讓我認第二次葬過的鐵。」")
	var star_line := ""
	if GameState.has_flag("c6_refuse_all"):
		star_line = _t("\n星讀：「你的拒絕，比任何戰魂都亮。」")
	var ng_line := ""
	if GameState.ng_plus > 0:
		ng_line = _t("\n\n[b]黑焰迴響 ×%d 通關。[/b] 稱號：迴響行者。") % GameState.ng_plus
		if GameState.stain_flame:
			ng_line += _t(" 沾焰灰邊仍在。")
	var title_pop := ""
	if not new_titles.is_empty():
		title_pop = _t("\n\n新稱號：%s") % "、".join(new_titles)
	_panel(
		_t("終章 · 晨光"),
		_t("黑焰潰散的那一刻，法師之塔自塔頂裂開。\n五方聖獸卸下重擔，化作星辰。\n\n而那個曾經連劍都拔了三次才拔起的傭兵，站在晨光裡——\n不是因為變得多強，是因為從未把心餵給焰。\n\n麥穗：%s%s%s%s%s\n\n[b]通關。[/b] 塔外，黑焰裂縫仍在顫。") % [maisui_line, ding_line, star_line, ng_line, title_pop],
		[
			{"text": _t("黑焰裂縫（通關後）"), "cb": _go_postgame_hub},
			{"text": _t("稱號牆"), "cb": _go_title_wall},
			{"text": _t("黑焰迴響（再走一次）"), "cb": _go_ng_plus_menu},
			{"text": _t("再逛逛（騎士堡）"), "cb": _go_c1_town},
			{"text": _t("回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
		]
	)


# ─── 通關後 · 黑焰裂縫 ───

func _go_postgame_hub() -> void:
	## 通關後中樞：裂縫 + 獵場
	if not GameState.has_flag("game_cleared"):
		_play_dialog(DialogLines.lines("post.rift_not_open"))
		return
	GameState.set_flag("postgame.rift_unlocked", true)
	GameState.set_chapter("cleared")
	RiftSchedule.refresh_day()
	SaveManager.save_game()
	AudioManager.play_bgm("tower")
	var body: String = RiftSchedule.hub_status_text()
	body += _t("\n\n★＝本週焦點。有獎次數用盡後仍可練習。")
	var feat: String = RiftSchedule.featured_mode()
	var buttons: Array = [
		{"text": _t("本週焦點·%s") % RiftSchedule.featured_name(), "cb": func(): _go_rift_intro(feat)},
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
		{"text": _t("野外獵場"), "cb": func(): _open_explore("hunting_grounds", Screen.C1_WILD)},
		{"text": _t("塔下營地"), "cb": _go_c6_camp},
		{"text": _t("騎士堡"), "cb": _go_c1_town},
		{"text": _t("存檔回標題"), "cb": func(): SaveManager.save_game(); _go_title()},
	])
	buttons.insert(0, {"text": _t("黑焰迴響（NG+）"), "cb": _go_ng_plus_menu})
	buttons.insert(1, {"text": _t("稱號牆"), "cb": _go_title_wall})
	TitleCatalog.evaluate_all()
	_panel(_t("通關後 · 黑焰裂縫"), body, buttons)


func _go_rift_intro(mode: String) -> void:
	RiftSchedule.refresh_day()
	var rewarded: bool = RiftSchedule.daily_left() > 0
	var attempt_note: String
	if rewarded:
		attempt_note = _t("消耗 1 次今日有獎（剩餘將為 %d）。") % (RiftSchedule.daily_left() - 1)
		if RiftSchedule.is_featured(mode):
			attempt_note += _t(" 本週焦點：金幣×1.5。")
	else:
		attempt_note = _t("今日有獎已用盡——此為練習局（金幣大減、無經驗）。")
	var lines := {
		"wrath": [
			{"speaker": _t("旁白"), "text": _t("裂縫口。焰在無臉的輪廓裡顫。")},
			{"speaker": _t("系統"), "text": _t("火圈很密。閃不掉就會累積灼燒，疊到三層會炸開。跳出圈外能退掉一層。")},
		],
		"tide": [
			{"speaker": _t("旁白"), "text": _t("海水氣味的黑焰。刺胞鼓起又癟。")},
			{"speaker": _t("系統"), "text": _t("時間內解決三隻刺胞。本體會輪流擋掉普攻或技能傷害，看牠的樣子換手。")},
		],
		"statue": [
			{"speaker": _t("旁白"), "text": _t("三尊石像輪流亮起一隻眼。")},
			{"speaker": _t("系統"), "text": _t("只打會發光的那一尊。全部倒下，本體才會現身。落石時按 J。")},
		],
		"chrono": [
			{"speaker": _t("旁白"), "text": _t("地上的焰結成倒數的環。")},
			{"speaker": _t("系統"), "text": _t("炸彈亮起時按 J 拆掉。落石的時候記得躲。")},
		],
	}
	var arr: Array = lines.get(mode, [{"speaker": _t("系統"), "text": _t("裂縫張開。")}]).duplicate()
	arr.append({"speaker": _t("系統"), "text": attempt_note})
	_play_dialog(arr, func():
		RiftSchedule.consume_attempt()
		SaveManager.save_game()
		_start_battle(mode)
	)


func _go_rift_win(mode: String) -> void:
	GameState.hp = GameState.max_hp
	var wins := int(GameState.get_flag("postgame.rift_wins", 0))
	var mult: Dictionary = RiftSchedule.reward_mult(mode)
	var extra := ""
	if bool(mult.get("practice", false)):
		extra = _t("\n（練習局：獎勵已縮減）")
	elif bool(mult.get("featured", false)):
		extra = _t("\n（本週焦點加成已套用）")
	if GameState.has_flag("title.rift_walker"):
		extra += _t("\n（裂縫行者）焰裡也有你的節奏。")
	_play_dialog(DialogLines.lines("post.rift_win", {
		"mode": RiftSchedule.mode_name(mode),
		"wins": wins,
		"extra": extra,
	}), func():
		RiftSchedule.clear_attempt_flag()
		_go_postgame_hub()
	)
