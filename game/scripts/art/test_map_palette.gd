extends SceneTree
## godot --headless -s res://scripts/art/test_map_palette.gd

const MapPalette = preload("res://scripts/art/map_palette.gd")

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var keys := ["bg", "grade", "wash", "vignette", "horizon", "tile"]
	for r in MapPalette.REGIONS.keys():
		var p: Dictionary = MapPalette.REGIONS[r]
		for k in keys:
			if not p.has(k) or not (p[k] is Color):
				_fail("%s 缺色盤欄 %s" % [r, k])
				continue
		var g: Color = p["grade"]
		if g.r < 0.7 or g.g < 0.7 or g.b < 0.7:
			_fail("%s grade 過暗，會把底圖染成單色塊" % r)

	var cases := {
		"village": "village",
		"village_mill": "village",
		"road_inn": "road",
		"town": "town",
		"town_forge": "town",
		"town_keep": "town",
		"barracks_yard": "town",
		"wild_leo_court": "wild",
		"hunting_grounds": "wild",
		"mist_village": "mist",
		"starfall_plain": "mist",
		"dojo_inner": "dojo",
		"forest_lake": "forest",
		"coast_harbor": "coast",
		"tower_foyer": "tower",
		"blackflame_scar": "tower",
	}
	for mid in cases.keys():
		var got := MapPalette.region_of(str(mid))
		if got != str(cases[mid]):
			_fail("region_of(%s)=%s 期望 %s" % [mid, got, cases[mid]])

	if not MapPalette.is_indoor("town_forge") or MapPalette.is_indoor("town"):
		_fail("室內判定：四店才算室內，廣場不算")

	var forge: Dictionary = MapPalette.of("town_forge")
	var plaza: Dictionary = MapPalette.of("town")
	if forge.get("bg") == plaza.get("bg"):
		_fail("鐵匠鋪應比廣場更暖，不該共用同一 bg")

	## 禁止再靠前綴偷母域底圖（拼貼主因）
	var ev_src := FileAccess.get_file_as_string("res://scripts/world/explore_view.gd")
	if ev_src.contains("begins_with(prefix)") and ev_src.contains("map_bg(prefix"):
		_fail("explore_view 又用前綴偷母域底圖了")

	if _ok:
		print("MAP_PALETTE_OK")
		quit(0)
		return
	print("MAP_PALETTE_FAIL")
	quit(1)
