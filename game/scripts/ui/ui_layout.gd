extends Node
## 楓式視窗位置記憶：寫入 GameState.ui_layout，跟存檔一起走。

signal layout_changed(key: String)

const KEYS := ["hud", "hotbar", "inv", "minimap"]


func _ready() -> void:
	pass


func ensure() -> void:
	if GameState.ui_layout == null:
		GameState.ui_layout = {}
	if typeof(GameState.ui_layout) != TYPE_DICTIONARY:
		GameState.ui_layout = {}


func has_pos(key: String) -> bool:
	ensure()
	var d: Variant = GameState.ui_layout.get(key, null)
	return d is Dictionary and d.has("x") and d.has("y")


func get_pos(key: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	ensure()
	if not has_pos(key):
		return fallback
	var d: Dictionary = GameState.ui_layout[key]
	return Vector2(float(d.get("x", fallback.x)), float(d.get("y", fallback.y)))


func set_pos(key: String, pos: Vector2, persist: bool = true) -> void:
	ensure()
	GameState.ui_layout[key] = {"x": pos.x, "y": pos.y}
	layout_changed.emit(key)
	if persist:
		## 拖曳結束即寫檔，避免只記得到關遊戲前
		if Engine.get_main_loop() is SceneTree:
			var sm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SaveManager")
			if sm and sm.has_method("save_game") and GameState.chapter != "title":
				sm.call("save_game")


func apply_to(control: Control, key: String, fallback: Vector2 = Vector2.ZERO) -> void:
	if control == null:
		return
	var p := get_pos(key, fallback)
	if p == Vector2.ZERO and not has_pos(key):
		if fallback != Vector2.ZERO:
			control.position = fallback
		return
	control.position = _clamp_pos(control, p)


func _clamp_pos(control: Control, pos: Vector2) -> Vector2:
	var vp := Vector2(1280, 720)
	if control.get_viewport():
		vp = control.get_viewport().get_visible_rect().size
	var sz := control.size
	if sz.x < 8.0 or sz.y < 8.0:
		sz = control.get_combined_minimum_size()
	if sz.x < 8.0:
		sz.x = 120.0
	if sz.y < 8.0:
		sz.y = 80.0
	pos.x = clampf(pos.x, -sz.x + 80.0, vp.x - 40.0)
	pos.y = clampf(pos.y, 0.0, vp.y - 40.0)
	return pos


func reset_all() -> void:
	ensure()
	GameState.ui_layout.clear()
	layout_changed.emit("*")
