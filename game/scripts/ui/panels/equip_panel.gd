extends RefCounted
## 裝備面板：真正多武器欄（3）＋防具／飾品＋背包。
##
## 從 main.gd 抽出。不走 ui_panel()，自己畫圖示格子。
## 宿主介面見 main.gd「面板宿主介面」。導覽走 ui_goto()。
##
## 刻意不用 class_name（見 AGENTS.md「寫測試的規矩」）。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const ContentLoc := preload("res://scripts/systems/content_loc.gd")

var _host: Node
## 點空武器欄後，等背包選一把裝進去（-1＝無）
var _pending_loadout: int = -1


static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)


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
	card.custom_minimum_size = Vector2(560, 0)
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
	title.text = _t("裝備")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(title)

	var b := EquipmentSystem.bonus_totals()
	var sum := Label.new()
	sum.text = _t("總加成  攻+%d  防+%d  血+%d  ·  暴擊 %.1f%%  暴傷 +%.0f%%") % [
		int(b.atk), int(b.def), int(b.hp),
		GameState.effective_crit(), GameState.effective_crit_dmg(),
	]
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.add_theme_font_size_override("font_size", 12)
	sum.add_theme_color_override("font_color", UiStyle.INK_DIM)
	root.add_child(sum)

	## ── 真正多武器欄 ──
	var wh := Label.new()
	wh.text = _t("武器欄（戰鬥耗盡自動切換 · 第2欄 Lv10 · 第3欄 Lv16）")
	wh.add_theme_font_size_override("font_size", 13)
	wh.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(wh)

	if _pending_loadout >= 0:
		var hint := Label.new()
		hint.text = _t("▶ 請點背包中的【武器】裝入第 %d 欄（或點取消）") % [_pending_loadout + 1]
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.75, 0.35, 0.2))
		root.add_child(hint)
		var cancel := Button.new()
		cancel.text = _t("取消選欄")
		UiStyle.style_button(cancel, false)
		cancel.pressed.connect(func():
			AudioManager.play_ui()
			_pending_loadout = -1
			open()
		)
		root.add_child(cancel)

	var loadout_row := HBoxContainer.new()
	loadout_row.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout_row.add_theme_constant_override("separation", 10)
	root.add_child(loadout_row)
	for i in EquipmentSystem.WEAPON_LOADOUT_SIZE:
		loadout_row.add_child(_loadout_card(i))

	## ── 防具 ──
	var armor_h := Label.new()
	armor_h.text = _t("防具")
	armor_h.add_theme_font_size_override("font_size", 13)
	armor_h.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(armor_h)
	var armor_row := HBoxContainer.new()
	armor_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(armor_row)
	armor_row.add_child(_slot_card("armor"))

	## ── 飾品六槽 ──
	var acc_h := Label.new()
	if EquipmentSystem.accessories_unlocked():
		acc_h.text = _t("飾品六槽")
	else:
		acc_h.text = _t("飾品六槽（Lv%d 開放）") % EquipmentSystem.ACCESSORY_LEVEL_REQ
	acc_h.add_theme_font_size_override("font_size", 13)
	acc_h.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	root.add_child(acc_h)
	var acc_grid := GridContainer.new()
	acc_grid.columns = 3
	acc_grid.add_theme_constant_override("h_separation", 8)
	acc_grid.add_theme_constant_override("v_separation", 8)
	root.add_child(acc_grid)
	for s in EquipmentSystem.ACCESSORY_SLOTS:
		acc_grid.add_child(_slot_card(s, true, EquipmentSystem.accessories_unlocked()))

	## ── 背包 ──
	var bag_h := Label.new()
	if _pending_loadout >= 0:
		bag_h.text = _t("背包（點武器裝入第 %d 欄）") % [_pending_loadout + 1]
	else:
		bag_h.text = _t("背包（點擊裝備）")
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
		empty.text = _t("背包尚無裝備。野外掉落或找釘釘鍛造。")
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", UiStyle.INK_DIM)
		root.add_child(empty)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var btn_back := Button.new()
	btn_back.text = _t("返回")
	UiStyle.style_button(btn_back, true)
	btn_back.pressed.connect(func():
		AudioManager.play_ui()
		_pending_loadout = -1
		_host.ui_goto("hub")
	)
	actions.add_child(btn_back)
	_host.ui_refresh_hud()


func _loadout_card(index: int) -> Control:
	var unlocked := EquipmentSystem.loadout_slot_unlocked(index)
	var uid := EquipmentSystem.loadout_uid(index) if unlocked else ""
	var inst := EquipmentSystem.weapon_inst(uid)
	var active := unlocked and index == EquipmentSystem.active_loadout_index() and uid != ""
	var picking := _pending_loadout == index

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150, 0)
	box.add_theme_constant_override("separation", 4)

	var lab := Label.new()
	if not unlocked:
		lab.text = _t("欄 %d · Lv%d") % [index + 1, EquipmentSystem.loadout_unlock_level(index)]
	elif active:
		lab.text = _t("欄 %d · 使用中") % [index + 1]
	else:
		lab.text = _t("欄 %d") % [index + 1]
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", UiStyle.KEY_STRONG if active else UiStyle.INK_DIM)
	box.add_child(lab)

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(130, 130)
	var st := StyleBoxFlat.new()
	if not unlocked:
		st.bg_color = Color(0.88, 0.88, 0.9, 1)
		st.border_color = Color(0.6, 0.6, 0.65, 0.7)
	elif picking:
		st.bg_color = Color(1.0, 0.95, 0.88, 1)
		st.border_color = Color(0.9, 0.55, 0.2, 1)
	elif active:
		st.bg_color = Color(0.92, 0.96, 1.0, 1)
		st.border_color = Color(0.25, 0.55, 0.9, 1)
	else:
		st.bg_color = Color(0.94, 0.92, 0.95, 1)
		st.border_color = UiStyle.WOOD
	st.set_border_width_all(3 if active or picking else 2)
	st.set_corner_radius_all(8)
	cell.add_theme_stylebox_override("panel", st)
	box.add_child(cell)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(inner)

	if not unlocked:
		var lock_l := Label.new()
		lock_l.text = _t("未解鎖")
		lock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_l.add_theme_font_size_override("font_size", 12)
		lock_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
		inner.add_child(lock_l)
		var need := Label.new()
		need.text = _t("需要 Lv%d") % EquipmentSystem.loadout_unlock_level(index)
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		need.add_theme_font_size_override("font_size", 11)
		need.add_theme_color_override("font_color", UiStyle.INK_DIM)
		inner.add_child(need)
		return box

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
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
		name_l.text = _t("（空）· 點此裝填")
		name_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
	else:
		var line := str(inst.get("line", ""))
		name_l.text = str(inst.get("name", "?"))
		if line != "":
			name_l.text += "\n[%s]" % line
		name_l.add_theme_color_override("font_color", UiStyle.INK)
	inner.add_child(name_l)

	if not inst.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		if not active:
			var use_btn := Button.new()
			use_btn.text = _t("使用")
			UiStyle.style_button(use_btn, true)
			use_btn.pressed.connect(func():
				AudioManager.play_ui()
				var r2: Dictionary = EquipmentSystem.switch_weapon_loadout(index)
				_host.ui_toast(str(r2.get("msg", "")))
				_pending_loadout = -1
				open()
			)
			row.add_child(use_btn)
		var ue := Button.new()
		ue.text = _t("卸下")
		UiStyle.style_button(ue, false)
		ue.pressed.connect(func():
			AudioManager.play_ui()
			var r3: Dictionary = EquipmentSystem.unequip_loadout_slot(index)
			_host.ui_toast(str(r3.get("msg", "")))
			_pending_loadout = -1
			open()
		)
		row.add_child(ue)
	else:
		var fill := Button.new()
		fill.text = _t("裝填")
		UiStyle.style_button(fill, true)
		fill.pressed.connect(func():
			AudioManager.play_ui()
			_pending_loadout = index
			open()
		)
		box.add_child(fill)

	return box


func _slot_card(slot: String, compact: bool = false, unlocked: bool = true) -> Control:
	var slot_name := EquipmentSystem.slot_label(slot)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(100 if compact else 140, 0)
	box.add_theme_constant_override("separation", 4)
	var lab := Label.new()
	lab.text = slot_name
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 11 if compact else 12)
	lab.add_theme_color_override("font_color", UiStyle.INK_DIM)
	box.add_child(lab)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(88 if compact else 120, 88 if compact else 120)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.88, 0.88, 0.9, 1) if not unlocked else Color(0.94, 0.92, 0.95, 1)
	st.border_color = Color(0.6, 0.6, 0.65, 0.7) if not unlocked else UiStyle.WOOD
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	cell.add_theme_stylebox_override("panel", st)
	box.add_child(cell)
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(inner)
	if not unlocked:
		var lock_l := Label.new()
		lock_l.text = _t("Lv%d") % EquipmentSystem.ACCESSORY_LEVEL_REQ
		lock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_l.add_theme_font_size_override("font_size", 11)
		lock_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
		inner.add_child(lock_l)
		return box
	var uid := str(GameState.equip_slots.get(slot, ""))
	var inst: Dictionary = {}
	if uid != "" and GameState.equip_worn.has(uid):
		inst = GameState.equip_worn[uid]
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48 if compact else 72, 48 if compact else 72)
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
	name_l.add_theme_font_size_override("font_size", 10 if compact else 11)
	if inst.is_empty():
		name_l.text = _t("（空）")
		name_l.add_theme_color_override("font_color", UiStyle.INK_DIM)
	else:
		name_l.text = str(inst.get("name", "?"))
		name_l.add_theme_color_override("font_color", UiStyle.INK)
	inner.add_child(name_l)
	if not inst.is_empty():
		var btn := Button.new()
		btn.text = _t("卸下")
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
	var is_weapon := EquipmentSystem.normalize_slot(str(inst.get("slot", ""))) == "weapon"
	var highlight := _pending_loadout >= 0 and is_weapon
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1.0, 0.96, 0.9, 1) if highlight else Color(0.97, 0.95, 0.93, 1)
	st.border_color = Color(0.9, 0.5, 0.2, 0.9) if highlight else Color(0.76, 0.37, 0.45, 0.55)
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
	if is_weapon:
		var line := str(inst.get("line", ""))
		if line != "":
			ql.text = "%s · %s" % [ql.text, line]
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.add_theme_font_size_override("font_size", 10)
	ql.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ql)
	return cell


func wear(uid: String) -> void:
	var inst := EquipmentSystem.find_bag(uid)
	if inst.is_empty():
		_host.ui_toast(_t("背包沒有此裝。"))
		open()
		return
	var is_weapon := EquipmentSystem.normalize_slot(str(inst.get("slot", ""))) == "weapon"
	if _pending_loadout >= 0:
		if not is_weapon:
			_host.ui_toast(_t("請選擇武器裝入武器欄。"))
			return
		var r: Dictionary = EquipmentSystem.equip_weapon_to_loadout(uid, _pending_loadout)
		_host.ui_toast(str(r.get("msg", "")))
		_pending_loadout = -1
		open()
		return
	var r2: Dictionary = EquipmentSystem.equip(uid)
	_host.ui_toast(str(r2.get("msg", "")))
	open()


func unequip(slot: String) -> void:
	var r: Dictionary = EquipmentSystem.unequip(slot)
	_host.ui_toast(str(r.get("msg", "")))
	open()
