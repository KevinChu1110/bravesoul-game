extends SceneTree
## BGM 把關測試：godot --headless -s res://scripts/art/test_bgm.gd
##
## 守四件事：
##   1. 曲目清單就是下面 EXPECT_IDS 這幾首，一首不多一首不少
##   2. 每一首都載得到（.ogg／.mp3 真配樂或 .wav 後備，至少要有一個）
##   3. 換成壓縮格式的曲子一定要有可讀的長度，檔案壞了要當場抓出來
##   4. loops.json 只能有已知曲目 id，循環起點不能是負數、也不能超過曲長
##
## 第 4 點特別重要：循環起點打錯（例如把秒寫成毫秒）會讓曲子從尾巴開始循環，
## 聽起來像壞掉但不會報任何錯，只靠耳朵很難抓。
##
## 第 1 點是後來補的。原本只跑迴圈檢查「清單裡的每一首都載得到」，
## 變異測試把清單從 13 首砍到 3 首，測試照樣全綠，還很有精神地印
## 「13 首全部載得到」—— 迴圈跑空的時候，任何「每一個都對」都是真的。
## 凡是「對清單裡的每一項做檢查」，都要先釘住清單本身。
##
## 注意：用 `-s` 跑時，autoload 的 _ready 在 _initialize 之後才執行，
## 所以檢查必須等到第一個影格，不能寫在 _initialize 裡。

const BGM_DIR := "res://assets/audio/bgm"
const LOOPS_PATH := "res://assets/audio/bgm/loops.json"
## 真配樂可用的格式，順序＝AudioManager 的挑選順序
const MUSIC_EXTS: Array[String] = ["ogg", "mp3"]

## 遊戲該有的曲目。少一首＝有場景會沒配樂，多一首＝有曲子沒人放。
## 兩種都不會噴錯，所以釘在這裡，增刪曲目時逼人來改一次。
const EXPECT_IDS: Array[String] = [
	"title", "village", "town", "mist", "dojo", "forest", "coast",
	"wild", "road", "battle", "boss", "tower", "ending",
]

var _ok := true
var _done := false


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var am := root.get_node_or_null("AudioManager")
	if am == null:
		_fail("AudioManager autoload missing")
		_finish()
		return true

	var ids: Array = am.bgm_ids()
	if not _check_id_list(ids):
		_finish()
		return true
	_check_all_loadable(am, ids)
	_check_loops_json(ids)
	_finish()
	return true


## 先釘住清單本身。下面每一條檢查都是「對清單裡的每一首做某件事」，
## 清單被砍短的話那些檢查會全部變成空轉，而空轉的迴圈永遠是綠的。
func _check_id_list(ids: Array) -> bool:
	var got: Array[String] = []
	for id in ids:
		got.append(str(id))
	var missing: Array[String] = []
	for want in EXPECT_IDS:
		if not got.has(want):
			missing.append(want)
	var extra: Array[String] = []
	for g in got:
		if not EXPECT_IDS.has(g):
			extra.append(g)
	if not missing.is_empty() or not extra.is_empty():
		_fail("曲目清單對不上：少了 %s，多了 %s（增刪曲目要一起改 EXPECT_IDS）"
			% [str(missing), str(extra)])
		return false
	if got.size() != EXPECT_IDS.size():
		_fail("曲目清單有重複的 id：%s" % str(got))
		return false
	return true


func _check_all_loadable(am: Node, ids: Array) -> void:
	var real_n := 0
	for id in ids:
		var src: String = am.bgm_source(str(id))
		if src == "":
			_fail("%s 載不到（%s 與 .wav 都沒有）" % [id, str(MUSIC_EXTS)])
			return
		if src == "wav":
			continue
		real_n += 1
		if not _check_music_file(str(id), src):
			return
	print("  ok %d 首全部載得到（真配樂 %d 首、程式合成 %d 首）"
		% [ids.size(), real_n, ids.size() - real_n])


func _check_music_file(id: String, ext: String) -> bool:
	var path := "%s/%s.%s" % [BGM_DIR, id, ext]
	var s: Variant = load(path)
	if not (s is AudioStream):
		_fail("%s.%s 載進來不是音訊資源" % [id, ext])
		return false
	if (s as AudioStream).get_length() <= 0.0:
		_fail("%s.%s 讀不出長度，檔案可能壞了" % [id, ext])
		return false
	return true


## 找出這首曲子實際用的真配樂檔（沒有就回空字串）
func _music_path(id: String) -> String:
	for ext in MUSIC_EXTS:
		var p := "%s/%s.%s" % [BGM_DIR, id, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


func _check_loops_json(ids: Array) -> void:
	if not FileAccess.file_exists(LOOPS_PATH):
		print("  ok 尚無 loops.json（還沒換真配樂，正常）")
		return
	var f := FileAccess.open(LOOPS_PATH, FileAccess.READ)
	if f == null:
		_fail("loops.json 開不起來")
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		_fail("loops.json 不是物件")
		return

	var d: Dictionary = data
	for k in d:
		var id := str(k)
		if not ids.has(id):
			_fail("loops.json 有不認識的曲目 id：%s" % id)
			return
		var off := float(d[k])
		if off < 0.0:
			_fail("%s 的循環起點是負數：%s" % [id, str(off)])
			return
		var path := _music_path(id)
		if path == "":
			_fail("loops.json 有 %s，但找不到對應的真配樂檔" % id)
			return
		var s: Variant = load(path)
		if s is AudioStream:
			var dur: float = (s as AudioStream).get_length()
			if dur > 0.0 and off >= dur:
				_fail("%s 的循環起點 %.2f 秒超過曲長 %.2f 秒（單位寫錯？）" % [id, off, dur])
				return
	print("  ok loops.json %d 筆，id 與循環起點都合法" % d.size())


func _finish() -> void:
	if _ok:
		print("BGM_OK")
		quit(0)
	else:
		print("BGM_FAIL")
		quit(1)
