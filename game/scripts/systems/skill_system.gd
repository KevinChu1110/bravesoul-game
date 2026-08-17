extends Node
## 技能（招）：習得 · 熟練 · 升級。旅途養招，與器／魂正交。
## 戰鬥以怒氣滿自動放出「當前優先技能」；UI 看列表與下級預覽。
##
## 設計（對齊原版 Brave Soul）：
##   6 職業 × 每職兩套**對等**武器系統（不是主副武器）。
##   遊俠＝弓＋火槍、忍者＝匕首＋鏢、騎士＝劍＋槍……
##   選任一武器 → 開該職業兩套武器的技能樹；出招優先用**當前裝備／流派**那條線。

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const MAX_LV := 3

## 熟練門檻：升到該級所需累計熟練（自上一級起算）
const MASTERY_NEED := {
	2: 30,
	3: 80,
}

## 6 職業 → 兩套對等武器系統（順序不代表主副）
const PROFESSION_WEAPONS := {
	"knight": ["sword", "spear"],
	"viking": ["axe", "hammer"],
	"ninja": ["dagger", "dart"],
	"monk": ["fist", "claw"],
	"mage": ["magic", "crystal"],
	"ranger": ["bow", "gun"],
}

const PROFESSION_NAME := {
	"knight": "騎士",
	"viking": "維京",
	"ninja": "忍者",
	"monk": "武鬥家",
	"mage": "法師",
	"ranger": "遊俠",
}

## 武器 id → 該線「起手／簽名」招（選此武器系統時強制習得）
const CLASS_SIGNATURE := {
	"sword": "slash",
	"spear": "line_thrust",
	"axe": "axe_split",
	"hammer": "stone_crush",
	"dagger": "quick_stab",
	"dart": "mist_needle",
	"fist": "combo_fist",
	"claw": "claw_rake",
	"magic": "magic_bolt",
	"crystal": "shard_bolt",
	"bow": "quick_shot",
	"gun": "powder_shot",
	## 舊 id 相容
	"soul": "magic_bolt",
	"iron": "stone_crush",
}

## 舊簽名 id → 仍保留在目錄（相容舊存檔／測試）
const LEGACY_SIGNATURE_ALIAS := {
	"blade_dance": "sword",
	"wind_arrow": "bow",
	"star_pierce": "magic",
	"pressure_fist": "fist",
	"heavy_cleave": "axe",
	"iron_guard": "hammer",
	"prism_ward": "crystal",
}

## 目錄裡要翻的欄位（其餘是數值與 id，不能動）
const SKILL_TEXT_FIELDS: PackedStringArray = ["name", "desc", "lv2", "lv3", "unlock_hint"]

## 完整技能目錄：每武器線 4 招（Lv1 / 7 / 13 / 16）＋少量簽名保留
## MULTI 以等效倍率近似（戰鬥引擎暫只支援單段 mult / heal）
const CATALOG: Array[Dictionary] = [
	# ── 騎士 · 劍 ──
	{
		"id": "slash",
		"name": "橫斬",
		"line": "sword",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 1.8,
		"priority": 10,
		"req_level": 1,
		"desc": "基礎劍技。怒氣滿時自動使出。旅途的第一招。",
		"lv2": "倍率↑，出手更俐落。",
		"lv3": "附帶鋒勢：倍率再升。",
		"unlock_hint": "劍系起手 · 或初戰灰鬚指點",
	},
	{
		"id": "counter_strike",
		"name": "反戈一擊",
		"line": "sword",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 2.4,
		"priority": 22,
		"req_level": 7,
		"desc": "長劍初期強招。吃一記後反咬。",
		"lv2": "反擊更重。",
		"lv3": "反戈尾勁延長。",
		"unlock_hint": "雷歐後 · 或劍系 Lv7",
	},
	{
		"id": "emergency_heal",
		"name": "緊急恢復",
		"line": "sword",
		"profession": "knight",
		"kind": "heal",
		"base_mult": 0.0,
		"heal_pct": 0.30,
		"priority": 5,
		"req_level": 13,
		"desc": "★ 13 級任務技。吐一口氣回血；危急時自動優先。",
		"lv2": "恢復量略增。",
		"lv3": "恢復再增，危機能撐住。",
		"unlock_hint": "C1 鍛刀 · 或劍系 Lv13",
	},
	{
		"id": "thunder_fury",
		"name": "怒雷狂擊",
		"line": "sword",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 2.6,
		"priority": 40,
		"req_level": 16,
		"desc": "★ 16 級暴怒技。滿怒優先的大招。",
		"lv2": "雷勢更強。",
		"lv3": "怒雷尾音延長。",
		"unlock_hint": "擊敗雷歐 · 或劍系 Lv16",
	},
	{
		"id": "blade_dance",
		"name": "連鋒三斬",
		"line": "sword",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 0.7,
		"hits": 3,
		"priority": 28,
		"req_level": 8,
		"desc": "劍道中段：中速連斬，熟練成長快。",
		"lv2": "連鋒更密。",
		"lv3": "三斬尾勁延長。",
		"unlock_hint": "劍系 Lv8",
	},
	# ── 騎士 · 槍 ──
	{
		"id": "line_thrust",
		"name": "一線突刺",
		"line": "spear",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 1.9,
		"priority": 12,
		"req_level": 1,
		"desc": "槍系起手：卡住距離的迎擊一刺。",
		"lv2": "槍線更長。",
		"lv3": "突刺附短暫壓制。",
		"unlock_hint": "槍系起手",
	},
	{
		"id": "phalanx_sweep",
		"name": "方陣橫掃",
		"line": "spear",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 2.3,
		"priority": 24,
		"req_level": 7,
		"desc": "槍桿橫掃半圈，逼退貼身。",
		"lv2": "掃勢更開。",
		"lv3": "橫掃附帶破勢。",
		"unlock_hint": "槍系 Lv7",
	},
	{
		"id": "spiral_pierce",
		"name": "螺旋貫穿",
		"line": "spear",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 2.7,
		"priority": 34,
		"req_level": 13,
		"desc": "★ 槍系任務技。旋轉一刺貫甲。",
		"lv2": "貫穿更深。",
		"lv3": "尾勁延長。",
		"unlock_hint": "槍系 Lv13",
	},
	{
		"id": "sky_lance",
		"name": "天槍落",
		"line": "spear",
		"profession": "knight",
		"kind": "attack",
		"base_mult": 3.2,
		"priority": 42,
		"req_level": 16,
		"desc": "★ 槍系暴怒技。自高處落下的致命一擊。",
		"lv2": "落勢更沉。",
		"lv3": "天槍擊地餘波。",
		"unlock_hint": "槍系 Lv16",
	},
	# ── 維京 · 斧 ──
	{
		"id": "axe_split",
		"name": "劈砍",
		"line": "axe",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 2.0,
		"priority": 12,
		"req_level": 1,
		"desc": "基礎斧技。一記有重量。",
		"lv2": "斧勢更沉。",
		"lv3": "劈砍封頂前一檔。",
		"unlock_hint": "斧系起手",
	},
	{
		"id": "beowulf",
		"name": "貝奧武夫之力",
		"line": "axe",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 2.35,
		"priority": 23,
		"req_level": 7,
		"desc": "斧鎚初期強化一擊——把力量砸進斧刃。",
		"lv2": "力道更兇。",
		"lv3": "怒號延長傷害窗口。",
		"unlock_hint": "斧系 Lv7",
	},
	{
		"id": "def_break",
		"name": "防禦崩壞",
		"line": "axe",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 2.5,
		"priority": 33,
		"req_level": 13,
		"desc": "★ 13 級任務技。破敵防禦的一擊。",
		"lv2": "破防更深。",
		"lv3": "崩壞餘波再抬傷。",
		"unlock_hint": "斧系 Lv13",
	},
	{
		"id": "doom_strike",
		"name": "滅世一擊",
		"line": "axe",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 3.0,
		"priority": 41,
		"req_level": 16,
		"desc": "★ 16 級暴怒技。慢、重、痛（人品技風味）。",
		"lv2": "滅勢更沉。",
		"lv3": "一擊封頂前一檔。",
		"unlock_hint": "斧系 Lv16",
	},
	{
		"id": "heavy_cleave",
		"name": "重斧斷",
		"line": "axe",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 2.45,
		"priority": 30,
		"req_level": 8,
		"desc": "斧道中段簽名：一擊有重量。",
		"lv2": "斧勢更沉。",
		"lv3": "斷勢封頂前一檔。",
		"unlock_hint": "斧系 Lv8",
	},
	# ── 維京 · 鎚 ──
	{
		"id": "stone_crush",
		"name": "碎岩鎚",
		"line": "hammer",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 1.95,
		"priority": 11,
		"req_level": 1,
		"desc": "鎚系起手：砸裂岩石般的一記。",
		"lv2": "砸勢更穩。",
		"lv3": "碎岩餘震。",
		"unlock_hint": "鎚系起手",
	},
	{
		"id": "anvil_slam",
		"name": "鐵砧墜擊",
		"line": "hammer",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 2.4,
		"priority": 25,
		"req_level": 7,
		"desc": "整具鐵砧砸下。慢但壓得死。",
		"lv2": "墜擊更重。",
		"lv3": "地面震波。",
		"unlock_hint": "鎚系 Lv7",
	},
	{
		"id": "iron_guard",
		"name": "鐵骨吐息",
		"line": "hammer",
		"profession": "viking",
		"kind": "heal",
		"base_mult": 0.0,
		"heal_pct": 0.22,
		"priority": 8,
		"req_level": 5,
		"desc": "鎚系穩血：較早觸發的吐息。",
		"lv2": "回血略增。",
		"lv3": "危急門檻更寬。",
		"unlock_hint": "鎚系 · 或 Lv5",
	},
	{
		"id": "earth_breaker",
		"name": "裂地轟",
		"line": "hammer",
		"profession": "viking",
		"kind": "attack",
		"base_mult": 3.1,
		"priority": 40,
		"req_level": 16,
		"desc": "★ 鎚系暴怒技。砸開地面的終結一擊。",
		"lv2": "裂地更寬。",
		"lv3": "轟擊封頂。",
		"unlock_hint": "鎚系 Lv16",
	},
	# ── 忍者 · 匕首 ──
	{
		"id": "quick_stab",
		"name": "急刺",
		"line": "dagger",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 1.5,
		"priority": 14,
		"req_level": 1,
		"desc": "匕首起手：快速一擊。",
		"lv2": "刺勢更快。",
		"lv3": "急刺識破破綻。",
		"unlock_hint": "匕首系起手",
	},
	{
		"id": "fatal_throw",
		"name": "致命投擲",
		"line": "dagger",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 2.5,
		"priority": 26,
		"req_level": 7,
		"desc": "鏢匕初期強招。出手即殺機。",
		"lv2": "投擲更準。",
		"lv3": "致命尾勁。",
		"unlock_hint": "匕首系 Lv7",
	},
	{
		"id": "crystal_tornado",
		"name": "水晶龍捲",
		"line": "dagger",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 0.7,
		"hits": 4,
		"priority": 35,
		"req_level": 13,
		"desc": "★ 13 級任務技。連擊渦旋，四段真傷。",
		"lv2": "龍捲更密。",
		"lv3": "水晶尾刃。",
		"unlock_hint": "匕首系 Lv13",
	},
	{
		"id": "shinra",
		"name": "森羅萬象",
		"line": "dagger",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 0.2,
		"hits": 16,
		"priority": 44,
		"req_level": 16,
		"desc": "★ 16 級暴怒技。萬象連刺十六段。",
		"lv2": "連刺更疾。",
		"lv3": "森羅必中尾勁。",
		"unlock_hint": "匕首系 Lv16",
	},
	# ── 忍者 · 鏢 ──
	{
		"id": "mist_needle",
		"name": "霧影鏢",
		"line": "dart",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 1.7,
		"priority": 15,
		"req_level": 1,
		"desc": "鏢系起手：高速真假同色的一手。",
		"lv2": "鏢影更密。",
		"lv3": "識破破綻，倍率再升。",
		"unlock_hint": "鏢系起手",
	},
	{
		"id": "shadow_fan",
		"name": "影扇鏢",
		"line": "dart",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 0.6,
		"hits": 4,
		"priority": 27,
		"req_level": 7,
		"desc": "一把扇出的影鏢，覆蓋走位死角。",
		"lv2": "扇面更開。",
		"lv3": "影鏢連鎖。",
		"unlock_hint": "鏢系 Lv7",
	},
	{
		"id": "phantom_rain",
		"name": "幻影雨",
		"line": "dart",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 0.55,
		"hits": 5,
		"priority": 36,
		"req_level": 13,
		"desc": "★ 鏢系任務技。真假難辨的鏢雨。",
		"lv2": "雨勢更密。",
		"lv3": "幻影追擊。",
		"unlock_hint": "鏢系 Lv13",
	},
	{
		"id": "thousand_needles",
		"name": "千針葬",
		"line": "dart",
		"profession": "ninja",
		"kind": "attack",
		"base_mult": 0.28,
		"hits": 12,
		"priority": 45,
		"req_level": 16,
		"desc": "★ 鏢系暴怒技。千針齊發的終結。",
		"lv2": "針勢更疾。",
		"lv3": "葬影封頂。",
		"unlock_hint": "鏢系 Lv16",
	},
	# ── 武鬥家 · 拳 ──
	{
		"id": "combo_fist",
		"name": "連環拳",
		"line": "fist",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 0.6,
		"hits": 3,
		"priority": 12,
		"req_level": 1,
		"desc": "三連拳起手，三段打擊。",
		"lv2": "拳勢更密。",
		"lv3": "連環尾勁。",
		"unlock_hint": "拳系起手",
	},
	{
		"id": "hundred_flowers",
		"name": "百花亂舞",
		"line": "fist",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 0.55,
		"hits": 5,
		"priority": 26,
		"req_level": 7,
		"desc": "拳爪初期連段，五段亂舞。",
		"lv2": "亂舞更疾。",
		"lv3": "百花收束一擊。",
		"unlock_hint": "拳系 Lv7",
	},
	{
		"id": "energy_beam",
		"name": "高能光束",
		"line": "fist",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 3.0,
		"priority": 35,
		"req_level": 13,
		"desc": "★ 13 級任務技。體內氣化作光束。",
		"lv2": "光束更聚。",
		"lv3": "高能過載。",
		"unlock_hint": "拳系 Lv13",
	},
	{
		"id": "quake_slash",
		"name": "疾風地裂斬",
		"line": "fist",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 3.6,
		"priority": 43,
		"req_level": 16,
		"desc": "★ 16 級暴怒技。撕裂大地的一擊。",
		"lv2": "地裂更廣。",
		"lv3": "疾風二次衝擊。",
		"unlock_hint": "拳系 Lv16",
	},
	{
		"id": "pressure_fist",
		"name": "破勢拳",
		"line": "fist",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 2.05,
		"priority": 24,
		"req_level": 6,
		"desc": "拳道中段：貼身連打，破對手架勢。",
		"lv2": "拳勢更密。",
		"lv3": "破勢尾勁。",
		"unlock_hint": "拳系 Lv6",
	},
	# ── 武鬥家 · 爪 ──
	{
		"id": "claw_rake",
		"name": "裂爪",
		"line": "claw",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 1.75,
		"priority": 13,
		"req_level": 1,
		"desc": "爪系起手：撕裂防線。",
		"lv2": "爪痕更深。",
		"lv3": "裂爪連帶破勢。",
		"unlock_hint": "爪系起手",
	},
	{
		"id": "tiger_rush",
		"name": "虎撲",
		"line": "claw",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 2.4,
		"priority": 27,
		"req_level": 7,
		"desc": "低姿撲上，雙爪撕開。",
		"lv2": "撲勢更猛。",
		"lv3": "虎吼壓制。",
		"unlock_hint": "爪系 Lv7",
	},
	{
		"id": "blood_petal",
		"name": "血瓣爪",
		"line": "claw",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 0.6,
		"hits": 5,
		"priority": 36,
		"req_level": 13,
		"desc": "★ 爪系任務技。瓣狀爪痕連切。",
		"lv2": "血瓣更密。",
		"lv3": "尾刃延長。",
		"unlock_hint": "爪系 Lv13",
	},
	{
		"id": "void_rend",
		"name": "虛空撕裂",
		"line": "claw",
		"profession": "monk",
		"kind": "attack",
		"base_mult": 3.5,
		"priority": 44,
		"req_level": 16,
		"desc": "★ 爪系暴怒技。撕開空間的終結。",
		"lv2": "撕裂更銳。",
		"lv3": "虛空餘波。",
		"unlock_hint": "爪系 Lv16",
	},
	# ── 法師 · 杖 ──
	{
		"id": "magic_bolt",
		"name": "魔彈",
		"line": "magic",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 1.8,
		"priority": 12,
		"req_level": 1,
		"desc": "基礎魔法彈。",
		"lv2": "魔彈更聚。",
		"lv3": "彈尾星屑。",
		"unlock_hint": "法杖起手",
	},
	{
		"id": "ice_lance",
		"name": "寒冰刺",
		"line": "magic",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 2.4,
		"priority": 25,
		"req_level": 7,
		"desc": "冰錐貫穿。",
		"lv2": "冰刺更長。",
		"lv3": "寒霜減速風味（倍率↑）。",
		"unlock_hint": "法杖 Lv7",
	},
	{
		"id": "fireball",
		"name": "火球術",
		"line": "magic",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 3.0,
		"priority": 34,
		"req_level": 13,
		"desc": "★ 13 級任務技。灼熱火球。",
		"lv2": "火球更大。",
		"lv3": "爆炎餘波。",
		"unlock_hint": "法杖 Lv13",
	},
	{
		"id": "meteor",
		"name": "隕石術",
		"line": "magic",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 3.6,
		"priority": 42,
		"req_level": 16,
		"desc": "★ 16 級暴怒技。隕石轟炸。",
		"lv2": "隕石更沉。",
		"lv3": "墜星連環。",
		"unlock_hint": "法杖 Lv16",
	},
	{
		"id": "star_pierce",
		"name": "星芒穿刺",
		"line": "magic",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 2.2,
		"priority": 28,
		"req_level": 6,
		"desc": "法／星途中段：偏暴擊節奏的一刺。",
		"lv2": "星芒更銳。",
		"lv3": "穿刺附短暫識破。",
		"unlock_hint": "法杖 Lv6 · 或星途",
	},
	# ── 法師 · 水晶 ──
	{
		"id": "shard_bolt",
		"name": "晶屑彈",
		"line": "crystal",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 1.7,
		"priority": 11,
		"req_level": 1,
		"desc": "水晶起手：鋒利晶屑。",
		"lv2": "晶屑更密。",
		"lv3": "彈尾折射。",
		"unlock_hint": "水晶起手",
	},
	{
		"id": "prism_ward",
		"name": "晶盾吐息",
		"line": "crystal",
		"profession": "mage",
		"kind": "heal",
		"base_mult": 0.0,
		"heal_pct": 0.26,
		"priority": 9,
		"req_level": 5,
		"desc": "把護盾織成吐息，穩血活得久。",
		"lv2": "回血略增。",
		"lv3": "危急門檻更寬。",
		"unlock_hint": "水晶 · 或 Lv5",
	},
	{
		"id": "crystal_prison",
		"name": "晶牢",
		"line": "crystal",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 2.6,
		"priority": 32,
		"req_level": 13,
		"desc": "★ 水晶任務技。囚禁後碎裂傷害。",
		"lv2": "牢籠更硬。",
		"lv3": "碎裂擴散。",
		"unlock_hint": "水晶 Lv13",
	},
	{
		"id": "prism_nova",
		"name": "棱鏡新星",
		"line": "crystal",
		"profession": "mage",
		"kind": "attack",
		"base_mult": 3.4,
		"priority": 41,
		"req_level": 16,
		"desc": "★ 水晶暴怒技。折射爆發。",
		"lv2": "新星更亮。",
		"lv3": "七色散裂。",
		"unlock_hint": "水晶 Lv16",
	},
	# ── 遊俠 · 弓 ──
	{
		"id": "quick_shot",
		"name": "速射",
		"line": "bow",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 1.6,
		"priority": 12,
		"req_level": 1,
		"desc": "弓系起手：快速一箭。",
		"lv2": "射速↑。",
		"lv3": "速射連珠。",
		"unlock_hint": "弓系起手",
	},
	{
		"id": "piercing_shot",
		"name": "穿甲箭",
		"line": "bow",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 2.4,
		"priority": 25,
		"req_level": 7,
		"desc": "貫穿箭，專破厚甲。",
		"lv2": "穿甲更深。",
		"lv3": "尾勁貫穿。",
		"unlock_hint": "弓系 Lv7",
	},
	{
		"id": "multi_shot",
		"name": "多重箭",
		"line": "bow",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 0.7,
		"hits": 4,
		"priority": 34,
		"req_level": 13,
		"desc": "★ 13 級任務技。四連真射。",
		"lv2": "箭數更穩。",
		"lv3": "多重追擊。",
		"unlock_hint": "弓系 Lv13",
	},
	{
		"id": "arrow_storm",
		"name": "箭雨風暴",
		"line": "bow",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 0.35,
		"hits": 10,
		"priority": 43,
		"req_level": 16,
		"desc": "★ 16 級暴怒技。十箭蓋地。",
		"lv2": "雨勢更猛。",
		"lv3": "風暴收束。",
		"unlock_hint": "弓系 Lv16",
	},
	{
		"id": "wind_arrow",
		"name": "疾風穿矢",
		"line": "bow",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 2.15,
		"priority": 30,
		"req_level": 6,
		"desc": "弓道中段：遠距一箭，吃暴擊節奏。",
		"lv2": "穿矢更銳。",
		"lv3": "尾勁延長。",
		"unlock_hint": "弓系 Lv6",
	},
	# ── 遊俠 · 火槍 ──
	{
		"id": "powder_shot",
		"name": "火銃點射",
		"line": "gun",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 2.2,
		"priority": 16,
		"req_level": 1,
		"desc": "火槍起手：遠距爆發點射。",
		"lv2": "裝藥更穩。",
		"lv3": "點射尾音延長。",
		"unlock_hint": "火槍起手",
	},
	{
		"id": "double_tap",
		"name": "雙擊",
		"line": "gun",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 2.55,
		"priority": 28,
		"req_level": 7,
		"desc": "兩發連扣，第二發更痛。",
		"lv2": "連扣更穩。",
		"lv3": "雙擊暴心。",
		"unlock_hint": "火槍 Lv7",
	},
	{
		"id": "explosive_round",
		"name": "爆裂彈",
		"line": "gun",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 3.0,
		"priority": 36,
		"req_level": 13,
		"desc": "★ 火槍任務技。著彈爆炸。",
		"lv2": "爆心更大。",
		"lv3": "破片餘波。",
		"unlock_hint": "火槍 Lv13",
	},
	{
		"id": "last_bullet",
		"name": "最後一彈",
		"line": "gun",
		"profession": "ranger",
		"kind": "attack",
		"base_mult": 3.7,
		"priority": 46,
		"req_level": 16,
		"desc": "★ 火槍暴怒技。決生死的一響。",
		"lv2": "膛壓更高。",
		"lv3": "終擊封頂。",
		"unlock_hint": "火槍 Lv16",
	},
]


## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

func _ready() -> void:
	ensure_skill_map()


func ensure_skill_map() -> void:
	## 與舊存檔 skill_slash_lv 對齊（只寫入，不經 get_lv 迴圈）
	if not GameState.skill_data.has("slash") and GameState.skill_slash_lv > 0:
		GameState.skill_data["slash"] = {
			"lv": clampi(GameState.skill_slash_lv, 0, MAX_LV),
			"mastery": 0,
		}
	_sync_legacy_slash()


## 招式名與說明在非繁中會被 ContentLoc 換掉。翻在這裡而不是各個顯示點，
## 是因為 def_of() 是整個目錄唯一的讀取入口 —— 下游怎麼用都吃得到。
func def_of(id: String) -> Dictionary:
	for d in CATALOG:
		if str(d.get("id", "")) == id:
			return ContentLoc.apply("skill", d, SKILL_TEXT_FIELDS)
	return {}


func skill_entry(id: String) -> Dictionary:
	var e: Variant = GameState.skill_data.get(id, null)
	if e is Dictionary:
		return e
	return {"lv": 0, "mastery": 0}


func get_lv(id: String) -> int:
	return clampi(int(skill_entry(id).get("lv", 0)), 0, MAX_LV)


func get_mastery(id: String) -> int:
	return maxi(0, int(skill_entry(id).get("mastery", 0)))


func is_learned(id: String) -> bool:
	return get_lv(id) >= 1


func _set_entry(id: String, lv: int, mastery: int) -> void:
	GameState.skill_data[id] = {
		"lv": clampi(lv, 0, MAX_LV),
		"mastery": maxi(0, mastery),
	}
	if id == "slash":
		_sync_legacy_slash()


func _set_lv(id: String, lv: int) -> void:
	var e: Dictionary = skill_entry(id)
	_set_entry(id, lv, int(e.get("mastery", 0)))


func _sync_legacy_slash() -> void:
	var e: Variant = GameState.skill_data.get("slash", null)
	if e is Dictionary:
		GameState.skill_slash_lv = clampi(int(e.get("lv", 0)), 0, MAX_LV)
	else:
		pass


func display_name(id: String) -> String:
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return id
	var lv: int = get_lv(id)
	if lv <= 0:
		return str(d.get("name", id))
	return "%s · Lv%d" % [str(d.get("name", id)), lv]


func hits_for(id: String) -> int:
	## 多段攻擊段數；單段為 1
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return 1
	return maxi(1, int(d.get("hits", 1)))


func mult_for(id: String) -> float:
	## 單段倍率（多段技為每段倍率）
	var d: Dictionary = def_of(id)
	if d.is_empty() or str(d.get("kind", "")) == "heal":
		return 1.0
	var base: float = float(d.get("base_mult", 1.8))
	var lv: int = maxi(1, get_lv(id))
	return base * (1.0 + 0.12 * float(lv - 1))


func total_mult_for(id: String) -> float:
	## 期望總倍率（段數 × 每段）
	return mult_for(id) * float(hits_for(id))


func heal_pct_for(id: String) -> float:
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return 0.0
	var base: float = float(d.get("heal_pct", 0.30))
	var lv: int = maxi(1, get_lv(id))
	## 每級 +3% 最大血
	return base + 0.03 * float(lv - 1)


func mastery_need_for_next(id: String) -> int:
	var lv: int = get_lv(id)
	if lv <= 0 or lv >= MAX_LV:
		return 0
	return int(MASTERY_NEED.get(lv + 1, 999))


func mastery_progress_line(id: String) -> String:
	var lv: int = get_lv(id)
	if lv <= 0:
		return _t("未習得")
	if lv >= MAX_LV:
		return _t("滿級")
	var need: int = mastery_need_for_next(id)
	var cur: int = get_mastery(id)
	return _t("熟練 %d／%d") % [mini(cur, need), need]


func can_level_up(id: String) -> bool:
	if not is_learned(id):
		return false
	var lv: int = get_lv(id)
	if lv >= MAX_LV:
		return false
	return get_mastery(id) >= mastery_need_for_next(id)


func try_level_up(id: String) -> bool:
	if not can_level_up(id):
		return false
	var e: Dictionary = skill_entry(id)
	var need: int = mastery_need_for_next(id)
	var left: int = maxi(0, int(e.get("mastery", 0)) - need)
	_set_entry(id, get_lv(id) + 1, left)
	return true


## 戰鬥有效命中：+1～3 熟練；滿了不自動升，等 UI／導師體悟（可選自動）
func add_mastery(id: String, amount: int = 2) -> Dictionary:
	## 回傳 {leveled: bool, lv: int, mastery: int, name: String}
	if not is_learned(id):
		return {}
	if get_lv(id) >= MAX_LV:
		return {"leveled": false, "lv": get_lv(id), "mastery": get_mastery(id), "name": display_name(id)}
	var e: Dictionary = skill_entry(id)
	var m: int = int(e.get("mastery", 0)) + maxi(0, amount)
	_set_entry(id, get_lv(id), m)
	var leveled := false
	## 自動升一級（旅途養招，不卡 UI）
	while can_level_up(id):
		try_level_up(id)
		leveled = true
	return {
		"leveled": leveled,
		"lv": get_lv(id),
		"mastery": get_mastery(id),
		"name": display_name(id),
	}


func learn(id: String, min_lv: int = 1) -> bool:
	## 習得；若已學則只抬到 min_lv
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return false
	var cur: int = get_lv(id)
	if cur >= min_lv:
		return false
	_set_lv(id, maxi(cur, min_lv))
	return true


func normalize_weapon_id(class_id: String) -> String:
	var cid := str(class_id)
	match cid:
		"soul":
			return "magic"
		"iron":
			return "hammer"
		_:
			return cid


func _path_id() -> String:
	return normalize_weapon_id(str(GameState.path_style))


func profession_of(weapon_id: String) -> String:
	var wid := normalize_weapon_id(weapon_id)
	for prof in PROFESSION_WEAPONS.keys():
		var weapons: Array = PROFESSION_WEAPONS[prof]
		if wid in weapons:
			return str(prof)
	return ""


func weapons_of_profession(prof: String) -> Array:
	var w: Variant = PROFESSION_WEAPONS.get(prof, [])
	if w is Array:
		return w
	return []


func sibling_weapon(weapon_id: String) -> String:
	## 同職業另一套武器系統（對等，無主副）
	var prof := profession_of(weapon_id)
	if prof == "":
		return ""
	var wid := normalize_weapon_id(weapon_id)
	for w in weapons_of_profession(prof):
		if str(w) != wid:
			return str(w)
	return ""


func _path_is(class_id: String) -> bool:
	return _path_id() == normalize_weapon_id(class_id)


func _profession_is(prof: String) -> bool:
	return profession_of(_path_id()) == prof


func signature_for_class(class_id: String) -> String:
	return str(CLASS_SIGNATURE.get(normalize_weapon_id(class_id), ""))


func skills_for_line(line: String) -> Array:
	var wid := normalize_weapon_id(line)
	var out: Array = []
	for d in CATALOG:
		if str(d.get("line", "")) == wid:
			out.append(str(d.get("id", "")))
	return out


func skills_for_profession(prof: String) -> Array:
	var out: Array = []
	for w in weapons_of_profession(prof):
		for sid in skills_for_line(str(w)):
			out.append(sid)
	return out


func is_unlocked(id: String) -> bool:
	## 可否習得 — 等級／職業武器系統可解鎖，不全綁主線
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return false
	var line := str(d.get("line", ""))
	var prof := str(d.get("profession", profession_of(line)))
	var req := int(d.get("req_level", 1))
	var lv := GameState.level
	var active := _path_id()
	var same_line := active != "" and active == line
	var same_prof := prof != "" and _profession_is(prof)
	var in_prof_tree := same_line or same_prof

	match id:
		"slash":
			## 旅途通用起手；劍系或未選流派也能體悟
			return true
		"counter_strike":
			return GameState.has_flag("boss.leo_cleared") or (in_prof_tree and lv >= 7) or lv >= 12
		"emergency_heal":
			return GameState.has_flag("c1_forged") or GameState.has_flag("c1_entered_city") \
				or (in_prof_tree and lv >= 13) or lv >= 10
		"thunder_fury":
			return GameState.has_flag("boss.leo_cleared") \
				or (same_line and lv >= 16) \
				or (same_prof and lv >= 16) \
				or lv >= 18
		"star_pierce":
			return same_line or same_prof or lv >= 6 or GameState.has_flag("c1_soul_intro")
		"iron_guard", "prism_ward":
			return same_line or same_prof or lv >= 5
		_:
			## 起手技：選了這條武器或同職另一武器即可
			if req <= 1:
				return same_line or same_prof or lv >= 1 and active == ""
			## 中高階：需本職業任一套武器系統 + 等級
			if in_prof_tree and lv >= req:
				return true
			## 無流派時的慢解鎖（探索向）
			if active == "" and lv >= req + 4:
				return true
			## 跨職業極晚才能偷學（保底，不蓋自己路）
			if lv >= req + 8:
				return true
			return false


func try_unlock(id: String) -> bool:
	if is_learned(id):
		return false
	if not is_unlocked(id):
		return false
	return learn(id, 1)


## 戰鬥用：挑當前該放的技能
## 優先序：危急 heal → **當前武器系統**攻擊 → 同職業另一武器系統 → 其他已學
func pick_battle_skill(hp_ratio: float = 1.0) -> Dictionary:
	ensure_skill_map()
	var best_heal: Dictionary = {}
	var best_heal_p := -1
	for d in CATALOG:
		if str(d.get("kind", "")) != "heal":
			continue
		var sid: String = str(d.get("id", ""))
		if not is_learned(sid):
			continue
		var threshold := 0.40
		if sid == "iron_guard":
			threshold = 0.48 if get_lv("iron_guard") >= 3 else 0.44
		elif sid == "prism_ward":
			threshold = 0.46 if get_lv("prism_ward") >= 3 else 0.42
		if hp_ratio > threshold:
			continue
		var prio: int = int(d.get("priority", 0))
		if prio > best_heal_p:
			best_heal_p = prio
			best_heal = d
	if not best_heal.is_empty():
		var hid: String = str(best_heal.get("id", ""))
		return {
			"id": hid,
			"name": str(best_heal.get("name", hid)),
			"kind": "heal",
			"mult": 0.0,
			"heal_pct": heal_pct_for(hid),
		}

	var my_line := _path_id()
	var my_prof := profession_of(my_line)
	## tier: 2=當前武器系統, 1=同職業另一系統, 0=其他
	var best: Dictionary = {}
	var best_p := -1
	var best_tier := -1
	for d in CATALOG:
		var sid: String = str(d.get("id", ""))
		if str(d.get("kind", "")) != "attack":
			continue
		if not is_learned(sid):
			continue
		var line := str(d.get("line", ""))
		var prof := str(d.get("profession", profession_of(line)))
		var tier := 0
		if my_line != "" and line == my_line:
			tier = 2
		elif my_prof != "" and prof == my_prof:
			tier = 1
		var prio: int = int(d.get("priority", 0))
		if tier > best_tier or (tier == best_tier and prio > best_p):
			best_tier = tier
			best_p = prio
			best = d
	if best.is_empty():
		return {
			"id": "slash",
			"name": _t("橫斬"),
			"kind": "attack",
			"mult": 1.8,
			"hits": 1,
			"heal_pct": 0.0,
		}
	var sid2: String = str(best.get("id", "slash"))
	return {
		"id": sid2,
		"name": str(best.get("name", _t("橫斬"))),
		"kind": "attack",
		"mult": mult_for(sid2),
		"hits": hits_for(sid2),
		"heal_pct": 0.0,
	}


func battle_player_stats_patch() -> Dictionary:
	var kit: Dictionary = pick_battle_skill(1.0)
	return {
		"can_skill": is_learned("slash") or kit.get("id", "") != "",
		"slash_lv": maxi(1, get_lv("slash")),
		"skill_id": str(kit.get("id", "slash")),
		"skill_name": str(kit.get("name", _t("橫斬"))),
		"skill_mult": float(kit.get("mult", 1.8)),
		"skill_hits": int(kit.get("hits", 1)),
		"skill_kind": str(kit.get("kind", "attack")),
		"heal_pct": float(kit.get("heal_pct", 0.0)),
	}


## 導師指點：耗金給熟練（灰鬚）
const TUTOR_COST := 40
const TUTOR_MASTERY := 15

func can_tutor(id: String) -> bool:
	return is_learned(id) and get_lv(id) < MAX_LV and GameState.gold >= TUTOR_COST


func tutor_train(id: String) -> Dictionary:
	if not can_tutor(id):
		return {}
	GameState.add_gold(-TUTOR_COST)
	return add_mastery(id, TUTOR_MASTERY)


func panel_status_bbcode() -> String:
	ensure_skill_map()
	var lines: PackedStringArray = []
	lines.append(_t("[b]旅途 · 招式[/b]"))
	lines.append(_t("鐵匠養器 · 星途養魂 · [color=#c9e]旅途養招[/color]"))
	lines.append(_t("六職業各有兩套對等武器系統（非主副）；換武器系統就換出招風格。"))
	lines.append(_t("熟練靠戰鬥命中累積；滿了會自動升階。灰鬚可指點加速。"))
	var pid := _path_id()
	var prof := profession_of(pid)
	if prof != "":
		var pname := str(PROFESSION_NAME.get(prof, prof))
		var wpair: Array = weapons_of_profession(prof)
		var wlabels: PackedStringArray = []
		for w in wpair:
			wlabels.append(_weapon_label(str(w)))
		lines.append(_t("當前職業：%s（%s）") % [pname, " · ".join(wlabels)])
		var sig := signature_for_class(pid)
		if sig != "":
			if is_learned(sig):
				lines.append(_t("當前武器系統簽名：%s") % display_name(sig))
			else:
				lines.append(_t("當前武器系統簽名：%s（未習得）") % str(def_of(sig).get("name", sig)))
		var sib := sibling_weapon(pid)
		if sib != "":
			var ssig := signature_for_class(sib)
			if ssig != "" and is_learned(ssig):
				lines.append(_t("另一武器系統：%s · %s") % [_weapon_label(sib), display_name(ssig)])
			else:
				lines.append(_t("另一武器系統：%s（可切換遊玩）") % _weapon_label(sib))
	lines.append("")

	## 按職業分組列出
	var shown: Dictionary = {}
	for prof_key in ["knight", "viking", "ninja", "monk", "mage", "ranger"]:
		var any_visible := false
		var block: PackedStringArray = []
		var pname2 := str(PROFESSION_NAME.get(prof_key, prof_key))
		block.append(_t("[color=#8cf]— %s —[/color]") % pname2)
		for w in weapons_of_profession(prof_key):
			var wline := str(w)
			block.append(_t("  [color=#aaa]%s[/color]") % _weapon_label(wline))
			for d in CATALOG:
				if str(d.get("line", "")) != wline:
					continue
				var sid: String = str(d.get("id", ""))
				shown[sid] = true
				var name: String = str(d.get("name", sid))
				var slv: int = get_lv(sid)
				if slv <= 0:
					if is_unlocked(sid):
						block.append(_t("    [color=#aaa]· %s — 可體悟[/color]") % name)
						any_visible = true
					else:
						block.append("    [color=#666]· ？？？ — %s[/color]" % str(d.get("unlock_hint", _t("未解鎖"))))
					continue
				any_visible = true
				var kind: String = str(d.get("kind", "attack"))
				var stat_line := ""
				if kind == "heal":
					stat_line = _t("回復約 %d%%") % int(round(heal_pct_for(sid) * 100.0))
				else:
					var hn: int = hits_for(sid)
					if hn > 1:
						stat_line = _t("×%.2f ×%d") % [mult_for(sid), hn]
					else:
						stat_line = _t("×%.2f") % mult_for(sid)
				block.append("[b]    · %s · Lv%d[/b]  %s · %s" % [name, slv, mastery_progress_line(sid), stat_line])
				if slv < MAX_LV:
					var next_key := "lv%d" % (slv + 1)
					var preview: String = str(d.get(next_key, _t("下級：效果↑")))
					block.append(_t("      [color=#8cf]%s[/color]") % preview)
		## 只顯示與玩家有關或已解鎖任一一招的職業區塊，避免面板爆炸
		## 但至少永遠顯示當前職業
		if any_visible or prof_key == prof or prof == "":
			for bl in block:
				lines.append(bl)
			lines.append("")

	## 未分到職業的（理論上沒有）
	for d in CATALOG:
		var sid2: String = str(d.get("id", ""))
		if shown.has(sid2):
			continue
		if get_lv(sid2) <= 0 and not is_unlocked(sid2):
			continue
		lines.append("· %s" % display_name(sid2))

	var kit: Dictionary = pick_battle_skill(0.35)
	var kit_full: Dictionary = pick_battle_skill(1.0)
	lines.append(_t("[b]戰鬥優先[/b]"))
	lines.append(_t("  平常：%s") % str(kit_full.get("name", "—")))
	var any_heal := false
	for d2 in CATALOG:
		if str(d2.get("kind", "")) == "heal" and is_learned(str(d2.get("id", ""))):
			any_heal = true
			break
	if any_heal:
		lines.append(_t("  危急（低血）：%s") % str(kit.get("name", "—")))
	return "\n".join(lines)


func _weapon_label(wid: String) -> String:
	match normalize_weapon_id(wid):
		"sword":
			return _t("劍")
		"spear":
			return _t("槍")
		"axe":
			return _t("斧")
		"hammer":
			return _t("鎚")
		"dagger":
			return _t("匕首")
		"dart":
			return _t("鏢")
		"fist":
			return _t("拳")
		"claw":
			return _t("爪")
		"magic":
			return _t("杖")
		"crystal":
			return _t("水晶")
		"bow":
			return _t("弓")
		"gun":
			return _t("火槍")
		_:
			return wid


func grant_c0_slash() -> void:
	learn("slash", 1)


func grant_c1_greybeard() -> void:
	learn("slash", 1)
	if get_lv("slash") == 1:
		add_mastery("slash", 8)


func grant_leo_insight() -> void:
	try_unlock("thunder_fury")
	try_unlock("counter_strike")


func grant_heal_insight() -> void:
	try_unlock("emergency_heal")


## 選武器系統時：
##   1. 通用橫斬（旅途保底）
##   2. 該武器系統簽名／起手
##   3. 同職業另一武器系統起手（兩套都可玩，非主副）
##   4. 依等級 try_unlock 該職業已解鎖的招
## 回傳本次新習得的 skill id 列表
func grant_for_weapon_class(class_id: String) -> Array:
	var cid := normalize_weapon_id(class_id)
	var granted: Array = []
	if learn("slash", 1):
		granted.append("slash")

	var sig := signature_for_class(cid)
	if sig != "" and learn(sig, 1):
		granted.append(sig)

	## 同職業另一套武器系統的起手 —— 對等可玩
	var sib := sibling_weapon(cid)
	if sib != "":
		var ssig := signature_for_class(sib)
		if ssig != "" and learn(ssig, 1):
			granted.append(ssig)

	## 職業線上已解鎖的中高階一併體悟
	var prof := profession_of(cid)
	if prof != "":
		for sid in skills_for_profession(prof):
			if try_unlock(str(sid)):
				if str(sid) not in granted:
					granted.append(str(sid))

	return granted


## 等級提升時：把當前職業可解鎖的招試著體悟
func grant_level_insights() -> Array:
	var granted: Array = []
	var prof := profession_of(_path_id())
	var pool: Array = skills_for_profession(prof) if prof != "" else []
	if pool.is_empty():
		for d in CATALOG:
			pool.append(str(d.get("id", "")))
	for sid in pool:
		if try_unlock(str(sid)):
			granted.append(str(sid))
	return granted
