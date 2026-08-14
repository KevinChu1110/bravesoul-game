class_name SpriteDB
extends RefCounted
## 2D 資產路徑與探索 entity → 貼圖對照（邏輯仍用 id 字串）。

const ROOT := "res://assets/sprites"

static func tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func player_idle() -> Texture2D:
	return tex("%s/player/rabbit_idle_x3.png" % ROOT)


static func player_walk(frame: int) -> Texture2D:
	var i := posmod(frame, 4)
	return tex("%s/player/rabbit_walk_%d_x3.png" % [ROOT, i])


## 裝備武器疊層（依流派或已裝備武器）
static func player_weapon_class_id() -> String:
	## 優先 path_style；否則從裝備 base 推
	var ps := str(GameState.path_style)
	if ps != "" and ps not in ["soul", "iron", "magic_old"]:
		## 已遷移的流派 id
		if ps in ["sword", "bow", "magic", "fist", "axe", "hammer", "spear", "gun", "dart", "crystal"]:
			return ps
	## 從裝備 weapon 推
	if Engine.get_main_loop() is SceneTree:
		var es: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EquipmentSystem")
		if es and es.has_method("find_any"):
			var uid := str(GameState.equip_slots.get("weapon", "")) if GameState.equip_slots else ""
			if uid != "":
				var inst: Dictionary = es.call("find_any", uid)
				var base_id := str(inst.get("base_id", inst.get("id", "")))
				if base_id.find("bow") >= 0 or base_id.find("arrow") >= 0:
					return "bow"
				if base_id.find("staff") >= 0 or base_id.find("wand") >= 0 or base_id.find("tome") >= 0:
					return "magic"
				if base_id.find("axe") >= 0:
					return "axe"
				if base_id.find("hammer") >= 0 or base_id.find("mace") >= 0:
					return "hammer"
				if base_id.find("spear") >= 0 or base_id.find("lance") >= 0:
					return "spear"
				if base_id.find("gun") >= 0 or base_id.find("rifle") >= 0:
					return "gun"
				if base_id.find("dart") >= 0 or base_id.find("kunai") >= 0:
					return "dart"
				if base_id.find("crystal") >= 0 or base_id.find("orb") >= 0:
					return "crystal"
				if base_id.find("fist") >= 0 or base_id.find("glove") >= 0:
					return "fist"
				if base_id.find("sword") >= 0 or base_id.find("blade") >= 0 or GameState.weapon_name != "空手":
					return "sword"
	if GameState.weapon_name != "" and GameState.weapon_name != "空手":
		return "sword"
	return ""


static func player_weapon_overlay() -> Texture2D:
	var wid := player_weapon_class_id()
	if wid == "":
		return null
	var t := tex("%s/player/weapons/%s.png" % [ROOT, wid])
	if t:
		return t
	## 後備：通用劍
	return tex("%s/player/weapons/sword.png" % ROOT)


## 防具染色（穿上防具時身體色調變化）
static func player_armor_modulate() -> Color:
	var uid := ""
	if GameState.equip_slots:
		uid = str(GameState.equip_slots.get("armor", ""))
	if uid == "" or not GameState.equip_worn.has(uid):
		return Color(1, 1, 1, 1)
	var inst: Dictionary = GameState.equip_worn[uid]
	var base_id := str(inst.get("base_id", "")).to_lower()
	var q := str(inst.get("quality", inst.get("quality_label", ""))).to_lower()
	if base_id.find("cloth") >= 0 or base_id.find("robe") >= 0 or base_id.find("mage") >= 0:
		return Color(0.85, 0.80, 1.05, 1)  ## 法袍偏紫
	if base_id.find("leather") >= 0 or base_id.find("hide") >= 0:
		return Color(1.08, 0.92, 0.78, 1)  ## 皮甲偏暖
	if base_id.find("plate") >= 0 or base_id.find("mail") >= 0 or base_id.find("iron") >= 0 \
			or base_id.find("steel") >= 0 or base_id.find("knight") >= 0:
		return Color(0.82, 0.88, 1.05, 1)  ## 鐵甲偏冷藍
	## 品質後備
	if q.find("史詩") >= 0 or q.find("epic") >= 0:
		return Color(0.92, 0.82, 1.08, 1)
	if q.find("稀有") >= 0 or q.find("rare") >= 0:
		return Color(0.85, 0.92, 1.1, 1)
	return Color(1.02, 1.0, 0.95, 1)


static func player_battle() -> Texture2D:
	var idle := player_pose("idle")
	if idle:
		return idle
	return tex("%s/player/rabbit_battle.png" % ROOT)


## pose: idle | telegraph | attack | recover | skill
static func player_pose(pose: String) -> Texture2D:
	var t := tex("%s/player/poses/%s.png" % [ROOT, pose])
	if t:
		return t
	if pose == "idle":
		return tex("%s/player/rabbit_battle.png" % ROOT)
	return null


static func boss(mode: String) -> Texture2D:
	## 預設 idle 戰鬥立繪；優先 pose/idle
	var idle := boss_pose(mode, "idle")
	if idle:
		return idle
	var t := tex("%s/bosses/%s.png" % [ROOT, mode])
	if t == null and mode == "wrath":
		return tex("%s/bosses/demon.png" % ROOT)
	return t


static func boss_icon(mode: String) -> Texture2D:
	return tex("%s/bosses/%s_icon.png" % [ROOT, mode])


## pose: idle | telegraph | attack | recover
static func boss_pose(mode: String, pose: String) -> Texture2D:
	var key := _boss_art_key(mode)
	var t := tex("%s/bosses/poses/%s/%s.png" % [ROOT, key, pose])
	if t:
		return t
	## 回退：本體 png
	if pose == "idle":
		return tex("%s/bosses/%s.png" % [ROOT, key])
	return null


static func _boss_art_key(mode: String) -> String:
	## 戰鬥 mode → 貼圖目錄名
	match mode:
		"fog":
			return "fog"
		"wrath":
			return "wrath"
		"tide":
			return "tide"
		"statue":
			return "statue"
		"chrono":
			return "chrono"
		"echo":
			return "echo"
		_:
			return mode


static func map_bg(map_id: String) -> Texture2D:
	return tex("%s/maps/%s_bg.png" % [ROOT, map_id])


static func battle_bg(mode: String) -> Texture2D:
	return tex("%s/maps/battle_%s.png" % [ROOT, mode])


static func fx(kind: String) -> Texture2D:
	return tex("%s/fx/%s.png" % [ROOT, kind])


static func tile(kind: String) -> Texture2D:
	## kind: stone grass dirt wood sand mist dark
	var atlas := "%s/tiles/%s_atlas.png" % [ROOT, kind]
	if ResourceLoader.exists(atlas):
		return tex(atlas)
	var p32 := "%s/tiles/%s_32.png" % [ROOT, kind]
	if ResourceLoader.exists(p32):
		return tex(p32)
	return tex("%s/tiles/%s_16.png" % [ROOT, kind])


static func map_tile_kind(map_id: String) -> String:
	## 前綴對應，支援 0.9 多分區
	if map_id.begins_with("town") or map_id in ["barracks_yard", "wild_leo_court"]:
		return "stone"
	if map_id.begins_with("village") or map_id.begins_with("road") or map_id.begins_with("wild") \
			or map_id in ["crossroads", "cross_north", "cross_east", "caravan_camp", "hunting_grounds"]:
		return "dirt"
	if map_id.begins_with("mist"):
		return "mist"
	if map_id.begins_with("dojo"):
		return "wood"
	if map_id.begins_with("forest"):
		return "grass"
	if map_id.begins_with("coast"):
		return "sand"
	if map_id.begins_with("tower") or map_id in ["blackflame_scar"]:
		return "dark"
	if map_id in ["starfall_plain"]:
		return "mist"
	if map_id == "wall":
		return "wall"
	return "dark"


## 探索 entity id → 貼圖路徑
static func explore_entity_path(entity_id: String) -> String:
	match entity_id:
		# NPCs
		"maisui":
			return "%s/npcs/maisui.png" % ROOT
		"greybeard":
			return "%s/npcs/greybeard.png" % ROOT
		"ding":
			return "%s/npcs/ding.png" % ROOT
		"star":
			return "%s/npcs/star.png" % ROOT
		"sprout":
			return "%s/npcs/sprout.png" % ROOT
		"fog_hide":
			return "%s/npcs/fog_hide.png" % ROOT
		"acha":
			return "%s/npcs/acha.png" % ROOT
		"wind_ear":
			return "%s/npcs/wind_ear.png" % ROOT
		"tide_roar":
			return "%s/npcs/tide_roar.png" % ROOT
		"silk":
			return "%s/npcs/silk.png" % ROOT
		"amber":
			return "%s/npcs/amber.png" % ROOT
		"ronin":
			return "%s/npcs/ronin.png" % ROOT
		"knight_orphan":
			return "%s/npcs/knight_orphan.png" % ROOT
		# Boss markers
		"wolf":
			return "%s/bosses/wolf_icon.png" % ROOT
		"leo_gate":
			return "%s/bosses/leo_icon.png" % ROOT
		"fog_gate":
			return "%s/bosses/fog_icon.png" % ROOT
		"trial_hall":
			return "%s/bosses/abo_icon.png" % ROOT
		"falcon_nest":
			return "%s/bosses/falcon_icon.png" % ROOT
		"boar_cliff":
			return "%s/bosses/boar_icon.png" % ROOT
		# Props
		"sword":
			return "%s/props/sword.png" % ROOT
		"training_dummy", "dummy":
			return "%s/props/dummy.png" % ROOT if ResourceLoader.exists("%s/props/dummy.png" % ROOT) else "%s/props/sign.png" % ROOT
		"tea":
			return "%s/props/tea.png" % ROOT
		"fire":
			return "%s/props/fire.png" % ROOT
		"flag":
			return "%s/props/flag.png" % ROOT
		"menu_save", "save_c2", "save_c3", "save_c4", "save_c5":
			return "%s/props/save.png" % ROOT
		"exit_east", "exit_wild", "back_town", "back_knight", "back_mist", "back_dojo", "back_forest":
			return "%s/props/exit.png" % ROOT
		"camp":
			return "%s/props/camp.png" % ROOT
		"tower", "watch_tower":
			return "%s/props/tower.png" % ROOT
		"gate_bell":
			return "%s/props/bell.png" % ROOT
		"tea":
			return "%s/props/tea.png" % ROOT
		"herb_slope":
			return "%s/props/herb.png" % ROOT
		"dock":
			return "%s/props/dock.png" % ROOT
		"forge_c5", "forge_sign":
			return "%s/props/forge.png" % ROOT
		"path_mist", "path_dojo", "path_forest", "path_coast", "path_tower", "path_tower_c5", "arrow_path", "cliff_path", "sign_east", "trail_mark":
			return "%s/props/path.png" % ROOT
		"treehouse", "inn", "hut_a", "hut_b", "market", "cart", "burnt_field":
			return "%s/props/camp.png" % ROOT
		"look_back", "ash_pile", "dawn_glow":
			return "%s/props/fire.png" % ROOT
		"gate_arch", "milepost", "wall_notice":
			return "%s/props/tower.png" % ROOT
		"well", "fountain", "bench", "well_fog", "keep_well":
			return "%s/props/well.png" % ROOT if ResourceLoader.exists("%s/props/well.png" % ROOT) else "%s/props/save.png" % ROOT
		"rubble", "road_stone", "bush_a", "bush_b", "scarecrow", "rock", "ruin_pillar":
			return "%s/props/rock.png" % ROOT if ResourceLoader.exists("%s/props/rock.png" % ROOT) else "%s/props/herb.png" % ROOT
		"tree", "pine", "treehouse":
			return "%s/props/tree.png" % ROOT if ResourceLoader.exists("%s/props/tree.png" % ROOT) else "%s/props/camp.png" % ROOT
		"barrel", "crate":
			return "%s/props/barrel.png" % ROOT if ResourceLoader.exists("%s/props/barrel.png" % ROOT) else "%s/props/camp.png" % ROOT
		"lantern", "beacon":
			return "%s/props/lantern.png" % ROOT if ResourceLoader.exists("%s/props/lantern.png" % ROOT) else "%s/props/fire.png" % ROOT
		"sign", "sign_board", "milepost", "milepost_b":
			return "%s/props/sign.png" % ROOT if ResourceLoader.exists("%s/props/sign.png" % ROOT) else "%s/props/path.png" % ROOT
		"campfire", "refugee_fire":
			return "%s/props/campfire.png" % ROOT if ResourceLoader.exists("%s/props/campfire.png" % ROOT) else "%s/props/fire.png" % ROOT
		"shrine", "shrine_stub", "altar":
			return "%s/props/shrine.png" % ROOT if ResourceLoader.exists("%s/props/shrine.png" % ROOT) else "%s/props/bell.png" % ROOT
		"boat", "boat_wreck", "dock":
			return "%s/props/boat.png" % ROOT if ResourceLoader.exists("%s/props/boat.png" % ROOT) else "%s/props/dock.png" % ROOT
		"hut_a", "hut_b", "hut_c", "inn", "dorm", "stable", "chapel":
			return "%s/props/hut.png" % ROOT if ResourceLoader.exists("%s/props/hut.png" % ROOT) else "%s/props/camp.png" % ROOT
		"gate_arch", "tower_gate", "leo_gate":
			return "%s/props/gate.png" % ROOT if ResourceLoader.exists("%s/props/gate.png" % ROOT) else "%s/props/tower.png" % ROOT
		"banner", "flag":
			return "%s/props/banner.png" % ROOT if ResourceLoader.exists("%s/props/banner.png" % ROOT) else "%s/props/flag.png" % ROOT
		"merchant":
			return "%s/npcs/merchant.png" % ROOT
		_:
			return ""


static func explore_entity_tex(entity_id: String) -> Texture2D:
	return tex(explore_entity_path(entity_id))


## 精緻對話半身像（插畫，非探索像素）
static func portrait_path(key: String) -> String:
	return "%s/portraits/%s.png" % [ROOT, key]


static func portrait_tex(key: String) -> Texture2D:
	return tex(portrait_path(key))


## 對話／過場：中文 speaker 名 → 半身像（優先 portraits/ 精緻插畫）
static func speaker_portrait(speaker: String) -> Texture2D:
	var key := speaker.strip_edges()
	var id := ""
	match key:
		"麥穗", "maisui":
			id = "maisui"
		"灰鬚", "greybeard":
			id = "greybeard"
		"釘釘", "ding":
			id = "ding"
		"星讀", "star":
			id = "star"
		"小芽", "sprout":
			id = "sprout"
		"霧隱", "白霧", "fog_hide":
			id = "fog_hide"
		"小白", "兔勇者", "內心", "rabbit":
			id = "rabbit"
		"雷歐", "聖獅·雷歐", "leo":
			id = "leo"
		"阿茶", "acha":
			id = "acha"
		"風耳", "wind_ear":
			id = "wind_ear"
		"斷頁", "duanye":
			id = "duanye"
		"阿波", "abo":
			id = "abo"
		"疾影", "falcon":
			id = "falcon"
		"石拳", "boar":
			id = "boar"
		"魔王", "demon":
			id = "demon"
		"渣滓之狼", "狼", "wolf":
			id = "wolf"
		"潮吼", "潮聲", "tide_roar":
			id = "tide_roar"
		"黑焰疤主", "疤主", "scar_lord":
			id = "scar_lord"
		"鏡廊殘影", "殘影", "mirror_wraith":
			id = "mirror_wraith"
		"沉船船長影", "船長影", "wreck_captain":
			id = "wreck_captain"
		"行商", "行商頭領", "caravan_chief":
			id = "caravan_chief"
		"絲絨", "silk":
			id = "silk"
		"琥珀", "amber":
			id = "amber"
		"黑焰浪人", "浪人", "ronin":
			id = "ronin"
		"遺孤少年", "knight_orphan":
			id = "knight_orphan"
		"系統", "旁白", "系統·教學":
			return null
		_:
			id = key
	if id != "":
		var p := portrait_tex(id)
		if p:
			return p
	## 後備：探索像素／boss icon
	var by_id := explore_entity_tex(id if id != "" else key)
	if by_id:
		return by_id
	return boss_icon(id) if id != "" else null
