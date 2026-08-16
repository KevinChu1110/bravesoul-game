extends RefCounted
class_name StoryAnchors
## 主線錨點：N8 麥穗信等 flag 判斷與純對話資料。
##
## 進村強制讀信／客棧重讀共用同一正文；main 只負責 _play_dialog 與存檔／音效。

const FLAG_WHEAT_LETTER := "c2_wheat_letter"


static func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameState")
	return null


static func has_wheat_letter() -> bool:
	var gs := _gs()
	return gs != null and bool(gs.has_flag(FLAG_WHEAT_LETTER))


static func mark_wheat_letter_read() -> void:
	var gs := _gs()
	if gs:
		gs.set_flag(FLAG_WHEAT_LETTER, true)


## 開場句依是否仍持有／已斷麥稈分支
static func wheat_letter_open_line() -> String:
	var gs := _gs()
	if gs != null and (gs.wheat_stalk_broken or gs.has_wheat_stalk):
		return "麥穗的稈裡捲著一張薄紙。字跡被捏過。"
	if gs != null:
		return "霧隱將一封遲到的信放到桌上：「有人託人一站一站轉來。慢了。」"
	return "稈／行囊縫裡……有一張薄紙。字跡被捏過。"


## N8 延遲的信正文（進村強制／客棧互動共用）
static func wheat_letter_lines() -> Array:
	return [
		{"speaker": "系統", "text": wheat_letter_open_line()},
		{"speaker": "信", "text": "我還在。"},
		{"speaker": "信", "text": "不是因為預言，"},
		{"speaker": "信", "text": "是因為你還沒回來。"},
		{"speaker": "信", "text": "——麥穗"},
		{"speaker": "內心", "text": "……還在。那我就還能走。"},
		{"speaker": "日誌", "text": "麥穗的字。比預言輕，比劍重。"},
	]
