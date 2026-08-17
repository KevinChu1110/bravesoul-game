extends RefCounted
## 可走區遮罩：以底圖 art id 為 key 的正規化多邊形。
##
## 抽成獨立檔而不是留在 explore_view 裡，是為了能單獨測 ——
## explore_view 相依 GameState／OnlineGate 這些 autoload，而 `-s` 測試腳本
## 是在 autoload 註冊之前編譯的，一 preload 就是 compile error。
##
## 資料在 res://data/walkmask.json，格式與「為什麼有些地圖沒啟用」寫在那個檔裡。

const PATH := "res://data/walkmask.json"

static var _cache: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var raw = JSON.parse_string(f.get_as_text())
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("walkmask.json 解不開")
		return
	for k in (raw as Dictionary).keys():
		## 底線開頭是說明文字與停用的範例，不吃
		if str(k).begins_with("_"):
			continue
		var entry = raw[k]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var out := {"walk": [], "block": []}
		for field in ["walk", "block"]:
			for poly in (entry as Dictionary).get(field, []):
				var pts := PackedVector2Array()
				for pt in poly:
					if typeof(pt) == TYPE_ARRAY and (pt as Array).size() >= 2:
						pts.append(Vector2(float(pt[0]), float(pt[1])))
				## 少於三點構不成多邊形，丟掉而不是讓它靜靜失效
				if pts.size() >= 3:
					out[field].append(pts)
				elif pts.size() > 0:
					push_error("walkmask %s 的 %s 有一個多邊形只有 %d 點" % [k, field, pts.size()])
		_cache[str(k)] = out


## 這個 art 有沒有啟用遮罩。沒有 → 呼叫端退回舊的百分比方塊。
static func has(art: String) -> bool:
	_load()
	var e: Dictionary = _cache.get(art, {})
	return not (e.get("walk", []) as Array).is_empty()


## uv 是 0..1 的正規化座標（相對底圖左上角）
static func walkable(art: String, uv: Vector2) -> bool:
	_load()
	var e: Dictionary = _cache.get(art, {})
	var walk: Array = e.get("walk", [])
	if walk.is_empty():
		return true
	var inside := false
	for poly in walk:
		if Geometry2D.is_point_in_polygon(uv, poly):
			inside = true
			break
	if not inside:
		return false
	for poly in e.get("block", []):
		if Geometry2D.is_point_in_polygon(uv, poly):
			return false
	return true


## 測試與工具用
static func arts() -> PackedStringArray:
	_load()
	var out := PackedStringArray()
	for k in _cache.keys():
		out.append(str(k))
	return out


static func reload() -> void:
	_loaded = false
	_cache.clear()
