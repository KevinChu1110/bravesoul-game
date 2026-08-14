class_name UiStyle
extends RefCounted
## 楓之谷風小 UI：淺木框、米色紙、細黑邊、小字、緊湊按鈕（非現代玻璃）

## 木框／紙底
const WOOD := Color(0.42, 0.28, 0.14, 1.0)
const WOOD_DARK := Color(0.28, 0.18, 0.10, 1.0)
const WOOD_LIGHT := Color(0.62, 0.45, 0.28, 1.0)
const PAPER := Color(0.96, 0.93, 0.86, 0.96)
const PAPER_SOFT := Color(0.93, 0.89, 0.80, 0.94)
const INK := Color(0.18, 0.14, 0.10, 1.0)
const INK_DIM := Color(0.40, 0.34, 0.28, 1.0)
const CREAM := Color(0.18, 0.14, 0.10, 1.0)  ## 文字主色（深）
const CREAM_DIM := Color(0.42, 0.36, 0.30, 1.0)
const GOLD := Color(0.72, 0.52, 0.12, 1.0)
const COPPER := Color(0.55, 0.38, 0.16, 1.0)  ## 兼容舊呼叫＝木褐
const COPPER_DIM := Color(0.48, 0.34, 0.18, 0.95)
const MIST := Color(0.35, 0.50, 0.70, 1.0)
const DANGER := Color(0.78, 0.18, 0.18, 1.0)
const GOOD := Color(0.20, 0.55, 0.28, 1.0)
## 血條／藍條／經驗（楓式）
const HP_FILL := Color(0.86, 0.22, 0.22, 1.0)
const HP_BG := Color(0.35, 0.12, 0.12, 0.95)
const MP_FILL := Color(0.22, 0.42, 0.82, 1.0)
const MP_BG := Color(0.12, 0.18, 0.35, 0.95)
const EXP_FILL := Color(0.92, 0.78, 0.18, 1.0)
const EXP_BG := Color(0.30, 0.26, 0.10, 0.95)
const RAGE_FILL := Color(0.95, 0.55, 0.12, 1.0)


static func panel_style(accent: Color = WOOD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.border_color = accent
	s.set_border_width_all(3)
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(2, 2)
	return s


static func panel_style_dark() -> StyleBoxFlat:
	## 半透明木底（疊在場景上）
	var s := panel_style(WOOD_DARK)
	s.bg_color = Color(0.96, 0.93, 0.86, 0.88)
	return s


static func dialogue_style() -> StyleBoxFlat:
	var s := panel_style(WOOD)
	s.bg_color = Color(0.98, 0.95, 0.88, 0.97)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 8
	s.border_color = WOOD_DARK
	s.set_border_width_all(3)
	return s


static func chip_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.94, 0.90, 0.80, 0.95)
	s.border_color = WOOD_LIGHT
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func button_normal() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.94, 0.88, 0.72, 1.0)
	s.border_color = WOOD_DARK
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func button_hover() -> StyleBoxFlat:
	var s := button_normal()
	s.bg_color = Color(1.0, 0.95, 0.78, 1.0)
	s.border_color = GOLD
	return s


static func button_pressed() -> StyleBoxFlat:
	var s := button_normal()
	s.bg_color = Color(0.82, 0.72, 0.52, 1.0)
	s.border_color = WOOD
	return s


static func button_disabled() -> StyleBoxFlat:
	var s := button_normal()
	s.bg_color = Color(0.75, 0.72, 0.68, 0.7)
	s.border_color = Color(0.5, 0.45, 0.4, 0.6)
	return s


static func style_button(btn: Button, primary: bool = false) -> void:
	var normal := button_normal()
	if primary:
		normal.bg_color = Color(0.55, 0.72, 0.95, 1.0)  ## 楓式藍鈕
		normal.border_color = Color(0.20, 0.32, 0.55, 1.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", button_hover())
	btn.add_theme_stylebox_override("pressed", button_pressed())
	btn.add_theme_stylebox_override("focus", button_hover())
	btn.add_theme_stylebox_override("disabled", button_disabled())
	btn.add_theme_color_override("font_color", INK)
	btn.add_theme_color_override("font_hover_color", INK)
	btn.add_theme_color_override("font_pressed_color", WOOD_DARK)
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.45, 0.75))
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(0, 32)


static func style_progress(bar: ProgressBar, fill: Color, bg: Color) -> void:
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color = bg
	bg_s.set_border_width_all(1)
	bg_s.border_color = WOOD_DARK
	bg_s.set_corner_radius_all(2)
	var fill_s := StyleBoxFlat.new()
	fill_s.bg_color = fill
	fill_s.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("background", bg_s)
	bar.add_theme_stylebox_override("fill", fill_s)
	bar.show_percentage = false


static func dim_rect(parent: Control, alpha: float = 0.35) -> ColorRect:
	var d := ColorRect.new()
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.color = Color(0.08, 0.06, 0.04, alpha)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(d)
	return d


static func name_tag_style() -> StyleBoxFlat:
	## 角色頭上小名牌
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.98, 0.95, 0.88, 0.9)
	s.border_color = WOOD_DARK
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s
