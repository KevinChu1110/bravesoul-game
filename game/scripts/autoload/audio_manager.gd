extends Node
## 音效池 + BGM 循環（淡入淡出切曲）

const SFX_DIR := "res://assets/audio/sfx"
const BGM_DIR := "res://assets/audio/bgm"
## 循環起點（秒）。真配樂通常有一段不該重複的前奏，循環要從前奏之後開始。
## 由 tools/import_bgm.py 產生，見 docs/MEDIA.md
const BGM_LOOPS_PATH := "res://assets/audio/bgm/loops.json"
const POOL_SIZE := 8
const BGM_FADE := 0.7

var _streams: Dictionary = {}  ## sfx id -> AudioStream
var _bgm_streams: Dictionary = {}  ## bgm id -> AudioStream
var _bgm_loops: Dictionary = {}  ## bgm id -> 循環起點（秒）
var _bgm_sources: Dictionary = {}  ## bgm id -> "ogg" | "wav"
var _pool: Array = []  ## AudioStreamPlayer
var _pool_i: int = 0
var _sfx_db: float = -4.0
var _bgm_db: float = -6.0  ## 新 BGM 偏暖 pad，略降避免刺耳
var _muted: bool = false
var _bgm_muted: bool = false
var _step_cd: float = 0.0

var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_active: AudioStreamPlayer
var _current_bgm: String = ""
var _fade_tween: Tween


func _ready() -> void:
	_build_pool()
	_build_bgm_players()
	_preload_sfx()
	_preload_bgm()


func _process(delta: float) -> void:
	if _step_cd > 0.0:
		_step_cd = maxf(0.0, _step_cd - delta)


func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPool_%d" % i
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func _build_bgm_players() -> void:
	_bgm_a = AudioStreamPlayer.new()
	_bgm_a.name = "BgmA"
	_bgm_a.bus = "Master"
	add_child(_bgm_a)
	_bgm_b = AudioStreamPlayer.new()
	_bgm_b.name = "BgmB"
	_bgm_b.bus = "Master"
	add_child(_bgm_b)
	_bgm_active = _bgm_a


func _preload_sfx() -> void:
	var names := [
		"parry", "hit", "slash", "fire", "wind", "rock", "clock",
		"reveal", "break", "stop", "clash", "victory", "defeat",
		"ui", "interact", "step", "warn", "dodge", "battle_start",
		"craft",  ## 可選；缺檔時 play_craft_success 走 ui+reveal
	]
	for n in names:
		var path := "%s/%s.wav" % [SFX_DIR, n]
		if ResourceLoader.exists(path):
			_streams[n] = load(path)


func bgm_ids() -> Array:
	return [
		"title", "village", "town", "mist", "dojo", "forest", "coast",
		"wild", "road", "battle", "boss", "tower", "ending",
	]


## 哪些曲子已經換成真配樂（面板／測試用）
func bgm_source(id: String) -> String:
	return str(_bgm_sources.get(id, ""))


func _load_bgm_loops() -> void:
	_bgm_loops = {}
	if not FileAccess.file_exists(BGM_LOOPS_PATH):
		return
	var f := FileAccess.open(BGM_LOOPS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("BGM loops.json 格式不對，忽略")
		return
	for k in (data as Dictionary):
		_bgm_loops[str(k)] = float((data as Dictionary)[k])


func _preload_bgm() -> void:
	_load_bgm_loops()
	for n in bgm_ids():
		var stream := _load_bgm_stream(str(n))
		if stream == null:
			push_warning("BGM missing: %s/%s.(ogg|wav)" % [BGM_DIR, n])
			continue
		_bgm_streams[n] = stream


## 真配樂（.ogg／.mp3）優先；程式合成的 .wav 是後備，所以換曲只要丟檔案不用改程式。
## 兩種壓縮格式都收，是因為不是每台機器的 ffmpeg 都編得出 Vorbis。
func _load_bgm_stream(id: String) -> AudioStream:
	for ext in ["ogg", "mp3"]:
		var path := "%s/%s.%s" % [BGM_DIR, id, ext]
		if not ResourceLoader.exists(path):
			continue
		var s: Variant = load(path)
		if s == null:
			continue
		_bgm_sources[id] = ext
		var off := maxf(0.0, float(_bgm_loops.get(id, 0.0)))
		## duplicate：避免改到匯入快取本體，循環設定才穩定
		if s is AudioStreamOggVorbis:
			var v := (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
			v.loop = true
			v.loop_offset = off
			return v
		if s is AudioStreamMP3:
			var m := (s as AudioStreamMP3).duplicate() as AudioStreamMP3
			m.loop = true
			m.loop_offset = off
			return m
		if s is AudioStream:
			return s

	var wav_path := "%s/%s.wav" % [BGM_DIR, id]
	if not ResourceLoader.exists(wav_path):
		return null
	var stream: Variant = load(wav_path)
	if stream is AudioStreamWAV:
		var w := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		var bytes_per := 2  ## 16-bit PCM
		if w.format == AudioStreamWAV.FORMAT_8_BITS:
			bytes_per = 1
		elif w.format == AudioStreamWAV.FORMAT_IMA_ADPCM:
			bytes_per = 1
		var ch := 2 if w.stereo else 1
		var frames := 0
		if bytes_per * ch > 0 and w.data.size() > 0:
			frames = int(w.data.size() / (bytes_per * ch))
		w.loop_end = maxi(1, frames)
		_bgm_sources[id] = "wav"
		return w
	if stream is AudioStream:
		_bgm_sources[id] = "wav"
		return stream
	return null


func set_muted(v: bool) -> void:
	_muted = v
	if v:
		stop_bgm(0.2)


func set_bgm_muted(v: bool) -> void:
	_bgm_muted = v
	if v:
		stop_bgm(0.3)
	elif _current_bgm != "":
		var id := _current_bgm
		_current_bgm = ""
		play_bgm(id)


func play(id: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if _muted:
		return
	var stream: AudioStream = _streams.get(id)
	if stream == null or _pool.is_empty():
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	p.volume_db = _sfx_db + volume_db
	p.play()


func play_step() -> void:
	if _step_cd > 0.0:
		return
	_step_cd = 0.28
	play("step", randf_range(0.92, 1.08), -6.0)


func play_ui() -> void:
	play("ui", 1.0, -2.0)


func play_interact() -> void:
	play("interact")


## 鍛造成功記憶點：有 craft.wav 用專檔，否則 ui + reveal 疊層
func play_craft_success() -> void:
	if _streams.has("craft"):
		play("craft")
	else:
		play("ui", 1.05, -1.0)
		play("reveal", 1.12, -2.0)


## 觀星成功：reveal 為主、輕 ui 點綴
func play_ritual_success() -> void:
	play("reveal", 0.95)
	play("ui", 1.18, -5.0)


## ─── BGM ───

func play_bgm(id: String, fade: float = BGM_FADE) -> void:
	if id == "":
		return
	if _bgm_muted or _muted:
		_current_bgm = id
		return
	## 同曲且已在播 → 不重切（避免選單重建時靜音）
	if id == _current_bgm and _bgm_active and _bgm_active.playing:
		return
	var stream: AudioStream = _bgm_streams.get(id)
	if stream == null:
		## 熱載一次，避免第一次進遊戲表尚未就緒
		var path := "%s/%s.wav" % [BGM_DIR, id]
		if ResourceLoader.exists(path):
			var loaded = load(path)
			if loaded is AudioStreamWAV:
				var w := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				var bp := 2
				if w.format == AudioStreamWAV.FORMAT_8_BITS:
					bp = 1
				var ch := 2 if w.stereo else 1
				if bp * ch > 0 and w.data.size() > 0:
					w.loop_end = maxi(1, int(w.data.size() / (bp * ch)))
				_bgm_streams[id] = w
				stream = w
			elif loaded:
				_bgm_streams[id] = loaded
				stream = loaded
	if stream == null:
		push_warning("BGM not loaded: %s" % id)
		return
	var incoming: AudioStreamPlayer = _bgm_b if _bgm_active == _bgm_a else _bgm_a
	var outgoing: AudioStreamPlayer = _bgm_active

	if _fade_tween and is_instance_valid(_fade_tween):
		_fade_tween.kill()

	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	## 下一幀再確認；若仍未播則硬啟
	if not incoming.playing:
		incoming.volume_db = _bgm_db
		incoming.play()
	call_deferred("_ensure_bgm_playing", incoming)

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", _bgm_db, fade)
	if outgoing and outgoing != incoming and outgoing.playing:
		_fade_tween.tween_property(outgoing, "volume_db", -40.0, fade)
		_fade_tween.chain().tween_callback(func():
			if is_instance_valid(outgoing):
				outgoing.stop()
		)
	_bgm_active = incoming
	_current_bgm = id


func _ensure_bgm_playing(p: AudioStreamPlayer) -> void:
	if p == null or not is_instance_valid(p):
		return
	if not p.playing and p.stream != null and not _muted and not _bgm_muted:
		p.volume_db = _bgm_db
		p.play()


func stop_bgm(fade: float = BGM_FADE) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	var out := _bgm_active
	if out == null or not out.playing:
		_current_bgm = ""
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(out, "volume_db", -40.0, fade)
	_fade_tween.tween_callback(func():
		if is_instance_valid(out):
			out.stop()
	)
	_current_bgm = ""


func play_bgm_for_map(map_id: String) -> void:
	var id := map_to_bgm(map_id)
	play_bgm(id)


func play_bgm_for_battle(mode: String) -> void:
	if is_boss_battle(mode):
		play_bgm("boss")
	else:
		play_bgm("battle")


## 主線聖獸／魔王／秘境小 Boss 等「有記憶點」的戰
func is_boss_battle(mode: String) -> bool:
	return mode in [
		"leo", "fog", "abo", "demon", "falcon", "boar", "wrath", "tide",
		"statue", "chrono", "scar_lord", "mirror_wraith", "wreck_captain",
	]


static func map_to_bgm(map_id: String) -> String:
	if map_id.begins_with("village"):
		return "village"
	if map_id.begins_with("town") or map_id == "barracks_yard":
		return "town"
	if map_id.begins_with("wild") or map_id == "hunting_grounds":
		return "wild"
	if map_id.begins_with("road") or map_id.begins_with("cross") or map_id in ["caravan_camp", "starfall_plain"]:
		return "road"
	if map_id.begins_with("mist"):
		return "mist"
	if map_id.begins_with("dojo"):
		return "dojo"
	if map_id.begins_with("forest"):
		return "forest"
	if map_id.begins_with("coast"):
		return "coast"
	if map_id.begins_with("tower") or map_id == "blackflame_scar":
		return "tower"
	return "town"


## 戰鬥事件 → 音效
func on_battle_event(kind: String, data: Dictionary = {}) -> void:
	match kind:
		"perfect_parry":
			play("parry")
		"hit":
			if data.get("king_slash", false):
				play("clash", 0.9)
			else:
				play("hit", randf_range(0.95, 1.05), -2.0)
		"skill_hit":
			if data.get("parry_followup", false):
				play("parry", 1.05)
			else:
				play("slash")
		"skill_cast":
			play("slash", 1.1, -4.0)
		"hazard_warn":
			play("warn")
			var hk := str(data.get("kind", ""))
			if hk == "time_clock":
				play("clock", 1.0, -4.0)
		"hazard_window":
			play("clock", 1.2)
		"hazard_resolve":
			if bool(data.get("success", false)):
				play("dodge")
			else:
				var hk2 := str(data.get("kind", ""))
				match hk2:
					"fire_ring":
						play("fire")
					"wind_cut":
						play("wind")
					"rockfall":
						play("rock")
					"bomb":
						play("clash", 0.85)
					"time_clock":
						play("clock", 0.7)
					_:
						play("hit")
		"fog_reveal":
			play("reveal")
		"fog_phantom_hit":
			play("hit", 0.85)
		"abo_guard_break":
			play("break")
		"falcon_stop":
			play("stop")
		"boar_armor_break":
			if data.get("regrow", false):
				play("rock", 0.8)
			else:
				play("clash")
		"king_slash_start":
			play("warn", 0.9, -2.0)
		"temptation":
			play("reveal", 0.7, -4.0)
		_:
			pass


func battle_start(mode: String = "wolf") -> void:
	## 雜魚：battle_start；Boss：再疊 warn，與一般遭遇聽感分開
	play("battle_start")
	if is_boss_battle(mode):
		play("warn", 0.88, -1.0)
	play_bgm_for_battle(mode)


func battle_end(won: bool) -> void:
	if won:
		play("victory")
	else:
		play("defeat")
	## 暫時壓低 BGM，回探索時會由 map 切回
	if _bgm_active and _bgm_active.playing:
		_bgm_active.volume_db = _bgm_db - 8.0
