class_name CutscenePlayer
extends Control
## 全屏過場：底圖（或影片）淡入 → 立繪可選 → 字幕逐條 → 淡出回呼。
## 用法：play([{bg, video, portrait, speaker, text, hold}, ...], after)

signal finished

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SpriteDB = preload("res://scripts/art/sprite_db.gd")

## 影片放這裡；只給檔名時自動補上這層路徑與 .ogv
## Godot 內建只支援 Ogg Theora，轉檔用 tools/import_cutscene.py
const VIDEO_DIR := "res://assets/video"

## 過場專屬插畫放這裡。有插畫就用插畫，沒有就退回 bg 指定的地圖底圖——
## 這樣可以一段一段慢慢補，補到哪裡就好看到哪裡，不用等全部畫完才能上。
const ART_DIR := "res://assets/sprites/cutscenes"

var _slides: Array = []
var _index: int = 0
var _after: Callable = Callable()
var _busy: bool = false

var _bg: TextureRect
var _video: VideoStreamPlayer
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

	## 疊在底圖之上、暗幕之下：有影片時蓋掉底圖，沒影片時完全透明不影響原本表現
	_video = VideoStreamPlayer.new()
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.visible = false
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_on_video_finished)
	add_child(_video)

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
##   art: String 過場專屬插畫 id（optional）；找得到就蓋過 bg，找不到就安靜退回 bg
##   video: String 影片檔名或完整 res 路徑（optional）；有影片時蓋過 art／bg，
##          播完自動進下一張，玩家也可以隨時按鍵跳過
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
	_stop_video()
	if _black:
		_black.color.a = 1.0
	if _bg:
		_bg.modulate.a = 0.0
	if _portrait:
		_portrait.modulate.a = 0.0
	if _caption_panel:
		_caption_panel.modulate.a = 0.0


## 取過場專屬插畫。刻意不警告：大多數段落本來就還沒畫，那是預期狀態不是錯誤。
func _art_texture(art_key: String) -> Texture2D:
	if art_key == "":
		return null
	var path := art_key if art_key.begins_with("res://") else "%s/%s.png" % [ART_DIR, art_key]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 開始播影片；沒有影片或載不到就回 false，讓這張退回純底圖表現。
## 刻意不讓缺影片變成硬錯誤——過場沒播出來，遊戲還是要能走下去。
func _start_video(key: String) -> bool:
	_stop_video()
	if key == "":
		return false
	var path := key
	if not path.begins_with("res://"):
		path = "%s/%s.ogv" % [VIDEO_DIR, key]
	if not ResourceLoader.exists(path):
		push_warning("過場影片找不到：%s（用 tools/import_cutscene.py 轉檔）" % path)
		return false
	var st := load(path) as VideoStream
	if st == null:
		push_warning("過場影片載不進來：%s" % path)
		return false
	_video.stream = st
	_video.visible = true
	_video.play()
	return true


func _stop_video() -> void:
	if _video == null:
		return
	if _video.is_playing():
		_video.stop()
	_video.visible = false
	_video.stream = null


func _on_video_finished() -> void:
	## 影片自己播完＝這張講完了，直接進下一張
	if visible and not _busy:
		_advance()


func _show_slide() -> void:
	if _index >= _slides.size():
		_end_cutscene()
		return
	_busy = true
	var s: Dictionary = _slides[_index]
	## background
	## 專屬插畫優先；沒畫到的段落自動退回地圖底圖，所以可以一段一段補
	var tex: Texture2D = _art_texture(str(s.get("art", "")))
	var bg_key := str(s.get("bg", ""))
	if tex == null and bg_key != "":
		if bg_key.begins_with("res://"):
			if ResourceLoader.exists(bg_key):
				tex = load(bg_key) as Texture2D
		else:
			tex = SpriteDB.map_bg(bg_key)
			if tex == null and ResourceLoader.exists("res://assets/sprites/maps/%s.png" % bg_key):
				tex = load("res://assets/sprites/maps/%s.png" % bg_key) as Texture2D
	_bg.texture = tex
	## video（有的話蓋過底圖）
	var playing_video := _start_video(str(s.get("video", "")))
	## portrait
	var sp := str(s.get("speaker", ""))
	var port_key := str(s.get("portrait", sp))
	var ptex: Texture2D = SpriteDB.speaker_portrait(port_key)
	_portrait.texture = ptex
	_portrait.visible = ptex != null
	_speaker.text = sp
	_body.text = str(s.get("text", ""))

	var tw := create_tween()
	## 有底圖或影片才幾乎透黑；都沒有就保留暗幕，避免標題選單透出
	var black_target := 0.72
	if playing_video:
		black_target = 0.0
	elif tex:
		black_target = 0.12
	tw.tween_property(_black, "color:a", black_target, 0.35)
	if tex and not playing_video:
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
		_stop_video()
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
