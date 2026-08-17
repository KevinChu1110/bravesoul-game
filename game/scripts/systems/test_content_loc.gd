extends SceneTree
## 內容譯文層的測試：godot --headless -s res://scripts/systems/test_content_loc.gd
##
## 這層負責招式名、地名、物件標籤這些「寫死在 .gd 目錄常數裡」的字。
## 介面字串走 data/i18n，這些走 data/i18n/content ——
## 兩邊都翻完，韓文玩家才不會走進「Knight Keep · 演武場」這種半英半中的畫面。
##
## 守三件事：
##   1. 繁中要走快速路徑，原樣回傳（不能因為多包一層就改到原文）
##   2. 查得到就換掉，查不到要回**原文**，不能回空字串或 key
##   3. 覆蓋檔真的載得到，而且內容是每個語言不同的字
##
## 注意：這裡不碰 MapCatalog。那支相依 GameState autoload，而 `-s` 腳本
## 是在 autoload 註冊之前編譯的，一 import 就是 compile error。
## 地圖那條線由 tools/check_content_loc.py 顧原文對齊，畫面則靠實機截圖。

const CL := preload("res://scripts/systems/content_loc.gd")

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var loc: Node = root.get_node_or_null("Loc")
	if loc == null:
		_fail("沒有 Loc autoload，這支測不了")
		return _finish()

	## 1) 繁中原樣回傳
	loc.call("set_locale", "zh_TW")
	CL.reload()
	if CL.text("map", "營火") != "營火":
		_fail("繁中被動到了 —— 原文應該原樣回傳")

	## 2+3) 其他語言要真的換掉，而且各自不同
	var seen: Dictionary = {}
	for code in ["en", "ja", "ko", "es", "zh_CN"]:
		loc.call("set_locale", code)
		CL.reload()
		var got := CL.text("map", "營火")
		if got == "" or got == "營火":
			_fail("%s 的「營火」沒被換掉（拿到 %s）" % [code, got])
			continue
		if seen.has(got):
			_fail("%s 跟 %s 的「營火」翻成同一個字：%s" % [code, seen[got], got])
		seen[got] = code

		## 查不到的字要回原文，不能變空白 —— 玩家寧可看到中文也不要看到空的
		var miss := CL.text("map", "這句原文不存在於覆蓋表")
		if miss != "這句原文不存在於覆蓋表":
			_fail("%s 查不到的字沒有回原文，拿到：%s" % [code, miss])

		## 空字串進、空字串出，不要炸
		if CL.text("map", "") != "":
			_fail("%s 空字串沒有原樣回傳" % code)
	if _ok:
		print("  ok 5 個語言的覆蓋表都載得到，且各自不同")

	## 4) apply() 只覆蓋原本就有的欄位
	loc.call("set_locale", "en")
	CL.reload()
	var row := {"id": "nope", "name": "原名"}
	var out: Dictionary = CL.apply("map", row)
	if out.get("name") != "原名":
		_fail("apply() 查不到 id 時應該原樣回傳")
	if row.get("name") != "原名":
		_fail("apply() 改到了傳進去的原始 Dictionary")
	if _ok:
		print("  ok apply() 不會動到原始資料")

	_finish()


func _finish() -> void:
	if _ok:
		print("CONTENT_LOC_OK")
		quit(0)
	else:
		print("CONTENT_LOC_FAIL")
		quit(1)
