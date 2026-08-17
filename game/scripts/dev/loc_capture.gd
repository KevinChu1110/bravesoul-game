extends SceneTree
## 同一張地圖，六個語言各截一張 —— 驗 ContentLoc 那層在實機上真的有換掉字。
## 必須開視窗跑（headless 的 viewport 是空的）：
##   godot --path game -s res://scripts/dev/loc_capture.gd
const CODES := ["zh_TW", "en", "ja", "ko", "es"]
const MAP := "town"
const CL := preload("res://scripts/systems/content_loc.gd")

enum Step { BOOT, SET, WAIT, CAP, DONE }
var _step: Step = Step.BOOT
var _idx := 0
var _wait := 0
var _out := ""

func _initialize() -> void:
	_out = ProjectSettings.globalize_path("res://").path_join("../screenshots/loc")
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	var w := root.get_window()
	if w:
		w.size = Vector2i(1280, 720)

func _process(_d: float) -> bool:
	match _step:
		Step.BOOT:
			change_scene_to_file("res://scenes/main.tscn")
			_step = Step.SET
			_wait = 0
		Step.SET:
			_wait += 1
			if _wait < 40:
				return false
			if _idx >= CODES.size():
				_step = Step.DONE
				return false
			var loc: Node = root.get_node_or_null("Loc")
			loc.call("set_locale", CODES[_idx])
			CL.reload()
			var m: Node = current_scene
			if m and m.has_method("proof_jump_explore"):
				m.call("proof_jump_explore", MAP)
			_wait = 0
			_step = Step.WAIT
		Step.WAIT:
			_wait += 1
			if _wait >= 45:
				_step = Step.CAP
		Step.CAP:
			var img: Image = root.get_texture().get_image()
			var p := _out.path_join("map_%s.png" % CODES[_idx])
			print("LOC saved %s err=%s %dx%d" % [p, img.save_png(p), img.get_width(), img.get_height()])
			_idx += 1
			_wait = 40
			_step = Step.SET
		Step.DONE:
			print("LOC done")
			quit(0)
			return true
	return false
