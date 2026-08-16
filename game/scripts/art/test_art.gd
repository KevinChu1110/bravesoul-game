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

	if not _check_entity_coverage():
		ok = false

	if ok:
		print("ART_OK")
		quit(0)
	else:
		print("ART_FAIL")
		quit(1)


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
