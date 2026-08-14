class_name WindowDrag
extends RefCounted
## 讓 Control 視窗可拖曳；可選 layout_key 在放開時寫入 UiLayout

static func attach(window: Control, handle: Control, layout_key: String = "") -> void:
	if window == null or handle == null:
		return
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"dragging": false, "grab": Vector2.ZERO}
	handle.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					state["dragging"] = true
					state["grab"] = window.get_global_mouse_position() - window.global_position
					window.z_index = maxi(window.z_index, 70)
					handle.accept_event()
				else:
					if bool(state["dragging"]):
						state["dragging"] = false
						if layout_key != "":
							_save_layout(window, layout_key)
					handle.accept_event()
		elif ev is InputEventMouseMotion and bool(state["dragging"]):
			var gp: Vector2 = window.get_global_mouse_position() - (state["grab"] as Vector2)
			var vp := window.get_viewport().get_visible_rect().size
			var sz := window.size
			if sz.x < 8.0 or sz.y < 8.0:
				sz = window.get_combined_minimum_size()
			gp.x = clampf(gp.x, -sz.x + 80.0, vp.x - 40.0)
			gp.y = clampf(gp.y, 0.0, vp.y - 40.0)
			window.global_position = gp
			handle.accept_event()
	)


static func _save_layout(window: Control, layout_key: String) -> void:
	if Engine.get_main_loop() is SceneTree:
		var ul: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiLayout")
		if ul and ul.has_method("set_pos"):
			## 用 position（相對父）存；若父是全螢幕 root 則等同 global
			var pos: Vector2 = window.position
			ul.call("set_pos", layout_key, pos, true)
