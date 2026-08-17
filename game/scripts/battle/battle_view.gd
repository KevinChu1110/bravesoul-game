extends Control
## 戰鬥畫面：左右血條、格擋倒數、衝刺／受擊演出

const UiStyle = preload("res://scripts/ui/ui_style.gd")

signal battle_finished(won: bool)

@onready var log_label: RichTextLabel = %Log
@onready var player_hp: ProgressBar = %PlayerHP
@onready var player_rage: ProgressBar = %PlayerRage
@onready var player_hp_label: Label = %PlayerHPLabel
@onready var enemy_hp: ProgressBar = %EnemyHP
@onready var enemy_hp_label: Label = %EnemyHPLabel
@onready var enemy_name: Label = %EnemyName
@onready var player_name_l: Label = %PlayerName
@onready var banner: Label = %Banner
@onready var parry_hint: Label = %ParryHint
@onready var countdown: Label = %Countdown
@onready var countdown_sub: Label = %CountdownSub
@onready var telegraph: ColorRect = %TelegraphFlash
@onready var size_compare: Control = %SizeCompare
@onready var btn_flee: Button = %BtnFlee
@onready var player_body: TextureRect = $Arena/PlayerSlot/PlayerBody
@onready var enemy_body: TextureRect = $Arena/EnemySlot/EnemyBody
@onready var arena: HBoxContainer = $Arena
@onready var battle_bg: TextureRect = %BG
@onready var hazard_fx: TextureRect = %HazardFX

var sim: BattleSim
var _mode: String = "wolf"
var _ended: bool = false
var _player_home: Vector2
var _enemy_home: Vector2
var _shake: float = 0.0
var _last_cd_bucket: int = -1
var _tempt_layer: Control
var _tempt_stage: int = 0
var _refuse_btn: Button
var _enemy_base_mod: Color = Color.WHITE
var _player_base_mod: Color = Color.WHITE
var _boss_pose: String = "idle"  ## idle | telegraph | attack | recover
var _boss_art_key: String = ""
var _pose_tween: Tween
var _player_pose: String = "idle"
var _player_pose_tween: Tween
var _battle_weapon: TextureRect = null
var _battle_armor: TextureRect = null
var _skill_banner: Label
var _rage_ready: Label
var _coach: Label
var _coach_timer: float = 0.0
var _hud_styled: bool = false
var _log_panel: PanelContainer


func _is_world_mode(mode: String) -> bool:
	var WC = load("res://scripts/world/world_content.gd")
	return WC != null and WC.is_world_battle(mode)


func _is_world_miniboss(mode: String) -> bool:
	var WC = load("res://scripts/world/world_content.gd")
	return WC != null and WC.is_miniboss(mode)


func setup(mode: String) -> void:
	_mode = mode
	_ended = false
	_claim_hp_authority()
	_telemetry_watch(mode)
	_apply_hud_chrome()
	banner.visible = false
	countdown.visible = false
	countdown_sub.visible = false
	if hazard_fx:
		hazard_fx.visible = false
	if _skill_banner:
		_skill_banner.visible = false
	_hide_temptation()
	_player_home = player_body.position
	_enemy_home = enemy_body.position
	_apply_battle_art(mode)

	var max_h: int = GameState.effective_max_hp()
	## 入魂血量加成時，按比例抬當前 HP 上限感
	if GameState.hp > max_h:
		GameState.hp = max_h
	var stats := {
		"name": GameState.player_name,
		"max_hp": max_h,
		"hp": mini(GameState.hp, max_h),
		"atk": GameState.effective_atk(),
		"def": GameState.effective_def(),
		"speed": GameState.effective_speed(),
		"can_skill": GameState.skill_slash_lv >= 1 or mode == "wolf",
		"slash_lv": maxi(1, GameState.skill_slash_lv),
		"crit": GameState.effective_crit(),
		"crit_dmg": GameState.effective_crit_dmg(),
		"dmg_variance": GameState.effective_variance(),
	}
	## 招式系統：倍率／優先技名
	if Engine.get_main_loop() is SceneTree:
		var sk: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SkillSystem")
		if sk and sk.has_method("battle_player_stats_patch"):
			var patch: Dictionary = sk.call("battle_player_stats_patch")
			for k in patch.keys():
				stats[k] = patch[k]
			if mode == "wolf":
				stats["can_skill"] = true
	if mode == "leo":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 3
		sim = BattleSim.make_leo_fight(stats)
	elif mode == "fog":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 2
		sim = BattleSim.make_fog_fight(stats)
	elif mode == "demon":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 4
		stats["atk"] = int(stats["atk"]) + 4
		sim = BattleSim.make_demon_fight(stats)
		_ensure_temptation_ui()
	elif mode == "abo":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 2
		sim = BattleSim.make_abo_fight(stats)
	elif mode == "falcon":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 2
		stats["speed"] = int(stats["speed"]) + 2
		sim = BattleSim.make_falcon_fight(stats)
	elif mode == "boar":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 3
		sim = BattleSim.make_boar_fight(stats)
	elif mode == "wrath":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 3
		stats["atk"] = int(stats["atk"]) + 2
		sim = BattleSim.make_wrath_fight(stats)
	elif mode == "tide":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 2
		sim = BattleSim.make_tide_fight(stats)
	elif mode == "statue":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 3
		sim = BattleSim.make_statue_fight(stats)
	elif mode == "chrono":
		GameState.hp = GameState.max_hp
		stats["hp"] = GameState.max_hp
		stats["def"] = int(stats["def"]) + 2
		sim = BattleSim.make_chrono_fight(stats)
	elif _is_world_mode(mode):
		if _is_world_miniboss(mode):
			GameState.hp = GameState.max_hp
			stats["hp"] = GameState.max_hp
			stats["def"] = int(stats["def"]) + 2
		sim = BattleSim.make_world_fight(stats, mode)
	else:
		sim = BattleSim.make_tutorial_wolf_fight(stats)
	## 體型對照已撤：玩家回饋「看不懂、畫面花、不需要」
	_hide_size_compare()

	## 黑焰迴響：敵強化 + 機制窗略短
	var ng_m: float = GameState.ng_enemy_mult()
	if ng_m > 1.001:
		BattleSim.apply_ng_plus(sim, ng_m)
	if GameState.stain_flame:
		_player_base_mod = Color(0.75, 0.72, 0.78)
		player_body.modulate = _player_base_mod

	sim.event.connect(_on_event)
	sim.battle_ended.connect(_on_end)
	_refresh_hud()
	_ensure_coach()
	AudioManager.battle_start(_mode)
	_append_log("[color=#b8a88a]%s[/color]" % Loc.t("battle.start"))
	_flash_coach(_mode_coach_intro(mode), 3.2)
	if GameState.ng_plus > 0:
		_append_log("[color=#c8f]黑焰迴響 ×%d · 敵人強了 ×%.2f · 出手空檔更窄[/color]" % [
			GameState.ng_plus, ng_m
		])
		_flash_coach("二周目：敵人更硬，空檔更窄。一樣等綠了再擋。", 2.5)
	if GameState.stain_flame:
		_append_log("[color=#a88]沾焰：刃上有一層不肯散的灰。攻擊略升。[/color]")
	if mode == "leo":
		_append_log("雷歐：渺小的兔子……也想挑戰騎士之王？")
		_append_log("[color=#fa6]王者斬要擋，擋住就能反擊 · 火圈亮起後按 J 跳開[/color]")
		parry_hint.text = "【J】倒數變綠＝格擋　·　火圈預告後＝躍出"
	elif mode == "fog":
		_append_log("白霧：嘻嘻～真的假的，你分得清嗎？")
		_append_log("[color=#8cf]分身很多 · 只有本體發白時打得中 · 砍幻影會被反咬又變慢[/color]")
		parry_hint.text = "【Tab/1-3】鎖目標　·　本體發白才輸出　·　別打幻影"
	elif mode == "demon":
		_append_log("魔王：那就來——用你的微末，撞我的千年。")
		_append_log("[color=#c8f]黑焰必殺一定要擋 · 時鐘轉到時按 J · 血量掉到一半他會拒絕[/color]")
		parry_hint.text = "【J】必殺格擋　·　時鐘窗　·　階段點「我拒絕」"
	elif mode == "abo":
		_append_log("阿波：來。打我的架勢——用拳，不是用嘴。")
		_append_log("[color=#9c9]打散他的架勢 · 散開後傷害吃滿 · 但他會出重拳，記得擋[/color]")
		parry_hint.text = "打散架勢　·　趁散開輸出　·　重拳舉起時【J】"
	elif mode == "falcon":
		_append_log("疾影：你的眼睛……跟得上我嗎？")
		_append_log("[color=#8f8]牠停下那一拍才吃滿傷害 · 風聲響起按 J[/color]")
		parry_hint.text = "等【停拍】輸出　·　風切預告後【J】"
	elif mode == "boar":
		_append_log("石拳：哦？還站著？那就接下這一拳——")
		_append_log("[color=#c96]他衝來時按 J 硬碰，岩甲會裂 · 落石時按 J 躲開[/color]")
		parry_hint.text = "衝鋒【J】對撞剝甲　·　落岩【J】進安全區"
	elif mode == "wrath":
		_append_log("無臉：…………（焰在顫）")
		_append_log("[color=#f84]裂縫·怒火：密火圈 · 漏閃疊灼燒，滿 3 層大爆[/color]")
		parry_hint.text = "密火圈按 J · 勿讓灼燒疊滿"
	elif mode == "tide":
		_append_log("潮聲：刺胞在裂縫裡孵化……")
		_append_log("[color=#6cf]裂縫·潮噬：時間內解決刺胞 · 本體會輪流擋普攻或技能，看情況換手[/color]")
		parry_hint.text = "先解決刺胞 · 看牠擋什麼就換另一種"
	elif mode == "statue":
		_append_log("石響：三尊輪流亮起。")
		_append_log("[color=#ca8]裂縫·石像：只打發光石像 · 落岩 · 全滅後打本體[/color]")
		parry_hint.text = "鎖發光石像 · 落岩按 J"
	elif mode == "chrono":
		_append_log("時牢：倒數的焰在腳下盤成環。")
		_append_log("[color=#a8f]裂縫·時牢：炸彈窗按 J 拆除 · 落岩進安全[/color]")
		parry_hint.text = "炸彈拆除 · 落岩安全（J）"
	else:
		parry_hint.text = "%s · %s" % [Loc.t("tut.battle"), Loc.t("battle.rage_full")]


func _apply_hud_chrome() -> void:
	if _hud_styled:
		return
	_hud_styled = true
	## 側欄標題走語系
	var pst := get_node_or_null("SideBars/PlayerSide/PlayerSideTitle") as Label
	if pst:
		pst.text = Loc.t("battle.ally")
	var est := get_node_or_null("SideBars/EnemySide/EnemySideTitle") as Label
	if est:
		est.text = Loc.t("battle.enemy")
	var prl := get_node_or_null("SideBars/PlayerSide/PlayerRageLabel") as Label
	if prl:
		prl.text = Loc.t("battle.rage")
	var ptag := get_node_or_null("Arena/PlayerSlot/PlayerTag") as Label
	if ptag:
		ptag.text = Loc.t("battle.ally")
	var etag := get_node_or_null("Arena/EnemySlot/EnemyTag") as Label
	if etag:
		etag.text = Loc.t("battle.enemy")
	## 楓式：紅血／黃怒／敵血
	_style_bar(player_hp, Color(0.86, 0.22, 0.22), Color(0.35, 0.12, 0.12, 0.95))
	_style_bar(player_rage, Color(0.95, 0.55, 0.12), Color(0.30, 0.20, 0.08, 0.95))
	_style_bar(enemy_hp, Color(0.88, 0.28, 0.28), Color(0.30, 0.10, 0.10, 0.95))
	player_hp.modulate = Color.WHITE
	player_rage.modulate = Color.WHITE
	enemy_hp.modulate = Color.WHITE
	player_hp.custom_minimum_size.y = 14
	enemy_hp.custom_minimum_size.y = 14
	player_rage.custom_minimum_size.y = 8
	## 戰鬥背景是暗的，所以這裡的字一律走淺色。
	## 底下那幾個 if 曾經用 UiStyle.CREAM 覆寫回來——那個常數名字叫奶油色、
	## 值卻是墨色 #26242a（改成白底風格時語意翻轉了），於是近黑字畫在近黑底上。
	## 更麻煩的是後續狀態變化只改 modulate，而 modulate 是乘法，
	## 近黑乘任何係數只會更黑，那行字沒有任何狀態救得回來。底色修好，狀態變化才有意義。
	for lab in [player_name_l, enemy_name, player_hp_label, enemy_hp_label, parry_hint, banner]:
		if lab:
			lab.add_theme_font_size_override("font_size", 14 if lab != banner else 16)
			lab.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
			lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
			lab.add_theme_constant_override("shadow_offset_x", 1)
			lab.add_theme_constant_override("shadow_offset_y", 1)

	if player_name_l:
		player_name_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		player_name_l.add_theme_constant_override("shadow_offset_x", 1)
		player_name_l.add_theme_constant_override("shadow_offset_y", 1)
	if enemy_name:
		enemy_name.add_theme_color_override("font_color", Color(1.0, 0.75, 0.7))
		enemy_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		enemy_name.add_theme_constant_override("shadow_offset_x", 1)
		enemy_name.add_theme_constant_override("shadow_offset_y", 1)
	if player_hp_label:
		player_hp_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.86))
	if enemy_hp_label:
		enemy_hp_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.68))
	if parry_hint:
		parry_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		parry_hint.add_theme_constant_override("shadow_offset_x", 1)
		parry_hint.add_theme_constant_override("shadow_offset_y", 1)
		## 這行寫著要按哪一顆鍵，是全場最該讀得到的字
		parry_hint.add_theme_font_size_override("font_size", 18)
	if countdown:
		countdown.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		countdown.add_theme_constant_override("shadow_offset_x", 2)
		countdown.add_theme_constant_override("shadow_offset_y", 2)
	if countdown_sub:
		countdown_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		countdown_sub.add_theme_constant_override("shadow_offset_x", 1)
		countdown_sub.add_theme_constant_override("shadow_offset_y", 1)

	## 戰鬥 log：半透明紙底（包一層 Panel）
	if log_label and log_label.get_parent() and not (log_label.get_parent() is PanelContainer):
		var parent_ctrl: Control = log_label.get_parent() as Control
		var idx := log_label.get_index()
		_log_panel = PanelContainer.new()
		_log_panel.name = "LogPanel"
		_log_panel.anchor_left = log_label.anchor_left
		_log_panel.anchor_top = log_label.anchor_top
		_log_panel.anchor_right = log_label.anchor_right
		_log_panel.anchor_bottom = log_label.anchor_bottom
		_log_panel.offset_left = log_label.offset_left
		_log_panel.offset_top = log_label.offset_top
		_log_panel.offset_right = log_label.offset_right
		_log_panel.offset_bottom = log_label.offset_bottom
		var ls := StyleBoxFlat.new()
		ls.bg_color = Color(0.06, 0.05, 0.08, 0.78)
		ls.border_color = Color(0.55, 0.42, 0.28, 0.55)
		ls.set_border_width_all(1)
		ls.set_corner_radius_all(4)
		ls.content_margin_left = 10
		ls.content_margin_right = 10
		ls.content_margin_top = 6
		ls.content_margin_bottom = 6
		_log_panel.add_theme_stylebox_override("panel", ls)
		parent_ctrl.add_child(_log_panel)
		parent_ctrl.move_child(_log_panel, idx)
		log_label.reparent(_log_panel)
		log_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		log_label.offset_left = 0
		log_label.offset_top = 0
		log_label.offset_right = 0
		log_label.offset_bottom = 0
		## 戰報是「打在幻影上，毫無作用」「無法逃離此戰」這些因果的唯一出口，
		## 原本是深灰畫在近黑面板上，約 3.2:1
		log_label.add_theme_color_override("default_color", Color(0.86, 0.84, 0.8))
		log_label.add_theme_font_size_override("normal_font_size", 14)

	## 中央橫幅
	if banner:
		banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		banner.add_theme_constant_override("shadow_offset_x", 2)
		banner.add_theme_constant_override("shadow_offset_y", 2)
		banner.add_theme_font_size_override("font_size", 44)
		banner.pivot_offset = banner.size * 0.5

	if btn_flee:
		UiStyle.style_button(btn_flee, false)
		btn_flee.text = Loc.t("battle.flee")

	## 技能名橫幅（獨立於格擋 banner）
	if _skill_banner == null:
		_skill_banner = Label.new()
		_skill_banner.name = "SkillBanner"
		_skill_banner.visible = false
		_skill_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_skill_banner.offset_top = 170
		_skill_banner.offset_bottom = 210
		_skill_banner.offset_left = -220
		_skill_banner.offset_right = 220
		_skill_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_skill_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_skill_banner.add_theme_font_size_override("font_size", 28)
		_skill_banner.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
		_skill_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_skill_banner.add_theme_constant_override("shadow_offset_x", 2)
		_skill_banner.add_theme_constant_override("shadow_offset_y", 2)
		_skill_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_skill_banner)

	## 怒氣就緒提示
	if _rage_ready == null:
		_rage_ready = Label.new()
		_rage_ready.name = "RageReady"
		_rage_ready.text = Loc.t("battle.rage_full")
		_rage_ready.visible = false
		_rage_ready.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_rage_ready.offset_left = 28
		_rage_ready.offset_top = 168
		_rage_ready.offset_right = 280
		_rage_ready.offset_bottom = 192
		_rage_ready.add_theme_font_size_override("font_size", 13)
		_rage_ready.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		_rage_ready.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_rage_ready.add_theme_constant_override("shadow_offset_x", 1)
		_rage_ready.add_theme_constant_override("shadow_offset_y", 1)
		_rage_ready.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rage_ready)
	_ensure_coach()


func _ensure_coach() -> void:
	if _coach and is_instance_valid(_coach):
		return
	_coach = Label.new()
	_coach.name = "BattleCoach"
	_coach.visible = false
	_coach.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_coach.offset_top = -240
	_coach.offset_bottom = -200
	_coach.offset_left = -360
	_coach.offset_right = 360
	_coach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach.add_theme_font_size_override("font_size", 18)
	_coach.add_theme_color_override("font_color", Color(0.55, 0.95, 0.85))
	_coach.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_coach.add_theme_constant_override("shadow_offset_x", 2)
	_coach.add_theme_constant_override("shadow_offset_y", 2)
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_coach)


func _mode_coach_intro(mode: String) -> String:
	match mode:
		"leo":
			return "提示：倒數變綠立刻按 J 格擋！火圈亮起後再按 J 躍出"
		"fog":
			return "提示：Tab 鎖本體 · 本體發白才砍 · 打錯幻影會痛"
		"abo":
			return "用技能打散架勢比較快 · 散開後全力打"
		"falcon":
			return "提示：別追殘影 · 等停拍再打 · 風切預告按 J"
		"boar":
			return "提示：衝鋒時對撞（J）剝甲 · 落岩進安全區"
		"demon":
			return "提示：必殺與時鐘都靠 J · 血量階段記得「我拒絕」"
		"wolf":
			return "提示：自動互砍 · 怒氣滿會放招 · 撐住就好"
		_:
			return "提示：注意畫面中央提示 · 時機窗按 J"


func _flash_coach(text: String, sec: float = 2.4) -> void:
	_ensure_coach()
	if _coach == null:
		return
	_coach.text = text
	_coach.visible = true
	_coach.modulate = Color(1, 1, 1, 1)
	_coach_timer = sec


func _tick_coach(delta: float) -> void:
	if _coach_timer > 0.0 and _coach:
		_coach_timer -= delta
		if _coach_timer <= 0.0:
			_coach.visible = false
		elif _coach_timer < 0.4:
			_coach.modulate.a = maxf(0.0, _coach_timer / 0.4)


func _style_bar(bar: ProgressBar, fill: Color, back: Color) -> void:
	if bar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = back
	bg.set_corner_radius_all(3)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.2, 0.18, 0.16, 0.9)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.show_percentage = false


func _flash_skill_banner(skill_name: String, player_side: bool = true) -> void:
	if _skill_banner == null:
		return
	_skill_banner.text = "〔 %s 〕" % skill_name
	_skill_banner.add_theme_color_override(
		"font_color",
		Color(0.65, 0.88, 1.0) if player_side else Color(1.0, 0.55, 0.5)
	)
	_skill_banner.visible = true
	_skill_banner.modulate = Color(1, 1, 1, 0)
	_skill_banner.scale = Vector2(0.7, 0.7)
	_skill_banner.pivot_offset = Vector2(220, 20)
	var tw := create_tween()
	tw.tween_property(_skill_banner, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(_skill_banner, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.55)
	tw.tween_property(_skill_banner, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		if is_instance_valid(_skill_banner):
			_skill_banner.visible = false
	)


func _apply_battle_art(mode: String) -> void:
	## 立繪比例：素材約 160×200（兔）／220×240（Boss），維持長寬比、不擠扁
	_player_pose = "idle"
	var ptex := SpriteDB.player_pose("idle")
	if ptex == null:
		ptex = SpriteDB.player_battle()
	if ptex:
		player_body.texture = ptex
	player_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_body.custom_minimum_size = Vector2(200, 250)
	_player_base_mod = SpriteDB.player_armor_modulate()
	player_body.modulate = _player_base_mod
	_apply_battle_weapon_overlay()

	_boss_art_key = mode
	_boss_pose = "idle"
	## 廣域戰：專用 art → fallback art
	var art_mode := mode
	if _is_world_mode(mode):
		var WC = load("res://scripts/world/world_content.gd")
		if WC:
			art_mode = str(WC.art_key(mode))
			_boss_art_key = art_mode
	var etex := SpriteDB.boss_pose(art_mode, "idle")
	if etex == null:
		etex = SpriteDB.boss(art_mode)
	if etex == null and _is_world_mode(mode):
		var WC2 = load("res://scripts/world/world_content.gd")
		var fb := str(WC2.art_fallback(mode)) if WC2 else "wolf"
		etex = SpriteDB.boss(fb)
		_boss_art_key = fb
	if etex:
		enemy_body.texture = etex
	enemy_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	match mode:
		"leo":
			enemy_body.custom_minimum_size = Vector2(280, 310)
			_enemy_base_mod = Color(1.05, 0.95, 0.8)
		"fog":
			enemy_body.custom_minimum_size = Vector2(240, 270)
			_enemy_base_mod = Color(0.85, 0.9, 1.0)
		"demon":
			enemy_body.custom_minimum_size = Vector2(300, 330)
			_enemy_base_mod = Color(0.95, 0.8, 1.0)
		"abo":
			enemy_body.custom_minimum_size = Vector2(270, 300)
			_enemy_base_mod = Color(0.9, 1.0, 0.9)
		"falcon":
			enemy_body.custom_minimum_size = Vector2(250, 270)
			_enemy_base_mod = Color(0.85, 1.05, 0.95)
		"boar":
			enemy_body.custom_minimum_size = Vector2(280, 300)
			_enemy_base_mod = Color(1.05, 0.95, 0.85)
		"wrath":
			enemy_body.custom_minimum_size = Vector2(280, 310)
			_enemy_base_mod = Color(1.15, 0.55, 0.4)
		"tide":
			enemy_body.custom_minimum_size = Vector2(270, 300)
			_enemy_base_mod = Color(0.55, 0.85, 1.15)
		"statue":
			enemy_body.custom_minimum_size = Vector2(270, 300)
			_enemy_base_mod = Color(0.95, 0.85, 0.7)
		"chrono":
			enemy_body.custom_minimum_size = Vector2(280, 310)
			_enemy_base_mod = Color(0.85, 0.65, 1.15)
		"scar_lord":
			enemy_body.custom_minimum_size = Vector2(270, 300)
			_enemy_base_mod = Color(1.1, 0.5, 0.75)
		"mirror_wraith":
			enemy_body.custom_minimum_size = Vector2(250, 280)
			_enemy_base_mod = Color(0.8, 0.9, 1.15)
		"wreck_captain":
			enemy_body.custom_minimum_size = Vector2(280, 300)
			_enemy_base_mod = Color(0.7, 0.85, 1.0)
		_:
			if _is_world_miniboss(mode):
				enemy_body.custom_minimum_size = Vector2(260, 290)
			else:
				enemy_body.custom_minimum_size = Vector2(220, 240)
			_enemy_base_mod = Color.WHITE
	enemy_body.modulate = _enemy_base_mod

	## 背景解析（專屬圖 → 那場仗發生的地圖 → 保底）統一在 SpriteDB.battle_bg_path()。
	## 這裡原本自己寫了一串 fallback（demon→fog→boar→wolf），而那四張正是
	## 「主角＋敵人都畫好」的完成稿插圖 —— 於是打某些王的時候，
	## 背景裡有另一隻主角在跟別的怪對砍。
	var bg := SpriteDB.battle_bg(mode)
	if battle_bg and bg:
		battle_bg.texture = bg
		battle_bg.modulate = _battle_bg_tint(mode)
	elif battle_bg:
		battle_bg.texture = null
		battle_bg.modulate = Color(0.12, 0.1, 0.16)


func _apply_battle_weapon_overlay() -> void:
	## 掛在 player_body 底下（不是 PlayerSlot VBox）：
	## VBox 會重排 sibling，固定 position 無效；當 body 子節點則 lunge／scale 自動跟著走。
	## 裝備讀 SpriteDB（當前武器／防具／流派），下一場 setup → _apply_battle_art 會重讀。
	if player_body == null:
		return
	if _battle_armor == null or not is_instance_valid(_battle_armor):
		_battle_armor = TextureRect.new()
		_battle_armor.name = "PlayerArmorOverlay"
		_battle_armor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_battle_armor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_battle_armor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_battle_armor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		player_body.add_child(_battle_armor)
	elif _battle_armor.get_parent() != player_body:
		_battle_armor.reparent(player_body)
	if _battle_weapon == null or not is_instance_valid(_battle_weapon):
		_battle_weapon = TextureRect.new()
		_battle_weapon.name = "PlayerWeaponOverlay"
		_battle_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_battle_weapon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_battle_weapon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_battle_weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		player_body.add_child(_battle_weapon)
	elif _battle_weapon.get_parent() != player_body:
		_battle_weapon.reparent(player_body)
	_layout_battle_equipment_overlays()
	## body 尺寸可能在下一幀才穩定（VBox 排版）
	if not player_body.resized.is_connected(_layout_battle_equipment_overlays):
		player_body.resized.connect(_layout_battle_equipment_overlays)
	call_deferred("_layout_battle_equipment_overlays")


func _layout_battle_equipment_overlays() -> void:
	if player_body == null:
		return
	var bs := player_body.size
	if bs.x < 8.0 or bs.y < 8.0:
		bs = player_body.custom_minimum_size
	if bs.x < 8.0:
		bs = Vector2(200, 250)
	## 防具：略縮於身體中央
	if _battle_armor and is_instance_valid(_battle_armor):
		var atex := SpriteDB.player_armor_overlay()
		if atex:
			var asz := Vector2(bs.x * 0.78, bs.y * 0.78)
			_battle_armor.texture = atex
			_battle_armor.visible = true
			_battle_armor.custom_minimum_size = asz
			_battle_armor.size = asz
			_battle_armor.position = Vector2((bs.x - asz.x) * 0.5, bs.y * 0.12)
			_battle_armor.modulate = Color(1, 1, 1, 0.88)
			_battle_armor.z_index = 1
		else:
			_battle_armor.visible = false
	## 武器：右前手位置（與探索疊層同源 SpriteDB）
	if _battle_weapon and is_instance_valid(_battle_weapon):
		var wtex := SpriteDB.player_weapon_overlay()
		if wtex:
			var wsz := Vector2(bs.x * 0.38, bs.y * 0.38)
			wsz.x = clampf(wsz.x, 56.0, 96.0)
			wsz.y = clampf(wsz.y, 56.0, 96.0)
			_battle_weapon.texture = wtex
			_battle_weapon.visible = true
			_battle_weapon.custom_minimum_size = wsz
			_battle_weapon.size = wsz
			_battle_weapon.position = Vector2(bs.x * 0.52, bs.y * 0.34)
			_battle_weapon.pivot_offset = wsz * 0.5
			_battle_weapon.rotation_degrees = -22.0
			_battle_weapon.z_index = 2
		else:
			_battle_weapon.visible = false


func _ensure_temptation_ui() -> void:
	if _tempt_layer and is_instance_valid(_tempt_layer):
		return
	_tempt_layer = Control.new()
	_tempt_layer.name = "TemptationLayer"
	_tempt_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tempt_layer.visible = false
	_tempt_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tempt_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.08, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_tempt_layer.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -280
	box.offset_top = -160
	box.offset_right = 280
	box.offset_bottom = 200
	box.add_theme_constant_override("separation", 14)
	_tempt_layer.add_child(box)

	var title := Label.new()
	title.name = "TemptTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.55, 0.6))
	box.add_child(title)

	var body := RichTextLabel.new()
	body.name = "TemptBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(520, 100)
	body.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(body)

	_refuse_btn = Button.new()
	_refuse_btn.name = "RefuseBtn"
	_refuse_btn.text = "我拒絕"
	_refuse_btn.custom_minimum_size = Vector2(0, 56)
	_refuse_btn.pressed.connect(_on_refuse_pressed)
	box.add_child(_refuse_btn)

	var listen_btn := Button.new()
	listen_btn.text = "……聽聽看（之後仍可拒絕）"
	listen_btn.pressed.connect(_on_listen_then_refuse)
	box.add_child(listen_btn)


func _hide_temptation() -> void:
	if _tempt_layer and is_instance_valid(_tempt_layer):
		_tempt_layer.visible = false
	_tempt_stage = 0


func _show_temptation(data: Dictionary) -> void:
	_ensure_temptation_ui()
	_tempt_stage = int(data.get("stage", 1))
	var title: Label = _tempt_layer.find_child("TemptTitle", true, false)
	var body: RichTextLabel = _tempt_layer.find_child("TemptBody", true, false)
	if title:
		title.text = "誘惑 · %s" % str(data.get("title", ""))
	if body:
		body.text = str(data.get("text", ""))
	var scale_f := float(data.get("refuse_scale", 1.0))
	var font_sz := int(round(20.0 * scale_f))
	_refuse_btn.add_theme_font_size_override("font_size", font_sz)
	_refuse_btn.custom_minimum_size = Vector2(0, maxi(48, int(40 * scale_f)))
	_refuse_btn.text = "我拒絕"
	_tempt_layer.visible = true
	_tempt_layer.move_to_front()
	_append_log("[color=#f9a]戰鬥暫停：魔王的誘惑（%s）[/color]" % data.get("title"))


func _on_refuse_pressed() -> void:
	if sim == null or _tempt_stage <= 0:
		return
	var st := _tempt_stage
	_hide_temptation()
	sim.resolve_temptation(st, true)
	var keys := ["", "c6_refuse_power", "c6_refuse_revenge", "c6_refuse_peace"]
	if st >= 1 and st <= 3:
		GameState.set_flag(keys[st], true)
	_append_log("[color=#8f8]你拒絕了（%s）。黑焰外殼裂開一點。[/color]" % st)
	if st == 3:
		_enemy_base_mod = Color(0.85, 0.8, 0.9)
		enemy_body.modulate = _enemy_base_mod
		enemy_name.text = "前任·至弱者殘影"
		_append_log("[color=#ddf]黑焰大片剝落……外形收束。[/color]")


func _on_listen_then_refuse() -> void:
	## 簡化：聽完仍走拒絕（不開壞結局）
	_append_log("你聽完了……心裡仍搖頭。")
	_on_refuse_pressed()


func _hide_size_compare() -> void:
	if is_instance_valid(size_compare):
		size_compare.visible = false


func _process(delta: float) -> void:
	_tick_coach(delta)
	if _parry_note_left > 0.0:
		_parry_note_left = maxf(0.0, _parry_note_left - delta)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		arena.position = Vector2(randf_range(-4, 4), randf_range(-3, 3)) * (_shake * 8.0)
		if _shake <= 0.0:
			arena.position = Vector2.ZERO
	if sim == null or _ended:
		return
	sim.step(delta)
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or _ended:
		return
	if sim.sim_paused:
		return
	if _mode == "fog" and event.is_action_pressed("ui_focus_next"):
		## Tab
		var tid := sim.cycle_player_target(1)
		if tid != "":
			_append_log("鎖定：%s" % sim.get_unit(tid).display_name)
		get_viewport().set_input_as_handled()
		return
	if _mode == "fog" and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				sim.set_player_target("phantom_a")
				_append_log("鎖定：幻影甲")
				get_viewport().set_input_as_handled()
			KEY_2:
				sim.set_player_target("white_fog")
				_append_log("鎖定：白霧本體")
				get_viewport().set_input_as_handled()
			KEY_3:
				sim.set_player_target("phantom_b")
				_append_log("鎖定：幻影乙")
				get_viewport().set_input_as_handled()
	if event.is_action_pressed("parry"):
		if sim.try_react():
			_shake = 0.3
			_flash(player_body, Color(1, 0.95, 0.5))
		get_viewport().set_input_as_handled()


## ── 戰鬥中的 HP 權威 ──
##
## 開戰時玩家的 HP 被快照進 BattleUnit，之後整場只有那一份在動。
## 兩個後果，都要在這裡收乾淨：
##   1. 喝藥若只加 GameState.hp，戰鬥單位一滴都沒回 —— 藥被吃掉但沒效果。
##   2. 左上角那塊狀態板讀的是 GameState.hp，整場停在開戰前的數字，
##      跟戰鬥畫面自己那條血條各說各話。
## 所以：藥交給戰鬥單位吃（_battle_heal），戰鬥單位的血每幀鏡回 GameState。

func _claim_hp_authority() -> void:
	var inv := _inventory_node()
	if inv != null:
		inv.set("hp_authority", Callable(self, "_battle_heal"))


func _release_hp_authority() -> void:
	var inv := _inventory_node()
	if inv != null and inv.get("hp_authority") == Callable(self, "_battle_heal"):
		inv.set("hp_authority", Callable())


func _inventory_node() -> Node:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		return (t as SceneTree).root.get_node_or_null("InventorySystem")
	return null


## 逃跑不走 _on_end()，戰鬥畫面直接被清掉。不在這裡交還的話，
## InventorySystem 會一直握著指向已釋放節點的 Callable。
func _exit_tree() -> void:
	_release_hp_authority()


## 回傳「實際回了多少」——訊息要靠這個數字，回 0 就會顯示「HP +0」，
## 那正是玩家該看到的（滿血喝藥本來就沒有效果）。
func _battle_heal(h: int) -> int:
	if sim == null or _ended:
		return 0
	var p: BattleUnit = sim.get_unit("player")
	if p == null or not p.is_alive():
		return 0
	var before := p.hp
	p.hp = mini(p.max_hp, p.hp + h)
	var healed := p.hp - before
	if healed > 0:
		_flash(player_body, Color(0.6, 1.0, 0.7))
		_append_log("[color=#6f6]回復 %d[/color]" % healed)
		_refresh_hud()
	return healed


func _mirror_hp_to_state(p: BattleUnit) -> void:
	if p == null:
		return
	var hp := maxi(0, p.hp)
	if GameState.hp != hp:
		GameState.hp = hp
	if Engine.get_main_loop() is SceneTree:
		(Engine.get_main_loop() as SceneTree).call_group(MapleHud.VITALS_GROUP, "refresh_vitals")


## 裂縫四種各自的染色。背景是共用的地圖底圖，靠色調把四場仗分開。
func _battle_bg_tint(mode: String) -> Color:
	match mode:
		"wrath":
			return Color(1.1, 0.55, 0.45, 1)
		"tide":
			return Color(0.55, 0.7, 1.0, 1)
		"statue":
			return Color(0.85, 0.75, 0.6, 1)
		"chrono":
			return Color(0.7, 0.55, 0.95, 1)
		"mirror_wraith":
			return Color(0.75, 0.75, 0.8, 1)
	return Color(1, 1, 1, 1)


func _refresh_hud() -> void:
	if sim == null:
		return
	var p: BattleUnit = sim.get_unit("player")
	var e := _primary_enemy()
	_mirror_hp_to_state(p)

	if p:
		player_name_l.text = p.display_name
		player_hp.max_value = p.max_hp
		player_hp.value = p.hp
		var status := ""
		if p.atb_freeze_left > 0.0:
			status = " [凍結]"
		elif p.atb_slow_left > 0.0:
			status = " [寒意]"
		elif p.atk_buff_left > 0.0 and p.atk_buff_mult > 1.0:
			status = " [強化]"
		elif p.atk_buff_left > 0.0 and p.atk_buff_mult < 1.0:
			status = " [虛弱]"
		player_hp_label.text = "HP %d／%d%s" % [p.hp, p.max_hp, status]
		player_rage.max_value = 100
		player_rage.value = p.rage
		## 怒氣將近滿／已滿提示
		if _rage_ready:
			if p.can_skill and p.rage >= 100.0:
				_rage_ready.visible = true
				_rage_ready.text = Loc.t("battle.rage_full")
				_rage_ready.modulate = Color(1.0, 0.85, 0.4)
			elif p.can_skill and p.rage >= 70.0:
				_rage_ready.visible = true
				_rage_ready.text = Loc.t("battle.rage_pct", {"n": int(p.rage)})
				_rage_ready.modulate = Color(0.9, 0.75, 0.5, 0.85)
			else:
				_rage_ready.visible = false
	## 場地機制 HUD（火圈／時鐘）優先於一般提示
	if sim.hazard_kind != "" and sim.hazard_phase != "idle":
		_update_hazard_hud()
	if e:
		if _mode == "fog":
			var real_u: BattleUnit = sim.get_unit("white_fog")
			if real_u:
				enemy_name.text = real_u.display_name
				enemy_hp.max_value = real_u.max_hp
				enemy_hp.value = real_u.hp
				enemy_hp_label.text = "本體 HP %d / %d" % [real_u.hp, real_u.max_hp]
				if real_u.vulnerable:
					enemy_body.modulate = Color(1.35, 1.35, 1.4)
					telegraph.visible = true
					telegraph.color = Color(0.85, 0.9, 1.0, 0.2)
					countdown.visible = true
					countdown.text = "看破"
					countdown.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
					countdown_sub.visible = true
					countdown_sub.text = "破綻！攻擊本體才有效"
					parry_hint.text = "破綻中 · 確認鎖定本體(鍵2) · 剩餘約 %.1fs" % sim.fog_vuln_left
					parry_hint.modulate = Color(0.7, 0.95, 1.0)
				else:
					enemy_body.modulate = Color(0.7, 0.75, 0.9)
					telegraph.visible = false
					countdown.visible = false
					countdown_sub.visible = false
					var punit: BattleUnit = sim.get_unit("player")
					var lock_n := "本體"
					if punit and punit.target_id != "":
						var lt := sim.get_unit(punit.target_id)
						if lt:
							lock_n = lt.display_name
					parry_hint.text = "鎖定中：%s · Tab/1/2/3 切換 · 等本體發白" % lock_n
					parry_hint.modulate = Color(0.85, 0.85, 0.95)
		else:
			enemy_name.text = e.display_name
			enemy_hp.max_value = e.max_hp
			enemy_hp.value = e.hp
			enemy_hp_label.text = "HP %d / %d" % [e.hp, e.max_hp]
			if e.telegraph_active and not sim.sim_paused:
				_update_parry_countdown(e)
			elif not sim.sim_paused:
				countdown.visible = false
				countdown_sub.visible = false
				telegraph.visible = false
				if _mode == "leo":
					parry_hint.modulate = Color(1, 1, 1)
					parry_hint.text = "王者斬會出現倒數。數字變綠時按 J 或滑鼠格擋。"
				elif _mode == "demon":
					parry_hint.modulate = Color(1, 1, 1)
					parry_hint.text = "黑焰必殺可格擋 · 階段誘惑選「我拒絕」"
				elif _mode == "abo":
					_update_abo_guard_hud()
				elif _mode == "falcon":
					_update_falcon_hud()
				elif _mode == "boar":
					_update_boar_hud()
				elif _mode == "wrath":
					_update_wrath_hud()
				elif _mode == "tide":
					_update_tide_hud()
				elif _mode == "statue":
					_update_statue_hud()
				elif _mode == "chrono":
					_update_chrono_hud()


func _update_tide_hud() -> void:
	if sim == null or not sim.tide_mode:
		return
	countdown.visible = true
	countdown_sub.visible = true
	if sim.tide_wave_active:
		countdown.text = "刺%d" % sim._count_polyps()
		countdown.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
		countdown_sub.text = "清刺胞！剩餘 %.1fs" % sim.tide_wave_left
		parry_hint.text = "優先清黑焰刺胞"
		parry_hint.modulate = Color(0.6, 0.95, 1.0)
	else:
		countdown.text = "技" if sim.tide_phase_skill else "普"
		countdown.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		countdown_sub.text = "他在擋技能 · 改用普攻" if sim.tide_phase_skill else "他在擋普攻 · 改用技能"
		parry_hint.text = "趁現在打 · 刺胞還會再冒"
		parry_hint.modulate = Color(0.8, 0.9, 1.0)
	## 不在此覆寫攻擊幀；由 _set_boss_pose 管


func _update_statue_hud() -> void:
	if sim == null or not sim.statue_mode:
		return
	countdown.visible = true
	countdown_sub.visible = true
	if sim.statue_body_spawned:
		countdown.text = "本體"
		countdown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		countdown_sub.text = "石像盡碎 · 殘響現身"
		parry_hint.text = "輸出本體 · 落岩仍要 J"
		if _boss_art_key != "echo":
			_boss_art_key = "echo"
			_set_boss_pose(_boss_pose if _boss_pose != "" else "idle")
	else:
		countdown.text = "石%d" % (sim.statue_active_idx + 1)
		countdown.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		countdown_sub.text = "只打發光石像 · 約 %.1fs 輪轉" % sim.statue_rotate_cd
		parry_hint.text = "打亮的那尊 · 打錯無效"
		if _boss_art_key != "statue":
			_boss_art_key = "statue"
		if _boss_pose == "idle":
			enemy_body.modulate = Color(1.2, 1.15, 0.85)


func _update_chrono_hud() -> void:
	if sim == null or not sim.chrono_mode:
		return
	if sim.hazard_phase != "idle":
		return
	var e := _primary_enemy()
	if e and e.telegraph_active:
		return
	countdown.visible = true
	countdown.text = "時"
	countdown.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	countdown_sub.visible = true
	countdown_sub.text = "炸彈拆除 · 落岩進安全"
	parry_hint.text = "預告後按 J"
	parry_hint.modulate = Color(0.9, 0.8, 1.0)


func _update_wrath_hud() -> void:
	if sim == null or not sim.wrath_mode:
		return
	if sim.hazard_phase != "idle":
		return
	countdown.visible = true
	countdown_sub.visible = true
	var e := _primary_enemy()
	if e and e.telegraph_active:
		return  ## 交給格擋倒數
	var st: int = sim.burn_stacks
	countdown.text = "灼%d" % st
	if st >= 2:
		countdown.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
		countdown_sub.text = "危險！灼燒 %d/%d · 再漏就爆" % [st, BattleSim.BURN_STACK_MAX]
		parry_hint.modulate = Color(1, 0.45, 0.35)
	else:
		countdown.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
		countdown_sub.text = "灼燒 %d/%d · 密火圈漏閃會疊層" % [st, BattleSim.BURN_STACK_MAX]
		parry_hint.modulate = Color(1, 0.75, 0.5)
	parry_hint.text = "密火圈：預告後按 J · 必殺可格擋"
	enemy_body.modulate = Color(1.1 + st * 0.08, 0.5 - st * 0.05, 0.35)


func _update_hazard_hud() -> void:
	if sim == null:
		return
	var names := {
		"fire_ring": "火圈",
		"time_clock": "控時時鐘",
		"lightning": "導雷",
		"wind_cut": "風切",
		"rockfall": "落岩",
		"bomb": "時牢炸彈",
	}
	var nm: String = names.get(sim.hazard_kind, sim.hazard_kind)
	countdown.visible = true
	countdown_sub.visible = true
	_show_hazard_fx(sim.hazard_kind, sim.hazard_phase)
	if sim.hazard_phase == "warn":
		telegraph.visible = true
		telegraph.color = Color(1.0, 0.45, 0.15, 0.22)
		countdown.text = "注意"
		countdown.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
		countdown_sub.text = "%s 即將生效… %.1fs" % [nm, sim.hazard_timer]
		parry_hint.text = "準備：黃色「閃」出現時按 J"
		parry_hint.modulate = Color(1, 0.7, 0.4)
	elif sim.hazard_phase == "window":
		telegraph.visible = true
		telegraph.color = Color(1.0, 0.9, 0.2, 0.25 + 0.1 * sin(Time.get_ticks_msec() * 0.03))
		countdown.text = "閃"
		countdown.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
		countdown_sub.text = "%s！現在按 J 或滑鼠  %.1fs" % [nm, sim.hazard_timer]
		parry_hint.text = "互動窗：按 J"
		parry_hint.modulate = Color(1, 1, 0.5)
		_pulse_countdown()


func _show_hazard_fx(kind: String, phase: String) -> void:
	if hazard_fx == null:
		return
	var fx_key := kind
	if kind == "wind_cut" and phase == "window":
		fx_key = "wind_cut_line"
	elif kind == "rockfall" and phase == "window":
		fx_key = "safe_zone"
	var t := SpriteDB.fx(fx_key)
	if t == null:
		t = SpriteDB.fx(kind)
	if t == null:
		hazard_fx.visible = false
		return
	hazard_fx.texture = t
	hazard_fx.visible = true
	var pulse := 0.75 + 0.2 * sin(Time.get_ticks_msec() * 0.01)
	if phase == "window":
		hazard_fx.modulate = Color(1, 1, 0.7, pulse)
		hazard_fx.scale = Vector2(1.1, 1.1)
	else:
		hazard_fx.modulate = Color(1, 0.7, 0.4, 0.7)
		hazard_fx.scale = Vector2.ONE


func _update_falcon_hud() -> void:
	if sim == null or not sim.falcon_mode:
		return
	## 若正在風切互動，交給 hazard HUD
	if sim.hazard_phase != "idle":
		return
	if sim.falcon_stop_left > 0.0:
		countdown.visible = true
		countdown.text = "停"
		countdown.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
		countdown_sub.visible = true
		countdown_sub.text = "真身定格！全額傷害  %.1fs" % sim.falcon_stop_left
		parry_hint.text = "輸出窗"
		parry_hint.modulate = Color(0.6, 1.0, 0.7)
		enemy_body.modulate = Color(1.25, 1.35, 1.2)
		telegraph.visible = true
		telegraph.color = Color(0.5, 0.95, 0.7, 0.12)
	else:
		countdown.visible = true
		countdown.text = "速"
		countdown.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
		countdown_sub.visible = true
		countdown_sub.text = "殘影飛掠中… 等停拍"
		parry_hint.text = "此時只 scratch · 等「停」"
		parry_hint.modulate = Color(0.75, 0.85, 0.95)
		enemy_body.modulate = Color(0.55, 0.7, 0.75)
		telegraph.visible = false


func _update_boar_hud() -> void:
	if sim == null or not sim.boar_mode:
		return
	if sim.hazard_phase != "idle":
		return
	var e: BattleUnit = sim.get_unit("boar")
	countdown.visible = true
	countdown_sub.visible = true
	if e and e.telegraph_active:
		var win := e.state_timer <= 1.0
		if win:
			countdown.text = "撞"
			countdown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			countdown_sub.text = "對撞！按 J 卸力剝岩甲  %.1fs" % e.state_timer
			parry_hint.text = "現在對撞"
			parry_hint.modulate = Color(1, 0.9, 0.4)
		else:
			countdown.text = "衝"
			countdown.add_theme_color_override("font_color", Color(1.0, 0.5, 0.35))
			countdown_sub.text = "石拳衝鋒蓄力… 準備對撞"
			parry_hint.text = "準備 J"
			parry_hint.modulate = Color(1, 0.6, 0.4)
		telegraph.visible = true
		telegraph.color = Color(0.9, 0.4, 0.2, 0.2)
	else:
		countdown.text = "甲%d" % sim.boar_armor
		countdown.add_theme_color_override("font_color", Color(0.85, 0.7, 0.45))
		countdown_sub.text = "岩甲 %d 層 · 對撞可剝" % sim.boar_armor
		parry_hint.text = "等衝鋒對撞 · 落岩按 J 進安全"
		parry_hint.modulate = Color(0.9, 0.85, 0.7)
		telegraph.visible = false
		enemy_body.modulate = Color(0.85, 0.8, 0.75) if sim.boar_armor > 0 else Color(1.1, 0.95, 0.85)


func _update_abo_guard_hud() -> void:
	if sim == null or not sim.abo_mode:
		return
	if sim.abo_broken_left > 0.0:
		countdown.visible = true
		countdown.text = "破防"
		countdown.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		countdown_sub.visible = true
		countdown_sub.text = "架勢崩壞！剩 %.1f 秒 · 全力輸出" % sim.abo_broken_left
		parry_hint.text = "破防中 · 傷害全額"
		parry_hint.modulate = Color(0.5, 1.0, 0.55)
		telegraph.visible = true
		telegraph.color = Color(0.3, 0.9, 0.4, 0.15)
		enemy_body.modulate = Color(1.15, 1.25, 1.05)
	else:
		countdown.visible = true
		var pct := int(round(sim.abo_guard / BattleSim.ABO_GUARD_MAX * 100.0))
		countdown.text = "%d%%" % pct
		countdown.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		countdown_sub.visible = true
		countdown_sub.text = "架勢 %d / %d（技能打得快）" % [int(sim.abo_guard), int(BattleSim.ABO_GUARD_MAX)]
		parry_hint.text = "他架著 · 現在打不痛 · 先把架勢打散"
		parry_hint.modulate = Color(1, 0.85, 0.5)
		telegraph.visible = false
		enemy_body.modulate = _enemy_base_mod


func _update_parry_countdown(e: BattleUnit) -> void:
	telegraph.visible = true
	countdown.visible = true
	countdown_sub.visible = true
	## 蓄力全程保持 telegraph 幀；進入格擋窗略強調
	if e.telegraph_active:
		if e.state_timer <= BattleSim.PARRY_WINDOW:
			if _boss_pose != "attack":
				_set_boss_pose("telegraph")
				## 格擋窗：微放大呼吸
				enemy_body.scale = Vector2.ONE * (1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.02))
		else:
			_set_boss_pose("telegraph")

	var remain := e.state_timer
	var in_window := remain <= BattleSim.PARRY_WINDOW and remain > 0.0

	## 整段前搖的「距離出手」秒數（顯示用）
	var display_sec := remain
	## 倒數桶：3 / 2 / 1 / 格擋
	var bucket: int
	if in_window:
		bucket = 0
	elif remain > 1.2:
		bucket = 3
	elif remain > 0.7:
		bucket = 2
	else:
		bucket = 1

	if in_window:
		telegraph.color = Color(0.2, 0.9, 0.35, 0.22 + 0.12 * sin(Time.get_ticks_msec() * 0.025))
		countdown.text = "格擋"
		countdown.add_theme_color_override("font_color", Color(0.4, 1.0, 0.45))
		countdown_sub.text = "現在按 J 或滑鼠左鍵！"
		countdown_sub.add_theme_color_override("font_color", Color(0.6, 1.0, 0.65))
		if _parry_note_left <= 0.0:
			parry_hint.text = "格擋時機！（剩餘 %.1f 秒）" % remain
			parry_hint.modulate = Color(0.5, 1.0, 0.5)
		if _last_cd_bucket != 0:
			_last_cd_bucket = 0
			_pulse_countdown()
	else:
		telegraph.color = Color(1, 0.25, 0.2, 0.2 + 0.1 * sin(Time.get_ticks_msec() * 0.02))
		countdown.text = str(bucket)
		countdown.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		countdown_sub.text = "王者斬蓄力中… %.1f 秒後可格擋" % maxf(0.0, remain - BattleSim.PARRY_WINDOW)
		countdown_sub.add_theme_color_override("font_color", Color(1, 0.7, 0.55))
		if _parry_note_left <= 0.0:
			parry_hint.text = "準備：倒數到「格擋」再按"
			parry_hint.modulate = Color(1, 0.55, 0.45)
		if bucket != _last_cd_bucket:
			_last_cd_bucket = bucket
			_pulse_countdown()

	## 小字顯示精確剩餘
	countdown_sub.text += "\n(出手倒數 %.1fs)" % display_sec


## 格擋回饋短暫蓋掉提示條。倒數每幀都在寫 parry_hint，
## 所以要記一個到期時間，讓 _update_parry_countdown 在期間內別覆蓋回去。
var _parry_note_left: float = 0.0


func _flash_parry_note(text: String, col: Color) -> void:
	if parry_hint == null:
		return
	parry_hint.text = text
	parry_hint.modulate = col
	_parry_note_left = 0.9


func _pulse_countdown() -> void:
	countdown.scale = Vector2(1.35, 1.35)
	var tw := create_tween()
	tw.tween_property(countdown, "scale", Vector2.ONE, 0.12)


## 切換 Boss 攻擊幀（telegraph 蓄力 / attack 出手 / recover / idle）
func _set_player_pose(pose: String, punch: bool = false) -> void:
	if pose == _player_pose and not punch:
		return
	_player_pose = pose
	var t: Texture2D = SpriteDB.player_pose(pose)
	if t == null and pose != "idle":
		t = SpriteDB.player_pose("idle")
	if t == null:
		t = SpriteDB.player_battle()
	if t:
		player_body.texture = t
	if punch or pose == "attack" or pose == "skill":
		if _player_pose_tween and _player_pose_tween.is_valid():
			_player_pose_tween.kill()
		player_body.scale = Vector2(1.1, 0.94)
		_player_pose_tween = create_tween()
		_player_pose_tween.tween_property(player_body, "scale", Vector2.ONE, 0.12)
	elif pose == "telegraph":
		if _player_pose_tween and _player_pose_tween.is_valid():
			_player_pose_tween.kill()
		player_body.scale = Vector2(0.97, 1.05)
		_player_pose_tween = create_tween()
		_player_pose_tween.tween_property(player_body, "scale", Vector2.ONE, 0.15)


func _set_boss_pose(pose: String, punch: bool = false) -> void:
	if pose == _boss_pose and not punch:
		return
	_boss_pose = pose
	var key := _boss_art_key
	if sim and sim.statue_mode and sim.statue_body_spawned:
		key = "echo"
	elif _mode == "statue" and not (sim and sim.statue_body_spawned):
		key = "statue"
	var t: Texture2D = SpriteDB.boss_pose(key, pose)
	if t == null and pose != "idle":
		t = SpriteDB.boss_pose(key, "idle")
	if t == null:
		t = SpriteDB.boss(key if key != "" else _mode)
	if t:
		enemy_body.texture = t
	## 出手時額外衝刺感
	if punch or pose == "attack":
		if _pose_tween and _pose_tween.is_valid():
			_pose_tween.kill()
		enemy_body.scale = Vector2(1.12, 0.92)
		_pose_tween = create_tween()
		_pose_tween.tween_property(enemy_body, "scale", Vector2.ONE, 0.14)
	elif pose == "telegraph":
		if _pose_tween and _pose_tween.is_valid():
			_pose_tween.kill()
		enemy_body.scale = Vector2(0.96, 1.06)
		_pose_tween = create_tween()
		_pose_tween.tween_property(enemy_body, "scale", Vector2(1.02, 1.02), 0.2)


func _boss_pose_from_unit(u: BattleUnit) -> void:
	if u == null or not u.is_alive():
		_set_boss_pose("idle")
		return
	if u.telegraph_active:
		_set_boss_pose("telegraph")
	elif u.state == BattleUnit.State.WINDUP:
		_set_boss_pose("telegraph")
	elif u.state == BattleUnit.State.STRIKE:
		_set_boss_pose("attack", true)
	elif u.state == BattleUnit.State.RECOVER:
		_set_boss_pose("recover")
	elif u.state == BattleUnit.State.CAST:
		_set_boss_pose("telegraph")
	else:
		_set_boss_pose("idle")


func _is_enemy_actor(id: String) -> bool:
	if id == "" or id == "player":
		return false
	return true


func _primary_enemy() -> BattleUnit:
	if sim == null:
		return null
	if sim.units.has("demon"):
		return sim.get_unit("demon")
	if sim.units.has("abo"):
		return sim.get_unit("abo")
	if sim.units.has("falcon"):
		return sim.get_unit("falcon")
	if sim.units.has("boar"):
		return sim.get_unit("boar")
	if sim.units.has("wrath"):
		return sim.get_unit("wrath")
	if sim.units.has("tide"):
		return sim.get_unit("tide")
	if sim.units.has("echo") and sim.get_unit("echo") and sim.get_unit("echo").is_alive():
		return sim.get_unit("echo")
	if sim.statue_mode:
		var sid := "statue_%d" % sim.statue_active_idx
		if sim.units.has(sid) and sim.get_unit(sid).is_alive():
			return sim.get_unit(sid)
	if sim.units.has("chrono"):
		return sim.get_unit("chrono")
	if sim.units.has("white_fog"):
		return sim.get_unit("white_fog")
	var enemies := sim.living_of(BattleUnit.Team.ENEMY)
	if not enemies.is_empty():
		return enemies[0]
	if sim.units.has("leo"):
		return sim.get_unit("leo")
	if sim.units.has("wolf"):
		return sim.get_unit("wolf")
	return null


## 戰鬥的開始與結果從這裡回報，不從 main.gd。
## 掛在 battle_finished 上而不是逐個 emit 點插一行，逃跑／中途結束才不會漏。
func _telemetry_watch(mode: String) -> void:
	var tel: Node = _telemetry_node()
	if tel == null:
		return
	tel.call("battle_started", mode)
	if not battle_finished.is_connected(_on_telemetry_battle_finished):
		battle_finished.connect(_on_telemetry_battle_finished)


func _on_telemetry_battle_finished(won: bool) -> void:
	var tel: Node = _telemetry_node()
	if tel:
		tel.call("battle_finished", _mode, won)


func _on_event(kind: String, data: Dictionary) -> void:
	AudioManager.on_battle_event(kind, data)
	match kind:
		"parry_early":
			## 「差一點」——機會還在，要講清楚，不然玩家以為格擋壞了
			_append_log("[color=#fc8]太早了 · 等倒數變綠[/color]")
			AudioManager.play("ui", 0.9, -8.0)
			_flash_parry_note("太早了", Color(1.0, 0.78, 0.45))
		"parry_whiff":
			## 機會用掉了：這一次前搖已經沒有第二下
			_append_log("[color=#e88]揮空了 · 這一擊擋不掉[/color]")
			AudioManager.play("miss", 1.0, -6.0)
			_flash(player_body, Color(1.0, 0.55, 0.45))
			_shake = 0.12
			_flash_parry_note("揮空 · 這一擊沒機會了", Color(1.0, 0.5, 0.42))
		"parry_spent":
			_flash_parry_note("這一擊的機會用完了", Color(0.85, 0.6, 0.55))
		"attack_swing":
			var aid := str(data.get("id", ""))
			_lunge(aid)
			if _is_enemy_actor(aid):
				_set_boss_pose("attack", true)
				get_tree().create_timer(0.18).timeout.connect(func():
					if is_instance_valid(self) and not _ended:
						_set_boss_pose("recover")
				)
				get_tree().create_timer(0.45).timeout.connect(func():
					if is_instance_valid(self) and not _ended and _boss_pose == "recover":
						_set_boss_pose("idle")
				)
			elif aid == "player":
				_set_player_pose("attack", true)
				get_tree().create_timer(0.2).timeout.connect(func():
					if is_instance_valid(self) and not _ended:
						_set_player_pose("recover")
				)
				get_tree().create_timer(0.45).timeout.connect(func():
					if is_instance_valid(self) and not _ended and _player_pose == "recover":
						_set_player_pose("idle")
				)
		"hit":
			var crit_s := "暴擊" if data.get("crit", false) else ""
			var ks := "【王者斬】" if data.get("king_slash", false) else ""
			_append_log("%s%s 造成 %s 傷害 %s" % [ks, data.get("attacker"), data.get("damage"), crit_s])
			_spawn_float(str(data.get("defender")), str(data.get("damage")), Color(1, 0.4, 0.35))
			_flash(_body_of(str(data.get("defender"))), Color(1, 0.3, 0.3))
			if data.get("defender") == "player":
				_try_wheat_save(int(data.get("hp", 0)))
			if data.get("king_slash", false):
				_shake = 0.4
				countdown.visible = false
				countdown_sub.visible = false
				_set_boss_pose("attack", true)
				get_tree().create_timer(0.35).timeout.connect(func():
					if is_instance_valid(self) and not _ended:
						_set_boss_pose("idle")
				)
		"miss":
			_append_log("%s 未中" % data.get("attacker"))
			_spawn_float(str(data.get("defender")), "未中", Color(0.7, 0.7, 0.8))
		"skill_cast":
			_append_log("[color=#8cf]%s 使出 %s[/color]" % [data.get("id"), data.get("skill")])
			var sid := str(data.get("id", ""))
			var skn := str(data.get("skill", "技能"))
			_flash_skill_banner(skn, sid == "player")
			_lunge(sid)
			if _is_enemy_actor(sid):
				_set_boss_pose("telegraph")
			elif sid == "player":
				_set_player_pose("skill", true)
		"skill_hit":
			if str(data.get("kind", "")) == "heal" or int(data.get("heal", 0)) > 0:
				_append_log("[color=#8f8]%s！回復 %s[/color]" % [data.get("skill"), data.get("heal", 0)])
				_spawn_float(str(data.get("defender", "player")), "+%s" % data.get("heal", 0), Color(0.5, 1.0, 0.65))
				_flash(_body_of(str(data.get("defender", "player"))), Color(0.5, 1.0, 0.7))
			else:
				_append_log("[color=#8cf]%s！%s 傷害[/color]" % [data.get("skill"), data.get("damage")])
				_spawn_float(str(data.get("defender")), str(data.get("damage")), Color(0.6, 0.85, 1))
				_flash(_body_of(str(data.get("defender"))), Color(0.6, 0.8, 1))
			if str(data.get("attacker", "")) == "player":
				_set_player_pose("attack", true)
				_grant_skill_mastery(str(data.get("skill_id", "slash")))
				get_tree().create_timer(0.25).timeout.connect(func():
					if is_instance_valid(self) and not _ended:
						_set_player_pose("idle")
				)
			if data.get("parry_followup", false):
				_shake = 0.25
				_set_boss_pose("recover")
				get_tree().create_timer(0.4).timeout.connect(func():
					if is_instance_valid(self) and not _ended:
						_set_boss_pose("idle")
				)
		"perfect_parry":
			## 不用「微末一格／體型對照」等開發梗；只給可讀的短提示
			banner.text = str(data.get("banner", "完美格擋"))
			if banner.text == "微末一格":
				banner.text = "完美格擋"
			banner.visible = true
			banner.modulate = Color(1, 1, 1, 1)
			banner.add_theme_font_size_override("font_size", 28)
			banner.scale = Vector2(0.85, 0.85)
			banner.pivot_offset = banner.size * 0.5 if banner.size.x > 1 else Vector2(200, 40)
			var tw := create_tween()
			tw.tween_property(banner, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.55)
			tw.tween_property(banner, "modulate:a", 0.0, 0.18)
			GameState.set_flag("c1_perfect_parry_once", true)
			_flash(enemy_body, Color(1.2, 1.15, 0.7))
			_set_boss_pose("recover")
			get_tree().create_timer(0.5).timeout.connect(func():
				if is_instance_valid(self) and not _ended:
					_set_boss_pose("idle")
			)
			var pfx := SpriteDB.fx("parry_flash")
			if hazard_fx and pfx:
				hazard_fx.texture = pfx
				hazard_fx.visible = true
				hazard_fx.modulate = Color(1, 1, 0.8, 0.9)
				get_tree().create_timer(0.35).timeout.connect(func():
					if is_instance_valid(hazard_fx):
						hazard_fx.visible = false
				)
			_append_log("[color=#ffd700]== %s ==[/color]" % data.get("banner", "格擋"))
			countdown.visible = false
			countdown_sub.visible = false
		"banner_end":
			banner.visible = false
		"king_slash_start":
			var lab := str(data.get("label", "王者斬"))
			_append_log("[color=#f66]蓄力：%s！看畫面中央倒數／格擋窗[/color]" % lab)
			_pulse_enemy()
			_set_boss_pose("telegraph")
			_last_cd_bucket = -1
		"state":
			## 單位狀態回 idle 時收招
			if str(data.get("state", "")) == "idle" and _is_enemy_actor(str(data.get("id", ""))):
				if _boss_pose != "telegraph":
					_set_boss_pose("idle")
		"hazard_warn":
			_append_log("[color=#fa6]%s 預告…[/color]" % _hazard_name(str(data.get("kind"))))
		"hazard_window":
			_append_log("[color=#ff5]%s 互動窗！按 J[/color]" % _hazard_name(str(data.get("kind"))))
		"hazard_resolve":
			var ok := bool(data.get("success", false))
			var msg := str(data.get("msg", ""))
			if ok:
				_append_log("[color=#8f8]%s[/color]" % msg)
			else:
				_append_log("[color=#f88]%s[/color]" % msg)
				if data.has("damage"):
					_spawn_float("player", str(data.get("damage")), Color(1, 0.5, 0.2))
					_flash(player_body, Color(1, 0.4, 0.2))
					_try_wheat_save(int(data.get("hp", 1)))
			countdown.visible = false
			countdown_sub.visible = false
			telegraph.visible = false
			if hazard_fx:
				hazard_fx.visible = false
		"temptation":
			_show_temptation(data)
		"temptation_resolved":
			pass
		"demon_shell_break":
			if data.get("refuse_all", false):
				GameState.set_flag("c6_refuse_all", true)
		"abo_guard_changed":
			pass  ## HUD 每幀更新
		"abo_guard_break":
			_append_log("[color=#8f8]架勢崩壞！破防！（第 %s 次）[/color]" % data.get("count"))
			_shake = 0.25
			_flash(enemy_body, Color(0.6, 1.0, 0.5))
			countdown.text = "破防"
		"abo_guard_recover":
			_append_log("阿波重新站穩架勢……")
		"falcon_stop":
			_append_log("[color=#8f8]疾影停拍！真身暴露！[/color]")
			_shake = 0.08
		"falcon_blur":
			_append_log("風又起了……")
		"boar_armor_break":
			if data.get("regrow", false):
				_append_log("[color=#c96]石拳狂怒，岩甲再生一層！[/color]")
			else:
				_append_log("[color=#8f8]對撞成功！岩甲剩餘 %s[/color]" % data.get("armor"))
			_shake = 0.2
		"burn_stacks":
			if data.get("detonate", false):
				_append_log("[color=#f44]灼燒引爆！[/color]")
				_shake = 0.35
				_flash(player_body, Color(1, 0.3, 0.1))
			elif int(data.get("stacks", 0)) > 0:
				_append_log("[color=#f86]灼燒疊層：%s[/color]" % data.get("stacks"))
		"tide_summon":
			_append_log("[color=#6cf]黑焰刺胞×%s 孵化！%.0f 秒內清除[/color]" % [data.get("count"), data.get("time")])
			_shake = 0.1
		"tide_wave_clear":
			_append_log("[color=#8f8]刺胞清除。潮勢暫緩。[/color]")
		"tide_wave_fail":
			_append_log("[color=#f88]刺胞爆發！受傷 %s[/color]" % data.get("damage"))
			_flash(player_body, Color(0.4, 0.7, 1.0))
			_shake = 0.3
			_try_wheat_save(int(data.get("hp", 1)))
		"tide_phase":
			_append_log("[color=#8cf]%s[/color]" % data.get("label"))
		"statue_active":
			_append_log("[color=#fc8]石像 %s 亮起！[/color]" % data.get("id"))
			enemy_body.modulate = Color(1.25, 1.15, 0.8)
		"statue_block":
			_append_log("[color=#aaa]打在未亮石像上，無效[/color]")
			_spawn_float(str(data.get("id", "enemy")), "無效", Color(0.7, 0.7, 0.75))
		"echo_spawn":
			_append_log("[color=#ff8]石像盡碎——殘響本體出現！[/color]")
			_shake = 0.25
			_boss_art_key = "echo"
			_set_boss_pose("idle")
		"parry_window":
			if bool(data.get("open", false)):
				_set_boss_pose("telegraph")
			else:
				if _boss_pose == "telegraph":
					_set_boss_pose("idle")
		"fog_reveal":
			_append_log("[color=#cff]白霧露出破綻！快打本體！[/color]")
			_shake = 0.1
		"fog_hide":
			_append_log("霧又合上了……")
		"fog_phantom_hit":
			var chill_s := " · 寒意（出手變慢）" if data.get("chill", false) else ""
			_append_log("[color=#f88]打到幻影！反噬 %s%s[/color]" % [data.get("recoil"), chill_s])
			_flash(player_body, Color(0.7, 0.5, 0.9))
			_spawn_float("player", str(data.get("recoil")), Color(0.8, 0.5, 1))
			if int(data.get("hp", 1)) <= 0:
				_try_wheat_save(0)
		"fog_blocked":
			_append_log("[color=#aaa]打在霧上，毫無作用（等看破）[/color]")
			_spawn_float(str(data.get("defender")), "看不破", Color(0.7, 0.75, 0.85))
		"target_changed":
			pass
		_:
			pass


func _body_of(id: String) -> TextureRect:
	if id == "player":
		return player_body
	return enemy_body


func _lunge(id: String) -> void:
	var body := _body_of(id)
	var home := _player_home if id == "player" else _enemy_home
	var dir := 1.0 if id == "player" else -1.0
	var tw := create_tween()
	tw.tween_property(body, "position", home + Vector2(dir * 36, 0), 0.08)
	tw.tween_property(body, "position", home, 0.12)


func _flash(body: TextureRect, c: Color) -> void:
	if body == null:
		return
	var base := _player_base_mod if body == player_body else _enemy_base_mod
	body.modulate = c
	var tw := create_tween()
	tw.tween_property(body, "modulate", base, 0.15)


func _pulse_enemy() -> void:
	var tw := create_tween()
	tw.tween_property(enemy_body, "scale", Vector2(1.15, 1.15), 0.2)
	tw.tween_property(enemy_body, "scale", Vector2.ONE, 0.3)


func _spawn_float(target_id: String, text: String, color: Color) -> void:
	var body := _body_of(target_id)
	if body == null:
		return
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 24)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lab.add_theme_constant_override("shadow_offset_x", 1)
	lab.add_theme_constant_override("shadow_offset_y", 1)
	lab.position = body.global_position + Vector2(body.size.x * 0.25, -16)
	lab.z_index = 20
	add_child(lab)
	var rise := lab.position + Vector2(randf_range(-12.0, 12.0), -52.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position", rise, 0.55)
	tw.tween_property(lab, "scale", Vector2(1.12, 1.12), 0.12)
	tw.tween_property(lab, "modulate:a", 0.0, 0.4).set_delay(0.2)
	tw.chain().tween_callback(lab.queue_free)


func _grant_skill_mastery(skill_id: String) -> void:
	if skill_id == "":
		skill_id = "slash"
	var tree := get_tree()
	if tree == null:
		return
	var sk: Node = tree.root.get_node_or_null("SkillSystem")
	if sk == null or not sk.has_method("add_mastery"):
		return
	var amt: int = 1 + (randi() % 3)  ## 1～3
	var res: Dictionary = sk.call("add_mastery", skill_id, amt)
	if res.is_empty():
		return
	if bool(res.get("leveled", false)):
		_append_log("[color=#fc8]招式體悟！%s[/color]" % str(res.get("name", "")))
		_spawn_float("player", "體悟", Color(1.0, 0.85, 0.45))


func _try_wheat_save(hp_after: int) -> void:
	if hp_after > 0:
		return
	if not GameState.has_wheat_stalk or GameState.wheat_stalk_broken:
		return
	var p: BattleUnit = sim.get_unit("player")
	if p == null:
		return
	p.hp = 1
	p.state = BattleUnit.State.IDLE
	p.atb = 0.0
	sim.finished = false
	GameState.has_wheat_stalk = false
	GameState.wheat_stalk_broken = true
	GameState.set_flag("c0_wheat_saved", true)
	_append_log("[color=#fc8]麥穗給的麥稈碎裂了。你撐過了這一擊。[/color]")
	_flash(player_body, Color(1, 0.85, 0.4))
	_shake = 0.2


func _on_end(won: bool) -> void:
	_ended = true
	_release_hp_authority()
	countdown.visible = false
	countdown_sub.visible = false
	AudioManager.battle_end(won)
	if won:
		banner.text = "勝　利"
		banner.modulate = Color(1, 1, 1, 1)
		_append_log("[color=#6f6]勝利！[/color]")
		var p: BattleUnit = sim.get_unit("player")
		if p:
			GameState.hp = maxi(1, p.hp)
		if _mode == "wolf":
			GameState.set_flag("c0_first_battle", true)
			if Engine.get_main_loop() is SceneTree:
				var sk0: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SkillSystem")
				if sk0 and sk0.has_method("grant_c0_slash"):
					sk0.call("grant_c0_slash")
			if GameState.skill_slash_lv < 1:
				GameState.skill_slash_lv = 1
			GameState.add_gold(15)
			_award_xp(20)
		elif _mode == "leo":
			GameState.set_flag("boss.leo_cleared", true)
			if Engine.get_main_loop() is SceneTree:
				var sk1: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SkillSystem")
				if sk1 and sk1.has_method("grant_leo_insight"):
					sk1.call("grant_leo_insight")
			GameState.add_gold(300)
			_award_xp(200)
			GameState.add_stardust(4)
		elif _mode == "fog":
			GameState.set_flag("boss.white_fog_cleared", true)
			GameState.add_gold(250)
			_award_xp(180)
			GameState.add_stardust(3)
		elif _mode == "demon":
			GameState.set_flag("boss.demon_cleared", true)
			GameState.add_gold(400)
			_award_xp(300)
			GameState.add_stardust(6)
			if sim and sim.refuse_count >= 3:
				GameState.set_flag("c6_refuse_all", true)
		elif _mode == "abo":
			GameState.set_flag("boss.abo_cleared", true)
			GameState.add_gold(280)
			_award_xp(200)
			GameState.add_stardust(3)
			if sim and sim.abo_break_count >= 2:
				GameState.set_flag("c3_abo_perfect", true)
		elif _mode == "falcon":
			GameState.set_flag("boss.shadowwind_cleared", true)
			GameState.add_gold(260)
			_award_xp(190)
			GameState.add_stardust(3)
		elif _mode == "boar":
			GameState.set_flag("boss.stonefist_cleared", true)
			GameState.add_gold(270)
			_award_xp(195)
			GameState.add_stardust(3)
		elif _mode in ["wrath", "tide", "statue", "chrono"]:
			_grant_rift_rewards(_mode)
			GameState.add_stardust(2)
		elif _mode == "wolf":
			GameState.add_stardust(1)
	else:
		banner.text = "敗　北"
		banner.modulate = Color(1, 1, 1, 1)
		_append_log("[color=#f66]敗北……[/color]")
		GameState.hp = maxi(1, GameState.max_hp / 2)
	banner.visible = true
	await get_tree().create_timer(1.6).timeout
	battle_finished.emit(won)


func _append_log(t: String) -> void:
	log_label.append_text(t + "\n")


func _hazard_name(kind: String) -> String:
	match kind:
		"fire_ring":
			return "火圈"
		"time_clock":
			return "控時時鐘"
		"lightning":
			return "導雷"
		"wind_cut":
			return "風切"
		"rockfall":
			return "落岩"
		"bomb":
			return "時牢炸彈"
		_:
			return kind


func _on_btn_flee_pressed() -> void:
	if _mode in ["leo", "fog", "demon", "abo", "falcon", "boar", "wrath", "tide", "statue", "chrono"]:
		_append_log("無法逃離此戰。")
		return
	_ended = true
	battle_finished.emit(false)


func _award_xp(n: int) -> void:
	if n <= 0:
		return
	var r: Dictionary = GameState.add_xp(n)
	var g := int(r.get("gained", n))
	_append_log("[color=#9cf]經驗 +%d（%d／%d · Lv%d）[/color]" % [g, GameState.xp, GameState.xp_to_next(), GameState.level])
	for m in r.get("messages", []):
		_append_log("[color=#fc8]%s[/color]" % str(m))


func _grant_rift_rewards(mode: String) -> void:
	var flag_map: Dictionary = {
		"wrath": "postgame.wrath_cleared",
		"tide": "postgame.tide_cleared",
		"statue": "postgame.statue_cleared",
		"chrono": "postgame.chrono_cleared",
	}
	var flag_key: String = str(flag_map.get(mode, ""))
	if flag_key != "":
		GameState.set_flag(flag_key, true)
	var wins := int(GameState.get_flag("postgame.rift_wins", 0)) + 1
	GameState.set_flag("postgame.rift_wins", wins)
	if wins >= 5:
		GameState.set_flag("title.rift_walker", true)

	var mult: Dictionary = RiftSchedule.reward_mult(mode)
	## 經濟 0.15：裂縫基準 200→160（可重複／練習局仍 ×0.35），避免終局刷金溢出
	var gold_n: int = int(round(160.0 * float(mult.get("gold", 1.0))))
	var xp_n: int = int(round(150.0 * float(mult.get("xp", 1.0))))
	if gold_n > 0:
		GameState.add_gold(gold_n)
	if xp_n > 0:
		_award_xp(xp_n)
	if not bool(mult.get("practice", false)):
		GameState.set_flag("item.rift_ember", true)
	var first := "postgame.%s_first_bonus" % mode
	if bool(mult.get("first_bonus", true)) and not GameState.has_flag(first):
		GameState.atk += 1
		GameState.set_flag(first, true)
	if bool(mult.get("practice", false)):
		_append_log("[color=#aaa]練習局：金幣×0.35，無經驗／首通加成[/color]")
	elif bool(mult.get("featured", false)):
		_append_log("[color=#fc8]本週焦點：金幣×1.5 · 經驗×1.25[/color]")


## autoload 之間用絕對路徑 get_node 在某些啟動時機會噴錯，一律從 SceneTree.root 走
func _telemetry_node() -> Node:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		return (t as SceneTree).root.get_node_or_null("Telemetry")
	return null
