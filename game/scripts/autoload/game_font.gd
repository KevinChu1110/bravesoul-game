extends Node
## 全域字型：把 Noto Sans CJK 掛成專案預設，並串好語言後備。
## Autoload：GameFont（要排在 UI 之前）
##
## 為什麼需要：Godot 內建的預設字型是 Open Sans，**一個漢字都沒有**。
## 中文之所以看得到，是靠 macOS 在算繪時的系統字型後備 —— 換到沒裝 CJK 字型的
## Linux 就是整片豆腐，而我們有出 Linux 版。加了日／韓之後更明顯：
## 一台機器可能有中文字型卻沒有諺文。
##
## 現代的 Noto Sans TC／SC／KR 是**分語言子集**，不是舊的泛 CJK 單檔 ——
## 實測 TC 有假名（日文 0 缺字）但缺諺文與部分簡體字形。所以要串後備鏈。

const BASE := "res://assets/fonts/NotoSansTC-Regular.otf"
## 順序有意義：先補諺文，再補簡體字形
const FALLBACKS := [
	"res://assets/fonts/NotoSansKR-Regular.otf",
	"res://assets/fonts/NotoSansSC-Regular.otf",
]


func _ready() -> void:
	var f := _build()
	if f == null:
		push_warning("GameFont：字型載不到，會退回引擎預設（非拉丁字可能變豆腐）")
		return
	var theme := ThemeDB.get_default_theme()
	if theme != null:
		theme.default_font = f


func _build() -> FontFile:
	var base := FontFile.new()
	if base.load_dynamic_font(BASE) != OK:
		return null
	var chain: Array[Font] = []
	for p in FALLBACKS:
		var fb := FontFile.new()
		if fb.load_dynamic_font(p) == OK:
			chain.append(fb)
	base.fallbacks = chain
	return base
