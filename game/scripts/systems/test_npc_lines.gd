extends SceneTree
## NPC 台詞資料化的把關測試：godot --headless -s res://scripts/systems/test_npc_lines.gd
##
## 遷移當下是用「新舊對拍」驗的：窮舉 344 種 flag／周目狀態 × 10 個 NPC，比對讀 JSON
## 的新版與原硬編碼版輸出是否完全相同（3440 組全中）。那份硬編碼版隨遷移一起刪除，
## 所以這裡改用從「已驗證正確的資料」導出的黃金樣本把關。
##
## 為什麼不能只靠 migrate_npc_lines.py 的 round-trip：round-trip 只證明「文字一條沒掉」，
## 證明不了「條件綁對了」—— 規則掛錯條件，文字集合照樣完全一致。

## 黃金樣本：每筆是「在某個狀態下，某 NPC 該講什麼」。
## 挑的都是規則挑選容易出錯的地方：ng_plus 與 flag 同時成立、兩個 flag 並存、
## 預設規則、以及「預設就是沒有台詞」。
const GOLDEN: Array = [
	{"npc": "greybeard", "ng": 1, "flags": ["boss.leo_cleared"], "n": 2, "first": "又一次。腳印疊在舊路上——你還記得第一次拔劍拔了三次嗎？"},
	{"npc": "greybeard", "ng": 0, "flags": ["boss.leo_cleared", "boss.white_fog_cleared"], "n": 2, "first": "霧也看破了？眼睛比劍先長。"},
	{"npc": "greybeard", "ng": 0, "flags": [], "n": 2, "first": "聖獅在內殿。你若不是送死，就先把劍養好。"},
	{"npc": "star", "ng": 0, "flags": [], "n": 0, "first": ""},
	{"npc": "ding", "ng": 0, "flags": ["side.ding_debt_done"], "n": 2, "first": "舊債還了。爐火……比以前穩一點。"},
	{"npc": "ronin", "ng": 0, "flags": ["side.ronin_spared"], "n": 1, "first": "……刃收了。路還長。別學我把焰當柴。"},
	{"npc": "tide_roar_idle", "ng": 0, "flags": ["c5_entered"], "n": 2, "first": "衝過來的時候別逃——迎上去。對撞。"},
	{"npc": "silk", "ng": 0, "flags": ["c2_wheat_letter"], "n": 2, "first": "兔子？來找書的少，來找藉口的多。"},
	{"npc": "knight_orphan", "ng": 0, "flags": ["side.ding_debt_asked"], "n": 2, "first": "斷劍？在武器架那邊。我不敢碰——怕鐵匠生氣。"},
	{"npc": "knight_orphan", "ng": 0, "flags": [], "n": 2, "first": "演武場以前很吵。現在只剩風。"},
]

## 目前有資料檔的 NPC。新增 NPC 時把 id 加進來，測試才會涵蓋到。
const NPCS: Array[String] = [
	"greybeard", "ding", "maisui_village", "fog_hide", "silk",
	"ronin", "acha", "star", "wind_ear_idle", "tide_roar_idle",
	"knight_orphan",
]

## 預設規則刻意是空的，不算缺台詞：
##   star           — 沒解鎖觀星前不搭話
##   maisui_village — 走主線對話，村裡的麥穗平時不另外出聲
const MAY_BE_SILENT: Array[String] = ["star", "maisui_village"]

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_fail("GameState autoload missing")
		_finish()
		return

	_check_data_health()
	_check_fresh_start(gs)
	_check_golden(gs)
	_finish()


## 資料檔本身合不合法
func _check_data_health() -> void:
	var ids := NpcLines.all_ids()
	if ids.size() != NPCS.size():
		_fail("data/npc_lines 有 %d 個檔，測試名單有 %d 個：%s" % [ids.size(), NPCS.size(), str(ids)])
		return
	for npc in NPCS:
		if not NpcLines.has_npc(npc):
			_fail("找不到 %s 的資料檔" % npc)
			return
	print("  ok 資料檔 %d 個，id 與名單相符" % ids.size())


## 全新開局下每個 NPC 都要講得出話，而且每句都要有 speaker
func _check_fresh_start(gs: Node) -> void:
	gs.reset_new_game()
	for npc in NPCS:
		var lines: Array = NpcLines.for_npc(npc)
		if lines.is_empty() and not MAY_BE_SILENT.has(npc):
			_fail("%s 在全新開局下沒有任何台詞" % npc)
			return
		for l in lines:
			if str(l.get("speaker", "")) == "":
				_fail("%s 有台詞沒有 speaker" % npc)
				return
	print("  ok 全新開局下 %d 個 NPC 台詞與 speaker 都在" % NPCS.size())


func _check_golden(gs: Node) -> void:
	for g in GOLDEN:
		gs.reset_new_game()
		gs.ng_plus = int(g["ng"])
		for f in g["flags"]:
			gs.set_flag(str(f), true)
		var npc := str(g["npc"])
		var got: Array = NpcLines.for_npc(npc)
		var label := "%s（ng=%d flags=%s）" % [npc, int(g["ng"]), str(g["flags"])]
		if got.size() != int(g["n"]):
			_fail("%s 台詞數 %d，期望 %d" % [label, got.size(), int(g["n"])])
			return
		var first := ""
		if got.size() > 0:
			first = str(got[0].get("text", ""))
		if first != str(g["first"]):
			_fail("%s 選到的規則不對\n    實際=%s\n    期望=%s" % [label, first, str(g["first"])])
			return
	print("  ok 黃金樣本 %d 筆全部相符" % GOLDEN.size())


func _finish() -> void:
	if _ok:
		print("NPC_LINES_OK")
		quit(0)
	else:
		print("NPC_LINES_FAIL")
		quit(1)
