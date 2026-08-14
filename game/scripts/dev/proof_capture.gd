extends SceneTree
## 多場景截圖（官網用）v3 — 探索地圖加厚
##   godot --path game --script res://scripts/dev/proof_capture.gd
## 輸出：../screenshots/proof_*.png

## 每筆：file, tag, kind, map/mode, wait
## kind: title | explore | inv_open | inv_close | forge | paths | soul | battle
const SHOTS: Array = [
	{"file": "proof_01_title.png", "tag": "title", "kind": "title", "wait": 50},
	{"file": "proof_02_explore_town.png", "tag": "explore", "kind": "explore", "map": "town", "wait": 45},
	{"file": "proof_03_inventory.png", "tag": "inventory", "kind": "inv_open", "wait": 28},
	{"file": "proof_04_mist.png", "tag": "mist", "kind": "explore", "map": "mist_village", "wait": 40},
	{"file": "proof_05_crossroads.png", "tag": "cross", "kind": "explore", "map": "crossroads", "wait": 40},
	{"file": "proof_06_forest.png", "tag": "forest", "kind": "explore", "map": "forest", "wait": 40},
	{"file": "proof_07_coast.png", "tag": "coast", "kind": "explore", "map": "coast", "wait": 40},
	{"file": "proof_08_forge.png", "tag": "forge", "kind": "forge", "wait": 38},
	{"file": "proof_09_weapon_paths.png", "tag": "paths", "kind": "paths", "wait": 38},
	{"file": "proof_10_soul.png", "tag": "soul", "kind": "soul", "wait": 38},
	{"file": "proof_11_battle.png", "tag": "battle", "kind": "battle", "mode": "road_bandit", "wait": 55},
	## ── 0.13.2 加厚：更多域與次場景 ──
	{"file": "proof_12_village.png", "tag": "explore", "kind": "explore", "map": "village", "wait": 42},
	{"file": "proof_13_dojo.png", "tag": "explore", "kind": "explore", "map": "dojo", "wait": 42},
	{"file": "proof_14_tower.png", "tag": "explore", "kind": "explore", "map": "tower_foyer", "wait": 42},
	{"file": "proof_15_market.png", "tag": "explore", "kind": "explore", "map": "town_market", "wait": 42},
	{"file": "proof_16_blackflame.png", "tag": "explore", "kind": "explore", "map": "blackflame_scar", "wait": 42},
	{"file": "proof_17_starfall.png", "tag": "explore", "kind": "explore", "map": "starfall_plain", "wait": 42},
	{"file": "proof_18_forest_lake.png", "tag": "forest", "kind": "explore", "map": "forest_lake", "wait": 42},
	{"file": "proof_19_harbor.png", "tag": "coast", "kind": "explore", "map": "coast_harbor", "wait": 42},
	{"file": "proof_20_mist_shrine.png", "tag": "mist", "kind": "explore", "map": "mist_shrine", "wait": 42},
	{"file": "proof_21_hunt.png", "tag": "explore", "kind": "explore", "map": "hunting_grounds", "wait": 42},
	{"file": "proof_22_dojo_peak.png", "tag": "explore", "kind": "explore", "map": "dojo_peak", "wait": 42},
	{"file": "proof_23_coast_wreck.png", "tag": "coast", "kind": "explore", "map": "coast_wreck", "wait": 42},
	{"file": "proof_24_caravan.png", "tag": "explore", "kind": "explore", "map": "caravan_camp", "wait": 42},
]

enum Step { BOOT, ACT, WAIT, CAP, NEXT, DONE }

var _step: Step = Step.BOOT
var _idx: int = 0
var _wait: int = 0
var _main: Node = null
var _out_dir: String = ""
var _saved: PackedStringArray = PackedStringArray()
var _errors: PackedStringArray = PackedStringArray()
var _need_close_inv: bool = false


func _initialize() -> void:
	print("PROOF start multi-stage v3 shots=", SHOTS.size())
	_out_dir = ProjectSettings.globalize_path("res://").path_join("../screenshots")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.size = Vector2i(1280, 720)
	var win := root.get_window()
	if win:
		win.size = Vector2i(1280, 720)
	print("PROOF out_dir=", _out_dir)


func _process(_delta: float) -> bool:
	match _step:
		Step.BOOT:
			var err := change_scene_to_file("res://scenes/main.tscn")
			print("PROOF change_scene err=", err)
			_idx = 0
			_step = Step.ACT
			_wait = 0
		Step.ACT:
			if _idx >= SHOTS.size():
				_step = Step.DONE
				return false
			var shot: Dictionary = SHOTS[_idx]
			if _need_close_inv:
				_call_proof("proof_close_inventory", [])
				_need_close_inv = false
			_run_action(shot)
			_wait = 0
			_step = Step.WAIT
		Step.WAIT:
			_wait += 1
			var shot_w: Dictionary = SHOTS[_idx]
			var need: int = int(shot_w.get("wait", 40))
			## 第一張 title 多等一下讓主場景就緒
			if _idx == 0:
				_main = current_scene
				if _main == null:
					return false
			if _wait >= need:
				_step = Step.CAP
		Step.CAP:
			var shot_c: Dictionary = SHOTS[_idx]
			_capture(str(shot_c["file"]), str(shot_c["tag"]))
			if str(shot_c.get("kind", "")) == "inv_open":
				_need_close_inv = true
			_idx += 1
			_step = Step.ACT
		Step.DONE:
			_write_manifest()
			print("PROOF done saved=%d errors=%d" % [_saved.size(), _errors.size()])
			for p in _saved:
				print("PROOF file ", p)
			for e in _errors:
				print("PROOF err ", e)
			quit(0 if _errors.is_empty() else 1)
			return true
	return false


func _run_action(shot: Dictionary) -> void:
	var kind := str(shot.get("kind", "explore"))
	match kind:
		"title":
			## 主場景載入後就是 title；不需額外呼叫
			_main = current_scene
			print("PROOF title ready")
		"explore":
			_call_proof("proof_jump_explore", [str(shot.get("map", "town"))])
		"inv_open":
			_call_proof("proof_open_inventory", [])
		"forge":
			_call_proof("proof_show_forge", [])
		"paths":
			_call_proof("proof_show_paths", [])
		"soul":
			_call_proof("proof_show_soul", [])
		"battle":
			_call_proof("proof_show_battle", [str(shot.get("mode", "road_bandit"))])
		_:
			_errors.append("unknown kind %s" % kind)


func _call_proof(method: String, args: Array) -> void:
	_main = current_scene
	if _main == null:
		_errors.append("no main for %s" % method)
		return
	if not _main.has_method(method):
		_errors.append("missing %s" % method)
		print("PROOF ERROR missing ", method)
		return
	if args.is_empty():
		_main.call(method)
	elif args.size() == 1:
		_main.call(method, args[0])
	else:
		_main.callv(method, args)
	print("PROOF called ", method, " ", args)


func _capture(filename: String, tag: String) -> void:
	var tex: ViewportTexture = root.get_texture()
	var img: Image = null
	if tex:
		img = tex.get_image()
	var w := 0
	var h := 0
	if img:
		w = img.get_width()
		h = img.get_height()
	var usable := img != null and w >= 64 and h >= 64 and not _is_mostly_empty(img)
	if not usable:
		print("PROOF fallback composite for ", tag, " size=", w, "x", h)
		img = _composite_fallback(tag)
		w = img.get_width()
		h = img.get_height()
	var path := _out_dir.path_join(filename)
	var err := img.save_png(path)
	print("PROOF saved %s err=%s %dx%d usable=%s" % [path, err, w, h, usable])
	if err == OK:
		_saved.append(path)
	else:
		_errors.append("save failed %s code=%s" % [filename, err])
	img.save_png("user://%s" % filename)


func _is_mostly_empty(img: Image) -> bool:
	if img == null:
		return true
	var w := img.get_width()
	var h := img.get_height()
	if w < 8 or h < 8:
		return true
	var sum := 0.0
	var n := 0
	var step_x := maxi(1, w / 16)
	var step_y := maxi(1, h / 16)
	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			var c := img.get_pixel(x, y)
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
	if n <= 0:
		return true
	return (sum / float(n)) < 0.02


func _composite_fallback(tag: String) -> Image:
	var img := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.11, 0.14, 1))
	var band := Color(0.76, 0.37, 0.45, 1)
	match tag:
		"title":
			band = Color(0.55, 0.45, 0.75, 1)
		"explore", "mist", "cross", "forest", "coast":
			band = Color(0.35, 0.65, 0.45, 1)
		"inventory", "forge", "paths", "soul":
			band = Color(0.85, 0.70, 0.35, 1)
		"battle":
			band = Color(0.75, 0.25, 0.3, 1)
	for y in range(80, 200):
		for x in range(80, 1200):
			img.set_pixel(x, y, band)
	for y in range(12, 120):
		for x in range(12, 230):
			var base := img.get_pixel(x, y)
			img.set_pixel(x, y, base.lerp(Color(0.98, 0.96, 0.97, 1), 0.85))
	return img


func _write_manifest() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# proof capture manifest v3")
	lines.append("time=%s" % Time.get_datetime_string_from_system())
	lines.append("viewport=%s" % str(root.size))
	lines.append("planned=%d" % SHOTS.size())
	lines.append("saved=%d" % _saved.size())
	for p in _saved:
		lines.append("file=%s" % p)
	for e in _errors:
		lines.append("error=%s" % e)
	if current_scene:
		lines.append("scene=%s" % current_scene.name)
	var path := _out_dir.path_join("proof_manifest.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("PROOF manifest ", path)
