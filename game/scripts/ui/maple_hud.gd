class_name MapleHud
extends Control
## 楓之谷風狀態板：可拖曳移動

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const WindowDrag = preload("res://scripts/ui/window_drag.gd")

var _panel: PanelContainer
var _name_l: Label
var _lv_l: Label
var _hp_bar: ProgressBar
var _hp_l: Label
var _mp_bar: ProgressBar
var _mp_l: Label
var _exp_bar: ProgressBar
var _gold_l: Label
var _tip_l: Label
var _drag_handle: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	## 不用 anchors 鎖死，改 position 以便拖曳
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0
	anchor_bottom = 0
	position = Vector2(8, 8)
	size = Vector2(220, 112)
	custom_minimum_size = Vector2(220, 112)
	_build()
	WindowDrag.attach(self, _drag_handle, "hud")
	call_deferred("_restore_layout")


func _restore_layout() -> void:
	if Engine.get_main_loop() is SceneTree:
		var ul: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiLayout")
		if ul and ul.has_method("apply_to"):
			ul.call("apply_to", self, "hud", Vector2(8, 8))


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_style_dark())
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)

	## 標題列可拖
	_drag_handle = PanelContainer.new()
	_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.88, 0.82, 0.68, 0.95)
	hs.set_corner_radius_all(2)
	hs.content_margin_left = 4
	hs.content_margin_right = 4
	hs.content_margin_top = 1
	hs.content_margin_bottom = 1
	_drag_handle.add_theme_stylebox_override("panel", hs)
	v.add_child(_drag_handle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_handle.add_child(row)

	_lv_l = Label.new()
	_lv_l.add_theme_font_size_override("font_size", 11)
	_lv_l.add_theme_color_override("font_color", UiStyle.GOLD)
	_lv_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_lv_l)

	_name_l = Label.new()
	_name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_l.add_theme_font_size_override("font_size", 13)
	_name_l.add_theme_color_override("font_color", UiStyle.INK)
	_name_l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.5))
	_name_l.add_theme_constant_override("shadow_offset_x", 1)
	_name_l.add_theme_constant_override("shadow_offset_y", 1)
	_name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_name_l)

	var drag_hint := Label.new()
	drag_hint.text = "⠿"
	drag_hint.add_theme_font_size_override("font_size", 10)
	drag_hint.add_theme_color_override("font_color", UiStyle.INK_DIM)
	drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(drag_hint)

	_hp_bar = _make_bar()
	UiStyle.style_progress(_hp_bar, UiStyle.HP_FILL, UiStyle.HP_BG)
	v.add_child(_hp_bar)
	_hp_l = Label.new()
	_hp_l.visible = false

	_mp_bar = _make_bar()
	UiStyle.style_progress(_mp_bar, UiStyle.MP_FILL, UiStyle.MP_BG)
	v.add_child(_mp_bar)
	_mp_l = Label.new()
	_mp_l.visible = false

	_exp_bar = _make_bar()
	_exp_bar.custom_minimum_size = Vector2(0, 8)
	UiStyle.style_progress(_exp_bar, UiStyle.EXP_FILL, UiStyle.EXP_BG)
	v.add_child(_exp_bar)

	_gold_l = Label.new()
	_gold_l.add_theme_font_size_override("font_size", 11)
	_gold_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
	_gold_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_gold_l)

	_tip_l = Label.new()
	_tip_l.add_theme_font_size_override("font_size", 10)
	_tip_l.add_theme_color_override("font_color", Color(0.45, 0.35, 0.2, 1))
	_tip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_l.text = "拖標題移動 · I背包 1-8快捷"
	v.add_child(_tip_l)


func _make_bar() -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 12)
	b.max_value = 100
	b.value = 100
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func refresh() -> void:
	if not is_inside_tree():
		return
	var name_s := str(GameState.player_name)
	if name_s == "":
		name_s = "小白"
	var tier: int = int(GameState.weapon_tier)
	var lv_approx: int = maxi(1, tier + 1 + (1 if GameState.has_flag("boss.leo_cleared") else 0) \
		+ (1 if GameState.has_flag("boss.white_fog_cleared") else 0) \
		+ (1 if GameState.has_flag("boss.abo_cleared") else 0))
	if GameState.ng_plus > 0:
		lv_approx += GameState.ng_plus * 5
	_lv_l.text = "Lv.%d" % lv_approx
	_name_l.text = name_s

	var max_hp: int = GameState.effective_max_hp()
	var hp: int = mini(GameState.hp, max_hp)
	_hp_bar.max_value = maxi(1, max_hp)
	_hp_bar.value = hp
	_hp_bar.tooltip_text = "HP %d / %d" % [hp, max_hp]

	var dust: int = int(GameState.stardust)
	var dust_cap: int = maxi(30, dust)
	_mp_bar.max_value = dust_cap
	_mp_bar.value = dust
	_mp_bar.tooltip_text = "星屑 %d" % dust

	var exp_v := 0.12
	match str(GameState.chapter):
		"c0":
			exp_v = 0.08
		"c1":
			exp_v = 0.22
		"c2":
			exp_v = 0.38
		"c3":
			exp_v = 0.52
		"c4":
			exp_v = 0.65
		"c5":
			exp_v = 0.78
		"c6":
			exp_v = 0.9
		"cleared":
			exp_v = 1.0
	if GameState.has_flag("boss.scar_lord_cleared"):
		exp_v = mini(1.0, exp_v + 0.03)
	_exp_bar.max_value = 100
	_exp_bar.value = exp_v * 100.0

	var claim := 0
	if Engine.get_main_loop() is SceneTree:
		var q: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("QuestSystem")
		if q and q.has_method("claimable_count"):
			claim = int(q.call("claimable_count"))
	var claim_s := "  待領%d" % claim if claim > 0 else ""
	var week := "一周目" if GameState.ng_plus <= 0 else "二周目×%d" % GameState.ng_plus
	_gold_l.text = "金 %d · %s · %s%s" % [GameState.gold, GameState.weapon_name, week, claim_s]
	_tip_l.text = "HP %d/%d · 星屑 %d · 拖移此窗" % [hp, max_hp, dust]
