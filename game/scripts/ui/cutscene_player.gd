class_name CutscenePlayer
extends Control
## 全屏過場：底圖淡入 → 立繪可選 → 字幕逐條 → 淡出回呼。
## 用法：play([{bg, portrait, speaker, text, hold}, ...], after)

signal finished

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SpriteDB = preload("res://scripts/art/sprite_db.gd")

var _slides: Array = []
var _index: int = 0
var _after: Callable = Callable()
var _busy: bool = false

var _bg: TextureRect
var _dim: ColorRect
var _portrait: TextureRect
var _caption_panel: PanelContainer
var _speaker: Label
var _body: RichTextLabel
var _hint: Label
var _black: ColorRect


func _ready() -> void:
	visible = false
	## 隱藏時絕不擋滑鼠（這是標題「卡選單」主因之一）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0.02, 0.02, 0.04, 1)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_black)

	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(1, 1, 1, 0)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.02, 0.05, 0.35)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(280, 350)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait.offset_left = 40
	_portrait.offset_top = -420
	_portrait.offset_right = 320
	_portrait.offset_bottom = -70
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.modulate = Color(1, 1, 1, 0)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	_caption_panel = PanelContainer.new()
	## 底部寬字幕條（勿漂到左上）
	_caption_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_panel.offset_left = 48
	_caption_panel.offset_right = -48
	_caption_panel.offset_top = -200
	_caption_panel.offset_bottom = -28
	_caption_panel.add_theme_stylebox_override("panel", UiStyle.dialogue_style())
	_caption_panel.modulate = Color(1, 1, 1, 0)
	_caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_caption_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 18)
	_speaker.add_theme_color_override("font_color", UiStyle.COPPER)
	v.add_child(_speaker)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(0, 64)
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_color_override("default_color", UiStyle.CREAM)
	v.add_child(_body)

	_hint = Label.new()
	_hint.text = "▼  Space / E  繼續"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", UiStyle.CREAM_DIM)
	v.add_child(_hint)


## slides: Array of Dictionary
##   bg: String map key or full res path (optional)
##   portrait: String speaker name for SpriteDB (optional)
##   speaker: String
##   text: String
##   hold: float auto-advance seconds (0 = wait input)
func play(slides: Array, after: Callable = Callable()) -> void:
	_slides = slides
	_index = 0
	_after = after
	_busy = false
	## 強制全屏，避免錨點失效只剩左上角小框、卻仍攔截點擊
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	## 全程至少半黑，標題選單不會「透出來」讓人誤以為還在點選單
	if _black:
		_black.color = Color(0.02, 0.02, 0.04, 1.0)
	_bg.modulate.a = 0.0
	_portrait.modulate.a = 0.0
	_caption_panel.modulate.a = 0.0
	_show_slide()


## 強制中止（回標題／Esc），不呼叫 after
func abort() -> void:
	_slides = []
	_index = 0
	_after = Callable()
	_busy = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _black:
		_black.color.a = 1.0
	if _bg:
		_bg.modulate.a = 0.0
	if _portrait:
		_portrait.modulate.a = 0.0
	if _caption_panel:
		_caption_panel.modulate.a = 0.0


func _show_slide() -> void:
	if _index >= _slides.size():
		_end_cutscene()
		return
	_busy = true
	var s: Dictionary = _slides[_index]
	## background
	var bg_key := str(s.get("bg", ""))
	var tex: Texture2D = null
	if bg_key != "":
		if bg_key.begins_with("res://"):
			if ResourceLoader.exists(bg_key):
				tex = load(bg_key) as Texture2D
		else:
			tex = SpriteDB.map_bg(bg_key)
			if tex == null and ResourceLoader.exists("res://assets/sprites/maps/%s.png" % bg_key):
				tex = load("res://assets/sprites/maps/%s.png" % bg_key) as Texture2D
	_bg.texture = tex
	## portrait
	var sp := str(s.get("speaker", ""))
	var port_key := str(s.get("portrait", sp))
	var ptex: Texture2D = SpriteDB.speaker_portrait(port_key)
	_portrait.texture = ptex
	_portrait.visible = ptex != null
	_speaker.text = sp
	_body.text = str(s.get("text", ""))

	var tw := create_tween()
	## 有底圖才幾乎透黑；沒底圖保留暗幕，避免標題選單透出
	var black_target := 0.12 if tex else 0.72
	tw.tween_property(_black, "color:a", black_target, 0.35)
	if tex:
		tw.parallel().tween_property(_bg, "modulate:a", 1.0, 0.45)
	if ptex:
		_portrait.modulate.a = 0.0
		tw.parallel().tween_property(_portrait, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(_caption_panel, "modulate:a", 1.0, 0.3)
	tw.tween_callback(func():
		_busy = false
		var hold := float(s.get("hold", 0.0))
		if hold > 0.0:
			get_tree().create_timer(hold).timeout.connect(func():
				if visible and not _busy:
					_advance()
			)
	)


func _advance() -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_caption_panel, "modulate:a", 0.0, 0.15)
	tw.parallel().tween_property(_portrait, "modulate:a", 0.0, 0.2)
	## 若下一張同 bg 不需全黑
	var next_bg := ""
	if _index + 1 < _slides.size():
		next_bg = str(_slides[_index + 1].get("bg", ""))
	var cur_bg := str(_slides[_index].get("bg", "")) if _index < _slides.size() else ""
	if next_bg != cur_bg or _index + 1 >= _slides.size():
		tw.parallel().tween_property(_bg, "modulate:a", 0.0, 0.25)
		tw.tween_property(_black, "color:a", 1.0, 0.2)
	tw.tween_callback(func():
		_index += 1
		if _index >= _slides.size():
			_end_cutscene()
		else:
			_show_slide()
	)


func _end_cutscene() -> void:
	_busy = true
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0, 0.25)
	tw.tween_callback(func():
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy = false
		var cb := _after
		_after = Callable()
		finished.emit()
		if cb.is_valid():
			cb.call()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	var go := false
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		go = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true
	if go:
		_advance()
		get_viewport().set_input_as_handled()
