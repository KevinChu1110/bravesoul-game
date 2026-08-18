class_name ExploreView
extends Control
## 俯視可走場景（Control 座標，免物理）。WASD／方向鍵移動，靠近按 E 互動。
## 2D：地圖底圖 + TileMap 地磚 + 實心格碰撞 + 角色／NPC。

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const UiStyle = preload("res://scripts/ui/ui_style.gd")

signal interacted(id: String)
signal hint_changed(text: String)

const SPEED := 240.0
const PLAYER_SIZE := Vector2(56, 72)
## 腳底碰撞盒（相對 player_pos）
const PLAYER_HIT := Rect2(12, 52, 32, 16)
const INTERACT_DIST := 64.0
const WALK_FPS := 8.0

var map_id: String = ""
var frozen: bool = false
var player_pos: Vector2 = Vector2(200, 360)
var _bounds: Rect2 = Rect2(40, 80, 1200, 560)
var _entities: Array = []  ## Dictionary id,pos,size,label,color,solid
var _near_id: String = ""
var _player: TextureRect
var _player_armor: TextureRect  ## 防具疊層
var _player_weapon: TextureRect  ## 裝備武器疊層
var _player_accessory: TextureRect  ## 飾品
var _player_shadow: TextureRect
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
## 有手繪底圖時不畫牆磚 —— 底圖已經畫好房子與岩石了，再鋪一層灰色牆磚
## 就會在畫面上多出一堆格線方框（翠谷村左下那棟屋、右上帳篷就是這樣來的）。
var _has_scenic_bg := false
## 目前地圖底圖的 art id —— walkmask 是以 art 為 key（多張地圖共用同一張底圖）
var _art_id := ""

const WalkMask := preload("res://scripts/world/walk_mask.gd")
var _banner: TextureRect
var _vignette: ColorRect
var _scroll: Control  ## 攝影機層：整塊世界內容
var _world: Control  ## 世界層（實體 + 玩家，Y 排序）
var _facing_left: bool = false
var _walk_t: float = 0.0
var _moving: bool = false
## 探索動作姿（與戰鬥 poses 同源）：attack / skill / hit / telegraph / recover
var _action_pose: String = ""
var _action_pose_left: float = 0.0
var _action_pose_tween: Tween
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



## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

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
		_hint.text = text if text != "" else _t("WASD／方向鍵移動 · 靠近後按 E 互動")
		hint_changed.emit(_hint.text)


func setup(p_map_id: String) -> void:
	map_id = p_map_id
	## 記住人在哪張圖，戰敗時才知道是在哪一段倒下的
	var tel: Node = _telemetry_node()
	if tel:
		tel.call("set_place", p_map_id)
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
	hint_changed.emit(_t("WASD 移動 · E 互動 · M 開關小地圖 · 路標切換分區"))
	call_deferred("_request_presence")


func set_frozen(v: bool) -> void:
	frozen = v


func entity_label(id: String) -> String:
	for e in _entities:
		if str(e.get("id", "")) == id:
			return str(e.get("label", id))
	return id


## 播放與戰鬥一致的 chibi 姿態（短暫覆蓋 walk/idle）
func play_action_pose(pose: String, duration: float = 0.4) -> void:
	if pose == "" or pose == "idle":
		_action_pose = ""
		_action_pose_left = 0.0
		return
	_action_pose = pose
	_action_pose_left = maxf(0.12, duration)
	if _player == null:
		return
	## 與 battle_view 類似的 punch 感
	if _action_pose_tween and _action_pose_tween.is_valid():
		_action_pose_tween.kill()
	var sx := -1.0 if _facing_left else 1.0
	match pose:
		"attack", "skill":
			_player.scale = Vector2(sx * 1.1, 0.94)
		"hit":
			_player.scale = Vector2(sx * 0.92, 1.06)
		"telegraph":
			_player.scale = Vector2(sx * 0.97, 1.05)
		_:
			_player.scale = Vector2(sx, 1.0)
	_action_pose_tween = create_tween()
	_action_pose_tween.tween_property(_player, "scale", Vector2(sx, 1.0), 0.14)
	_update_player_visual()


func play_attack_pose(duration: float = 0.38) -> void:
	play_action_pose("attack", duration)


func play_hit_pose(duration: float = 0.4) -> void:
	play_action_pose("hit", duration)


func play_skill_pose(duration: float = 0.45) -> void:
	play_action_pose("skill", duration)


func show_player_bubble(text: String, secs: float = 2.0) -> void:
	_spawn_bubble(player_pos + Vector2(PLAYER_SIZE.x * 0.5, -8), text, secs, Color(0.98, 0.95, 0.88))


func _request_presence() -> void:
	## 星途殘影：有連線才拉；離線顯示本地「假足跡」氛圍
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
		var name_s := str(row.get("display_name", _t("星途旅人")))
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
	var seeds := [_t("灰影"), _t("無名人"), _t("遠方的氣味")]
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
		"maisui": _t("……還活著就好。"),
		"greybeard": _t("哼。旗還在。"),
		"ding": _t("鐵還熱。"),
		"sprout": _t("我也想練劍……"),
		"star": _t("星屑不等人。"),
		"merchant": _t("六域的價碼我都懂。"),
		"fog_hide": _t("霧裡……有人在笑。"),
		"acha": _t("茶涼了再打。"),
		"wind_ear": _t("風說……有客。"),
		"tide_roar": _t("浪比人實在。"),
		"duanye": _t("卷末未寫完。"),
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
	## 底圖是手繪插畫不是像素畫（town_bg 有 63,141 種顏色、邊緣帶抗鋸齒），
	## 而專案預設是 NEAREST。用 NEAREST 把它放大 2.3 倍（而且不是整數倍），
	## 抗鋸齒的邊會被硬放大成階梯狀，石板描邊有的 2px 有的 3px —— 那就是
	## 「看起來不精緻」的主因。畫過的圖要用 LINEAR。
	## 玩家與 prop 是真像素畫，維持 NEAREST。
	_floor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
	_banner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	## 橫幅半透明再降一點：有 scenic 底圖時少搶視覺
	_banner.modulate = Color(1, 1, 1, 0.42)
	_scroll.add_child(_banner)

	## 底部 vignette 加深景深
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 淺 vignette：過重會整圖髒、搶物件可讀性
	_vignette.color = Color(0.02, 0.02, 0.04, 0.14)
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
	title_chip.position = Vector2(248, 12)
	title_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_chip.add_theme_stylebox_override("panel", UiStyle.chip_style())
	add_child(title_chip)
	## 把 title 掛在 chip 上
	remove_child(_title)
	title_chip.add_child(_title)
	_title.position = Vector2.ZERO
	_title.add_theme_color_override("font_color", UiStyle.INK)
	_title.add_theme_font_size_override("font_size", 13)

	_build_minimap_ui()

	## 底部互動提示框（有邊框；靠近時變提示物件名）
	var hint_bar := PanelContainer.new()
	hint_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_bar.anchor_left = 0.5
	hint_bar.anchor_right = 0.5
	hint_bar.offset_left = -200
	hint_bar.offset_right = 200
	hint_bar.offset_top = -86
	hint_bar.offset_bottom = -48
	hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_bar.add_theme_stylebox_override("panel", UiStyle.hint_bar_style())
	hint_bar.z_index = 20
	add_child(hint_bar)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", UiStyle.INK)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = _t("移動靠近目標 · 按 E 互動")
	hint_bar.add_child(_hint)

	_player_shadow = TextureRect.new()
	_player_shadow.texture = _shadow_tex()
	_player_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_player_shadow.size = Vector2(36, 12)
	_player_shadow.modulate = Color(0, 0, 0, 0.42)
	_player_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_player_shadow)

	_player = TextureRect.new()
	_player.name = "PlayerBody"
	_player.size = PLAYER_SIZE
	_player.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.texture = SpriteDB.player_idle()
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.add_child(_player)

	_player_armor = TextureRect.new()
	_player_armor.name = "PlayerArmor"
	_player_armor.size = PLAYER_SIZE
	_player_armor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_armor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_armor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_armor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_armor.visible = false
	_world.add_child(_player_armor)

	_player_weapon = TextureRect.new()
	_player_weapon.name = "PlayerWeapon"
	_player_weapon.size = Vector2(40, 40)
	_player_weapon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_weapon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_weapon.visible = false
	_world.add_child(_player_weapon)

	_player_accessory = TextureRect.new()
	_player_accessory.name = "PlayerAccessory"
	_player_accessory.size = Vector2(22, 22)
	_player_accessory.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_accessory.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_accessory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_accessory.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_accessory.visible = false
	_world.add_child(_player_accessory)

	## 角色名牌（頭上）
	var name_tag := PanelContainer.new()
	name_tag.name = "PlayerNameTag"
	## 預設不顯示玩家頭頂字牌，減少畫面雜訊
	name_tag.visible = false
	name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_tag.add_theme_stylebox_override("panel", UiStyle.name_tag_style())
	var ntl := Label.new()
	ntl.text = str(GameState.player_name) if str(GameState.player_name) != "" else _t("小白")
	ntl.add_theme_font_size_override("font_size", 10)
	ntl.add_theme_color_override("font_color", UiStyle.INK)
	ntl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_tag.add_child(ntl)
	_world.add_child(name_tag)
	name_tag.set_meta("is_player_tag", true)

	## 裝備變更時刷新外觀
	if EquipmentSystem and not EquipmentSystem.equipment_changed.is_connected(_on_equipment_visual_changed):
		EquipmentSystem.equipment_changed.connect(_on_equipment_visual_changed)


func _on_equipment_visual_changed() -> void:
	_update_player_visual()


## 接地陰影用的柔邊橢圓。原本是 ColorRect —— 硬邊矩形，看起來像腳下墊了一塊
## 黑板，反而更浮。程序生成一張帶羽化的橢圓，畫一次快取起來重複用。
static var _shadow_tex_cache: Texture2D = null


static func _shadow_tex() -> Texture2D:
	if _shadow_tex_cache != null:
		return _shadow_tex_cache
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			## 橢圓內外的正規化距離：1.0 剛好在邊緣
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var d := sqrt(dx * dx + dy * dy)
			## smoothstep 羽化，中心最濃、邊緣化開
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_shadow_tex_cache = ImageTexture.create_from_image(img)
	return _shadow_tex_cache


## 依 y 座標給一點深度縮放：越靠畫面上方（遠）越小。
## 幅度刻意很小 —— 手繪底圖的透視本來就不是嚴格的，拉太多會更假。
## 只影響「顯示」，碰撞仍用 e.size／PLAYER_SIZE，不會改變手感。
const DEPTH_SCALE_NEAR := 1.05
const DEPTH_SCALE_FAR := 0.90


func _depth_scale(world_y: float) -> float:
	var top := FLOOR_RECT.position.y
	var hgt := maxf(1.0, FLOOR_RECT.size.y)
	var t := clampf((world_y - top) / hgt, 0.0, 1.0)
	return lerpf(DEPTH_SCALE_FAR, DEPTH_SCALE_NEAR, t)


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
	var has_scenic_bg := bg_tex != null
	_has_scenic_bg = has_scenic_bg
	_art_id = art_id
	if has_scenic_bg:
		## 完整顯示手繪底圖。必須 STRETCH_SCALE 對齊 FLOOR_RECT，
		## 否則 COVERED 裁切會讓美術建築與 entity／碰撞座標錯位（看起來像穿模）。
		_floor.texture = bg_tex
		_floor.modulate = Color(1, 1, 1, 1)
		_floor.stretch_mode = TextureRect.STRETCH_SCALE
		_floor_tint.color = Color(0.04, 0.03, 0.06, 0.10)
	else:
		_floor.texture = null
		_floor_tint.color = Color(0.12, 0.1, 0.1, 0.5)

	_build_tilemap(art_id if art_id != "" else id, has_scenic_bg)

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


func _build_tilemap(map_id_s: String, scenic_bg: bool = false) -> void:
	if _tile_map == null or _tile_host == null:
		return
	_tile_host.position = FLOOR_RECT.position
	_map_cols = int(FLOOR_RECT.size.x / TILE_PX)
	_map_rows = int(FLOOR_RECT.size.y / TILE_PX)
	var kind := SpriteDB.map_tile_kind(map_id_s)
	var ts := _get_or_make_tileset(kind)
	if ts == null:
		_tile_map.clear()
		if _wall_map:
			_wall_map.clear()
		return
	_tile_map.tile_set = ts
	_tile_map.clear()
	## 有風景底圖時：不再鋪滿 tile（那會蓋掉 Gemini 場景圖，變成「醜地板」）
	## 只在邊角極淡點綴；無底圖時才滿鋪可走地面
	var seed_n := map_id_s.hash()
	var variants := 4
	var src: TileSetSource = ts.get_source(0)
	if src is TileSetAtlasSource:
		var atlas := src as TileSetAtlasSource
		if atlas.texture:
			variants = maxi(1, int(atlas.texture.get_width() / TILE_PX))
	if scenic_bg:
		## 輕量邊緣碎石／路徑，幾乎透明
		for y in _map_rows:
			for x in _map_cols:
				var edge := x <= 1 or y <= 1 or x >= _map_cols - 2 or y >= _map_rows - 2
				var path := false
				if map_id_s in ["town", "dojo"] and (y == _map_rows / 2 or y == _map_rows / 2 + 1):
					path = true
				if map_id_s == "road" and abs(y - _map_rows / 2) <= 1:
					path = true
				if not edge and not path:
					continue
				if edge and (x + y + seed_n) % 3 != 0:
					continue
				var n := int(abs(sin(float(x * 12 + y * 7 + seed_n)) * 1000.0))
				_tile_map.set_cell(Vector2i(x, y), 0, Vector2i(n % variants, 0))
		_tile_map.modulate = Color(1, 1, 1, 0.22)
	else:
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
		"training_dummy", "zen_pond", "scripture", "master_room", "bamboo_wall",
		"peak_platform", "stone_garden", "tree", "pine", "gate", "hut",
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
	var paint := not _has_scenic_bg
	for x in _map_cols:
		_set_solid(Vector2i(x, 0), true, paint)
		_set_solid(Vector2i(x, _map_rows - 1), true, paint)
	for y in _map_rows:
		_set_solid(Vector2i(0, y), true, paint)
		_set_solid(Vector2i(_map_cols - 1, y), true, paint)
	## 2) 建築／大型 prop 佔位（上半身實心，腳邊可站可互動）
	for e in _entities:
		if not _entity_is_solid(e):
			continue
		var pos: Vector2 = e.pos
		var sz: Vector2 = e.size
		## 放大明顯建築的碰撞（entity 標記常比畫面建築小）
		var scale_hit := _entity_collision_scale(str(e.get("id", "")))
		var hit_w := maxf(24.0, sz.x * scale_hit.x)
		var hit_h := maxf(20.0, sz.y * scale_hit.y)
		var ox := pos.x + (sz.x - hit_w) * 0.5
		var oy := pos.y + sz.y - hit_h  ## 對齊腳底
		## 碰撞偏上：只擋軀幹，底部 12px 可站
		var r := Rect2(ox + 4.0, oy + 4.0, maxf(12.0, hit_w - 8.0), maxf(12.0, hit_h * 0.62))
		_stamp_solid_rect(r, paint)
	## 3) 可走區：有 walkmask 就用它，否則退回舊的百分比方塊
	##
	## 舊做法是每張地圖手寫一兩個 Rect2 百分比（「上緣 8% 是遠山」），
	## 跟畫面上實際畫了什麼幾乎無關 —— 兔子照樣走上城牆與屋頂。
	## walkmask 是照著底圖描出來的多邊形，能站的地方才是能站的地方。
	if not WalkMask.has(_art_id):
		for r2 in _scenic_blockers(map_id):
			_stamp_solid_rect(r2, false)
	else:
		## 逐格判定：格心不在可走區內 → 實心
		for cy in _map_rows:
			for cx in _map_cols:
				var uv := Vector2(
					(float(cx) + 0.5) / float(maxi(1, _map_cols)),
					(float(cy) + 0.5) / float(maxi(1, _map_rows)))
				if not WalkMask.walkable(_art_id, uv):
					_set_solid(Vector2i(cx, cy), true, false)
	## 確保玩家出生點不在實心上
	_unstuck_player()


func _entity_collision_scale(id: String) -> Vector2:
	## 回傳 (寬倍, 高倍) 相對於 catalog size
	if id in ["hut_a", "hut_b", "hut_c", "inn", "dorm", "stable", "chapel", "treehouse", "market", "market_b", "barracks", "hall", "throne_hall"]:
		return Vector2(2.4, 2.2)
	if id in ["gate_arch", "tower_gate", "leo_gate", "trial_hall", "watch_tower", "tower", "peak_platform", "master_room"]:
		return Vector2(2.0, 2.0)
	if id in ["shrine", "shrine_stub", "well", "well_fog", "fountain", "forge_c5", "camp", "tent_a", "tent_b", "boat_wreck", "dock"]:
		return Vector2(1.8, 1.6)
	if id in ["scroll_wall", "bamboo_wall", "wall_notice", "fence_row", "ravine"]:
		return Vector2(2.2, 1.4)
	return Vector2(1.15, 1.1)


func _scenic_blockers(mid: String) -> Array:
	## 相對 FLOOR 的額外實心區（世界座標）。只擋主要不可走區，避免鎖死探索。
	var o := FLOOR_RECT.position
	var s := FLOOR_RECT.size
	var raw: Array = []
	## 地圖上緣 10%：遠山／屋頂帶（略縮，避免鎖死北向）
	raw.append(Rect2(o.x + s.x * 0.08, o.y, s.x * 0.84, s.y * 0.08))
	match mid:
		"dojo", "dojo_inner", "dojo_peak":
			## 左上建築、右上竹林（避開中央院落）
			raw.append(Rect2(o.x + s.x * 0.06, o.y + s.y * 0.10, s.x * 0.22, s.y * 0.32))
			raw.append(Rect2(o.x + s.x * 0.70, o.y + s.y * 0.10, s.x * 0.22, s.y * 0.30))
		"town", "town_keep", "town_market":
			raw.append(Rect2(o.x + s.x * 0.58, o.y + s.y * 0.08, s.x * 0.30, s.y * 0.28))
			raw.append(Rect2(o.x + s.x * 0.08, o.y + s.y * 0.08, s.x * 0.20, s.y * 0.24))
		"forest", "forest_deep", "forest_lake", "forest_canopy":
			raw.append(Rect2(o.x, o.y + s.y * 0.18, s.x * 0.10, s.y * 0.65))
			raw.append(Rect2(o.x + s.x * 0.90, o.y + s.y * 0.18, s.x * 0.10, s.y * 0.65))
		"mist_village", "mist_shrine":
			raw.append(Rect2(o.x + s.x * 0.12, o.y + s.y * 0.10, s.x * 0.20, s.y * 0.26))
		"coast", "coast_harbor", "coast_wreck":
			raw.append(Rect2(o.x + s.x * 0.08, o.y + s.y * 0.82, s.x * 0.84, s.y * 0.14))
		"tower_foyer", "tower_camp", "blackflame_scar":
			raw.append(Rect2(o.x + s.x * 0.38, o.y + s.y * 0.08, s.x * 0.24, s.y * 0.30))
		_:
			pass
	## 出生點周圍挖空，避免一進來就卡住
	var spawn_safe := Rect2(player_pos - Vector2(80, 80), Vector2(160 + PLAYER_SIZE.x, 160 + PLAYER_SIZE.y))
	var out: Array = []
	for item in raw:
		var r: Rect2 = item
		if not r.intersects(spawn_safe):
			out.append(r)
			continue
		## 簡單策略：與 spawn 重疊的 blocker 整塊丟掉（寧可少擋、勿卡死）
		pass
	return out


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


func _entity_display_size(e: Dictionary, tex: Texture2D) -> Vector2:
	var base: Vector2 = e.size
	var id := str(e.get("id", ""))
	var tw := maxf(1.0, float(tex.get_width()))
	var th := maxf(1.0, float(tex.get_height()))
	var aspect := tw / th
	## 建築類放大
	var target_h := maxf(base.y, 56.0)
	if id in ["hut_a", "hut_b", "hut_c", "inn", "dorm", "treehouse", "market", "chapel", "stable", "barracks"]:
		target_h = maxf(base.y * 2.2, 110.0)
	elif id in ["gate_arch", "tower", "watch_tower", "trial_hall", "leo_gate", "gate"]:
		target_h = maxf(base.y * 2.0, 100.0)
	elif id in ["well", "shrine", "forge_c5", "camp", "campfire", "boat", "dock"]:
		target_h = maxf(base.y * 1.6, 72.0)
	elif id in ["tree", "pine"]:
		target_h = maxf(base.y * 2.5, 96.0)
	elif SpriteDB.explore_entity_path(id).find("/npcs/") >= 0:
		target_h = maxf(base.y, 64.0)
	else:
		target_h = maxf(base.y * 1.35, 52.0)
	var target_w := target_h * aspect
	## 上限避免遮滿畫面
	target_h = minf(target_h, 160.0)
	target_w = minf(target_w, 180.0)
	return Vector2(target_w, target_h)


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
		_world.add_child(root)

		## 底座陰影。原本是 ColorRect，硬邊矩形看起來像腳下墊了塊黑板；
		## 而且尺寸用 e.size 算，但有貼圖時 root.size 會被改成 disp，
		## 於是大建築的陰影只有一小條、小物件的陰影卻超出去。
		## 改成柔邊橢圓，並在拿到顯示尺寸之後才擺。
		var shadow := TextureRect.new()
		shadow.texture = _shadow_tex()
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_SCALE
		shadow.modulate = Color(0, 0, 0, 0.34)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shadow)

		var tex := SpriteDB.explore_entity_tex(e.id)
		## 底圖已經畫過的景物（房子／樹／岩石／船骸…）不再疊一張 prop 上去，
		## 只留互動熱區 —— 走近了名稱牌與 E 提示照樣會跳出來。
		## 沒有底圖的地圖仍要畫，否則畫面上根本看不到東西。
		##
		## 注意這裡不能只把 tex 設成 null：那會掉進下面的色塊 fallback，
		## 變成在漂亮底圖上畫一個半透明彩色方框，比疊 sprite 還糟。
		var hide_scenery := _has_scenic_bg and SpriteDB.is_scenery_prop(str(e.id))
		if hide_scenery:
			## 看不見的東西不該有影子
			shadow.visible = false
			root.set_meta("sort_y", e.pos.y + e.size.y)
		elif tex:
			## 依貼圖比例放大顯示，避免 48px 框塞大建築圖卻仍像色塊
			var disp := _entity_display_size(e, tex)
			root.size = disp
			var spr := TextureRect.new()
			spr.set_anchors_preset(Control.PRESET_FULL_RECT)
			spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(spr)
			## 腳底對齊原 catalog 錨點底部
			var foot_y: float = e.pos.y + e.size.y
			var dk := _depth_scale(foot_y)
			disp *= dk
			root.size = disp
			spr.size = disp
			root.position = Vector2(e.pos.x + e.size.x * 0.5 - disp.x * 0.5, foot_y - disp.y)
			root.set_meta("sort_y", foot_y)
			## 陰影：寬度取顯示寬的七成，壓在 root 底部
			var shw: float = disp.x * 0.70
			shadow.size = Vector2(shw, maxf(7.0, shw * 0.26))
			shadow.position = Vector2(disp.x * 0.5 - shw * 0.5, disp.y - shadow.size.y * 0.60)
		else:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(e.color.r, e.color.g, e.color.b, 0.45)
			sb.border_color = Color(e.color.r * 1.3, e.color.g * 1.3, e.color.b * 1.3, 0.8)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			var box := Panel.new()
			box.set_anchors_preset(Control.PRESET_FULL_RECT)
			box.add_theme_stylebox_override("panel", sb)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(box)
			root.set_meta("sort_y", e.pos.y + e.size.y)
			var bw: float = e.size.x * 0.70
			shadow.size = Vector2(bw, maxf(6.0, bw * 0.26))
			shadow.position = Vector2(e.size.x * 0.5 - bw * 0.5, e.size.y - shadow.size.y * 0.60)

		## 名稱牌：預設隱藏，只在靠近時顯示（避免滿場白字「好花」）
		var name_chip := PanelContainer.new()
		name_chip.visible = false
		name_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_chip.add_theme_stylebox_override("panel", UiStyle.interact_name_style())
		name_chip.position = Vector2(root.size.x * 0.5 - 40, -52)
		var lab := Label.new()
		lab.text = e.label
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 12)
		lab.add_theme_color_override("font_color", UiStyle.INK)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_chip.add_child(lab)
		root.add_child(name_chip)
		root.set_meta("label_node", lab)
		root.set_meta("name_chip", name_chip)
		## 靠近時的 E 互動框（有邊框）
		var badge_panel := PanelContainer.new()
		badge_panel.visible = false
		badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_panel.add_theme_stylebox_override("panel", UiStyle.interact_badge_style())
		badge_panel.position = Vector2(root.size.x * 0.5 - 18, -84)
		var badge := Label.new()
		badge.text = "E"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 15)
		badge.add_theme_color_override("font_color", UiStyle.KEY_DEEP)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_panel.add_child(badge)
		root.add_child(badge_panel)
		root.set_meta("badge", badge)
		root.set_meta("badge_panel", badge_panel)
		root.set_meta("badge_bg", null)  ## 舊欄位相容
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
	## 鍵盤（方向鍵／WASD）與手把（左搖桿／十字鍵）皆綁在 ui_*，見 project.godot [input]
	if Input.is_action_pressed("ui_left"):
		dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		dir.x += 1
	if Input.is_action_pressed("ui_up"):
		dir.y -= 1
	if Input.is_action_pressed("ui_down"):
		dir.y += 1
	if _action_pose_left > 0.0:
		_action_pose_left -= delta
		if _action_pose_left <= 0.0:
			_action_pose = ""
			_action_pose_left = 0.0
	## 動作姿期間仍可移動，但視覺鎖在 pose 上
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
	## 每幀 Y 排序，減少走進建築前後穿模感
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
	_minimap_root.add_theme_stylebox_override("panel", UiStyle.panel_style_dark())
	add_child(_minimap_root)
	call_deferred("_place_minimap_default")

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_root.add_child(v)

	var head := PanelContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_theme_stylebox_override("panel", UiStyle.header_style())
	v.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_row)
	var ht := Label.new()
	ht.text = _t("小地圖")
	ht.add_theme_font_size_override("font_size", 11)
	ht.add_theme_color_override("font_color", UiStyle.KEY_STRONG)
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(ht)
	var tip := Label.new()
	tip.text = "M"
	tip.add_theme_font_size_override("font_size", 10)
	tip.add_theme_color_override("font_color", UiStyle.INK_FAINT)
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
	legend.text = _t("● 你  ·  路標  ·  NPC  ·  點")
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
	## 身體：動作姿優先，否則步行／待機（與戰鬥 poses 同源）
	if _action_pose != "":
		var pt := SpriteDB.player_pose(_action_pose)
		if pt:
			_player.texture = pt
		else:
			var idle_fb := SpriteDB.player_idle()
			if idle_fb:
				_player.texture = idle_fb
	elif _moving:
		var frame := int(_walk_t) % 4
		var t := SpriteDB.player_walk(frame)
		if t:
			_player.texture = t
	else:
		var idle := SpriteDB.player_idle()
		if idle:
			_player.texture = idle
	## 受擊短暫偏紅，其餘維持防具染色
	if _action_pose == "hit":
		_player.modulate = SpriteDB.player_armor_modulate() * Color(1.15, 0.75, 0.75, 1)
	else:
		_player.modulate = SpriteDB.player_armor_modulate()
	var foot_y := player_pos.y + PLAYER_SIZE.y
	## 防具疊層：貼圖是「軀幹甲片」不是全身，不可拉滿 PLAYER_SIZE（會像穿歪／紙娃娃破圖）
	if _player_armor:
		var atex := SpriteDB.player_armor_overlay()
		if atex:
			_player_armor.visible = true
			_player_armor.texture = atex
			var asz := Vector2(PLAYER_SIZE.x * 0.72, PLAYER_SIZE.y * 0.48)
			_player_armor.size = asz
			## 對齊胸腹：頭約上 1/3，甲從 ~28% 高度開始
			var aoff := Vector2((PLAYER_SIZE.x - asz.x) * 0.5, PLAYER_SIZE.y * 0.30)
			_player_armor.position = player_pos + aoff
			_player_armor.pivot_offset = asz * 0.5
			_player_armor.scale.x = -1.0 if _facing_left else 1.0
			_player_armor.modulate = Color(1, 1, 1, 0.92)
			_player_armor.set_meta("sort_y", foot_y + 0.2)
		else:
			_player_armor.visible = false
	## 武器疊層：右手握把區（僅武器圖，非整隻角色）
	if _player_weapon:
		var wtex := SpriteDB.player_weapon_overlay()
		if wtex:
			_player_weapon.visible = true
			_player_weapon.texture = wtex
			var wsz := Vector2(PLAYER_SIZE.x * 0.55, PLAYER_SIZE.y * 0.55)
			wsz.x = clampf(wsz.x, 28.0, 42.0)
			wsz.y = clampf(wsz.y, 28.0, 42.0)
			_player_weapon.size = wsz
			var hand := Vector2(PLAYER_SIZE.x * 0.58, PLAYER_SIZE.y * 0.42)
			if _facing_left:
				hand.x = PLAYER_SIZE.x * 0.02
			_player_weapon.position = player_pos + hand
			_player_weapon.pivot_offset = wsz * Vector2(0.35, 0.65)
			_player_weapon.scale.x = -1.0 if _facing_left else 1.0
			_player_weapon.rotation_degrees = -28.0 if not _facing_left else 28.0
			_player_weapon.set_meta("sort_y", foot_y + 0.5)
		else:
			_player_weapon.visible = false
	## 飾品：小圖掛胸前，避免蓋住臉
	if _player_accessory:
		var xtex := SpriteDB.player_accessory_overlay()
		if xtex:
			_player_accessory.visible = true
			_player_accessory.texture = xtex
			var xsz := Vector2(18, 18)
			_player_accessory.size = xsz
			var ap := Vector2(PLAYER_SIZE.x * 0.38, PLAYER_SIZE.y * 0.36)
			if _facing_left:
				ap.x = PLAYER_SIZE.x * 0.30
			_player_accessory.position = player_pos + ap
			_player_accessory.scale.x = -1.0 if _facing_left else 1.0
			_player_accessory.set_meta("sort_y", foot_y + 0.3)
		else:
			_player_accessory.visible = false
	if _player_shadow:
		## 陰影跟著深度一起縮，遠處的腳印才不會比近處還大
		var sh_k := _depth_scale(foot_y)
		var sh_w := (PLAYER_SIZE.x - 8.0) * sh_k
		var sh_h := 12.0 * sh_k
		_player_shadow.size = Vector2(sh_w, sh_h)
		_player_shadow.position = Vector2(
			player_pos.x + PLAYER_SIZE.x * 0.5 - sh_w * 0.5,
			foot_y - sh_h * 0.62)
		_player_shadow.set_meta("sort_y", foot_y - 1.0)
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
				_hint.text = _t("移動靠近目標 · 按 E 互動")
			_hint.modulate = Color(1, 1, 1, 0.9)
			hint_changed.emit(_hint.text)
		else:
			var label := best
			for e in _entities:
				if e.id == best:
					label = e.label
					break
			_hint.text = "〔 E 〕  %s" % label
			_hint.modulate = Color(1, 1, 1, 1)
			hint_changed.emit(_hint.text)
		_highlight_near()


func _highlight_near() -> void:
	for e in _entities:
		var root: Control = _entity_nodes.get(e.id)
		if root == null:
			continue
		var badge_panel: Control = root.get_meta("badge_panel") if root.has_meta("badge_panel") else null
		var name_chip: Control = root.get_meta("name_chip") if root.has_meta("name_chip") else null
		var badge_bg: ColorRect = root.get_meta("badge_bg") if root.has_meta("badge_bg") else null
		var on: bool = (e.id == _near_id)
		if on:
			## 輕量高亮，避免 scale 抖動 + 過曝
			root.modulate = Color(1.06, 1.05, 1.02)
			root.scale = Vector2.ONE
			if badge_panel:
				badge_panel.visible = true
				badge_panel.position = Vector2(root.size.x * 0.5 - 18, -84)
			if name_chip:
				name_chip.visible = true
				name_chip.position = Vector2(root.size.x * 0.5 - 40, -52)
			if badge_bg:
				badge_bg.visible = true
		else:
			root.modulate = Color.WHITE
			root.scale = Vector2.ONE
			if badge_panel:
				badge_panel.visible = false
			if name_chip:
				name_chip.visible = false
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
		if lab != "" and not lab.begins_with(_t("往")) and not lab.begins_with(_t("回")):
			show_entity_bubble(_near_id, lab, 1.6)
		interacted.emit(_near_id)
		get_viewport().set_input_as_handled()


## autoload 之間用絕對路徑 get_node 在某些啟動時機會噴錯，一律從 SceneTree.root 走
func _telemetry_node() -> Node:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		return (t as SceneTree).root.get_node_or_null("Telemetry")
	return null
