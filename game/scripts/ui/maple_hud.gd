class_name MapleHud
extends Control
## Artale 風狀態板：白底卡片 · 粉紅標題列 · 可拖曳

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const WindowDrag = preload("res://scripts/ui/window_drag.gd")

var _panel: PanelContainer
var _name_l: Label
var _lv_l: Label
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _exp_bar: ProgressBar
var _gold_l: Label
var _tip_l: Label
var _drag_handle: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0
	anchor_bottom = 0
	position = Vector2(10, 10)
	size = Vector2(228, 118)
	custom_minimum_size = Vector2(228, 118)
	_build()
	WindowDrag.attach(self, _drag_handle, "hud")
	call_deferred("_restore_layout")


func _restore_layout() -> void:
	if Engine.get_main_loop() is SceneTree:
		var ul: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiLayout")
		if ul and ul.has_method("apply_to"):
			ul.call("apply_to", self, "hud", Vector2(10, 10))


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_style_dark())
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)

	## 標題列
	_drag_handle = PanelContainer.new()
	_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_drag_handle.add_theme_stylebox_override("panel", UiStyle.header_style())
	v.add_child(_drag_handle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_handle.add_child(row)

	_lv_l = Label.new()
	_lv_l.add_theme_font_size_override("font_size", 11)
	_lv_l.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	_lv_l.add_theme_constant_override("font_weight", 700)
	_lv_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_lv_l)

	_name_l = Label.new()
	_name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_l.add_theme_font_size_override("font_size", 13)
	_name_l.add_theme_color_override("font_color", UiStyle.INK)
	_name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_name_l)

	var drag_hint := Label.new()
	drag_hint.text = "⠿"
	drag_hint.add_theme_font_size_override("font_size", 11)
	drag_hint.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(drag_hint)

	_hp_bar = _make_bar(12)
	UiStyle.style_progress(_hp_bar, UiStyle.HP_FILL, UiStyle.HP_BG)
	v.add_child(_hp_bar)

	_mp_bar = _make_bar(10)
	UiStyle.style_progress(_mp_bar, UiStyle.MP_FILL, UiStyle.MP_BG)
	v.add_child(_mp_bar)

	_exp_bar = _make_bar(7)
	UiStyle.style_progress(_exp_bar, UiStyle.EXP_FILL, UiStyle.EXP_BG)
	v.add_child(_exp_bar)

	_gold_l = Label.new()
	_gold_l.add_theme_font_size_override("font_size", 11)
	_gold_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
	_gold_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_gold_l)

	_tip_l = Label.new()
	_tip_l.add_theme_font_size_override("font_size", 10)
	_tip_l.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	_tip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_tip_l)


func _make_bar(h: float = 10) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, h)
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
	var lv_real: int = maxi(1, int(GameState.level))
	_lv_l.text = "Lv.%d" % lv_real
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

	var need_xp: int = maxi(1, GameState.xp_to_next())
	_exp_bar.max_value = 100
	_exp_bar.value = clampf(float(GameState.xp) / float(need_xp) * 100.0, 0.0, 100.0)
	_exp_bar.tooltip_text = "經驗 %d／%d" % [GameState.xp, need_xp]

	var claim := 0
	if Engine.get_main_loop() is SceneTree:
		var q: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("QuestSystem")
		if q and q.has_method("claimable_count"):
			claim = int(q.call("claimable_count"))
	var claim_s := " · 待領%d" % claim if claim > 0 else ""
	var week := "一周目" if GameState.ng_plus <= 0 else "迴響×%d" % GameState.ng_plus
	_gold_l.text = "金 %d · 戰力 %d · %s%s" % [GameState.gold, GameState.power_score(), week, claim_s]

	var path_s := GameState.path_display() if GameState.path_style != "" else "未選流派"
	_tip_l.text = "%s · %s · Esc選單" % [GameState.weapon_name, path_s]
