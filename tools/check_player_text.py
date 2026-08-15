#!/usr/bin/env python3
"""玩家面文字的守門員。

檢查兩件事：
  1. 設計文件／實作用語洩漏（SPEC_TERMS）
  2. 簡體字與陸語詞混入（本作是 zh_TW）


起因：遊戲對玩家講的第一句話曾經是「歡迎來到翠嶺。這是一則『故事優先』的旅途。」，
行商 NPC 在 12 個活動檔裡說「進度不罰」。這些都是 README／docs 裡的開發用語，
被當成文案貼進了產品。玩家不該讀到我們怎麼規劃這款遊戲，只該讀到這款遊戲。

掃描範圍（玩家看得到的地方）：
  game/scripts/**/*.gd  的中文字串字面值（跳過 dev/ 與 test_*）
  game/data/**/*.json   （跳過純開發者欄位，如 note）
  web/**/*.html         的可見文字

用法：
    python3 tools/check_player_text.py          # 有問題就 exit 1
    python3 tools/check_player_text.py --list   # 只列出，不當成失敗
"""

import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 規格書／開發者語域的詞。加詞前先想：玩家在遊戲裡讀到這個詞會不會出戲？
SPEC_TERMS = [
    "故事優先", "加厚", "體驗承諾", "不做清單", "系統堆疊", "閉環", "自洽",
    "掛點", "分層", "軟鎖", "三重養成", "選配", "通關門票", "產品重心",
    "重做策略", "迭代", "版本規劃", "玩法循環", "核心循環", "數值調校",
    "手感穩定", "內容密度", "探索密度", "進度不罰", "主線永遠", "可選加厚",
    # 介面／系統實作用語：玩家該讀到發生了什麼，不是我們怎麼實作的
    "HUD", "機制窗", "權重", "偏科", "戰利：", "稱號進度", "重跑",
    "普攻減半", "技傷減半", "相位", "破防條", "看破窗",
    # 開發標籤與流程圖語言被寫進台詞：NPC 不會這樣講話
    "（教學）", "（訓練）", "（提示）", "循環懂", "→賣", "材料行循環",
    # 攻略／官網文案裡的工程與統計語言
    "正交", "錨點", "隱性友善", "隱性加成", "中位配置", "不必死磕",
]

# 陸語詞（本作是 zh_TW，用詞要跟得上台灣讀者）
MAINLAND = {
    "視頻": "影片", "軟件": "軟體", "硬件": "硬體", "網絡": "網路",
    "信息": "訊息", "默認": "預設", "用戶": "使用者", "屏幕": "螢幕",
    "激活": "啟用", "死磕": "硬拚", "靠譜": "可靠", "服務器": "伺服器",
    "登錄": "登入", "注冊": "註冊", "菜單": "選單", "插件": "外掛",
    "緩存": "快取", "內存": "記憶體", "文件夾": "資料夾", "調試": "除錯",
}

# 合法用法：這些詞在特定語境是真的在講遊戲世界，不是規格語。
# 格式：(詞, 該行必須同時含有的字串) —— 命中就放行。
ALLOW = [
    ("門檻", "門檻上"),        # 「阿波坐在門檻上喝茶」是真的門檻
    ("門檻", "危急門檻"),      # 技能數值術語，玩家介面上本來就這樣講
    ("里程碑", "里程碑·"),     # 地圖上的路標地名
    ("里程碑", "里程碑上"),    # 同上，敘述文字
]

# 簡體專用字 → 正體。只列「兩岸寫法不同」的，正簡同形字（走、向、台…）不列，
# 否則會掃出上千個假警報。發現新的就往這裡加。
SIMPLIFIED = {
    "篱": "籬", "装": "裝", "迹": "跡", "别": "別", "东": "東", "极": "極",
    "两": "兩", "为": "為", "会": "會", "传": "傳", "伤": "傷", "众": "眾",
    "体": "體", "关": "關", "剑": "劍", "动": "動", "势": "勢", "单": "單",
    "变": "變", "号": "號", "后": "後", "听": "聽", "国": "國", "声": "聲",
    "处": "處", "备": "備", "头": "頭", "实": "實", "对": "對", "层": "層",
    "岁": "歲", "币": "幣", "师": "師", "带": "帶", "开": "開", "张": "張",
    "强": "強", "当": "當", "总": "總", "护": "護", "换": "換", "数": "數",
    "断": "斷", "旧": "舊", "时": "時", "术": "術", "机": "機", "杀": "殺",
    "条": "條", "来": "來", "样": "樣", "欢": "歡", "气": "氣", "没": "沒",
    "灯": "燈", "灵": "靈", "热": "熱", "爱": "愛", "独": "獨", "狮": "獅",
    "现": "現", "种": "種", "称": "稱", "稳": "穩", "简": "簡", "类": "類",
    "线": "線", "练": "練", "结": "結", "给": "給", "绝": "絕", "续": "續",
    "网": "網", "脑": "腦", "节": "節", "药": "藥", "获": "獲", "觉": "覺",
    "认": "認", "让": "讓", "说": "說", "读": "讀", "货": "貨", "质": "質",
    "费": "費", "车": "車", "转": "轉", "轻": "輕", "边": "邊", "过": "過",
    "还": "還", "这": "這", "进": "進", "远": "遠", "连": "連", "选": "選",
    "铁": "鐵", "错": "錯", "长": "長", "门": "門", "问": "問", "间": "間",
    "队": "隊", "险": "險", "隐": "隱", "难": "難", "雾": "霧", "静": "靜",
    "页": "頁", "预": "預", "领": "領", "题": "題", "风": "風", "飞": "飛",
    "马": "馬", "验": "驗", "鱼": "魚", "鸟": "鳥", "鸡": "雞", "麦": "麥",
    "黄": "黃", "齐": "齊", "龙": "龍",
}

# JSON 裡純給開發者看的欄位，不算玩家面
DEV_JSON_KEYS = ("note", "_comment", "tagline_dev")


def visible_html(path: str) -> str:
    s = io.open(path, encoding="utf-8", errors="ignore").read()
    s = re.sub(r"<script.*?</script>", " ", s, flags=re.S)
    s = re.sub(r"<style.*?</style>", " ", s, flags=re.S)
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    return s


def gd_strings(path: str) -> str:
    txt = io.open(path, encoding="utf-8").read()
    out = []
    for line in txt.split("\n"):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for m in re.findall(r'"([^"\n]*[一-鿿][^"\n]*)"', line):
            out.append(m)
    return "\n".join(out)


def json_player_text(path: str) -> str:
    out = []
    for line in io.open(path, encoding="utf-8").read().split("\n"):
        key = re.match(r'\s*"(\w+)"\s*:', line)
        if key and key.group(1) in DEV_JSON_KEYS:
            continue
        out.append(line)
    return "\n".join(out)


def allowed(term: str, line: str) -> bool:
    return any(t == term and ctx in line for t, ctx in ALLOW)


def collect():
    files = []
    for p in glob.glob(os.path.join(ROOT, "game/scripts/**/*.gd"), recursive=True):
        base = os.path.basename(p)
        if os.sep + "dev" + os.sep in p or base.startswith("test_"):
            continue
        files.append((p, gd_strings(p)))
    for p in glob.glob(os.path.join(ROOT, "game/data/**/*.json"), recursive=True):
        files.append((p, json_player_text(p)))
    for p in glob.glob(os.path.join(ROOT, "web/**/*.html"), recursive=True):
        files.append((p, visible_html(p)))
    return files


def main() -> None:
    list_only = "--list" in sys.argv
    hits = []
    for path, body in collect():
        rel = os.path.relpath(path, ROOT)
        for i, line in enumerate(body.split("\n"), 1):
            for term in SPEC_TERMS:
                if term in line and not allowed(term, line):
                    hits.append((rel, term, line.strip()[:100]))

    simp = []
    for path, body in collect():
        rel = os.path.relpath(path, ROOT)
        for line in body.split("\n"):
            bad = sorted({c for c in line if c in SIMPLIFIED})
            if bad:
                fix = "、".join(f"{c}→{SIMPLIFIED[c]}" for c in bad)
                simp.append((rel, fix, line.strip()[:100]))
            for cn, tw in MAINLAND.items():
                if cn in line:
                    simp.append((rel, f"{cn}→{tw}", line.strip()[:100]))

    if not hits and not simp:
        print("PLAYER_TEXT_OK：沒有開發用語、簡體字或陸語詞")
        return

    if hits:
        print(f"發現 {len(hits)} 處開發用語洩漏到玩家面：\n")
        for rel, term, line in hits:
            print(f"  {rel}")
            print(f"    「{term}」 → {line}")
        print(
            "\n這些是我們規劃／實作時的說法，不是玩家該讀到的話。"
            "\n改寫成「玩家實際體驗到什麼」，或若確屬遊戲世界用語，"
            "\n把它加進 tools/check_player_text.py 的 ALLOW。\n"
        )

    if simp:
        print(f"發現 {len(simp)} 處簡體字或陸語詞（本作是 zh_TW）：\n")
        for rel, fix, line in simp:
            print(f"  {rel}")
            print(f"    [{fix}] {line}")

    if not list_only:
        sys.exit(1)


if __name__ == "__main__":
    main()
