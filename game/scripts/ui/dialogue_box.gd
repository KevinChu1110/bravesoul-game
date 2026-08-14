class_name DialogueBox
extends Control
## 對話：打字機、半身像、半透明遮罩、銅邊紙面板。Space／E／點擊繼續。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SpriteDB = preload("res://scripts/art/sprite_db.gd")

signal finished
signal choice_selected(index: int)

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = %Speaker
@onready var body_label: RichTextLabel = %Body
@onready var continue_hint: Label = %ContinueHint
@onready var choices: VBoxContainer = %Choices
@onready var accent: ColorRect = %Accent
@onready var portrait: TextureRect = %Portrait
@onready var portrait_frame: PanelContainer = %PortraitFrame

var _lines: Array = []
var _index: int = 0
var _waiting_choice: bool = false
var _full_text: String = ""
var _type_i: int = 0
var _typing: bool = false
var _type_accum: float = 0.0
const TYPE_CPS := 48.0
var _dim: ColorRect


func _ready() -> void:
	visible = false
	choices.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_dim()
	_apply_look()


func _ensure_dim() -> void:
	if _dim and is_instance_valid(_dim):
		return
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.08, 0.07, 0.10, 0.42)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.z_index = -1
	add_child(_dim)
	move_child(_dim, 0)


func _apply_look() -> void:
	## 楓式：底欄較矮、米色紙、小半身像
	if panel:
		panel.add_theme_stylebox_override("panel", UiStyle.dialogue_style())
		panel.offset_top = -200.0
		panel.offset_bottom = -12.0
		panel.offset_left = 48.0
		panel.offset_right = -48.0
	if speaker_label:
		speaker_label.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
		speaker_label.add_theme_font_size_override("font_size", 15)
	if body_label:
		body_label.add_theme_color_override("default_color", UiStyle.INK)
		body_label.add_theme_font_size_override("normal_font_size", 15)
	if continue_hint:
		continue_hint.add_theme_color_override("font_color", UiStyle.INK_FAINT)
		continue_hint.add_theme_font_size_override("font_size", 11)
		continue_hint.text = "▼ Space / E"
	if accent:
		accent.color = UiStyle.KEY_STRONG
		accent.custom_minimum_size = Vector2(4, 0)
	if portrait_frame:
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(1, 1, 1, 1.0)
		ps.border_color = UiStyle.LINE
		ps.set_border_width_all(1)
		ps.set_corner_radius_all(8)
		portrait_frame.add_theme_stylebox_override("panel", ps)
		portrait_frame.custom_minimum_size = Vector2(110, 130)
	if portrait:
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = Vector2(96, 120)


func play(lines: Array) -> void:
	_lines = lines
	_index = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_dim()
	_apply_look()
	if _dim:
		_dim.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_dim, "modulate:a", 1.0, 0.18)
	_show_current()


func _show_current() -> void:
	_waiting_choice = false
	_typing = false
	choices.visible = false
	for c in choices.get_children():
		c.queue_free()

	if _index >= _lines.size():
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		finished.emit()
		return

	var line: Dictionary = _lines[_index]
	var sp: String = str(line.get("speaker", ""))
	speaker_label.text = sp
	## 半身像
	var ptex: Texture2D = SpriteDB.speaker_portrait(sp)
	if portrait and portrait_frame:
		if ptex:
			portrait.texture = ptex
			portrait_frame.visible = true
			portrait.modulate = Color(1, 1, 1, 0)
			var twp := create_tween()
			twp.tween_property(portrait, "modulate:a", 1.0, 0.15)
		else:
			portrait.texture = null
			portrait_frame.visible = false
	## 系統／旁白用霧藍，角色用銅
	if sp in ["系統", "旁白", "系統·教學"]:
		speaker_label.add_theme_color_override("font_color", UiStyle.MIST)
		if accent:
			accent.color = UiStyle.MIST
	else:
		speaker_label.add_theme_color_override("font_color", UiStyle.COPPER)
		if accent:
			accent.color = UiStyle.COPPER

	_full_text = str(line.get("text", ""))
	_type_i = 0
	_type_accum = 0.0
	body_label.text = ""
	continue_hint.visible = false
	_typing = true


func _process(dt: float) -> void:
	if not visible or not _typing:
		return
	_type_accum += dt * TYPE_CPS
	var n: int = int(_type_accum)
	if n <= 0:
		return
	_type_accum -= float(n)
	_type_i = mini(_full_text.length(), _type_i + n)
	body_label.text = _full_text.substr(0, _type_i)
	if _type_i >= _full_text.length():
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	body_label.text = _full_text
	var line: Dictionary = _lines[_index] if _index < _lines.size() else {}
	if line.has("choices"):
		_waiting_choice = true
		continue_hint.visible = false
		choices.visible = true
		var opts: Array = line["choices"]
		for i in opts.size():
			var btn := Button.new()
			btn.text = str(opts[i])
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UiStyle.style_button(btn, i == 0)
			var idx := i
			btn.pressed.connect(func(): _on_choice(idx))
			choices.add_child(btn)
	else:
		continue_hint.visible = true
		continue_hint.text = "▼  Space / E  繼續"


func _skip_or_advance() -> void:
	if _typing:
		_type_i = _full_text.length()
		_finish_typing()
		return
	if _waiting_choice:
		return
	_index += 1
	_show_current()


func _on_choice(i: int) -> void:
	choice_selected.emit(i)
	var line: Dictionary = _lines[_index] if _index < _lines.size() else {}
	## 支援 replies：依選項插入對應回覆（字串或台詞陣列），避免「選了打水卻回黑焰」
	if line.has("replies"):
		var replies: Array = line["replies"]
		if i >= 0 and i < replies.size():
			var r = replies[i]
			var insert_at := _index + 1
			if typeof(r) == TYPE_STRING:
				_lines.insert(insert_at, {
					"speaker": str(line.get("speaker", "")),
					"text": str(r),
				})
			elif typeof(r) == TYPE_ARRAY:
				var arr: Array = r
				for j in arr.size():
					var item = arr[j]
					if typeof(item) == TYPE_DICTIONARY:
						_lines.insert(insert_at + j, item)
					else:
						_lines.insert(insert_at + j, {
							"speaker": str(line.get("speaker", "")),
							"text": str(item),
						})
			elif typeof(r) == TYPE_DICTIONARY:
				_lines.insert(insert_at, r)
	_index += 1
	_show_current()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _waiting_choice:
			_skip_or_advance()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if not _waiting_choice:
			_skip_or_advance()
			get_viewport().set_input_as_handled()
