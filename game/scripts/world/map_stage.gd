@tool
extends Node2D
class_name MapStage
## 編輯器可預覽的地圖層。開 `scenes/maps/*.tscn` 即可擺裝飾／標記。
## 執行期由 ExploreView 掛上；EditorPreview 只在編輯器顯示半透明底圖。

@export var map_id: String = ""
@export var art_id: String = ""
@export var world_size: Vector2 = Vector2(1200, 700)


func _ready() -> void:
	_sync_editor_preview()


func _sync_editor_preview() -> void:
	var prev := get_node_or_null("EditorPreview")
	if prev == null:
		return
	## 遊戲執行時隱藏預覽底圖（ExploreView 已有正式底圖），避免疊兩層
	if not Engine.is_editor_hint():
		prev.visible = false
		return
	prev.visible = true
	if prev is Sprite2D and art_id != "":
		var path_webp := "res://assets/sprites/maps/%s_bg.webp" % art_id
		var path_png := "res://assets/sprites/maps/%s_bg.png" % art_id
		var tex: Texture2D = null
		if ResourceLoader.exists(path_webp):
			tex = load(path_webp) as Texture2D
		elif ResourceLoader.exists(path_png):
			tex = load(path_png) as Texture2D
		if tex and (prev as Sprite2D).texture != tex:
			(prev as Sprite2D).texture = tex


func spawn_marker() -> Marker2D:
	return get_node_or_null("Markers/Spawn") as Marker2D


func decor_root() -> Node2D:
	return get_node_or_null("Decor") as Node2D


## 把 Decor 下的 Sprite2D 位置列出來（給測試／除錯）
func list_decor_sprites() -> Array:
	var root := decor_root()
	if root == null:
		return []
	var out: Array = []
	for c in root.get_children():
		if c is Sprite2D:
			out.append({
				"name": c.name,
				"pos": (c as Node2D).position,
				"has_tex": (c as Sprite2D).texture != null,
			})
	return out
