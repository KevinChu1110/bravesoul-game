extends SceneTree
## 貼圖路徑煙霧測：godot --headless -s res://scripts/art/test_art.gd


func _initialize() -> void:
	var ok := true
	var checks: Array = [
		["player", SpriteDB.player_idle()],
		["battle_player", SpriteDB.player_battle()],
		["leo", SpriteDB.boss("leo")],
		["fog", SpriteDB.boss("fog")],
		["abo", SpriteDB.boss("abo")],
		["demon", SpriteDB.boss("demon")],
		["falcon", SpriteDB.boss("falcon")],
		["boar", SpriteDB.boss("boar")],
		["town_bg", SpriteDB.map_bg("town")],
		["forest_bg", SpriteDB.map_bg("forest")],
		["battle_leo", SpriteDB.battle_bg("leo")],
		["battle_scar_wisp", SpriteDB.battle_bg("scar_wisp")],
		["ding", SpriteDB.explore_entity_tex("ding")],
		["fire_ring", SpriteDB.fx("fire_ring")],
		["tile_stone", SpriteDB.tile("stone")],
		["tile_grass", SpriteDB.tile("grass")],
		["player_atk", SpriteDB.player_pose("attack")],
		["player_skill", SpriteDB.player_pose("skill")],
	]
	for c in checks:
		if c[1] == null:
			push_error("missing texture: %s" % c[0])
			ok = false
		else:
			print("OK ", c[0], " ", c[1].get_size())
	## 音效檔
	for sfx in ["parry", "hit", "slash", "fire", "reveal", "break", "step", "victory"]:
		var path := "res://assets/audio/sfx/%s.wav" % sfx
		if not ResourceLoader.exists(path):
			push_error("missing sfx: %s" % sfx)
			ok = false
		else:
			print("OK sfx ", sfx)
	## SpriteDB 必須在執行期查得到 GameState（不可在編譯期引用 autoload 識別字，
	## 否則 -s 跑測試時會 Compile Error → 退回跑主場景 → 永遠不結束）
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		push_error("GameState autoload missing")
		ok = false
	else:
		gs.reset_new_game()
		gs.path_style = "sword"
		var wid := SpriteDB.player_weapon_class_id()
		if wid != "sword":
			push_error("weapon class from path_style failed: got '%s' want 'sword'" % wid)
			ok = false
		else:
			print("OK weapon_class_from_path sword")
		## 各流派武器／防具疊層貼圖（探索＋戰鬥同源 SpriteDB）
		for cls in ["sword", "bow", "magic", "fist", "axe", "hammer", "spear", "gun", "dart", "crystal"]:
			gs.path_style = cls
			var otex: Texture2D = SpriteDB.player_weapon_overlay()
			if otex == null:
				push_error("weapon overlay missing for path %s" % cls)
				ok = false
			else:
				print("OK weapon_overlay ", cls, " ", otex.get_size())
		gs.path_style = "sword"
		for arm in ["plate", "leather", "veil", "cloth"]:
			var ap := "res://assets/sprites/player/armor/%s.png" % arm
			if not ResourceLoader.exists(ap):
				push_error("armor overlay asset missing: %s" % arm)
				ok = false
			else:
				print("OK armor_asset ", arm)
		## 完整紙娃娃：equipment.json 每個 base_id 都要有 paperdoll 疊層
		if not _check_paperdoll_coverage():
			ok = false

	if not _check_entity_coverage():
		ok = false
	if not _check_battle_backgrounds():
		ok = false

	if ok:
		print("ART_OK")
		quit(0)
	else:
		print("ART_FAIL")
		quit(1)


## 每一種戰鬥都要有背景，而且不可以用到「畫了角色的完成稿」。
##
## 踩過兩件事：
##   1. `maps/battle_leo.png` 那七張是主角＋敵人都畫好的插圖被當背景用。
##      打雷歐的時候背景裡有一隻比人還大的兔子在跟哥布林對砍，
##      前景又疊一隻活的主角。看起來像 bug，其實是「拿錯圖」。
##   2. 其餘十六種戰鬥連圖都沒有，背景直接是純黑。
##
## 現在解析順序是「專屬圖 → 那場仗發生的地圖 → 保底」，所以這裡守兩件事：
## 每一種模式都解析得到東西，而且 maps/ 底下不准再出現角色插圖。
func _check_battle_backgrounds() -> bool:
	## 所有會進戰鬥的 mode
	var modes: Array[String] = [
		"wolf", "leo", "fog", "abo", "falcon", "boar", "demon",
		"wrath", "tide", "statue", "chrono",
		"scar_lord", "mirror_wraith", "wreck_captain",
		"ash_rat", "road_bandit", "sewer_slime", "fog_shade",
		"bamboo_spirit", "forest_sprite", "coast_raider", "scar_wisp",
		"black_ronin",
	]
	var missing: PackedStringArray = []
	var dedicated := 0
	for m in modes:
		if SpriteDB.battle_bg_path(m) == "":
			missing.append(m)
		elif SpriteDB.battle_bg_is_dedicated(m):
			dedicated += 1
	if missing.size() > 0:
		push_error("這些戰鬥沒有背景，畫面會是純黑：%s" % ", ".join(missing))
		print("  FAIL 沒有背景的戰鬥：", ", ".join(missing))
		return false
	print("  ok %d 種戰鬥都有背景（其中 %d 種有專屬圖，其餘退到該地圖底圖）" % [
		modes.size(), dedicated
	])

	## maps/ 底下不該再有 battle_*：那個檔名現在專門留給「純背景」，
	## 而歷史上放在那裡的是畫了角色的完成稿。
	var dir := DirAccess.open("res://assets/sprites/maps")
	if dir == null:
		push_error("開不了 maps 目錄")
		return false
	var strays: PackedStringArray = []
	for f in dir.get_files():
		var base := f.trim_suffix(".import")
		if base.begins_with("battle_") and base.ends_with(".png"):
			var mode := base.trim_prefix("battle_").trim_suffix(".png")
			if not modes.has(mode):
				strays.append(base)
	if strays.size() > 0:
		push_error("maps/ 底下有對不到任何戰鬥的 battle_*：%s" % ", ".join(strays))
		print("  FAIL 對不到戰鬥的背景檔：", ", ".join(strays))
		return false
	return true


## 場景物件的貼圖覆蓋率。
##
## 守兩件事：
##   1. explore_entity_path 的 match 裡沒有「永遠執行不到的分支」。
##      GDScript 的 match 是由上往下第一個命中就回傳，同一個 id 寫在兩支
##      case 裡時，後面那支永遠不會跑。實際踩過：hut_a／inn 被前面一支
##      指到佔位圖 camp.png，後面那支寫好的 hut.png 從來沒被用過 ——
##      看畫面只覺得「這張圖怎麼怪怪的」，看程式碼兩支都在，不會有人起疑。
##   2. 覆蓋率不要退步。地圖裡每一個 entity 都該解析得到貼圖，或落在
##      下面那份「本來就沒有圖」的名單裡。新增地圖物件時若忘了接圖，
##      這條會把數字掉下去。
##
## 只驗「解析得到 / 解析不到」，不驗「圖挑得對不對」—— 後者要靠眼睛。
const MAP_CATALOG := "res://scripts/world/map_catalog.gd"
const SPRITE_DB := "res://scripts/art/sprite_db.gd"

## 覆蓋率下限。實測 335/426 = 78.6%（改這批之前是 106/426 = 24.9%）。
## 往上調可以，掉下來要說明為什麼。
const MIN_COVERAGE := 0.75


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _check_entity_coverage() -> bool:
	var src := _read(SPRITE_DB)
	if src == "":
		push_error("讀不到 %s" % SPRITE_DB)
		return false

	## ── 1. 找出被前面攔截、永遠執行不到的 case ──
	var in_match := false
	var seen: Dictionary = {}       ## id -> 第一次出現的行號
	var shadowed: PackedStringArray = []
	var lines := src.split("\n")
	for i in lines.size():
		var ln: String = lines[i]
		if ln.begins_with("static func explore_entity_path"):
			in_match = true
			continue
		if not in_match:
			continue
		if ln.strip_edges() == "_:":
			break
		## 只認 case 標頭：兩個 tab 開頭、以冒號結尾、內容全是字串字面值
		if not ln.begins_with("\t\t") or not ln.strip_edges().ends_with(":"):
			continue
		var head := ln.strip_edges().trim_suffix(":")
		if not head.begins_with("\""):
			continue
		for part in head.split(","):
			var id := part.strip_edges().trim_prefix("\"").trim_suffix("\"")
			if id == "":
				continue
			if seen.has(id):
				shadowed.append("%s（第 %d 行已攔截，第 %d 行永遠不執行）" % [id, int(seen[id]), i + 1])
			else:
				seen[id] = i + 1
	if shadowed.size() > 0:
		push_error("explore_entity_path 有永遠執行不到的 case：%s" % ", ".join(shadowed))
		print("  FAIL 有被攔截的 case：", ", ".join(shadowed))
		return false
	print("  ok match 的 %d 個 id 沒有互相攔截" % seen.size())

	## ── 2. 覆蓋率 ──
	var mc := _read(MAP_CATALOG)
	if mc == "":
		push_error("讀不到 %s" % MAP_CATALOG)
		return false
	var re := RegEx.create_from_string("_e\\(\\s*\"([^\"]+)\"")
	var total := 0
	var covered := 0
	var blanks: Dictionary = {}
	for m in re.search_all(mc):
		var eid := m.get_string(1)
		total += 1
		if SpriteDB.explore_entity_path(eid) != "":
			covered += 1
		else:
			blanks[eid] = true
	if total == 0:
		push_error("從 map_catalog 抓不到任何 entity —— 這條檢查等於沒在檢查")
		return false
	var rate := float(covered) / float(total)
	if rate < MIN_COVERAGE:
		push_error("場景物件貼圖覆蓋率 %.1f%%（%d/%d），低於下限 %.1f%%" % [
			rate * 100.0, covered, total, MIN_COVERAGE * 100.0
		])
		print("  FAIL 覆蓋率掉到 %.1f%%" % (rate * 100.0))
		return false
	print("  ok 場景物件貼圖覆蓋率 %.1f%%（%d/%d 個放置點；%d 種仍是純色方塊）" % [
		rate * 100.0, covered, total, blanks.size()
	])
	return true


## 紙娃娃：equipment.json 每個 base_id 都要有 paperdoll/{slot}/{id}.png
func _check_paperdoll_coverage() -> bool:
	var path := "res://data/tables/equipment.json"
	if not FileAccess.file_exists(path):
		push_error("equipment.json missing")
		return false
	var raw := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("equipment.json parse fail")
		return false
	var bases: Dictionary = data.get("bases", {})
	var missing: PackedStringArray = []
	var ok_n := 0
	for bid in bases.keys():
		var def: Dictionary = bases[bid]
		var slot := str(def.get("slot", "weapon"))
		var p := "res://assets/sprites/player/paperdoll/%s/%s.png" % [slot, bid]
		if ResourceLoader.exists(p):
			ok_n += 1
		else:
			missing.append("%s/%s" % [slot, bid])
	if missing.size() > 0:
		push_error("紙娃娃缺圖 %d：%s" % [missing.size(), ", ".join(missing)])
		print("  FAIL paperdoll missing: ", ", ".join(missing))
		return false
	print("  ok paperdoll 全覆蓋 %d/%d" % [ok_n, bases.size()])
	return true
