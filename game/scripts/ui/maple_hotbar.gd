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
	custom_minimum_size = Vector2(430, 58)
	size = Vector2(430, 58)
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
	var fallback := Vector2((vp.x - size.x) * 0.5, vp.y - size.y - 10)
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
	bs.bg_color = Color(0.96, 0.93, 0.86, 0.94)
	bs.border_color = UiStyle.WOOD_DARK
	bs.set_border_width_all(3)
	bs.set_corner_radius_all(3)
	bs.content_margin_left = 8
	bs.content_margin_right = 8
	bs.content_margin_top = 5
	bs.content_margin_bottom = 5
	_bar.add_theme_stylebox_override("panel", bs)
	add_child(_bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(col)

	var tip := Label.new()
	tip.text = "快捷欄 · 拖曳外框移動 · 1–8 使用"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 9)
	tip.add_theme_color_override("font_color", UiStyle.INK_DIM)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tip)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(row)

	for i in SLOT_N:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var ss := StyleBoxFlat.new()
		ss.bg_color = Color(0.88, 0.84, 0.76, 1)
		ss.border_color = UiStyle.WOOD
		ss.set_border_width_all(2)
		ss.set_corner_radius_all(2)
		slot.add_theme_stylebox_override("panel", ss)
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
		glyph.add_theme_color_override("font_color", UiStyle.INK)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(glyph)
		_glyphs.append(glyph)

		var cnt := Label.new()
		cnt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.offset_left = -28
		cnt.offset_top = -16
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.add_theme_font_size_override("font_size", 10)
		cnt.add_theme_color_override("font_color", UiStyle.INK)
		cnt.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.8))
		cnt.add_theme_constant_override("shadow_offset_x", 1)
		cnt.add_theme_constant_override("shadow_offset_y", 1)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(cnt)
		_counts.append(cnt)

		var key := Label.new()
		key.text = str(i + 1)
		key.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		key.offset_left = 2
		key.offset_top = 0
		key.add_theme_font_size_override("font_size", 9)
		key.add_theme_color_override("font_color", UiStyle.GOLD)
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
			empty.bg_color = Color(0.88, 0.84, 0.76, 1)
			empty.border_color = UiStyle.WOOD
			empty.set_border_width_all(2)
			empty.set_corner_radius_all(2)
			slot.add_theme_stylebox_override("panel", empty)
			continue
		var def: Dictionary = inv.call("catalog", id)
		glyph.text = str(def.get("glyph", "·"))
		glyph.add_theme_color_override("font_color", def.get("color", UiStyle.INK))
		var n := int(GameState.inventory.get(id, 0))
		cnt.text = str(n) if n > 1 else ""
		var filled := StyleBoxFlat.new()
		filled.bg_color = Color(0.94, 0.90, 0.82, 1)
		filled.border_color = def.get("color", UiStyle.WOOD) as Color
		filled.set_border_width_all(2)
		filled.set_corner_radius_all(2)
		slot.add_theme_stylebox_override("panel", filled)


func pulse_slot(index: int) -> void:
	if index < 0 or index >= _flash.size():
		return
	var f: ColorRect = _flash[index]
	f.color = Color(1, 1, 0.5, 0.55)
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.25)
