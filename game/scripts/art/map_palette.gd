extends RefCounted
## 六域色盤：同一域的圖走同一套色溫，避免 AI 底圖各自鮮豔、互撞成拼貼。
## 不重產圖——只在探索層做 grade／wash。室內無底圖的店舖也不准偷用母域廣場圖。

## region → {bg, grade, wash, vignette, horizon, tile}
const REGIONS := {
	"village": {
		"bg": Color(0.09, 0.045, 0.04),
		"grade": Color(0.96, 0.88, 0.80),
		"wash": Color(0.18, 0.06, 0.04, 0.12),
		"vignette": Color(0.04, 0.01, 0.01, 0.18),
		"horizon": Color(0.06, 0.02, 0.03, 0.22),
		"tile": Color(0.72, 0.52, 0.40),
	},
	"road": {
		"bg": Color(0.10, 0.12, 0.16),
		"grade": Color(0.88, 0.90, 0.97),
		"wash": Color(0.08, 0.10, 0.16, 0.10),
		"vignette": Color(0.02, 0.03, 0.06, 0.16),
		"horizon": Color(0.04, 0.05, 0.10, 0.20),
		"tile": Color(0.55, 0.58, 0.64),
	},
	"town": {
		"bg": Color(0.10, 0.10, 0.13),
		"grade": Color(0.90, 0.91, 0.96),
		"wash": Color(0.08, 0.09, 0.14, 0.08),
		"vignette": Color(0.03, 0.03, 0.05, 0.14),
		"horizon": Color(0.04, 0.04, 0.08, 0.18),
		"tile": Color(0.62, 0.62, 0.68),
	},
	"wild": {
		"bg": Color(0.08, 0.10, 0.07),
		"grade": Color(0.94, 0.90, 0.76),
		"wash": Color(0.12, 0.10, 0.04, 0.10),
		"vignette": Color(0.04, 0.04, 0.02, 0.16),
		"horizon": Color(0.06, 0.05, 0.02, 0.20),
		"tile": Color(0.58, 0.52, 0.36),
	},
	"mist": {
		"bg": Color(0.08, 0.09, 0.12),
		"grade": Color(0.82, 0.88, 0.96),
		"wash": Color(0.14, 0.18, 0.24, 0.16),
		"vignette": Color(0.04, 0.06, 0.10, 0.20),
		"horizon": Color(0.06, 0.08, 0.12, 0.24),
		"tile": Color(0.50, 0.58, 0.68),
	},
	"dojo": {
		"bg": Color(0.12, 0.10, 0.08),
		"grade": Color(0.96, 0.92, 0.84),
		"wash": Color(0.16, 0.10, 0.06, 0.08),
		"vignette": Color(0.05, 0.03, 0.02, 0.16),
		"horizon": Color(0.08, 0.05, 0.03, 0.18),
		"tile": Color(0.62, 0.50, 0.38),
	},
	"forest": {
		"bg": Color(0.05, 0.10, 0.06),
		"grade": Color(0.80, 0.94, 0.78),
		"wash": Color(0.04, 0.12, 0.06, 0.10),
		"vignette": Color(0.02, 0.05, 0.03, 0.18),
		"horizon": Color(0.03, 0.08, 0.04, 0.22),
		"tile": Color(0.36, 0.52, 0.38),
	},
	"coast": {
		"bg": Color(0.11, 0.13, 0.15),
		"grade": Color(0.96, 0.94, 0.88),
		"wash": Color(0.10, 0.14, 0.18, 0.08),
		"vignette": Color(0.04, 0.06, 0.08, 0.16),
		"horizon": Color(0.06, 0.08, 0.12, 0.18),
		"tile": Color(0.72, 0.66, 0.52),
	},
	"tower": {
		"bg": Color(0.06, 0.04, 0.08),
		"grade": Color(0.88, 0.80, 0.96),
		"wash": Color(0.12, 0.04, 0.16, 0.14),
		"vignette": Color(0.04, 0.01, 0.06, 0.22),
		"horizon": Color(0.08, 0.02, 0.10, 0.26),
		"tile": Color(0.42, 0.32, 0.50),
	},
}


static func region_of(map_id: String) -> String:
	if map_id.begins_with("village"):
		return "village"
	if map_id.begins_with("road"):
		return "road"
	if map_id.begins_with("town") or map_id == "barracks_yard":
		return "town"
	if map_id.begins_with("mist") or map_id == "starfall_plain":
		return "mist"
	if map_id.begins_with("dojo"):
		return "dojo"
	if map_id.begins_with("forest"):
		return "forest"
	if map_id.begins_with("coast"):
		return "coast"
	if map_id.begins_with("tower") or map_id == "blackflame_scar":
		return "tower"
	## 荒野、岔路、行商、獵場：焦土橄欖
	return "wild"


static func is_indoor(map_id: String) -> bool:
	return map_id in ["town_forge", "town_soul", "town_gem", "town_tutor"]


static func of(map_id: String) -> Dictionary:
	var base: Dictionary = REGIONS.get(region_of(map_id), REGIONS["wild"])
	var p: Dictionary = base.duplicate()
	match map_id:
		"town_forge":
			p["bg"] = Color(0.16, 0.08, 0.05)
			p["wash"] = Color(0.28, 0.10, 0.04, 0.22)
			p["tile"] = Color(0.70, 0.42, 0.28)
		"town_soul":
			p["bg"] = Color(0.06, 0.07, 0.16)
			p["wash"] = Color(0.10, 0.14, 0.32, 0.22)
			p["tile"] = Color(0.42, 0.48, 0.72)
		"town_gem":
			p["bg"] = Color(0.14, 0.06, 0.08)
			p["wash"] = Color(0.28, 0.08, 0.12, 0.20)
			p["tile"] = Color(0.68, 0.36, 0.42)
		"town_tutor":
			p["bg"] = Color(0.11, 0.10, 0.11)
			p["wash"] = Color(0.14, 0.12, 0.12, 0.16)
			p["tile"] = Color(0.58, 0.54, 0.50)
		"town_sewers":
			p["grade"] = Color(0.78, 0.88, 0.82)
			p["wash"] = Color(0.06, 0.12, 0.08, 0.14)
		_:
			pass
	return p
