extends RefCounted
class_name NpcLines
## NPC 多階段台詞：依 flag／周目回傳不同句組。

static func greybeard() -> Array:
	if GameState.ng_plus > 0 and GameState.has_flag("boss.leo_cleared"):
		return [
			{"speaker": "灰鬚", "text": "又一次。腳印疊在舊路上——你還記得第一次拔劍拔了三次嗎？"},
			{"speaker": "灰鬚", "text": "迴響裡的獅子更躁。格擋別鬆。"},
		]
	if GameState.has_flag("boss.demon_cleared"):
		return [
			{"speaker": "灰鬚", "text": "塔塌了一角。你卻還站著。……哼。進來喝茶。"},
			{"speaker": "灰鬚", "text": "招式若還要長，旅途養招還在。"},
		]
	if GameState.has_flag("boss.leo_cleared") and GameState.has_flag("boss.white_fog_cleared"):
		return [
			{"speaker": "灰鬚", "text": "霧也看破了？眼睛比劍先長。"},
			{"speaker": "灰鬚", "text": "塔在等。別學把焰當柴的傻子。"},
		]
	if GameState.has_flag("boss.leo_cleared"):
		return [
			{"speaker": "灰鬚", "text": "（背影）門為你開。"},
			{"speaker": "灰鬚", "text": "東南有霧。信會慢——人別慢。"},
		]
	if GameState.has_flag("c1_forged"):
		return [
			{"speaker": "灰鬚", "text": "刃有了。內殿的獅子不聽人話，聽刀。"},
			{"speaker": "灰鬚", "text": "你不是去證明你強。你是去讓它想起該守什麼。"},
		]
	return [
		{"speaker": "灰鬚", "text": "聖獅在內殿。你若不是送死，就先把劍養好。"},
		{"speaker": "灰鬚", "text": "招式不是看的。打中了才會長。"},
	]


static func ding() -> Array:
	if GameState.ng_plus > 0:
		return [
			{"speaker": "釘釘", "text": "又來？刃上的灰……你沾焰了？算了，我養器，不養命。"},
		]
	if GameState.has_flag("boss.demon_cleared"):
		return [
			{"speaker": "釘釘", "text": "鐵還在就好。——別再讓我認第二次葬過的鐵。"},
		]
	if GameState.has_flag("side.ding_debt_done"):
		return [
			{"speaker": "釘釘", "text": "舊債還了。爐火……比以前穩一點。"},
			{"speaker": "釘釘", "text": "升階還是要錢。感情不能當炭燒。"},
		]
	if GameState.has_flag("item.broken_blade"):
		return [
			{"speaker": "釘釘", "text": "那斷口……你從演武場撿的？給我。"},
		]
	if GameState.has_flag("side.ding_debt_asked"):
		return [
			{"speaker": "釘釘", "text": "斷劍還在演武場的武器架附近。別跟我說你迷路。"},
		]
	if GameState.has_flag("c1_forged"):
		return [
			{"speaker": "釘釘", "text": "微末之刃。名字難聽，好用就行。要升階拿金幣來。"},
			{"speaker": "釘釘", "text": "……有空的話，演武場那邊，幫我看一眼。舊債。"},
		]
	return [
		{"speaker": "釘釘", "text": "門開著不是讓兔子觀光的。"},
	]


static func maisui_village() -> Array:
	if GameState.ng_plus > 0:
		return [
			{"speaker": "麥穗", "text": "……你又站在灰裡了。這次也記得跑。"},
			{"speaker": "麥穗", "text": "信我寫過。氣味還在。走。"},
		]
	if GameState.has_flag("c2_wheat_letter"):
		return [
			{"speaker": "麥穗", "text": "（幻影般的記憶）我還在。不是因為預言。"},
		]
	return []  ## 走主線對話


static func fog_hide() -> Array:
	if GameState.ng_plus > 0 and GameState.has_flag("boss.white_fog_cleared"):
		return [
			{"speaker": "霧隱", "text": "二周目的霧更會笑。本體發白——別急。"},
		]
	if GameState.has_flag("side.fog_letter_done"):
		return [
			{"speaker": "霧隱", "text": "真信送達了。假的霧少了一層。"},
			{"speaker": "霧隱", "text": "你的眼睛……比第一次好用。"},
		]
	if GameState.has_flag("item.true_letter"):
		return [
			{"speaker": "霧隱", "text": "信在你身上。岔路的行商驛站——把真的交出去。"},
		]
	if GameState.has_flag("boss.white_fog_cleared"):
		return [
			{"speaker": "霧隱", "text": "霧散了。你的眼睛，還算能用。"},
			{"speaker": "霧隱", "text": "……還有一封真信。假的太多，真的要親手送。"},
		]
	if GameState.has_flag("c2_wheat_letter"):
		return [
			{"speaker": "霧隱", "text": "打影子，影子笑你。看破綻——刃抬起的那一幀，才是真的。"},
			{"speaker": "霧隱", "text": "幻廊在村東。白霧等你迷路。"},
		]
	return [
		{"speaker": "霧隱", "text": "先去客棧。有人把信一路轉到這裡……慢了。"},
	]


static func silk() -> Array:
	## 絲絨：書吏／典籍（騎士堡內城檔案）
	if GameState.has_flag("boss.demon_cleared"):
		return [
			{"speaker": "絲絨", "text": "塔的紀錄……我補了半頁。『至弱者拒絕了強。』"},
			{"speaker": "絲絨", "text": "預言寫錯了嗎？不——是被讀錯了。"},
		]
	if GameState.has_flag("boss.leo_cleared") and GameState.has_flag("c2_wheat_letter"):
		return [
			{"speaker": "絲絨", "text": "黑焰以野心為食。麥穗的字……比典籍真。"},
			{"speaker": "絲絨", "text": "民間版說：第一位至弱者進了塔。官方版刪了後半句。"},
		]
	if GameState.has_flag("c1_forged"):
		return [
			{"speaker": "絲絨", "text": "微末之刃？釘釘還肯認鐵，世界就還沒完。"},
			{"speaker": "絲絨", "text": "檔案庫門後：黑焰三說、騎士團解散令、以及一張被撕掉的『至弱』頁。"},
		]
	return [
		{"speaker": "絲絨", "text": "兔子？來找書的少，來找藉口的多。"},
		{"speaker": "絲絨", "text": "預言寫『至弱者至塔』。別急著對號入座——先讀完矛盾處。"},
	]


static func ronin() -> Array:
	if GameState.has_flag("side.ronin_spared"):
		return [
			{"speaker": "黑焰浪人", "text": "……刃收了。路還長。別學我把焰當柴。"},
		]
	if GameState.has_flag("side.ronin_defeated"):
		return [
			{"speaker": "黑焰浪人", "text": "（倒在地上）……強……又如何……"},
		]
	return [
		{"speaker": "黑焰浪人", "text": "站住。你也是來『變強』的？"},
		{"speaker": "黑焰浪人", "text": "黑焰教我：心一軟，就被吃乾淨。我不會再軟。"},
	]


static func acha() -> Array:
	if GameState.has_flag("boss.abo_cleared"):
		return [
			{"speaker": "阿茶", "text": "（笑著揉眼睛）他醒了一點……是你讓他想起茶還熱著。"},
			{"speaker": "阿茶", "text": "去塔之前……記得回來喝一口。"},
		]
	return [
		{"speaker": "阿茶", "text": "別怕。宗師架勢很硬——用拳去撞，灌滿破防，才打得動。"},
		{"speaker": "阿茶", "text": "技能比普攻更快灌滿那條破防條。"},
	]


static func star() -> Array:
	if GameState.ng_plus > 0:
		return [
			{"speaker": "星讀", "text": "迴響層的星盤會抖。足迹疊厚了——觀星更準，也更貪。"},
		]
	if GameState.has_flag("side.ronin_spared"):
		return [
			{"speaker": "星讀", "text": "岔路上有兩道足迹分開又並肩——有人沒把焰吞到底。"},
		]
	if GameState.has_flag("c1_soul_intro"):
		return [
			{"speaker": "星讀", "text": "足迹會再交疊。星屑夠了就來觀星。"},
		]
	return []


static func wind_ear_idle() -> Array:
	if GameState.has_flag("boss.shadowwind_cleared"):
		return [
			{"speaker": "風耳", "text": "風肯停了。你的耳朵……比弓還準。"},
			{"speaker": "風耳", "text": "海岸還在吼。去或不去，看你。"},
		]
	if GameState.has_flag("c4_entered"):
		return [
			{"speaker": "風耳", "text": "疾影不會等你。但真身會——短短一瞬。"},
			{"speaker": "風耳", "text": "別追殘影。等停拍，再射。"},
		]
	return [
		{"speaker": "風耳", "text": "森林認腳步，不認名。你走得慢——很好。"},
	]


static func tide_roar_idle() -> Array:
	if GameState.has_flag("boss.stonefist_cleared"):
		return [
			{"speaker": "潮吼", "text": "哈哈哈！力氣有方向了。去塔吧！"},
		]
	if GameState.has_flag("c5_entered"):
		return [
			{"speaker": "潮吼", "text": "衝過來的時候別逃——迎上去。對撞。"},
			{"speaker": "潮吼", "text": "岩甲一層一層剝。落岩亮區，蹲進去。"},
		]
	return [
		{"speaker": "潮吼", "text": "岸風鹹。你的刃……還能再響一次嗎？"},
	]
