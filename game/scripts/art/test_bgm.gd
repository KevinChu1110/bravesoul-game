extends SceneTree
func _init() -> void:
	var ok := true
	for id in ["title","village","town","mist","dojo","forest","coast","wild","road","battle","boss","tower","ending"]:
		var p := "res://assets/audio/bgm/%s.wav" % id
		if not ResourceLoader.exists(p):
			push_error("missing "+id); ok=false
		else:
			var s = load(p)
			print("OK ", id, " ", s.get_length() if s else 0)
	# play via AudioManager (autoload available with project)
	# when -s, autoloads may load after - test stream only
	if ok:
		print("BGM_OK"); quit(0)
	else:
		print("BGM_FAIL"); quit(1)
