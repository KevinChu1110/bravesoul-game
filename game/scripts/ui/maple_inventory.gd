class_name MapleInventory
extends Control
## 楓式物品欄：4×6 格子；標題列可拖曳移動

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const WindowDrag = preload("res://scripts/ui/window_drag.gd")
const COLS := 4
const ROWS := 6

signal closed
signal item_used(item_id: String)
signal assign_hotbar(item_id: String)

var _card: PanelContainer
var _grid: GridContainer
var _cells: Array = []
var _detail: RichTextLabel
var _title: Label
var _selected: String = ""
var _bag_ids: Array = []
var _dim: ColorRect


func _ready() -> void:
	visible = false
	## 根節點不擋場景；只有半透明遮罩與卡片吃輸入
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 60
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.08, 0.06, 0.04, 0.28)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dim)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(420, 360)
	_card.size = Vector2(420, 360)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	## 預設位置（可拖）
	_card.position = Vector2(120, 80)
	add_child(_card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_card.add_child(outer)

	## 標題列＝拖曳把手
	var head := PanelContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.90, 0.84, 0.70, 1)
	hs.border_color = UiStyle.WOOD_DARK
	hs.set_border_width_all(1)
	hs.set_corner_radius_all(2)
	hs.content_margin_left = 8
	hs.content_margin_right = 6
	hs.content_margin_top = 4
	hs.content_margin_bottom = 4
	head.add_theme_stylebox_override("panel", hs)
	outer.add_child(head)

	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_row)

	_title = Label.new()
	_title.text = "物品欄  ·  拖曳此列移動"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", UiStyle.WOOD_DARK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(_title)

	var close_btn := Button.new()
	close_btn.text = "關閉 (I)"
	UiStyle.style_button(close_btn, false)
	close_btn.pressed.connect(close)
	head_row.add_child(close_btn)

	WindowDrag.attach(_card, head, "inv")

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	outer.add_child(body)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(_grid)

	for i in COLS * ROWS:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(52, 52)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.9, 0.86, 0.78, 1)
		cs.border_color = UiStyle.WOOD
		cs.set_border_width_all(2)
		cs.set_corner_radius_all(2)
		cell.add_theme_stylebox_override("panel", cs)
		_grid.add_child(cell)
		_cells.append(cell)

		var stack := Control.new()
		stack.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(stack)

		var g := Label.new()
		g.name = "Glyph"
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.add_theme_font_size_override("font_size", 18)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(g)

		var c := Label.new()
		c.name = "Count"
		c.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		c.offset_left = -30
		c.offset_top = -16
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.add_theme_font_size_override("font_size", 11)
		c.add_theme_color_override("font_color", UiStyle.INK)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(c)

		var idx := i
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				_on_cell(idx, ev.button_index)
		)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(180, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = true
	_detail.custom_minimum_size = Vector2(180, 160)
	_detail.add_theme_color_override("default_color", UiStyle.INK)
	_detail.add_theme_font_size_override("normal_font_size", 12)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_detail)

	var use_btn := Button.new()
	use_btn.text = "使用 / 賣出"
	UiStyle.style_button(use_btn, true)
	use_btn.pressed.connect(func():
		if _selected != "":
			item_used.emit(_selected)
			refresh()
	)
	right.add_child(use_btn)

	var hb_btn := Button.new()
	hb_btn.text = "放到快捷欄"
	UiStyle.style_button(hb_btn, false)
	hb_btn.pressed.connect(func():
		if _selected != "":
			assign_hotbar.emit(_selected)
	)
	right.add_child(hb_btn)

	var tip := Label.new()
	tip.text = "拖標題列移動視窗\n左鍵選 · 雙擊使用\n右鍵使用／賣出"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", UiStyle.INK_DIM)
	right.add_child(tip)


func open() -> void:
	visible = true
	_selected = ""
	var vp := get_viewport().get_visible_rect().size
	var fallback := Vector2(
		maxi(20, int((vp.x - 420) * 0.5)),
		maxi(20, int((vp.y - 360) * 0.35))
	)
	if Engine.get_main_loop() is SceneTree:
		var ul: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiLayout")
		if ul and ul.has_method("apply_to"):
			ul.call("apply_to", _card, "inv", fallback)
		else:
			_card.position = fallback
	else:
		_card.position = fallback
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func refresh() -> void:
	var inv: Node = null
	if Engine.get_main_loop() is SceneTree:
		inv = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
	_bag_ids.clear()
	var list: Array = inv.call("bag_list") if inv else []
	for i in _cells.size():
		var cell: PanelContainer = _cells[i]
		var g: Label = cell.find_child("Glyph", true, false)
		var c: Label = cell.find_child("Count", true, false)
		if i < list.size():
			var it: Dictionary = list[i]
			var id := str(it.get("id", ""))
			_bag_ids.append(id)
			var def: Dictionary = it.get("def", {})
			if g:
				g.text = str(def.get("glyph", "·"))
				g.add_theme_color_override("font_color", def.get("color", UiStyle.INK))
			if c:
				var n := int(it.get("count", 0))
				c.text = str(n) if n > 1 else ""
			var sel := id == _selected
			var cs := StyleBoxFlat.new()
			cs.bg_color = Color(1.0, 0.96, 0.85, 1) if sel else Color(0.9, 0.86, 0.78, 1)
			cs.border_color = Color(0.85, 0.55, 0.15, 1) if sel else UiStyle.WOOD
			cs.set_border_width_all(2 if not sel else 3)
			cs.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("panel", cs)
		else:
			_bag_ids.append("")
			if g:
				g.text = ""
			if c:
				c.text = ""
			var empty := StyleBoxFlat.new()
			empty.bg_color = Color(0.88, 0.84, 0.76, 1)
			empty.border_color = UiStyle.WOOD
			empty.set_border_width_all(2)
			empty.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("panel", empty)
	_update_detail(inv)


func _update_detail(inv: Node) -> void:
	if _selected == "" or inv == null:
		_detail.text = "[color=#664]點格子查看道具。\n\n消耗品：使用回血／星屑\n素材：使用＝賣出金幣\n重要物：不可消耗[/color]"
		return
	var def: Dictionary = inv.call("catalog", _selected) as Dictionary
	var n: int = int(inv.call("count", _selected))
	var kind: String = str(def.get("kind", ""))
	var kind_s: String = kind
	match kind:
		"consumable":
			kind_s = "消耗"
		"material":
			kind_s = "素材（點使用可賣）"
		"key":
			kind_s = "重要"
	_detail.text = "[b]%s[/b] ×%d\n%s\n\n[color=#553]%s[/color]\n類型：%s" % [
		str(def.get("name", _selected)),
		n,
		str(def.get("desc", "")),
		kind_s,
		kind,
	]


var _last_click_i: int = -1
var _last_click_t: int = 0


func _on_cell(idx: int, button: int) -> void:
	if idx < 0 or idx >= _bag_ids.size():
		return
	var id := str(_bag_ids[idx])
	if id == "":
		_selected = ""
		refresh()
		return
	if button == MOUSE_BUTTON_RIGHT:
		_selected = id
		item_used.emit(id)
		refresh()
		return
	if button == MOUSE_BUTTON_LEFT:
		var now := Time.get_ticks_msec()
		if _last_click_i == idx and now - _last_click_t < 350:
			_selected = id
			item_used.emit(id)
			_last_click_i = -1
			refresh()
			return
		_last_click_i = idx
		_last_click_t = now
		_selected = id
		refresh()
