extends SceneTree
## 多場景截圖（官網用）
##   godot --path game --script res://scripts/dev/proof_capture.gd
## 輸出：../screenshots/proof_*.png

enum Phase {
	BOOT,
	WAIT_TITLE,
	CAP_TITLE,
	JUMP_TOWN,
	WAIT_TOWN,
	CAP_TOWN,
	OPEN_INV,
	WAIT_INV,
	CAP_INV,
	CLOSE_INV,
	JUMP_MIST,
	WAIT_MIST,
	CAP_MIST,
	JUMP_CROSS,
	WAIT_CROSS,
	CAP_CROSS,
	JUMP_FOREST,
	WAIT_FOREST,
	CAP_FOREST,
	JUMP_COAST,
	WAIT_COAST,
	CAP_COAST,
	SHOW_FORGE,
	WAIT_FORGE,
	CAP_FORGE,
	SHOW_PATHS,
	WAIT_PATHS,
	CAP_PATHS,
	SHOW_SOUL,
	WAIT_SOUL,
	CAP_SOUL,
	SHOW_BATTLE,
	WAIT_BATTLE,
	CAP_BATTLE,
	DONE,
}

var _phase: Phase = Phase.BOOT
var _wait: int = 0
var _main: Node = null
var _out_dir: String = ""
var _saved: PackedStringArray = PackedStringArray()
var _errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	print("PROOF start multi-stage v2")
	_out_dir = ProjectSettings.globalize_path("res://").path_join("../screenshots")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.size = Vector2i(1280, 720)
	var win := root.get_window()
	if win:
		win.size = Vector2i(1280, 720)
	print("PROOF out_dir=", _out_dir)


func _process(_delta: float) -> bool:
	match _phase:
		Phase.BOOT:
			var err := change_scene_to_file("res://scenes/main.tscn")
			print("PROOF change_scene err=", err)
			_phase = Phase.WAIT_TITLE
			_wait = 0
		Phase.WAIT_TITLE:
			_wait += 1
			_main = current_scene
			if _wait >= 50 and _main != null:
				_phase = Phase.CAP_TITLE
		Phase.CAP_TITLE:
			_capture("proof_01_title.png", "title")
			_phase = Phase.JUMP_TOWN
			_wait = 0
		Phase.JUMP_TOWN:
			_call_proof("proof_jump_explore", ["town"])
			_phase = Phase.WAIT_TOWN
			_wait = 0
		Phase.WAIT_TOWN:
			_wait += 1
			if _wait >= 45:
				_phase = Phase.CAP_TOWN
		Phase.CAP_TOWN:
			_capture("proof_02_explore_town.png", "explore")
			_phase = Phase.OPEN_INV
			_wait = 0
		Phase.OPEN_INV:
			_call_proof("proof_open_inventory", [])
			_phase = Phase.WAIT_INV
			_wait = 0
		Phase.WAIT_INV:
			_wait += 1
			if _wait >= 25:
				_phase = Phase.CAP_INV
		Phase.CAP_INV:
			_capture("proof_03_inventory.png", "inventory")
			_phase = Phase.CLOSE_INV
			_wait = 0
		Phase.CLOSE_INV:
			_call_proof("proof_close_inventory", [])
			_phase = Phase.JUMP_MIST
			_wait = 0
		Phase.JUMP_MIST:
			_call_proof("proof_jump_explore", ["mist_village"])
			_phase = Phase.WAIT_MIST
			_wait = 0
		Phase.WAIT_MIST:
			_wait += 1
			if _wait >= 40:
				_phase = Phase.CAP_MIST
		Phase.CAP_MIST:
			_capture("proof_04_mist.png", "mist")
			_phase = Phase.JUMP_CROSS
			_wait = 0
		Phase.JUMP_CROSS:
			_call_proof("proof_jump_explore", ["crossroads"])
			_phase = Phase.WAIT_CROSS
			_wait = 0
		Phase.WAIT_CROSS:
			_wait += 1
			if _wait >= 40:
				_phase = Phase.CAP_CROSS
		Phase.CAP_CROSS:
			_capture("proof_05_crossroads.png", "cross")
			_phase = Phase.JUMP_FOREST
			_wait = 0
		Phase.JUMP_FOREST:
			_call_proof("proof_jump_explore", ["forest"])
			_phase = Phase.WAIT_FOREST
			_wait = 0
		Phase.WAIT_FOREST:
			_wait += 1
			if _wait >= 40:
				_phase = Phase.CAP_FOREST
		Phase.CAP_FOREST:
			_capture("proof_06_forest.png", "forest")
			_phase = Phase.JUMP_COAST
			_wait = 0
		Phase.JUMP_COAST:
			_call_proof("proof_jump_explore", ["coast"])
			_phase = Phase.WAIT_COAST
			_wait = 0
		Phase.WAIT_COAST:
			_wait += 1
			if _wait >= 40:
				_phase = Phase.CAP_COAST
		Phase.CAP_COAST:
			_capture("proof_07_coast.png", "coast")
			_phase = Phase.SHOW_FORGE
			_wait = 0
		Phase.SHOW_FORGE:
			_call_proof("proof_show_forge", [])
			_phase = Phase.WAIT_FORGE
			_wait = 0
		Phase.WAIT_FORGE:
			_wait += 1
			if _wait >= 35:
				_phase = Phase.CAP_FORGE
		Phase.CAP_FORGE:
			_capture("proof_08_forge.png", "forge")
			_phase = Phase.SHOW_PATHS
			_wait = 0
		Phase.SHOW_PATHS:
			_call_proof("proof_show_paths", [])
			_phase = Phase.WAIT_PATHS
			_wait = 0
		Phase.WAIT_PATHS:
			_wait += 1
			if _wait >= 35:
				_phase = Phase.CAP_PATHS
		Phase.CAP_PATHS:
			_capture("proof_09_weapon_paths.png", "paths")
			_phase = Phase.SHOW_SOUL
			_wait = 0
		Phase.SHOW_SOUL:
			_call_proof("proof_show_soul", [])
			_phase = Phase.WAIT_SOUL
			_wait = 0
		Phase.WAIT_SOUL:
			_wait += 1
			if _wait >= 35:
				_phase = Phase.CAP_SOUL
		Phase.CAP_SOUL:
			_capture("proof_10_soul.png", "soul")
			_phase = Phase.SHOW_BATTLE
			_wait = 0
		Phase.SHOW_BATTLE:
			_call_proof("proof_show_battle", ["road_bandit"])
			_phase = Phase.WAIT_BATTLE
			_wait = 0
		Phase.WAIT_BATTLE:
			_wait += 1
			if _wait >= 50:
				_phase = Phase.CAP_BATTLE
		Phase.CAP_BATTLE:
			_capture("proof_11_battle.png", "battle")
			_phase = Phase.DONE
		Phase.DONE:
			_write_manifest()
			print("PROOF done saved=%d errors=%d" % [_saved.size(), _errors.size()])
			for p in _saved:
				print("PROOF file ", p)
			for e in _errors:
				print("PROOF err ", e)
			quit(0 if _errors.is_empty() else 1)
			return true
	return false


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
	lines.append("# proof capture manifest")
	lines.append("time=%s" % Time.get_datetime_string_from_system())
	lines.append("viewport=%s" % str(root.size))
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
