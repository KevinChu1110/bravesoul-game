class_name UiStyle
extends RefCounted
## Artale 風格 UI：粉紅主色 · 白底卡片 · 深墨字 · 細線陰影
## 參考 artale.live 官網 token，適配 Godot 遊戲內 HUD／面板。

## ── Brand / Key（玫瑰粉）──
const KEY := Color(0.894, 0.518, 0.612, 1.0)       ## #e4849c
const KEY_STRONG := Color(0.761, 0.369, 0.451, 1.0) ## #c25e73
const KEY_DEEP := Color(0.659, 0.243, 0.333, 1.0)   ## #a83e55
const KEY_SOFT := Color(0.984, 0.890, 0.914, 1.0)   ## #fbe3e9
const KEY_FAINT := Color(0.992, 0.949, 0.961, 1.0)  ## #fdf2f5

## ── Surface / Wood dark ──
const WOOD_DARKEST := Color(0.125, 0.110, 0.125, 1.0) ## #201c20
const WOOD_DARK := Color(0.169, 0.149, 0.188, 1.0)    ## #2b2630
const WOOD_MID := Color(0.231, 0.200, 0.235, 1.0)     ## #3b333c
const WOOD := WOOD_DARK  ## 兼容舊呼叫
const WOOD_LIGHT := Color(0.55, 0.48, 0.55, 1.0)

## ── Paper / Ink ──
const PAPER := Color(0.969, 0.965, 0.973, 0.98)  ## #f7f6f8
const PAPER_SOFT := Color(1.0, 1.0, 1.0, 0.98)
const CREAM := Color(0.149, 0.141, 0.165, 1.0)  ## 標題字色＝ink
const CREAM_DIM := Color(0.42, 0.408, 0.439, 1.0)
const INK := Color(0.149, 0.141, 0.165, 1.0)    ## #26242a
const INK_DIM := Color(0.420, 0.408, 0.439, 1.0) ## #6b6870
const INK_FAINT := Color(0.647, 0.635, 0.671, 1.0)
const LINE := Color(0.863, 0.847, 0.878, 1.0)    ## #dcd8e0
const LINE_SOFT := Color(0.902, 0.886, 0.918, 1.0)

const GOLD := KEY_STRONG
const COPPER := KEY
const COPPER_DIM := KEY_STRONG
const MIST := Color(0.45, 0.48, 0.62, 1.0)
const DANGER := KEY_DEEP
const GOOD := Color(0.243, 0.608, 0.420, 1.0)  ## #3e9b6b

## 血／藍／經驗
const HP_FILL := Color(0.86, 0.28, 0.32, 1.0)
const HP_BG := Color(0.22, 0.12, 0.14, 0.95)
const MP_FILL := Color(0.55, 0.42, 0.82, 1.0)  ## 星屑偏紫
const MP_BG := Color(0.14, 0.12, 0.22, 0.95)
const EXP_FILL := KEY
const EXP_BG := Color(0.22, 0.14, 0.16, 0.95)
const RAGE_FILL := Color(0.95, 0.55, 0.25, 1.0)


static func panel_style(accent: Color = LINE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER_SOFT
	s.border_color = accent if accent != LINE else LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.shadow_color = Color(0.17, 0.16, 0.20, 0.14)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s


static func panel_style_dark() -> StyleBoxFlat:
	## HUD / 面板：深色暖木／金邊質感框
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.13, 0.12, 0.15, 0.92)
	s.border_color = Color(0.75, 0.60, 0.45, 0.85)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0.05, 0.04, 0.06, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s


static func header_style() -> StyleBoxFlat:
	## 標題列（暗粉赤木）
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.22, 0.16, 0.20, 0.96)
	s.border_color = Color(0.76, 0.37, 0.45, 0.9)
	s.set_border_width_all(0)
	s.border_width_bottom = 1
	s.set_corner_radius_all(0)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.content_margin_left = 10
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func interact_badge_style() -> StyleBoxFlat:
	## 靠近互動物件時的「E」框
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.20, 0.16, 0.14, 0.96)
	s.border_color = Color(0.92, 0.75, 0.45, 1.0)
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.shadow_color = Color(0.05, 0.04, 0.06, 0.4)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s


static func interact_name_style() -> StyleBoxFlat:
	## 靠近時才顯示的名稱小牌
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.14, 0.13, 0.16, 0.92)
	s.border_color = Color(0.75, 0.60, 0.45, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	s.shadow_color = Color(0.05, 0.04, 0.06, 0.3)
	s.shadow_size = 4
	return s


static func hint_bar_style() -> StyleBoxFlat:
	## 底部操作提示框
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.11, 0.14, 0.92)
	s.border_color = Color(0.75, 0.60, 0.45, 0.75)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0.05, 0.04, 0.06, 0.35)
	s.shadow_size = 6
	return s


static func dialogue_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.11, 0.15, 0.95)
	s.border_color = Color(0.85, 0.68, 0.48, 0.9)
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 10
	s.shadow_color = Color(0.04, 0.03, 0.05, 0.5)
	s.shadow_size = 14
	return s


static func chip_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.94)
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	s.shadow_color = Color(0.17, 0.16, 0.20, 0.08)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 1)
	return s


static func button_normal() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 1.0)
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func button_hover() -> StyleBoxFlat:
	var s := button_normal()
	s.bg_color = KEY_FAINT
	s.border_color = KEY
	return s


static func button_pressed() -> StyleBoxFlat:
	var s := button_normal()
	s.bg_color = KEY_SOFT
	s.border_color = KEY_STRONG
	return s


static func button_disabled() -> StyleBoxFlat:
	var s := button_normal()
	s.bg_color = Color(0.94, 0.93, 0.95, 0.75)
	s.border_color = LINE_SOFT
	return s


static func button_primary() -> StyleBoxFlat:
	## Artale 主按鈕：粉紅漸層感（平面近似）
	var s := StyleBoxFlat.new()
	s.bg_color = KEY_STRONG
	s.border_color = KEY_DEEP
	s.set_border_width_all(0)
	s.border_width_bottom = 2
	s.set_corner_radius_all(6)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.shadow_color = Color(0.66, 0.24, 0.33, 0.28)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s


static func button_primary_hover() -> StyleBoxFlat:
	var s := button_primary()
	s.bg_color = KEY
	return s


static func style_button(btn: Button, primary: bool = false) -> void:
	if primary:
		btn.add_theme_stylebox_override("normal", button_primary())
		btn.add_theme_stylebox_override("hover", button_primary_hover())
		btn.add_theme_stylebox_override("pressed", button_primary())
		btn.add_theme_stylebox_override("focus", button_primary_hover())
		btn.add_theme_stylebox_override("disabled", button_disabled())
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
	else:
		btn.add_theme_stylebox_override("normal", button_normal())
		btn.add_theme_stylebox_override("hover", button_hover())
		btn.add_theme_stylebox_override("pressed", button_pressed())
		btn.add_theme_stylebox_override("focus", button_hover())
		btn.add_theme_stylebox_override("disabled", button_disabled())
		btn.add_theme_color_override("font_color", INK)
		btn.add_theme_color_override("font_hover_color", KEY_STRONG)
		btn.add_theme_color_override("font_pressed_color", KEY_DEEP)
	btn.add_theme_color_override("font_disabled_color", INK_FAINT)
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(0, 36)


static func style_progress(bar: ProgressBar, fill: Color, bg: Color) -> void:
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color = bg
	bg_s.set_border_width_all(1)
	bg_s.border_color = LINE
	bg_s.set_corner_radius_all(4)
	var fill_s := StyleBoxFlat.new()
	fill_s.bg_color = fill
	fill_s.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_s)
	bar.add_theme_stylebox_override("fill", fill_s)
	bar.show_percentage = false


static func dim_rect(parent: Control, alpha: float = 0.45) -> ColorRect:
	var d := ColorRect.new()
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.color = Color(0.08, 0.07, 0.10, alpha)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(d)
	return d


static func name_tag_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.94)
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	s.shadow_color = Color(0.17, 0.16, 0.20, 0.12)
	s.shadow_size = 3
	return s


static func slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.97, 0.96, 0.98, 1)
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	return s


static func add_button_juice(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	btn.mouse_entered.connect(func():
		if btn and is_instance_valid(btn):
			btn.pivot_offset = btn.size * 0.5
			var tw := btn.create_tween()
			tw.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_SINE)
	)
	btn.mouse_exited.connect(func():
		if btn and is_instance_valid(btn):
			var tw := btn.create_tween()
			tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
	)
	btn.button_down.connect(func():
		if btn and is_instance_valid(btn):
			btn.pivot_offset = btn.size * 0.5
			var tw := btn.create_tween()
			tw.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)
	)
	btn.button_up.connect(func():
		if btn and is_instance_valid(btn):
			var tw := btn.create_tween()
			tw.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.05)
	)
