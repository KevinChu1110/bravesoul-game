class_name ExploreView
extends Control
## 俯視可走場景（Control 座標，免物理）。WASD／方向鍵移動，靠近按 E 互動。
## 2D：地圖底圖 + TileMap 地磚 + 實心格碰撞 + 角色／NPC。

signal interacted(id: String)
signal hint_changed(text: String)

const SPEED := 240.0
const PLAYER_SIZE := Vector2(48, 64)
## 腳底碰撞盒（相對 player_pos）
const PLAYER_HIT := Rect2(10, 44, 28, 16)
const INTERACT_DIST := 64.0
const WALK_FPS := 8.0

var map_id: String = ""
var frozen: bool = false
var player_pos: Vector2 = Vector2(200, 360)
var _bounds: Rect2 = Rect2(40, 80, 1200, 560)
var _entities: Array = []  ## Dictionary id,pos,size,label,color,solid
var _near_id: String = ""
var _player: TextureRect
var _player_shadow: ColorRect
var _hint: Label
var _title: Label
var _minimap_root: PanelContainer
var _mmap_view: Control
var _mmap_player: ColorRect
var _mmap_cam: ColorRect
var _mmap_dots: Control
var _mmap_label: Label
var _mmap_size: Vector2 = Vector2(148, 100)
var _entity_nodes: Dictionary = {}  ## id -> Control root
var _bg: ColorRect
var _floor: TextureRect
var _floor_tint: ColorRect
var _tile_host: Node2D  ## TileMap 掛點
var _tile_map: TileMapLayer  ## 地面
var _wall_map: TileMapLayer  ## 牆／實心視覺
var _banner: TextureRect
var _vignette: ColorRect
var _scroll: Control  ## 攝影機層：整塊世界內容
var _world: Control  ## 世界層（實體 + 玩家，Y 排序）
var _facing_left: bool = false
var _walk_t: float = 0.0
var _moving: bool = false
var _banner_base_x: float = 40.0
const TILE_PX := 32
## 動態可行走區（大地圖）
var FLOOR_RECT := Rect2(40, 80, 1200, 560)
var _cam: Vector2 = Vector2.ZERO
const MapCatalog = preload("res://scripts/world/map_catalog.gd")
var _tileset_cache: Dictionary = {}  ## kind -> TileSet
## 格座標 -> true 實心（相對 TileHost，即 FLOOR 內）
var _solid: Dictionary = {}
var _map_cols: int = 0
var _map_rows: int = 0
var _guide_hint: String = ""  ## 教學殘留提示（無靠近物時顯示）
var _bubbles: Array = []  ## {node, life}
var _ambient_t: float = 0.0
var _ghost_host: Control = null
var _ghosts: Array = []  ## {root, phase}
var _presence_loaded: bool = false


func _place_minimap_default() -> void:
	if _minimap_root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var fallback := Vector2(vp.x - _minimap_root.size.x - 8, 8)
	if Engine.get_main_loop() is SceneTree:
		var ul: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiLayout")
		if ul and ul.has_method("has_pos") and ul.call("has_pos", "minimap"):
			ul.call("apply_to", _minimap_root, "minimap", fallback)
			return
	_minimap_root.position = fallback


func show_guide_hint(text: String) -> void:
	_guide_hint = text
	if _hint and _near_id == "":
		_hint.text = text if text != "" else "WASD／方向鍵移動 · 靠近後按 E 互動"
		hint_changed.emit(_hint.text)


func setup(p_map_id: String) -> void:
	map_id = p_map_id
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()
	_load_map(p_map_id)
	_apply_map_art(p_map_id)
	_rebuild_entities()
	_rebuild_collision()
	_rebuild_minimap()
	_update_player_visual()
	_ysort_world()
	_update_camera()
	hint_changed.emit("WASD 移動 · E 互動 · M 開關小地圖 · 路標切換分區")
	call_deferred("_request_presence")


func set_frozen(v: bool) -> void:
	frozen = v


func entity_label(id: String) -> String:
	for e in _entities:
		if str(e.get("id", "")) == id:
			return str(e.get("label", id))
	return id


func show_player_bubble(text: String, secs: float = 2.0) -> void:
	_spawn_bubble(player_pos + Vector2(PLAYER_SIZE.x * 0.5, -8), text, secs, Color(0.98, 0.95, 0.88))


func _request_presence() -> void:
	## 星途殘影：有連線才拉；離線顯示本地「假足迹」氛圍
	_clear_ghosts()
	if OnlineGate.is_online_enabled():
		OnlineGate.fetch_presence(map_id, _on_presence_result)
		return
	_spawn_offline_footprints()


func _on_presence_result(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	var list: Array = res.get("list", [])
	if list.is_empty():
		_spawn_offline_footprints()
		return
	var i := 0
	for row in list:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var uid := str(row.get("user_id", "g%d" % i))
		if OnlineGate.user_id != "" and uid == OnlineGate.user_id:
			continue
		var name_s := str(row.get("display_name", "星途旅人"))
		var pos := _ghost_pos_for(uid, i)
		_spawn_ghost(pos, name_s, false)
		i += 1
		if i >= 12:
			break
	if i == 0:
		_spawn_offline_footprints()
	_presence_loaded = true


func _spawn_offline_footprints() -> void:
	## 氛圍用：非同步「可能有人來過」
	var seeds := ["灰影", "無名人", "遠方的氣味"]
	for i in mini(2, seeds.size()):
		var pos := _ghost_pos_for("offline_%s_%d" % [map_id, i], i + 3)
		_spawn_ghost(pos, seeds[i], true)
	_presence_loaded = true


func _ghost_pos_for(key: String, salt: int) -> Vector2:
	var h := int(abs(key.hash()) + salt * 9973)
	var w := maxf(200.0, FLOOR_RECT.size.x - 120.0)
	var hh := maxf(160.0, FLOOR_RECT.size.y - 120.0)
	var x := FLOOR_RECT.position.x + 60.0 + float(h % int(w))
	var y := FLOOR_RECT.position.y + 40.0 + float((h / 7) % int(hh))
	return Vector2(x, y)


func _clear_ghosts() -> void:
	for g in _ghosts:
		var n: Node = g.get("root")
		if n and is_instance_valid(n):
			n.queue_free()
	_ghosts.clear()


func _spawn_ghost(pos: Vector2, name_s: String, offline_style: bool) -> void:
	if _world == null:
		return
	if _ghost_host == null:
		_ghost_host = Control.new()
		_ghost_host.name = "PresenceGhosts"
		_ghost_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(_ghost_host)
	var root := Control.new()
	root.position = pos
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = -1
	_ghost_host.add_child(root)

	var body := ColorRect.new()
	body.size = Vector2(36, 48)
	body.position = Vector2(0, 8)
	if offline_style:
		body.color = Color(0.55, 0.6, 0.75, 0.28)
	else:
		body.color = Color(0.75, 0.85, 1.0, 0.38)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)

	var head := ColorRect.new()
	head.size = Vector2(22, 20)
	head.position = Vector2(7, 0)
	head.color = body.color.lightened(0.15)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)

	var lab := Label.new()
	lab.text = name_s if name_s.length() <= 8 else name_s.substr(0, 7) + "…"
	lab.position = Vector2(-10, -18)
	lab.add_theme_font_size_override("font_size", 10)
	lab.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.75))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	lab.add_theme_constant_override("shadow_offset_x", 1)
	lab.add_theme_constant_override("shadow_offset_y", 1)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lab)

	root.set_meta("sort_y", pos.y + 56.0)
	_ghosts.append({"root": root, "phase": float(pos.x * 0.01), "base_y": pos.y})


func _process_ghosts(delta: float) -> void:
	for g in _ghosts:
		var root: Control = g.get("root")
		if root == null or not is_instance_valid(root):
			continue
		var ph: float = float(g.get("phase", 0.0)) + delta
		g["phase"] = ph
		var base_y: float = float(g.get("base_y", root.position.y))
		root.position.y = base_y + sin(ph * 1.7) * 3.0
		root.modulate.a = 0.75 + 0.2 * sin(ph * 2.3)


func show_entity_bubble(id: String, text: String = "", secs: float = 2.2) -> void:
	for e in _entities:
		if str(e.get("id", "")) != id:
			continue
		var pos: Vector2 = e.pos + Vector2(e.size.x * 0.5, -6)
		var t := text if text != "" else str(e.get("label", "..."))
		_spawn_bubble(pos, t, secs, Color(1, 1, 1))
		return


func _spawn_bubble(world_pos: Vector2, text: String, secs: float, fill: Color) -> void:
	if _world == null or text == "":
		return
	## 截短
	var t := text
	if t.length() > 28:
		t = t.substr(0, 26) + "…"
	var root := PanelContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(fill.r, fill.g, fill.b, 0.95)
	sb.border_color = Color(0.28, 0.18, 0.1, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	root.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = t
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", Color(0.18, 0.14, 0.1, 1))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lab)
	_world.add_child(root)
	## 先放再量寬
	root.position = world_pos - Vector2(40, 28)
	call_deferred("_center_bubble", root, world_pos)
	_bubbles.append({"node": root, "life": secs})


func _center_bubble(root: Control, world_pos: Vector2) -> void:
	if root and is_instance_valid(root):
		root.position = world_pos - Vector2(root.size.x * 0.5, root.size.y + 4)


func _process_bubbles(delta: float) -> void:
	var keep: Array = []
	for b in _bubbles:
		var n: Control = b.get("node")
		var life: float = float(b.get("life", 0)) - delta
		if n == null or not is_instance_valid(n) or life <= 0.0:
			if n and is_instance_valid(n):
				n.queue_free()
			continue
		b["life"] = life
		if life < 0.35:
			n.modulate.a = life / 0.35
		keep.append(b)
	_bubbles = keep


func _try_ambient_bubble() -> void:
	## 附近 NPC 偶爾冒泡（楓式氛圍）
	var lines := {
		"maisui": "……還活著就好。",
		"greybeard": "哼。旗還在。",
		"ding": "鐵還熱。",
		"sprout": "我也想練劍……",
		"star": "星屑不等人。",
		"merchant": "六域的價碼我都懂。",
		"fog_hide": "霧裡……有人在笑。",
		"acha": "茶涼了再打。",
		"wind_ear": "風說……有客。",
		"tide_roar": "浪比人實在。",
		"duanye": "卷末未寫完。",
	}
	var pc := _player_center()
	var candidates: Array = []
	for e in _entities:
		var id := str(e.get("id", ""))
		if not lines.has(id):
			continue
		var ec: Vector2 = e.pos + e.size * 0.5
		if pc.distance_to(ec) < 220.0:
			candidates.append(id)
	if candidates.is_empty():
		return
	var pick: String = str(candidates[randi() % candidates.size()])
	show_entity_bubble(pick, str(lines[pick]), 2.4)


func _build_chrome() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.06, 0.05, 0.08)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	## 可捲動世界層（地板 + tile + 實體）
	_scroll = Control.new()
	_scroll.name = "ScrollWorld"
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 不 clip：大世界需要畫在 viewport 內由相機位移
	add_child(_scroll)

	_floor = TextureRect.new()
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_floor.stretch_mode = TextureRect.STRETCH_SCALE
	_scroll.add_child(_floor)

	## 真 TileMap：地面 + 牆層
	_tile_host = Node2D.new()
	_tile_host.name = "TileHost"
	_tile_host.z_index = 0
	_scroll.add_child(_tile_host)
	_tile_map = TileMapLayer.new()
	_tile_map.name = "Ground"
	_tile_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tile_map.modulate = Color(1, 1, 1, 0.88)
	_tile_host.add_child(_tile_map)
	_wall_map = TileMapLayer.new()
	_wall_map.name = "Walls"
	_wall_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wall_map.modulate = Color(1, 1, 1, 0.95)
	_tile_host.add_child(_wall_map)

	_floor_tint = ColorRect.new()
	_floor_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_tint.color = Color(0, 0, 0, 0.12)
	_scroll.add_child(_floor_tint)

	_banner = TextureRect.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_banner.modulate = Color(1, 1, 1, 0.78)
	_scroll.add_child(_banner)

	## 底部 vignette 加深景深
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0.02, 0.02, 0.04, 0.35)
	_scroll.add_child(_vignette)

	_world = Control.new()
	_world.name = "World"
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_world)

	## 楓式地圖名：小木牌（避開左上狀態板）
	_title = Label.new()
	_title.position = Vector2(240, 10)
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color(0.2, 0.14, 0.1, 1))
	_title.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))
	_title.add_theme_constant_override("shadow_offset_x", 1)
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var title_chip := PanelContainer.new()
	title_chip.position = Vector2(232, 6)
	title_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tcs := StyleBoxFlat.new()
	tcs.bg_color = Color(0.96, 0.93, 0.86, 0.9)
	tcs.border_color = Color(0.42, 0.28, 0.14, 1)
	tcs.set_border_width_all(2)
	tcs.set_corner_radius_all(2)
	tcs.content_margin_left = 8
	tcs.content_margin_right = 8
	tcs.content_margin_top = 2
	tcs.content_margin_bottom = 2
	title_chip.add_theme_stylebox_override("panel", tcs)
	add_child(title_chip)
	## 把 title 掛在 chip 上
	remove_child(_title)
	title_chip.add_child(_title)
	_title.position = Vector2.ZERO

	_build_minimap_ui()

	## 底部楓式小提示（居中窄條）
	var hint_bar := PanelContainer.new()
	hint_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_bar.offset_top = -36
	hint_bar.offset_bottom = -6
	hint_bar.offset_left = 200
	hint_bar.offset_right = -200
	hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.98, 0.95, 0.88, 0.92)
	hs.border_color = Color(0.42, 0.28, 0.14, 1)
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(2)
	hs.content_margin_left = 10
	hs.content_margin_right = 10
	hs.content_margin_top = 3
	hs.content_margin_bottom = 3
	hint_bar.add_theme_stylebox_override("panel", hs)
	add_child(hint_bar)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.22, 0.16, 0.12, 1))
	_hint.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.5))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_bar.add_child(_hint)

	_player_shadow = ColorRect.new()
	_player_shadow.size = Vector2(36, 10)
	_player_shadow.color = Color(0, 0, 0, 0.4)
	_player_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_player_shadow)

	_player = TextureRect.new()
	_player.size = PLAYER_SIZE
	_player.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.texture = SpriteDB.player_idle()
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.add_child(_player)

	## 楓式角色名牌（頭上）
	var name_tag := PanelContainer.new()
	name_tag.name = "PlayerNameTag"
	name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nts := StyleBoxFlat.new()
	nts.bg_color = Color(0.98, 0.95, 0.88, 0.92)
	nts.border_color = Color(0.28, 0.18, 0.1, 1)
	nts.set_border_width_all(1)
	nts.set_corner_radius_all(2)
	nts.content_margin_left = 5
	nts.content_margin_right = 5
	nts.content_margin_top = 0
	nts.content_margin_bottom = 0
	name_tag.add_theme_stylebox_override("panel", nts)
	var ntl := Label.new()
	ntl.text = str(GameState.player_name) if str(GameState.player_name) != "" else "小白"
	ntl.add_theme_font_size_override("font_size", 10)
	ntl.add_theme_color_override("font_color", Color(0.2, 0.14, 0.1, 1))
	ntl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_tag.add_child(ntl)
	_world.add_child(name_tag)
	name_tag.set_meta("is_player_tag", true)


func _apply_map_art(id: String) -> void:
	var floor_rect := FLOOR_RECT
	_floor.position = floor_rect.position
	_floor.size = floor_rect.size
	_floor_tint.position = floor_rect.position
	_floor_tint.size = floor_rect.size
	_vignette.position = Vector2(floor_rect.position.x, floor_rect.position.y + floor_rect.size.y * 0.55)
	_vignette.size = Vector2(floor_rect.size.x, floor_rect.size.y * 0.45)

	## 底圖：專用 art → map id → 母域 fallback
	var art_id := id
	var data: Dictionary = MapCatalog.build(id)
	if data.has("art"):
		art_id = str(data.get("art", id))
	var bg_tex := SpriteDB.map_bg(art_id)
	if bg_tex == null:
		bg_tex = SpriteDB.map_bg(id)
	if bg_tex == null:
		## 前綴 fallback（產圖未完成時仍可看母域）
		for prefix in ["village", "road", "town", "wild", "mist", "dojo", "forest", "coast", "tower"]:
			if str(art_id).begins_with(prefix) or str(id).begins_with(prefix):
				bg_tex = SpriteDB.map_bg(prefix if prefix != "mist" else "mist_village")
				if bg_tex:
					break
	if bg_tex:
		_floor.texture = bg_tex
		_floor.modulate = Color(0.55, 0.55, 0.6, 0.55)
		_floor_tint.color = Color(0, 0, 0, 0.08)
	else:
		_floor.texture = null
		_floor_tint.color = Color(0.12, 0.1, 0.1, 0.5)

	_build_tilemap(art_id if art_id != "" else id)

	var banner_path := "res://assets/sprites/maps/%s_banner.png" % art_id
	if not ResourceLoader.exists(banner_path):
		banner_path = "res://assets/sprites/maps/%s_banner.png" % id
	if ResourceLoader.exists(banner_path):
		_banner.texture = load(banner_path) as Texture2D
		_banner_base_x = floor_rect.position.x
		_banner.position = Vector2(_banner_base_x, floor_rect.position.y)
		_banner.size = Vector2(minf(1400.0, floor_rect.size.x), 150)
		_banner.visible = true
	else:
		_banner.visible = false
		_banner.texture = null
	_update_camera()


func _get_or_make_tileset(kind: String) -> TileSet:
	if _tileset_cache.has(kind):
		return _tileset_cache[kind]
	var path := "res://assets/sprites/tiles/%s_atlas.png" % kind
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = SpriteDB.tile(kind)
	if tex == null:
		return null
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	## atlas 4 變體橫排；單圖則只建 (0,0)
	var cols := maxi(1, int(tex.get_width() / TILE_PX))
	for i in cols:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	_tileset_cache[kind] = ts
	return ts


func _build_tilemap(map_id_s: String) -> void:
	if _tile_map == null or _tile_host == null:
		return
	_tile_host.position = FLOOR_RECT.position
	var kind := SpriteDB.map_tile_kind(map_id_s)
	var ts := _get_or_make_tileset(kind)
	if ts == null:
		_tile_map.clear()
		if _wall_map:
			_wall_map.clear()
		return
	_tile_map.tile_set = ts
	_tile_map.clear()
	_map_cols = int(FLOOR_RECT.size.x / TILE_PX)
	_map_rows = int(FLOOR_RECT.size.y / TILE_PX)
	var seed_n := map_id_s.hash()
	var variants := 4
	var src: TileSetSource = ts.get_source(0)
	if src is TileSetAtlasSource:
		var atlas := src as TileSetAtlasSource
		if atlas.texture:
			variants = maxi(1, int(atlas.texture.get_width() / TILE_PX))
	for y in _map_rows:
		for x in _map_cols:
			var n := int(abs(sin(float(x * 12 + y * 7 + seed_n)) * 1000.0))
			var vi := n % variants
			if map_id_s in ["town", "dojo"] and (y == _map_rows / 2 or y == _map_rows / 2 + 1):
				vi = 0
			if map_id_s == "road" and abs(y - _map_rows / 2) <= 1:
				vi = mini(1, variants - 1)
			_tile_map.set_cell(Vector2i(x, y), 0, Vector2i(vi, 0))
	_tile_map.modulate = Color(1, 1, 1, 0.92)
	## 牆層 tileset
	var wall_ts := _get_or_make_tileset("wall")
	if _wall_map and wall_ts:
		_wall_map.tile_set = wall_ts
		_wall_map.clear()
	_solid.clear()


func _load_map(id: String) -> void:
	_entities.clear()
	var data: Dictionary = MapCatalog.build(id)
	_title.text = str(data.get("title", id))
	_bg.color = data.get("bg_color", Color(0.08, 0.08, 0.1)) as Color
	var origin: Vector2 = data.get("origin", Vector2(40, 80))
	var msize: Vector2 = data.get("size", Vector2(1600, 900))
	FLOOR_RECT = Rect2(origin, msize)
	_bounds = Rect2(origin + Vector2(20, 20), msize - Vector2(40, 40))
	player_pos = data.get("spawn", origin + Vector2(160, 360)) as Vector2
	var raw_ents: Array = data.get("entities", [])
	for e in raw_ents:
		if typeof(e) == TYPE_DICTIONARY:
			_entities.append(e)
	if _mmap_label:
		_mmap_label.text = "%s  ·  %.0f×%.0f" % [str(data.get("title", id)), msize.x, msize.y]


func _ent(id: String, pos: Vector2, size: Vector2, label: String, color: Color, solid: bool = false) -> Dictionary:
	return {"id": id, "pos": pos, "size": size, "label": label, "color": color, "solid": solid}


## 建築／障礙預設實心（NPC 可走過去方便互動）
func _entity_is_solid(e: Dictionary) -> bool:
	if bool(e.get("solid", false)):
		return true
	var id := str(e.get("id", ""))
	const SOLIDS: Array[String] = [
		"fire", "flag", "tower", "leo_gate", "inn", "fog_gate",
		"gate_bell", "trial_hall", "treehouse", "watch_tower", "falcon_nest",
		"dock", "forge_c5", "boar_cliff",
		"hut_a", "hut_b", "hut_c", "well", "cart", "market", "market_b", "fountain", "gate_arch",
		"wall_notice", "milepost", "milepost_b", "camp", "bridge", "fence_row",
		"well_fog", "shrine", "shrine_stub", "scroll_wall", "runestone", "boat_wreck",
		"barracks", "chapel", "stable", "hall", "throne_hall", "keep_well", "statue_knight",
		"ravine", "windmill", "pond", "dorm", "tower_gate", "tent_a", "tent_b",
		"refugee_fire", "altar", "beacon", "sign_board", "ruin_pillar", "falcon_nest_deep",
	]
	return id in SOLIDS


func _rebuild_collision() -> void:
	_solid.clear()
	if _wall_map:
		_wall_map.clear()
	if _map_cols <= 0 or _map_rows <= 0:
		_map_cols = int(FLOOR_RECT.size.x / TILE_PX)
		_map_rows = int(FLOOR_RECT.size.y / TILE_PX)
	## 1) 地圖邊界一圈實心牆
	for x in _map_cols:
		_set_solid(Vector2i(x, 0), true, true)
		_set_solid(Vector2i(x, _map_rows - 1), true, true)
	for y in _map_rows:
		_set_solid(Vector2i(0, y), true, true)
		_set_solid(Vector2i(_map_cols - 1, y), true, true)
	## 2) 建築佔位（上半身，底部留互動縫）
	for e in _entities:
		if not _entity_is_solid(e):
			continue
		var pos: Vector2 = e.pos
		var sz: Vector2 = e.size
		## 碰撞區：略縮、偏上，腳邊可站
		var r := Rect2(pos.x + 6.0, pos.y + 4.0, maxf(8.0, sz.x - 12.0), maxf(8.0, sz.y * 0.55))
		_stamp_solid_rect(r, true)
	## 確保玩家出生點不在實心上
	_unstuck_player()


func _set_solid(cell: Vector2i, solid: bool, paint_wall: bool = false) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= _map_cols or cell.y >= _map_rows:
		return
	if solid:
		_solid[cell] = true
		if paint_wall and _wall_map and _wall_map.tile_set:
			var vi: int = absi(cell.x * 3 + cell.y * 7) % 4
			_wall_map.set_cell(cell, 0, Vector2i(vi, 0))
	else:
		_solid.erase(cell)
		if _wall_map:
			_wall_map.erase_cell(cell)


func _stamp_solid_rect(world_rect: Rect2, paint_wall: bool = false) -> void:
	## world → tile（相對 FLOOR）
	var local := Rect2(world_rect.position - FLOOR_RECT.position, world_rect.size)
	var x0 := int(floor(local.position.x / TILE_PX))
	var y0 := int(floor(local.position.y / TILE_PX))
	var x1 := int(floor((local.position.x + local.size.x - 0.01) / TILE_PX))
	var y1 := int(floor((local.position.y + local.size.y - 0.01) / TILE_PX))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_set_solid(Vector2i(x, y), true, paint_wall)


func _world_to_cell(world: Vector2) -> Vector2i:
	var local := world - FLOOR_RECT.position
	return Vector2i(int(floor(local.x / TILE_PX)), int(floor(local.y / TILE_PX)))


func _is_solid_cell(cell: Vector2i) -> bool:
	return bool(_solid.get(cell, false))


## 腳底四角是否可站
func _can_stand_at(pos: Vector2) -> bool:
	var hit := Rect2(pos + PLAYER_HIT.position, PLAYER_HIT.size)
	## 仍受 bounds 限制
	if hit.position.x < _bounds.position.x or hit.position.y < _bounds.position.y:
		return false
	if hit.end.x > _bounds.end.x or hit.end.y > _bounds.end.y:
		return false
	var corners: Array[Vector2] = [
		hit.position,
		Vector2(hit.end.x - 0.1, hit.position.y),
		Vector2(hit.position.x, hit.end.y - 0.1),
		Vector2(hit.end.x - 0.1, hit.end.y - 0.1),
		hit.get_center(),
	]
	for c in corners:
		if _is_solid_cell(_world_to_cell(c)):
			return false
	return true


func _try_move(delta: float, dir: Vector2) -> void:
	var step := dir * SPEED * delta
	## 軸分離：可沿牆滑
	var try_x := player_pos + Vector2(step.x, 0.0)
	if _can_stand_at(try_x):
		player_pos.x = try_x.x
	var try_y := player_pos + Vector2(0.0, step.y)
	if _can_stand_at(try_y):
		player_pos.y = try_y.y
	player_pos.x = clampf(player_pos.x, _bounds.position.x, _bounds.end.x - PLAYER_SIZE.x)
	player_pos.y = clampf(player_pos.y, _bounds.position.y, _bounds.end.y - PLAYER_SIZE.y)


func _unstuck_player() -> void:
	if _can_stand_at(player_pos):
		return
	## 向四周找空位
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cand := player_pos + Vector2(dx * TILE_PX * 0.5, dy * TILE_PX * 0.5)
				cand.x = clampf(cand.x, _bounds.position.x, _bounds.end.x - PLAYER_SIZE.x)
				cand.y = clampf(cand.y, _bounds.position.y, _bounds.end.y - PLAYER_SIZE.y)
				if _can_stand_at(cand):
					player_pos = cand
					return


func _rebuild_entities() -> void:
	for k in _entity_nodes.keys():
		var n: Node = _entity_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
	_entity_nodes.clear()
	for e in _entities:
		var root := Control.new()
		root.position = e.pos
		root.size = e.size
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.set_meta("sort_y", e.pos.y + e.size.y)
		_world.add_child(root)

		## 底座陰影
		var shadow := ColorRect.new()
		shadow.size = Vector2(e.size.x * 0.7, 8)
		shadow.position = Vector2(e.size.x * 0.15, e.size.y - 6)
		shadow.color = Color(0, 0, 0, 0.35)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shadow)

		var tex := SpriteDB.explore_entity_tex(e.id)
		if tex:
			var spr := TextureRect.new()
			spr.set_anchors_preset(Control.PRESET_FULL_RECT)
			spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(spr)
		else:
			var box := ColorRect.new()
			box.set_anchors_preset(Control.PRESET_FULL_RECT)
			box.color = e.color
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(box)

		var lab := Label.new()
		lab.text = e.label
		lab.position = Vector2(-8, -22)
		lab.add_theme_font_size_override("font_size", 13)
		lab.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("shadow_offset_x", 1)
		lab.add_theme_constant_override("shadow_offset_y", 1)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(lab)
		root.set_meta("label_node", lab)
		## 靠近時顯示的 E 徽章
		var badge := Label.new()
		badge.text = " E "
		badge.visible = false
		badge.position = Vector2(e.size.x * 0.5 - 12, -44)
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08))
		badge.add_theme_color_override("font_shadow_color", Color(0.95, 0.8, 0.4, 0.9))
		badge.add_theme_constant_override("shadow_offset_x", 0)
		badge.add_theme_constant_override("shadow_offset_y", 0)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		## 黃底小牌
		var badge_bg := ColorRect.new()
		badge_bg.color = Color(0.92, 0.78, 0.35, 0.95)
		badge_bg.size = Vector2(28, 20)
		badge_bg.position = Vector2(e.size.x * 0.5 - 14, -46)
		badge_bg.visible = false
		badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(badge_bg)
		root.add_child(badge)
		root.set_meta("badge", badge)
		root.set_meta("badge_bg", badge_bg)
		root.pivot_offset = e.size * 0.5
		_entity_nodes[e.id] = root

	_ysort_world()
	## HUD 置頂（只動仍掛在 ExploreView 根上的節點）
	if _minimap_root and _minimap_root.get_parent() == self:
		move_child(_minimap_root, get_child_count() - 1)
	if _title and _title.get_parent() and _title.get_parent().get_parent() == self:
		var chip: Node = _title.get_parent()
		move_child(chip, get_child_count() - 1)
	elif _title and _title.get_parent() == self:
		move_child(_title, get_child_count() - 1)
	if _hint and _hint.get_parent() and _hint.get_parent().get_parent() == self:
		move_child(_hint.get_parent(), get_child_count() - 1)
	elif _hint and _hint.get_parent() == self:
		move_child(_hint, get_child_count() - 1)


func _ysort_world() -> void:
	## 依腳底 Y 排序：後排先畫、前排後畫
	if _world == null:
		return
	var kids: Array = _world.get_children()
	kids.sort_custom(func(a: Node, b: Node) -> bool:
		var ay := _sort_y_of(a)
		var by := _sort_y_of(b)
		if ay == by:
			return a.get_index() < b.get_index()
		return ay < by
	)
	for i in kids.size():
		_world.move_child(kids[i], i)


func _sort_y_of(n: Node) -> float:
	if n is Control:
		var c := n as Control
		if c.has_meta("sort_y"):
			return float(c.get_meta("sort_y"))
		return c.position.y + c.size.y
	return 0.0


func _process(delta: float) -> void:
	_process_bubbles(delta)
	_process_ghosts(delta)
	_ambient_t += delta
	if _ambient_t >= 7.5 and not frozen:
		_ambient_t = 0.0
		_try_ambient_bubble()
	if frozen:
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y += 1
	_moving = dir != Vector2.ZERO
	if _moving:
		dir = dir.normalized()
		if dir.x < -0.1:
			_facing_left = true
		elif dir.x > 0.1:
			_facing_left = false
		_try_move(delta, dir)
		_walk_t += delta * WALK_FPS
		AudioManager.play_step()
	else:
		_walk_t = 0.0
	_update_player_visual()
	_update_camera()
	_update_parallax()
	_update_near()
	if _moving:
		_ysort_world()


func _build_minimap_ui() -> void:
	## 右上角可視化小地圖
	_minimap_root = PanelContainer.new()
	_minimap_root.name = "MiniMap"
	## 自由定位（可拖），預設右上
	_minimap_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_minimap_root.position = Vector2(1280 - 196, 8)
	_minimap_root.custom_minimum_size = Vector2(180, 140)
	_minimap_root.size = Vector2(180, 140)
	_minimap_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.96, 0.93, 0.86, 0.92)
	ps.border_color = Color(0.42, 0.28, 0.14, 1)
	ps.set_border_width_all(3)
	ps.set_corner_radius_all(2)
	ps.content_margin_left = 6
	ps.content_margin_right = 6
	ps.content_margin_top = 4
	ps.content_margin_bottom = 4
	ps.shadow_color = Color(0, 0, 0, 0.3)
	ps.shadow_size = 3
	_minimap_root.add_theme_stylebox_override("panel", ps)
	add_child(_minimap_root)
	call_deferred("_place_minimap_default")

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_root.add_child(v)

	var head := PanelContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	var hps := StyleBoxFlat.new()
	hps.bg_color = Color(0.90, 0.84, 0.70, 1)
	hps.set_corner_radius_all(2)
	hps.content_margin_left = 4
	hps.content_margin_right = 4
	hps.content_margin_top = 1
	hps.content_margin_bottom = 1
	head.add_theme_stylebox_override("panel", hps)
	v.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_row)
	var ht := Label.new()
	ht.text = "小地圖 · 拖移"
	ht.add_theme_font_size_override("font_size", 11)
	ht.add_theme_color_override("font_color", Color(0.28, 0.18, 0.1, 1))
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(ht)
	var tip := Label.new()
	tip.text = "M"
	tip.add_theme_font_size_override("font_size", 10)
	tip.add_theme_color_override("font_color", Color(0.45, 0.35, 0.22, 1))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(tip)
	## 拖曳小地圖（位置寫入存檔）
	var WD = load("res://scripts/ui/window_drag.gd")
	if WD:
		WD.attach(_minimap_root, head, "minimap")

	_mmap_view = Control.new()
	_mmap_view.custom_minimum_size = _mmap_size
	_mmap_view.size = _mmap_size
	_mmap_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mmap_view.clip_contents = true
	v.add_child(_mmap_view)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.16, 0.14, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mmap_view.add_child(bg)

	## 邊框內框
	var frame := ColorRect.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 1
	frame.offset_top = 1
	frame.offset_right = -1
	frame.offset_bottom = -1
	frame.color = Color(0.1, 0.14, 0.13, 1)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mmap_view.add_child(frame)

	_mmap_dots = Control.new()
	_mmap_dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mmap_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mmap_view.add_child(_mmap_dots)

	## 鏡頭可視框
	_mmap_cam = ColorRect.new()
	_mmap_cam.color = Color(0.9, 0.95, 1.0, 0.12)
	_mmap_cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mmap_view.add_child(_mmap_cam)
	var cam_border := ReferenceRect.new()
	cam_border.name = "CamBorder"
	cam_border.border_color = Color(0.7, 0.85, 1.0, 0.65)
	cam_border.border_width = 1.0
	cam_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mmap_cam.add_child(cam_border)

	## 玩家
	_mmap_player = ColorRect.new()
	_mmap_player.size = Vector2(7, 7)
	_mmap_player.color = Color(0.35, 0.95, 0.75, 1.0)
	_mmap_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mmap_view.add_child(_mmap_player)

	_mmap_label = Label.new()
	_mmap_label.add_theme_font_size_override("font_size", 11)
	_mmap_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.82, 0.95))
	_mmap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mmap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_mmap_label)

	var legend := Label.new()
	legend.text = "● 你  ·  路標  ·  NPC  ·  點"
	legend.add_theme_font_size_override("font_size", 10)
	legend.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 0.9))
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(legend)


func _world_to_minimap(world: Vector2) -> Vector2:
	var o := FLOOR_RECT.position
	var s := FLOOR_RECT.size
	if s.x < 1.0 or s.y < 1.0:
		return Vector2.ZERO
	var nx := (world.x - o.x) / s.x
	var ny := (world.y - o.y) / s.y
	return Vector2(nx * _mmap_size.x, ny * _mmap_size.y)


func _rebuild_minimap() -> void:
	if _mmap_dots == null:
		return
	for c in _mmap_dots.get_children():
		c.queue_free()
	for e in _entities:
		var id := str(e.get("id", ""))
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var sz: Vector2 = e.get("size", Vector2(32, 32))
		var center := pos + sz * 0.5
		var p := _world_to_minimap(center)
		var dot := ColorRect.new()
		dot.size = Vector2(4, 4)
		dot.position = p - Vector2(2, 2)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		## 路標／出口偏金；Boss 偏紅；NPC 偏青；物件偏灰
		var col := Color(0.55, 0.6, 0.55, 0.85)
		if id.begins_with("exit") or id.begins_with("path_") or id.begins_with("back_") \
				or id in ["dawn_glow", "exit_world", "world_map_stone", "sign_board", "climb_tower"]:
			col = Color(0.95, 0.8, 0.35, 0.95)
			dot.size = Vector2(5, 5)
		elif id in ["leo_gate", "fog_gate", "fog_gate_deep", "trial_hall", "falcon_nest", "falcon_nest_deep", "boar_cliff", "boar_cliff_near"]:
			col = Color(0.95, 0.4, 0.4, 0.95)
			dot.size = Vector2(6, 6)
		elif id in ["maisui", "greybeard", "ding", "star", "sprout", "fog_hide", "acha", "wind_ear", "tide_roar", "duanye", "merchant"]:
			col = Color(0.45, 0.75, 1.0, 0.95)
			dot.size = Vector2(5, 5)
		elif id.begins_with("save") or id == "menu_save":
			col = Color(0.55, 0.9, 0.7, 0.9)
		dot.color = col
		_mmap_dots.add_child(dot)
	_update_minimap_markers()


func _update_minimap_markers() -> void:
	if _mmap_player == null or _mmap_view == null:
		return
	var pc := player_pos + PLAYER_SIZE * 0.5
	var pp := _world_to_minimap(pc)
	_mmap_player.position = pp - _mmap_player.size * 0.5
	## 鏡頭框
	var view := size
	if view.x < 64.0:
		view = Vector2(1280, 720)
	var cam_tl := _world_to_minimap(_cam)
	var cam_br := _world_to_minimap(_cam + view)
	var rpos := Vector2(minf(cam_tl.x, cam_br.x), minf(cam_tl.y, cam_br.y))
	var rsz := Vector2(absf(cam_br.x - cam_tl.x), absf(cam_br.y - cam_tl.y))
	rsz.x = clampf(rsz.x, 8.0, _mmap_size.x)
	rsz.y = clampf(rsz.y, 8.0, _mmap_size.y)
	rpos.x = clampf(rpos.x, 0.0, _mmap_size.x - rsz.x)
	rpos.y = clampf(rpos.y, 0.0, _mmap_size.y - rsz.y)
	_mmap_cam.position = rpos
	_mmap_cam.size = rsz


func _update_camera() -> void:
	## 玩家居中；大地圖可捲動
	if _scroll == null:
		return
	var view := size
	if view.x < 64.0 or view.y < 64.0:
		view = Vector2(1280, 720)
	var focus := player_pos + PLAYER_SIZE * 0.5
	var target := focus - view * 0.5
	var max_x := maxf(0.0, FLOOR_RECT.end.x - view.x + 40.0)
	var max_y := maxf(0.0, FLOOR_RECT.end.y - view.y + 40.0)
	_cam.x = clampf(target.x, 0.0, max_x)
	_cam.y = clampf(target.y, 0.0, max_y)
	_scroll.position = -_cam
	_update_minimap_markers()


func _update_parallax() -> void:
	if _banner == null or not _banner.visible:
		return
	var t := (player_pos.x - _bounds.position.x) / maxf(1.0, _bounds.size.x)
	_banner.position.x = _banner_base_x - t * 48.0
	_banner.position.y = FLOOR_RECT.position.y + sin(Time.get_ticks_msec() * 0.0006) * 2.0


func _update_player_visual() -> void:
	if _player == null:
		return
	_player.position = player_pos
	_player.pivot_offset = PLAYER_SIZE * 0.5
	_player.scale.x = -1.0 if _facing_left else 1.0
	_player.set_meta("sort_y", player_pos.y + PLAYER_SIZE.y)
	if _moving:
		var frame := int(_walk_t) % 4
		var t := SpriteDB.player_walk(frame)
		if t:
			_player.texture = t
	else:
		var idle := SpriteDB.player_idle()
		if idle:
			_player.texture = idle
	if _player_shadow:
		_player_shadow.position = player_pos + Vector2(6, PLAYER_SIZE.y - 6)
		_player_shadow.size = Vector2(PLAYER_SIZE.x - 12, 10)
		_player_shadow.set_meta("sort_y", player_pos.y + PLAYER_SIZE.y - 1.0)
	var tag := _world.get_node_or_null("PlayerNameTag") as Control
	if tag:
		tag.position = player_pos + Vector2(PLAYER_SIZE.x * 0.5 - 28, -16)
		tag.set_meta("sort_y", player_pos.y - 1.0)


func _player_center() -> Vector2:
	return player_pos + PLAYER_SIZE * 0.5


func _update_near() -> void:
	var best := ""
	var best_d := INTERACT_DIST
	var pc := _player_center()
	for e in _entities:
		var ec: Vector2 = e.pos + e.size * 0.5
		var d := pc.distance_to(ec)
		if d < best_d:
			best_d = d
			best = e.id
	if best != _near_id:
		_near_id = best
		if best == "":
			if _guide_hint != "":
				_hint.text = _guide_hint
			else:
				_hint.text = "WASD／方向鍵移動 · 靠近後按 E 互動"
			_hint.modulate = Color(0.85, 0.85, 0.9)
			hint_changed.emit(_hint.text)
		else:
			var label := best
			for e in _entities:
				if e.id == best:
					label = e.label
					break
			_hint.text = "E · 互動：%s" % label
			_hint.modulate = Color(1, 0.92, 0.55)
			hint_changed.emit(_hint.text)
		_highlight_near()


func _highlight_near() -> void:
	for e in _entities:
		var root: Control = _entity_nodes.get(e.id)
		if root == null:
			continue
		var badge: Label = root.get_meta("badge") if root.has_meta("badge") else null
		var badge_bg: ColorRect = root.get_meta("badge_bg") if root.has_meta("badge_bg") else null
		if e.id == _near_id:
			root.modulate = Color(1.15, 1.12, 1.05)
			root.scale = Vector2(1.05, 1.05)
			if badge:
				badge.visible = true
			if badge_bg:
				badge_bg.visible = true
		else:
			root.modulate = Color.WHITE
			root.scale = Vector2.ONE
			if badge:
				badge.visible = false
			if badge_bg:
				badge_bg.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if _minimap_root:
			_minimap_root.visible = not _minimap_root.visible
			get_viewport().set_input_as_handled()
			return
	if frozen:
		return
	if event.is_action_pressed("interact") and _near_id != "":
		AudioManager.play_interact()
		## 聊天泡泡：先冒一句再交主流程
		var lab := entity_label(_near_id)
		if lab != "" and not lab.begins_with("往") and not lab.begins_with("回"):
			show_entity_bubble(_near_id, lab, 1.6)
		interacted.emit(_near_id)
		get_viewport().set_input_as_handled()
