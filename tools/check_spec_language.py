#!/usr/bin/env python3
"""擋住「設計文件詞彙」洩漏到玩家面前。

起因：遊戲對玩家講的第一句話曾經是「歡迎來到翠嶺。這是一則『故事優先』的旅途。」，
行商 NPC 在 12 個活動檔裡說「進度不罰」。這些都是 README／docs 裡的開發用語，
被當成文案貼進了產品。玩家不該讀到我們怎麼規劃這款遊戲，只該讀到這款遊戲。

掃描範圍（玩家看得到的地方）：
  game/scripts/**/*.gd  的中文字串字面值（跳過 dev/ 與 test_*）
  game/data/**/*.json   （跳過純開發者欄位，如 note）
  web/**/*.html         的可見文字

用法：
    python3 tools/check_spec_language.py          # 有洩漏就 exit 1
    python3 tools/check_spec_language.py --list   # 只列出，不當成失敗
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
]

# 合法用法：這些詞在特定語境是真的在講遊戲世界，不是規格語。
# 格式：(詞, 該行必須同時含有的字串) —— 命中就放行。
ALLOW = [
    ("門檻", "門檻上"),        # 「阿波坐在門檻上喝茶」是真的門檻
    ("門檻", "危急門檻"),      # 技能數值術語，玩家介面上本來就這樣講
    ("里程碑", "里程碑·"),     # 地圖上的路標地名
    ("里程碑", "里程碑上"),    # 同上，敘述文字
]

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

    if not hits:
        print("SPEC_LANGUAGE_OK：玩家面文字沒有設計文件用語")
        return

    print(f"發現 {len(hits)} 處設計文件用語洩漏到玩家面：\n")
    for rel, term, line in hits:
        print(f"  {rel}")
        print(f"    「{term}」 → {line}")
    print(
        "\n這些是我們規劃遊戲時的說法，不是玩家該讀到的話。"
        "\n改寫成「玩家實際體驗到什麼」，或若確屬遊戲世界用語，"
        "\n把它加進 tools/check_spec_language.py 的 ALLOW。"
    )
    if not list_only:
        sys.exit(1)


if __name__ == "__main__":
    main()
