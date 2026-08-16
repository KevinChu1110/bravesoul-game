extends RefCounted
## 裝備面板（部位槽 + 背包格）。
##
## 從 main.gd 抽出的第三塊。這塊跟前兩塊不同：它不走 ui_panel()，而是自己畫
## —— 圖示格子、三部位槽、背包網格，title/body/buttons 那組表達不了。
## 所以它會用到 ui_host() / ui_clear_host() / ui_reset_fade()。
##
## 宿主介面見 main.gd 的「面板宿主介面」段落。導覽一律走 ui_goto()。
##
## 刻意不用 class_name（見 AGENTS.md「寫測試的規矩」）。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

var _host: Node


func _init(host: Node) -> void:
	_host = host


func open() -> void:
	EquipmentSystem._ensure_state()
	_host.ui_clear_host()
	_host.ui_reset_fade()

	var layer := Control.new()
	layer.name = "EquipLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.ui_host().add_child(layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.969, 0.965, 0.973, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(card)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12 if m != "margin_top" else 10)
	card.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "裝備"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(title)

	var b := EquipmentSystem.bonus_totals()
	var sum := Label.new()
	sum.text = "總加成  攻+%d  防+%d  血+%d  ·  暴擊 %.1f%%  暴傷 +%.0f%%" % [
		int(b.atk), int(b.def), int(b.hp),
		GameState.effective_crit(), GameState.effective_crit_dmg(),
	]
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.add_theme_font_size_override("font_size", 12)
	sum.add_theme_color_override("font_color", UiStyle.INK_DIM)
	root.add_child(sum)

	## 三部位槽
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 12)
	root.add_child(slots_row)
	for s in EquipmentSystem.SLOTS:
		slots_row.add_child(_slot_card(s))

	var bag_h := Label.new()
	bag_h.text = "背包（點擊裝備）"
	bag_h.add_theme_font_size_override("font_size", 13)
	bag_h.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(bag_h)

	var bag_grid := GridContainer.new()
	bag_grid.columns = 4
	bag_grid.add_theme_constant_override("h_separation", 8)
	bag_grid.add_theme_constant_override("v_separation", 8)
	root.add_child(bag_grid)
	var n := 0
	for e in GameState.equip_bag:
		if n >= 12:
			break
		bag_grid.add_child(_bag_cell(e))
		n += 1
	if n == 0:
		var empty := Label.new()
		empty.text = "背包尚無裝備。野外掉落或找釘釘鍛造。"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", UiStyle.INK_DIM)
		root.add_child(empty)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var btn_back := Button.new()
	btn_back.text = "返回"
	UiStyle.style_button(btn_back, true)
	btn_back.pressed.connect(func():
		AudioManager.play_ui()
		_host.ui_goto("hub")
	)
	actions.add_child(btn_back)
	_host.ui_refresh_hud()


func _slot_card(slot: String) -> Control:
	var slot_name := "武器"
	match slot:
		"armor":
			slot_name = "防具"
		"accessory":
			slot_name = "飾品"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(140, 0)
	box.add_theme_constant_override("separation", 4)
	var lab := Label.new()
	lab.text = slot_name
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", UiStyle.INK_DIM)
	box.add_child(lab)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(120, 120)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.94, 0.92, 0.95, 1)
	st.border_color = UiStyle.WOOD
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	cell.add_theme_stylebox_override("panel", st)
	box.add_child(cell)
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(inner)
	var uid := str(GameState.equip_slots.get(slot, ""))
	var inst: Dictionary = {}
	if uid != "" and GameState.equip_worn.has(uid):
		inst = GameState.equip_worn[uid]
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not inst.is_empty():
		var t: Texture2D = SpriteDB.equip_icon_for_inst(inst)
		if t:
			icon.texture = t
	inner.add_child(icon)
	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 11)
	if inst.is_empty():
		name_l.text = "（空）"
		name_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
	else:
		name_l.text = str(inst.get("name", "?"))
		name_l.add_theme_color_override("font_color", UiStyle.INK)
	inner.add_child(name_l)
	if not inst.is_empty():
		var btn := Button.new()
		btn.text = "卸下"
		UiStyle.style_button(btn, false)
		btn.pressed.connect(func():
			AudioManager.play_ui()
			unequip(slot)
		)
		box.add_child(btn)
	return box


func _bag_cell(inst: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(110, 110)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.95, 0.93, 1)
	st.border_color = Color(0.76, 0.37, 0.45, 0.55)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	cell.add_theme_stylebox_override("panel", st)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var uid := str(inst.get("uid", ""))
	btn.tooltip_text = EquipmentSystem.label(inst)
	btn.pressed.connect(func():
		AudioManager.play_ui()
		wear(uid)
	)
	cell.add_child(btn)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(col)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Texture2D = SpriteDB.equip_icon_for_inst(inst)
	if t:
		icon.texture = t
	col.add_child(icon)
	var nl := Label.new()
	nl.text = str(inst.get("name", "?"))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.add_theme_font_size_override("font_size", 10)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nl)
	var ql := Label.new()
	ql.text = str(inst.get("quality_label", ""))
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.add_theme_font_size_override("font_size", 10)
	ql.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ql)
	return cell


func wear(uid: String) -> void:
	var r: Dictionary = EquipmentSystem.equip(uid)
	_host.ui_toast(str(r.get("msg", "")))
	open()


func unequip(slot: String) -> void:
	var r: Dictionary = EquipmentSystem.unequip(slot)
	_host.ui_toast(str(r.get("msg", "")))
	open()
