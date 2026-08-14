extends Node
## 黑焰裂縫：週焦點輪替 + 每日有獎次數（存於 GameState.flags）
## Autoload：RiftSchedule

const MODES: Array[String] = ["wrath", "tide", "statue", "chrono"]
const DAILY_REWARD_CAP := 3

const DISPLAY: Dictionary = {
	"wrath": "怒火",
	"tide": "潮噬",
	"statue": "石像",
	"chrono": "時牢",
}

const CLEARED_FLAG: Dictionary = {
	"wrath": "postgame.wrath_cleared",
	"tide": "postgame.tide_cleared",
	"statue": "postgame.statue_cleared",
	"chrono": "postgame.chrono_cleared",
}


func mode_name(mode: String) -> String:
	return str(DISPLAY.get(mode, mode))


func today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


## 以 UTC 日序 / 7 當「週」索引，四套輪流
func week_index() -> int:
	var day: int = int(Time.get_unix_time_from_system() / 86400.0)
	if day < 0:
		day = 0
	return int(day / 7)


func featured_mode() -> String:
	var idx: int = week_index() % MODES.size()
	return MODES[idx]


func featured_name() -> String:
	return mode_name(featured_mode())


func is_featured(mode: String) -> bool:
	return mode == featured_mode()


func refresh_day() -> void:
	var t: String = today_key()
	if str(GameState.get_flag("postgame.rift_day", "")) != t:
		GameState.set_flag("postgame.rift_day", t)
		GameState.set_flag("postgame.rift_day_used", 0)


func daily_used() -> int:
	refresh_day()
	return int(GameState.get_flag("postgame.rift_day_used", 0))


func daily_left() -> int:
	return maxi(0, DAILY_REWARD_CAP - daily_used())


## 開戰時呼叫：消耗 1 次有獎名額；回傳是否有獎（false＝練習局）
func consume_attempt() -> bool:
	refresh_day()
	var used: int = daily_used()
	if used < DAILY_REWARD_CAP:
		GameState.set_flag("postgame.rift_day_used", used + 1)
		GameState.set_flag("postgame.rift_attempt_rewarded", true)
		return true
	GameState.set_flag("postgame.rift_attempt_rewarded", false)
	return false


func current_attempt_rewarded() -> bool:
	return bool(GameState.get_flag("postgame.rift_attempt_rewarded", true))


func clear_attempt_flag() -> void:
	if GameState.flags.has("postgame.rift_attempt_rewarded"):
		GameState.flags.erase("postgame.rift_attempt_rewarded")


## 結算倍率：有獎=1；本週焦點再 ×1.5 金／×1.25 經驗；練習=0.35 金、0 經驗
func reward_mult(mode: String) -> Dictionary:
	var rewarded: bool = current_attempt_rewarded()
	if not rewarded:
		return {"gold": 0.35, "xp": 0.0, "first_bonus": false, "practice": true, "featured": false}
	var g := 1.0
	var x := 1.0
	var feat := is_featured(mode)
	if feat:
		g = 1.5
		x = 1.25
	return {"gold": g, "xp": x, "first_bonus": true, "practice": false, "featured": feat}


func hub_status_text() -> String:
	refresh_day()
	var feat: String = featured_name()
	var left: int = daily_left()
	var used: int = daily_used()
	var wins: int = int(GameState.get_flag("postgame.rift_wins", 0))
	var title_s := ""
	if GameState.has_flag("title.rift_walker"):
		title_s = "\n稱號：裂縫行者"
	var marks := ""
	for m in MODES:
		var mark := "✓" if GameState.has_flag(str(CLEARED_FLAG.get(m, ""))) else "·"
		var star := "★" if is_featured(m) else " "
		marks += "%s%s%s　" % [star, mark, mode_name(m)]
	return "本週焦點：★%s（有獎時金幣×1.5）\n今日有獎：%d／%d 已用，剩餘 %d\n（用盡後仍可練習，獎勵大減）\n\n勝場：%d%s\n%s" % [
		feat, used, DAILY_REWARD_CAP, left, wins, title_s, marks.strip_edges()
	]


func button_label(mode: String) -> String:
	var base: String = mode_name(mode)
	var prefix := "★" if is_featured(mode) else ""
	var done := "✓" if GameState.has_flag(str(CLEARED_FLAG.get(mode, ""))) else ""
	return "%s%s%s" % [prefix, base, (" " + done) if done != "" else ""]
