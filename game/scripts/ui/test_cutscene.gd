extends SceneTree
## 過場把關測試：godot --headless -s res://scripts/ui/test_cutscene.gd
##
## 加了影片支援之後，最該守的是「影片沒轉出來時遊戲照樣走得下去」。
## 過場是主線的一部分，播不出來就卡在那裡的話，等於整個檔案報廢——
## 而缺影片這件事在出貨包裡特別容易發生（影片大，很容易漏進版控或漏進 export）。
##
## 守五件事：
##   1. 缺影片的 slide 要退回純底圖，不能中斷流程
##   2. **缺過場插畫的 slide 要退回地圖底圖**，不能變成一片空白
##   3. 過場一定要走到結尾並發出 finished
##   4. abort() 之後要完全收乾淨（隱藏、不再攔滑鼠）
##   5. 隱藏時絕不攔滑鼠——這是以前「標題卡選單」的元凶
##
## 第 2 點是這版最需要守的：十四段過場全部都掛了插畫 id，但插畫是一段一段慢慢補的，
## 大多數時候檔案並不存在。退回機制一旦壞掉，十四段過場會同時變成空白畫面。

const CutscenePlayerScript = preload("res://scripts/ui/cutscene_player.gd")

var _ok := true
var _cp: Control
var _finished := false
var _frames := 0
var _stage := 0


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	_cp = CutscenePlayerScript.new()
	root.add_child(_cp)
	_cp.finished.connect(func() -> void:
		_finished = true
	)


func _process(_delta: float) -> bool:
	_frames += 1

	if _stage == 0:
		## 隱藏狀態不該攔滑鼠
		if _cp.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("隱藏時仍在攔滑鼠（會讓底下的選單點不到）")
			return _finish()
		print("  ok 隱藏時不攔滑鼠")
		## 三張：缺插畫＋缺影片、純字幕、正常底圖；hold 都很短好讓它自己走完
		_cp.play([
			{
				"art": "這張插畫還沒畫", "bg": "town", "video": "這支影片不存在",
				"speaker": "旅人", "text": "第一張", "hold": 0.05,
			},
			{"speaker": "旅人", "text": "第二張", "hold": 0.05},
			{"bg": "town", "speaker": "旅人", "text": "第三張", "hold": 0.05},
		])
		if not _cp.visible:
			_fail("play() 之後過場沒有顯示")
			return _finish()
		## 第一張是同步顯示的，這裡就能驗退回機制
		if _cp._bg.texture == null:
			_fail("插畫不存在時沒有退回地圖底圖（畫面會是一片空白）")
			return _finish()
		print("  ok 插畫缺席時退回地圖底圖")
		if _cp._art_texture("完全不存在的插畫") != null:
			_fail("_art_texture 對不存在的插畫沒有回 null")
			return _finish()
		_stage = 1
		return false

	if _stage == 1:
		## 缺影片時影片層必須是關的，否則會蓋著一片空白
		if _cp._video.visible:
			_fail("影片載不到卻仍然顯示影片層")
			return _finish()
		if _finished:
			print("  ok 缺影片的 slide 有退回底圖，三張都走完並發出 finished")
			_stage = 2
		elif _frames > 600:
			_fail("過場沒有在合理時間內走完（缺影片可能卡住流程）")
			return _finish()
		return false

	if _stage == 2:
		if _cp.visible:
			_fail("finished 之後過場還顯示著")
			return _finish()
		if _cp.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("結束後仍在攔滑鼠")
			return _finish()
		print("  ok 結束後隱藏且不攔滑鼠")
		## 播到一半硬中止。
		## 專案裡目前一支影片都還沒轉出來，所以「abort 要把影片收乾淨」這條
		## 如果只是照常播一段沒有影片的過場，等於在驗一個本來就空的欄位——
		## 變異測試證實過：把 abort() 裡的 _stop_video() 整行刪掉，測試照樣全綠。
		## 所以這裡自己塞一個影片進去，逼 abort 真的動手收。
		_finished = false
		_cp.play([{"speaker": "旅人", "text": "中止測試", "hold": 0.0}])
		_cp._video.stream = VideoStreamTheora.new()
		_cp._video.visible = true
		_cp.abort()
		if _cp.visible:
			_fail("abort() 之後還顯示著")
			return _finish()
		if _cp.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("abort() 之後仍在攔滑鼠")
			return _finish()
		if _cp._video.visible or _cp._video.stream != null:
			_fail("abort() 沒有把影片收乾淨")
			return _finish()
		print("  ok abort() 收得乾淨（不顯示、不攔滑鼠、影片已卸下）")
		return _finish()

	return false


func _finish() -> bool:
	if _ok:
		print("CUTSCENE_OK")
		quit(0)
	else:
		print("CUTSCENE_FAIL")
		quit(1)
	return true
