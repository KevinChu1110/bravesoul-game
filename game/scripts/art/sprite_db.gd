class_name SpriteDB
extends RefCounted
## 2D 資產路徑與探索 entity → 貼圖對照（邏輯仍用 id 字串）。

const ROOT := "res://assets/sprites"

## GameState 走執行期查找，不要在編譯期引用 autoload 識別字。
## 原因：用 `godot --headless -s res://...` 跑測試腳本時，腳本的編譯早於 autoload 註冊，
## 直接寫 `GameState.xxx` 會 Compile Error，接著 Godot 會退回去跑主場景而永遠不結束。
## 同樣的寫法見 battle_sim.gd。
static func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameState")
	return null


static func tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func player_idle() -> Texture2D:
	return tex("%s/player/rabbit_idle_x3.png" % ROOT)


static func player_walk(frame: int) -> Texture2D:
	var i := posmod(frame, 4)
	return tex("%s/player/rabbit_walk_%d_x3.png" % [ROOT, i])


## 從裝備實例讀 base 定義（含 line）
static func _equip_inst(slot: String) -> Dictionary:
	var gs := _gs()
	if gs == null or gs.equip_slots == null:
		return {}
	var uid := str(gs.equip_slots.get(slot, ""))
	if uid == "" or not gs.equip_worn.has(uid):
		return {}
	return gs.equip_worn[uid] as Dictionary


static func _equip_line(slot: String) -> String:
	var inst := _equip_inst(slot)
	if inst.is_empty():
		return ""
	## 實例上可能有 line；否則查表
	var line := str(inst.get("line", ""))
	if line != "":
		return line
	var base_id := str(inst.get("base_id", ""))
	if Engine.get_main_loop() is SceneTree:
		var es: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EquipmentSystem")
		if es and es.has_method("base_def"):
			var def: Dictionary = es.call("base_def", base_id)
			return str(def.get("line", ""))
	return ""


static func _line_to_weapon_visual(line: String) -> String:
	match line:
		"sword", "bow", "magic", "fist", "axe", "hammer", "spear", "gun", "dart", "crystal", "dagger", "claw":
			return line
		"soul":
			return "magic"
		"iron":
			return "hammer"
		_:
			return ""


## ── 完整紙娃娃：優先 base_id 專用疊層，再退回類型圖 ──

static func _equip_base_id(slot: String) -> String:
	var inst := _equip_inst(slot)
	if inst.is_empty():
		return ""
	return str(inst.get("base_id", "")).strip_edges()


static func paperdoll_path(slot: String, base_id: String) -> String:
	if slot == "" or base_id == "":
		return ""
	return "%s/player/paperdoll/%s/%s.png" % [ROOT, slot, base_id]


static func paperdoll_tex(slot: String, base_id: String) -> Texture2D:
	return tex(paperdoll_path(slot, base_id))


## 裝備武器疊層（優先已裝備武器 → 流派）
static func player_weapon_class_id() -> String:
	## 1) 已裝備武器的 line / base_id
	var wline := _equip_line("weapon")
	var from_line := _line_to_weapon_visual(wline)
	if from_line != "":
		return from_line
	var inst := _equip_inst("weapon")
	if not inst.is_empty():
		var base_id := str(inst.get("base_id", inst.get("id", ""))).to_lower()
		var name_s := str(inst.get("name", "")).to_lower()
		var blob := base_id + " " + name_s
		if blob.find("bow") >= 0 or blob.find("弓") >= 0:
			return "bow"
		if blob.find("staff") >= 0 or blob.find("rod") >= 0 or blob.find("法") >= 0:
			return "magic"
		if blob.find("axe") >= 0 or blob.find("斧") >= 0:
			return "axe"
		if blob.find("hammer") >= 0 or blob.find("cudgel") >= 0 or blob.find("鎚") >= 0 or blob.find("棒") >= 0:
			return "hammer"
		if blob.find("spear") >= 0 or blob.find("槍") >= 0:
			return "spear"
		if blob.find("gun") >= 0 or blob.find("銃") >= 0:
			return "gun"
		if blob.find("dagger") >= 0 or blob.find("匕首") >= 0 or blob.find("短匕") >= 0:
			return "dagger"
		if blob.find("dart") >= 0 or blob.find("鏢") >= 0 or blob.find("針") >= 0:
			return "dart"
		if blob.find("crystal") >= 0 or blob.find("orb") >= 0 or blob.find("晶") >= 0:
			return "crystal"
		if blob.find("claw") >= 0 or blob.find("爪") >= 0:
			return "claw"
		if blob.find("fist") >= 0 or blob.find("拳") >= 0 or blob.find("手套") >= 0:
			return "fist"
		if blob.find("sword") >= 0 or blob.find("blade") >= 0 or blob.find("saber") >= 0 \
				or blob.find("edge") >= 0 or blob.find("劍") >= 0 or blob.find("刃") >= 0:
			return "sword"
	## 2) 流派
	var gs := _gs()
	var ps := str(gs.path_style) if gs else ""
	var from_path := _line_to_weapon_visual(ps)
	if from_path != "":
		return from_path
	if ps in ["sword", "bow", "magic", "fist", "axe", "hammer", "spear", "gun", "dart", "crystal", "dagger", "claw"]:
		return ps
	## 3) 舊武器名
	if gs and gs.weapon_name != "" and gs.weapon_name != "空手":
		return "sword"
	return ""


static func player_weapon_overlay() -> Texture2D:
	## 1) 每件武器 base_id 專用疊層
	var bid := _equip_base_id("weapon")
	if bid != "":
		var unique := paperdoll_tex("weapon", bid)
		if unique:
			return unique
	## 2) 類型共用（劍／弓／…）
	var wid := player_weapon_class_id()
	if wid == "":
		return null
	var t := tex("%s/player/weapons/%s.png" % [ROOT, wid])
	if t:
		return t
	## 新武器系統尚無專圖時退回同職近似
	match wid:
		"dagger":
			t = tex("%s/player/weapons/dart.png" % ROOT)
		"claw":
			t = tex("%s/player/weapons/fist.png" % ROOT)
	if t:
		return t
	return tex("%s/player/weapons/sword.png" % ROOT)


## 防具種類：plate | leather | veil | cloth | hide | wrap | gi | ""（類型 fallback）
## 六職對應：騎士 plate、維京 hide、忍者 wrap、武鬥 gi、法師 veil、遊俠 leather
static func player_armor_kind() -> String:
	var line := _equip_line("armor")
	var inst := _equip_inst("armor")
	var base_id := str(inst.get("base_id", "")).to_lower()
	var name_s := str(inst.get("name", "")).to_lower()
	var prof := str(inst.get("profession", "")).to_lower()
	var blob := base_id + " " + name_s + " " + line + " " + prof
	## 六職專用 base_id 先判
	match base_id:
		"knight_plate":
			return "plate"
		"viking_hide":
			return "hide"
		"ninja_wrap":
			return "wrap"
		"monk_gi":
			return "gi"
		"star_veil":
			return "veil"
		"ranger_leather":
			return "leather"
		"ash_mail":
			return "plate"
	if prof == "knight" or blob.find("plate") >= 0 or blob.find("knight") >= 0 \
			or line in ["sword", "spear"] or line == "iron":
		return "plate"
	if prof == "viking" or blob.find("hide") >= 0 or blob.find("viking") >= 0 \
			or blob.find("獸甲") >= 0 or line in ["axe", "hammer"]:
		return "hide"
	if prof == "ninja" or blob.find("wrap") >= 0 or blob.find("ninja") >= 0 \
			or blob.find("夜衣") >= 0 or line in ["dagger", "dart"]:
		return "wrap"
	if prof == "monk" or blob.find("gi") >= 0 or blob.find("monk") >= 0 \
			or blob.find("練衣") >= 0 or line in ["fist", "claw"]:
		return "gi"
	if prof == "mage" or blob.find("veil") >= 0 or blob.find("cloak") >= 0 \
			or blob.find("披風") >= 0 or blob.find("紗") >= 0 \
			or line in ["magic", "crystal", "soul"]:
		return "veil"
	if prof == "ranger" or blob.find("leather") >= 0 or blob.find("ranger") >= 0 \
			or blob.find("皮") >= 0 or line in ["bow", "gun"]:
		return "leather"
	if blob.find("cloth") >= 0 or blob.find("robe") >= 0:
		return "cloth"
	if not inst.is_empty():
		return "leather"
	return ""


static func player_armor_overlay() -> Texture2D:
	## 1) 每件防具 base_id
	var bid := _equip_base_id("armor")
	if bid != "":
		var unique := paperdoll_tex("armor", bid)
		if unique:
			return unique
	## 2) 類型／六職共用
	var kind := player_armor_kind()
	if kind == "":
		return null
	var t := tex("%s/player/armor/%s.png" % [ROOT, kind])
	if t:
		return t
	## 尚無專圖時退回近似類型
	match kind:
		"hide":
			return tex("%s/player/armor/leather.png" % ROOT)
		"wrap":
			return tex("%s/player/armor/veil.png" % ROOT)
		"gi":
			return tex("%s/player/armor/cloth.png" % ROOT)
	return null


## 防具染色（疊在身體 modulate；外層 armor 貼圖另加）
static func player_armor_modulate() -> Color:
	## 有專用甲片時只做極輕染色，避免蓋掉繪製色
	var bid := _equip_base_id("armor")
	if bid != "" and paperdoll_tex("armor", bid) != null:
		match bid:
			"star_veil":
				return Color(0.96, 0.94, 1.04, 1)
			"knight_plate":
				return Color(0.94, 0.96, 1.02, 1)
			"viking_hide":
				return Color(1.02, 0.96, 0.90, 1)
			"ninja_wrap":
				return Color(0.90, 0.92, 1.04, 1)
			"monk_gi":
				return Color(1.02, 0.98, 0.90, 1)
			"ranger_leather":
				return Color(1.04, 0.96, 0.86, 1)
			"ash_mail":
				return Color(0.96, 0.95, 0.94, 1)
			_:
				return Color(1, 1, 1, 1)
	var kind := player_armor_kind()
	match kind:
		"veil", "wrap":
			return Color(0.88, 0.84, 1.08, 1)
		"leather", "hide":
			return Color(1.06, 0.94, 0.82, 1)
		"plate":
			return Color(0.84, 0.90, 1.06, 1)
		"cloth", "gi":
			return Color(0.90, 1.02, 0.92, 1)
		_:
			return Color(1, 1, 1, 1)


static func player_accessory_kind() -> String:
	var inst := _equip_inst("accessory")
	if inst.is_empty():
		return ""
	var blob := (str(inst.get("base_id", "")) + " " + str(inst.get("name", ""))).to_lower()
	if blob.find("ring") >= 0 or blob.find("指環") >= 0:
		return "ring"
	return "pendant"  ## 預設墜飾


static func player_accessory_overlay() -> Texture2D:
	## 1) 每件飾品 base_id
	var bid := _equip_base_id("accessory")
	if bid != "":
		var unique := paperdoll_tex("accessory", bid)
		if unique:
			return unique
	## 2) 類型共用
	var kind := player_accessory_kind()
	if kind == "":
		return null
	return tex("%s/player/accessories/%s.png" % [ROOT, kind])


## 裝備圖鑑 icon（與官網 web/media/equipment 同源）
static func equip_icon(base_id: String) -> Texture2D:
	if base_id == "":
		return null
	var t := tex("%s/equipment/%s.png" % [ROOT, base_id])
	if t:
		return t
	## 紙娃娃疊層也可當 icon 後備
	for slot in ["weapon", "armor", "accessory"]:
		var pd := paperdoll_tex(slot, base_id)
		if pd:
			return pd
	return null


static func equip_icon_for_inst(inst: Dictionary) -> Texture2D:
	if inst.is_empty():
		return null
	var base_id := str(inst.get("base_id", ""))
	var t := equip_icon(base_id)
	if t:
		return t
	var slot := str(inst.get("slot", ""))
	## 直接走紙娃娃路徑
	if base_id != "" and slot != "":
		var pd := paperdoll_tex(slot, base_id)
		if pd:
			return pd
	var line := str(inst.get("line", ""))
	var vis := _line_to_weapon_visual(line)
	if vis != "":
		return tex("%s/player/weapons/%s.png" % [ROOT, vis])
	if slot == "armor":
		return player_armor_overlay()
	if slot == "accessory":
		return player_accessory_overlay()
	return player_weapon_overlay()


static func player_battle() -> Texture2D:
	## 與探索同一套 chibi 底圖（紙娃娃疊層才對得齊）
	var idle := player_idle()
	if idle:
		return idle
	return tex("%s/player/rabbit_battle.png" % ROOT)


## pose: idle | telegraph | attack | recover | skill
## 戰鬥／探索統一：底圖一律 chibi idle／walk；動作感靠 battle_view 的 scale／lunge。
## 舊 poses/*.png 保留檔案但不當預設（風格與 idle_x3 不一致）。
static func player_pose(pose: String) -> Texture2D:
	match pose:
		"attack", "skill":
			## 略用步行幀做出「出手」感
			var w := player_walk(1)
			if w:
				return w
		"telegraph":
			var w0 := player_walk(0)
			if w0:
				return w0
		"recover":
			var w2 := player_walk(2)
			if w2:
				return w2
		_:
			pass
	return player_idle()


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


## 每一種戰鬥該站在哪張圖前面。
##
## 這張表存在的理由：`maps/battle_<mode>.png` 只有七張，而且那七張是
## 「主角＋敵人都畫好」的**完成稿插圖**被當背景用 —— 打雷歐的時候，
## 背景裡有一隻比人還大的兔子在跟哥布林對砍，前景又疊一隻活的主角。
## 其餘十六種戰鬥連圖都沒有，`battle_view` 直接把背景設成純黑。
##
## 那七張已經搬到 `illustrations/duel_*.png`（它們本身是好圖，只是不能當背景）。
## 這張表讓每一場戰鬥都退到「那場仗實際發生的地方」的既有底圖，
## 五十幾張地圖底圖本來就在 repo 裡，不必等新美術就先不黑。
##
## 專屬戰鬥背景畫好之後丟 `maps/battle_<mode>.png`，會自動蓋過這張表。
const BATTLE_BG_MAP := {
	## 主線 Boss
	"wolf": "road",
	"leo": "wild_leo_court",
	"fog": "mist_village",
	"abo": "dojo",
	"falcon": "forest",
	"boar": "coast",
	"demon": "tower",
	## 通關後裂縫：都發生在黑焰疤地
	"wrath": "blackflame_scar",
	"tide": "coast_wreck",
	"statue": "tower_memory",
	"chrono": "tower_stairs",
	## 秘境小 Boss
	"scar_lord": "blackflame_scar",
	"mirror_wraith": "mist_mirror",
	"wreck_captain": "coast_wreck",
	## 雜魚：照牠們出沒的地方
	"ash_rat": "hunting_grounds",
	"road_bandit": "road_ruins",
	"sewer_slime": "town_sewers",
	"fog_shade": "mist_cliff",
	"bamboo_spirit": "dojo_bamboo",
	"forest_sprite": "forest_canopy",
	"coast_raider": "coast_wreck",
	"scar_wisp": "blackflame_scar",
	"black_ronin": "crossroads",
}

## 誰都沒對上時的最後一張。挑荒野是因為它夠中性，什麼仗擺上去都不突兀。
const BATTLE_BG_LAST_RESORT := "wild"


## 這場戰鬥的背景圖路徑。順序：專屬戰鬥背景 → 那場仗發生的地圖 → 保底。
## 回空字串代表連保底都不在（正常情況不該發生，test_art 會擋）。
static func battle_bg_path(mode: String) -> String:
	var own := "%s/maps/battle_%s.png" % [ROOT, mode]
	if ResourceLoader.exists(own):
		return own
	var map_id := str(BATTLE_BG_MAP.get(mode, ""))
	if map_id != "":
		var by_map := "%s/maps/%s_bg.png" % [ROOT, map_id]
		if ResourceLoader.exists(by_map):
			return by_map
	var last := "%s/maps/%s_bg.png" % [ROOT, BATTLE_BG_LAST_RESORT]
	return last if ResourceLoader.exists(last) else ""


## 這張背景是專屬畫的，還是退回去用地圖底圖的。給工具與測試看覆蓋率用。
static func battle_bg_is_dedicated(mode: String) -> bool:
	return ResourceLoader.exists("%s/maps/battle_%s.png" % [ROOT, mode])


static func battle_bg(mode: String) -> Texture2D:
	return tex(battle_bg_path(mode))


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
		"scar_boss":
			return "%s/bosses/scar_lord_icon.png" % ROOT
		"mirror_boss":
			return "%s/bosses/mirror_wraith_icon.png" % ROOT
		"wreck_boss":
			return "%s/bosses/wreck_captain_icon.png" % ROOT
		"duanye":
			return "%s/npcs/duanye.png" % ROOT
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
		"herb_slope":
			return "%s/props/herb.png" % ROOT
		"dock":
			return "%s/props/dock.png" % ROOT
		"forge_c5", "forge_sign":
			return "%s/props/forge.png" % ROOT
		"path_mist", "path_dojo", "path_forest", "path_coast", "path_tower", "path_tower_c5", "arrow_path", "cliff_path", "sign_east", "trail_mark":
			return "%s/props/path.png" % ROOT
		"market", "cart", "burnt_field", "stall_frame", "stall":
			return "%s/props/crate.png" % ROOT if ResourceLoader.exists("%s/props/crate.png" % ROOT) else "%s/props/camp.png" % ROOT
		"look_back", "ash_pile", "dawn_glow":
			return "%s/props/campfire.png" % ROOT if ResourceLoader.exists("%s/props/campfire.png" % ROOT) else "%s/props/fire.png" % ROOT
		"well", "fountain", "bench", "well_fog", "keep_well":
			return "%s/props/well.png" % ROOT if ResourceLoader.exists("%s/props/well.png" % ROOT) else "%s/props/save.png" % ROOT
		"rubble", "road_stone", "bush_a", "bush_b", "scarecrow", "scare_field", "rock", "ruin_pillar", "woodpile", "orchard":
			return "%s/props/rock.png" % ROOT if ResourceLoader.exists("%s/props/rock.png" % ROOT) else "%s/props/herb.png" % ROOT
		"tree", "pine", "treehouse":
			return "%s/props/tree.png" % ROOT if ResourceLoader.exists("%s/props/tree.png" % ROOT) else "%s/props/camp.png" % ROOT
		"barrel", "crate", "hunt_recycler":
			return "%s/props/barrel.png" % ROOT if ResourceLoader.exists("%s/props/barrel.png" % ROOT) else "%s/props/camp.png" % ROOT
		"lantern", "beacon":
			return "%s/props/lantern.png" % ROOT if ResourceLoader.exists("%s/props/lantern.png" % ROOT) else "%s/props/fire.png" % ROOT
		"sign", "sign_board", "milepost", "milepost_b", "wall_notice", "hunt_board", "hunt_start":
			return "%s/props/sign.png" % ROOT if ResourceLoader.exists("%s/props/sign.png" % ROOT) else "%s/props/path.png" % ROOT
		"campfire", "refugee_fire":
			return "%s/props/campfire.png" % ROOT if ResourceLoader.exists("%s/props/campfire.png" % ROOT) else "%s/props/fire.png" % ROOT
		"shrine", "shrine_stub", "altar", "message_stone":
			return "%s/props/shrine.png" % ROOT if ResourceLoader.exists("%s/props/shrine.png" % ROOT) else "%s/props/bell.png" % ROOT
		"boat", "boat_wreck":
			return "%s/props/boat.png" % ROOT if ResourceLoader.exists("%s/props/boat.png" % ROOT) else "%s/props/dock.png" % ROOT
		"hut_a", "hut_b", "hut_c", "inn", "dorm", "stable", "chapel", "half_house":
			return "%s/props/hut.png" % ROOT if ResourceLoader.exists("%s/props/hut.png" % ROOT) else "%s/props/camp.png" % ROOT
		"gate_arch", "tower_gate", "windmill", "fence_row":
			return "%s/props/gate.png" % ROOT if ResourceLoader.exists("%s/props/gate.png" % ROOT) else "%s/props/tower.png" % ROOT
		"banner":
			return "%s/props/banner.png" % ROOT if ResourceLoader.exists("%s/props/banner.png" % ROOT) else "%s/props/flag.png" % ROOT
		"merchant":
			return "%s/npcs/merchant.png" % ROOT
		_:
			return _fallback_prop_path(entity_id)


## 上面那張表沒列到的 entity 落到這裡。
##
## 為什麼需要這一層：地圖裡有 373 種 entity，明確列出來的只有 100 出頭；
## 其餘的在畫面上是純色方塊。一個一個補太慢也補不完，而且大多數缺口
## 根本不需要專屬圖 —— 「回岔路」「往塔頂」「石堆」用既有的那幾張就講得清楚。
##
## 規則走 **底線切出來的詞**，不是字串包含。用包含的話 forest 裡有 ore、
## store 裡有 tor，會把森林畫成石頭。切詞之後 to_forest_ruins 的詞是
## [to, forest, ruins]，只會命中第一個 to（導覽點）。
##
## 匹配不到就回空字串，讓 ExploreView 照舊畫純色方塊 —— 那是誠實的表示
## 「這個東西還沒有圖」，比硬湊一張不相干的圖好。
const _HEAD_PROP := {
	"back": "exit", "exit": "exit", "to": "exit", "leave": "exit",
	"path": "path", "trail": "path", "climb": "path", "cross": "path", "road": "path",
	"save": "save",
}

## 順序有意義：先比對細的再比對粗的。campfire 要排在 camp 前面，
## 不然營火會變成營帳。
const _TOKEN_PROP := [
	[["grave", "tomb", "shrine", "altar", "statue"], "shrine"],
	[["campfire", "bonfire"], "campfire"],
	[["camp", "tent"], "camp"],
	[["fire", "ember", "flame", "torch"], "fire"],
	[["hut", "house", "inn", "dorm", "cabin", "mill", "barn", "shed", "room", "hall"], "hut"],
	[["pine"], "pine"],
	[["tree", "wood", "orchard", "willow", "canopy", "log", "bamboo", "reed"], "tree"],
	[["rock", "stone", "bone", "rubble", "ore", "pile", "boulder", "vein", "obsidian"], "rock"],
	[["sign", "notice", "board", "post", "milepost", "plaque", "mark"], "sign"],
	[["gate", "arch", "door", "span"], "gate"],
	[["well", "pond", "water", "spring", "fountain", "pool"], "well"],
	[["boat", "dock", "ship", "wreck", "raft", "hull", "mast", "net"], "boat"],
	[["banner", "flag"], "banner"],
	[["barrel", "crate", "cart", "box", "wagon", "rack"], "barrel"],
	[["lantern", "lamp", "beacon", "candle", "incense"], "lantern"],
	[["tower", "keep", "spire", "column", "pillar"], "tower"],
	[["bell", "chime"], "bell"],
	[["forge", "anvil", "smith"], "forge"],
	[["herb", "grass", "moss", "bush", "field", "wheat", "crop", "scare", "bloom"], "herb"],
	[["cliff", "ridge", "slope", "peak", "canyon", "ravine"], "cliff"],
	[["nest"], "nest"],
	[["sword", "blade", "weapon", "armor"], "sword"],
	[["dummy", "training", "spar"], "dummy"],
	[["tea"], "tea"],
]


static func _fallback_prop_path(entity_id: String) -> String:
	var toks := entity_id.split("_", false)
	if toks.is_empty():
		return ""
	var name := ""
	if _HEAD_PROP.has(toks[0]):
		name = str(_HEAD_PROP[toks[0]])
	else:
		for rule in _TOKEN_PROP:
			var keys: Array = rule[0]
			var hit := false
			for tk in toks:
				if tk in keys:
					hit = true
					break
			if hit:
				name = str(rule[1])
				break
	if name == "":
		return ""
	var path := "%s/props/%s.png" % [ROOT, name]
	return path if ResourceLoader.exists(path) else ""


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
