extends SceneTree
## 翻譯表的把關測試：godot --headless -s res://scripts/autoload/test_i18n.gd
##
## 守兩件事：
##   1. 兩張表的 key 要一模一樣。少一個 key 不會報錯 —— Loc.t() 查不到就
##      **回傳 key 本身**，玩家會直接看到 "panel.world_map" 這種字串。
##   2. 程式裡 Loc.t("...") 用到的 key 都要在表裡。同上，漏了不會當掉，
##      只會在畫面上冒出一個看起來像亂碼的英文字。
##
## 這支不管「翻得好不好」（那要人看），只管「有沒有漏」。

const ZH := "res://../game/data/i18n/zh_TW.json"
const EN := "res://../game/data/i18n/en.json"

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _initialize() -> void:
	var zh := _load("res://data/i18n/zh_TW.json")
	var en := _load("res://data/i18n/en.json")
	if zh.is_empty() or en.is_empty():
		_fail("讀不到翻譯表（zh %d／en %d）" % [zh.size(), en.size()])
		return _finish()

	## 1) 兩邊 key 對齊
	var only_zh: PackedStringArray = []
	var only_en: PackedStringArray = []
	for k in zh.keys():
		if not en.has(k):
			only_zh.append(str(k))
	for k in en.keys():
		if not zh.has(k):
			only_en.append(str(k))
	if only_zh.size() > 0 or only_en.size() > 0:
		_fail("兩張表對不齊 —— 只有中文有：%s；只有英文有：%s" % [
			", ".join(only_zh), ", ".join(only_en)])
		return _finish()
	print("  ok 兩張表都是 %d 個 key，完全對齊" % zh.size())

	## 2) 程式用到的 key 都要在表裡
	var used: Dictionary = {}
	_scan_dir("res://scripts", used)
	if used.is_empty():
		_fail("從程式裡一個 Loc.t() 都沒抓到 —— 這條檢查等於沒在檢查")
		return _finish()
	var missing: PackedStringArray = []
	for k in used.keys():
		if not zh.has(k):
			missing.append(str(k))
	if missing.size() > 0:
		_fail("程式用了表裡沒有的 key，玩家會直接看到 key 本身：%s" % ", ".join(missing))
		return _finish()
	print("  ok 程式用到的 %d 個 key 都在表裡" % used.size())
	_finish()


func _scan_dir(path: String, used: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var re := RegEx.create_from_string('Loc\\.t\\(\\s*"([a-z0-9_.]+)"')
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		## 測試與量測腳本不算
		if f.begins_with("test_"):
			continue
		var fh := FileAccess.open(path + "/" + f, FileAccess.READ)
		if fh == null:
			continue
		## 逐行掃並跳過註解 —— loc.gd 的檔頭就寫著用法範例 Loc.t("key")，
		## 整檔一次掃會把那個範例當成真的 key，於是測試自己造出一個假失敗。
		for line in fh.get_as_text().split("\n"):
			var st := line.strip_edges()
			if st.begins_with("#"):
				continue
			for m in re.search_all(line):
				used[m.get_string(1)] = true
	for d in dir.get_directories():
		if d == "dev":
			continue
		_scan_dir(path + "/" + d, used)


func _finish() -> void:
	if _ok:
		print("I18N_OK")
		quit(0)
	else:
		print("I18N_FAIL")
		quit(1)
