extends Node
## 離線「公會／聯盟」社交層：貢獻、位階、佈告、週目標。
## 非連線；體感是單機裡的盟約社群（NPC 盟友留言）。

const FLAG_JOINED := "guild.joined"
const FLAG_CONTRIB := "guild.contrib"
const FLAG_NAME := "guild.name"
const FLAG_BOARD := "guild.board_idx"

const ContentLoc := preload("res://scripts/systems/content_loc.gd")
const GUILD_TEXT_FIELDS: PackedStringArray = ["name", "motto"]

## 公會名與箴言在非繁中會被 ContentLoc 換掉。要顯示給玩家的地方走 guilds()，
## 內部判定用 GUILDS 就好。
func guilds() -> Array:
	return ContentLoc.apply_all("guild", GUILDS, GUILD_TEXT_FIELDS)


const GUILDS: Array[Dictionary] = [
	{"id": "ash", "name": "灰燼旅團", "motto": "不慕強權，只護一息火種。", "color": "#c97"},
	{"id": "mist", "name": "薄霧書會", "motto": "真假同色時，我們互為眼睛。", "color": "#8ab"},
	{"id": "tide", "name": "岸火同盟", "motto": "力氣要有方向。", "color": "#6ac"},
]

const BOARD: Array[String] = [
	"【灰鬚】別在裂縫裡逞能。活著回來，才算貢獻。",
	"【星讀】星屑可以交公庫——別全砸在賭博心態上。",
	"【霧隱】新進的兔子：先讀完信，再進幻廊。",
	"【阿茶】道場茶席永遠有位子。先喘口氣。",
	"【釘釘】缺鐵就去荒野晃。別來跟我哭窮。",
	"【斷頁】卷上寫至弱。盟約寫的是——一起走完。",
	"【小芽】我練木劍一百下了！……大概。",
	"【潮吼】力氣若沒方向，只是浪打空岸！",
	"【風耳】停拍那一瞬，記得數自己的呼吸。",
	"【系統】本週盟約目標：裂縫勝場＋主線推進。貢獻可換補給。",
]


var guild_id: String = ""
var contrib: int = 0


func _ready() -> void:
	_load_from_state()


func _load_from_state() -> void:
	guild_id = str(GameState.get_flag(FLAG_NAME, ""))
	## 存的是 guild id
	if guild_id == "" and GameState.has_flag(FLAG_JOINED):
		guild_id = str(GameState.get_flag("guild.id", "ash"))
	else:
		guild_id = str(GameState.get_flag("guild.id", guild_id if guild_id != "" else ""))
	if guild_id == "" and GameState.has_flag(FLAG_JOINED):
		guild_id = "ash"
	contrib = int(GameState.get_flag(FLAG_CONTRIB, 0))


func is_joined() -> bool:
	return GameState.has_flag(FLAG_JOINED) and guild_id != ""


func join(gid: String) -> Dictionary:
	var found: Dictionary = {}
	for g in GUILDS:
		if str(g.get("id", "")) == gid:
			found = g
			break
	if found.is_empty():
		return {"ok": false, "msg": "找不到這個盟約。"}
	guild_id = gid
	GameState.set_flag(FLAG_JOINED, true)
	GameState.set_flag("guild.id", gid)
	GameState.set_flag(FLAG_NAME, str(found.get("name", gid)))
	if contrib <= 0:
		contrib = 10
		GameState.set_flag(FLAG_CONTRIB, contrib)
	SaveManager.save_game()
	return {"ok": true, "msg": "你加入了【%s】。\n「%s」" % [found.get("name", gid), found.get("motto", "")]}


func add_contrib(n: int) -> void:
	if not is_joined():
		return
	contrib = maxi(0, contrib + n)
	GameState.set_flag(FLAG_CONTRIB, contrib)
	## 不每次存檔，由呼叫端存


func rank_name() -> String:
	if contrib >= 300:
		return "盟主候補"
	if contrib >= 150:
		return "資深旅者"
	if contrib >= 60:
		return "正式成員"
	if contrib >= 10:
		return "見習"
	return "訪客"


func board_line() -> String:
	var idx := int(GameState.get_flag(FLAG_BOARD, 0))
	var line := BOARD[idx % BOARD.size()]
	## NG+ 額外留言
	if GameState.ng_plus > 0 and idx % 3 == 0:
		line = "【迴響】二周目的你，腳印疊在舊路上——盟約記得。"
	return line


func next_board() -> String:
	var idx := int(GameState.get_flag(FLAG_BOARD, 0)) + 1
	GameState.set_flag(FLAG_BOARD, idx)
	return board_line()


func status_bbcode() -> String:
	_load_from_state()
	if not is_joined():
		var s := "[b]尚未加入盟約[/b]\n選一個理念相近的公會，解鎖佈告與貢獻補給。\n\n"
		for g in GUILDS:
			s += "· %s\n  %s\n" % [g.get("name", ""), g.get("motto", "")]
		return s
	var gname := str(GameState.get_flag(FLAG_NAME, guild_id))
	return "[b]%s[/b]  ·  %s\n貢獻 %d　位階：%s\n\n佈告：\n%s" % [
		gname, rank_name(), contrib, rank_name(), board_line()
	]


func can_shop() -> bool:
	return is_joined() and contrib >= 30


func buy_supply() -> Dictionary:
	## 花 30 貢獻換補給
	_load_from_state()
	if not is_joined():
		return {"ok": false, "msg": "尚未加入盟約。"}
	if contrib < 30:
		return {"ok": false, "msg": "貢獻不足 30。"}
	contrib -= 30
	GameState.set_flag(FLAG_CONTRIB, contrib)
	GameState.add_gold(40)
	GameState.add_stardust(2)
	GameState.hp = GameState.effective_max_hp()
	SaveManager.save_game()
	return {"ok": true, "msg": "公庫補給：金 40 · 星屑 2 · 傷勢回穩。貢獻 −30。"}
