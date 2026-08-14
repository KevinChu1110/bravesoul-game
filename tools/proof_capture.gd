extends SceneTree
## Headless 證明：載入主場景數幀後截圖。
## 執行：godot --path game --headless --script res://../tools/proof_capture.gd
## 注意：--script 路徑相對 project；若失敗改用 tools 內嵌版。

const FRAMES := 90


func _initialize() -> void:
	print("proof_capture: start")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("proof_capture: cannot load main.tscn err=%s" % err)
		quit(1)
		return
	call_deferred("_after_frames")


func _after_frames() -> void:
	await process_frame
	for i in FRAMES:
		await process_frame
	_shot("proof_title")
	## 嘗試點進新遊戲太依賴 UI；只證明標題可渲染
	print("proof_capture: wrote title frame")
	quit(0)


func _shot(name: String) -> void:
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		push_error("proof_capture: no image")
		return
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	print("proof_capture: save %s -> %s" % [path, err])
	## 也試專案外
	var abs_path := OS.get_user_data_dir().path_join("%s.png" % name)
	print("proof_capture: user_data %s" % abs_path)
