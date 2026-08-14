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
		"well", "fountain", "bench":
			return "%s/props/save.png" % ROOT
		"rubble", "road_stone", "bush_a", "bush_b", "scarecrow":
			return "%s/props/herb.png" % ROOT
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
			id = "star"  ## 暫用星讀調色系半身；後補專圖
		"琥珀", "amber":
			id = "caravan_chief"
		"黑焰浪人", "浪人", "ronin":
			id = "scar_lord"  ## 暫用疤主影調；後補專圖
		"遺孤少年", "knight_orphan":
			id = "sprout"
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
