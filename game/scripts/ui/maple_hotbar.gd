class_name MapleHotbar
extends Control
## 楓式底部快捷欄 1–8；整條可拖曳

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const WindowDrag = preload("res://scripts/ui/window_drag.gd")
const SLOT_N := 8
const SLOT_SIZE := Vector2(46, 46)

signal slot_clicked(index: int)
signal slot_right_clicked(index: int)

var _bar: PanelContainer
var _slots: Array = []
var _glyphs: Array = []
var _counts: Array = []
var _keys: Array = []
var _flash: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0
	anchor_bottom = 0
	## 初始置底中（之後可拖）
	custom_minimum_size = Vector2(408, 54)
	size = Vector2(408, 54)
	_build()
	call_deferred("_place_default")
	if Engine.get_main_loop() is SceneTree:
		var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
		if inv:
			if inv.has_signal("inventory_changed"):
				inv.inventory_changed.connect(refresh)
			if inv.has_signal("hotbar_changed"):
				inv.hotbar_changed.connect(refresh)
	refresh()
	WindowDrag.attach(self, _bar, "hotbar")


func _place_default() -> void:
	var vp := get_viewport().get_visible_rect().size
	var fallback := Vector2((vp.x - size.x) * 0.5, vp.y - size.y - 14)
	if Engine.get_main_loop() is SceneTree:
		var ul: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiLayout")
		if ul and ul.has_method("has_pos") and ul.call("has_pos", "hotbar"):
			ul.call("apply_to", self, "hotbar", fallback)
			return
	position = fallback


func _build() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.13, 0.12, 0.15, 0.92)
	bs.border_color = Color(0.75, 0.60, 0.45, 0.85)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(10)
	bs.content_margin_left = 8
	bs.content_margin_right = 8
	bs.content_margin_top = 6
	bs.content_margin_bottom = 6
	bs.shadow_color = Color(0.05, 0.04, 0.06, 0.35)
	bs.shadow_size = 6
	bs.shadow_offset = Vector2(0, 2)
	_bar.add_theme_stylebox_override("panel", bs)
	add_child(_bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	for i in SLOT_N:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_stylebox_override("panel", UiStyle.slot_style())
		row.add_child(slot)
		_slots.append(slot)

		var stack := Control.new()
		stack.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(stack)

		var flash := ColorRect.new()
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.color = Color(1, 1, 0.6, 0)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(flash)
		_flash.append(flash)

		var glyph := Label.new()
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 16)
		glyph.add_theme_color_override("font_color", Color(0.95, 0.90, 0.85))
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(glyph)
		_glyphs.append(glyph)

		var cnt := Label.new()
		cnt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.offset_left = -28
		cnt.offset_top = -16
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.add_theme_font_size_override("font_size", 10)
		cnt.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		cnt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		cnt.add_theme_constant_override("shadow_offset_x", 1)
		cnt.add_theme_constant_override("shadow_offset_y", 1)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(cnt)
		_counts.append(cnt)

		var key := Label.new()
		key.text = str(i + 1)
		key.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		key.offset_left = 3
		key.offset_top = 1
		key.add_theme_font_size_override("font_size", 9)
		key.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(key)
		_keys.append(key)

		var idx := i
		slot.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				if ev.button_index == MOUSE_BUTTON_LEFT:
					slot_clicked.emit(idx)
					get_viewport().set_input_as_handled()
				elif ev.button_index == MOUSE_BUTTON_RIGHT:
					slot_right_clicked.emit(idx)
					get_viewport().set_input_as_handled()
		)


func refresh() -> void:
	var inv: Node = null
	if Engine.get_main_loop() is SceneTree:
		inv = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
	if inv == null or not inv.has_method("ensure_hotbar"):
		return
	inv.call("ensure_hotbar")
	var bar: Array = GameState.hotbar
	for i in SLOT_N:
		var id := str(bar[i]) if i < bar.size() else ""
		var glyph: Label = _glyphs[i]
		var cnt: Label = _counts[i]
		var slot: PanelContainer = _slots[i]
		if id == "" or int(GameState.inventory.get(id, 0)) <= 0:
			glyph.text = ""
			cnt.text = ""
			var empty := StyleBoxFlat.new()
			empty.bg_color = Color(0.18, 0.16, 0.20, 0.9)
			empty.border_color = Color(0.40, 0.35, 0.30, 0.7)
			empty.set_border_width_all(1)
			empty.set_corner_radius_all(4)
			slot.add_theme_stylebox_override("panel", empty)
			continue
		var def: Dictionary = inv.call("catalog", id)
		glyph.text = str(def.get("glyph", "·"))
		glyph.add_theme_color_override("font_color", Color(0.98, 0.95, 0.90))
		var n := int(GameState.inventory.get(id, 0))
		cnt.text = str(n) if n > 1 else ""
		var filled := StyleBoxFlat.new()
		filled.bg_color = Color(0.25, 0.20, 0.28, 0.95)
		filled.border_color = Color(0.85, 0.65, 0.40, 0.9)
		filled.set_border_width_all(2)
		filled.set_corner_radius_all(4)
		slot.add_theme_stylebox_override("panel", filled)


func pulse_slot(index: int) -> void:
	if index < 0 or index >= _flash.size():
		return
	var f: ColorRect = _flash[index]
	f.color = Color(1, 1, 0.5, 0.55)
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.25)
