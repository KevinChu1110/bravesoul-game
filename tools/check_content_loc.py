#!/usr/bin/env python3
"""內容目錄譯文的守門員。

data/i18n/content/<locale>/<domain>.json 是「以原文當 key」的覆蓋表。
這種表最容易爛的方式不是翻錯，是**原文改了、覆蓋表沒跟著改** ——
key 對不上就靜靜地掉回中文，測試全綠、玩家看到半英半中。

所以這支做兩件事：
  1. 從 .gd 抓出所有會走 ContentLoc 的字串（原文）
  2. 每個語言的覆蓋表都要蓋滿；有多出來的 key 就是原文已經改掉的殘留

用法：
    python3 tools/check_content_loc.py          # 有問題就 exit 1
    python3 tools/check_content_loc.py --list   # 只列出，不當成失敗
"""

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES = ("zh_CN", "en", "ja", "ko", "es")
CONTENT = os.path.join(ROOT, "game/data/i18n/content")

## domain → 從哪個檔、用哪些 regex 抓原文
SOURCES = {
    "map": [
        ("game/scripts/world/map_catalog.gd", [
            ## _e(id, x, y, w, h, "標籤", ...)
            r'_e\(\s*"[a-z0-9_]+"\s*,[^,]+,[^,]+,[^,]+,[^,]+,\s*"([^"]+)"',
            ## _base("地名", ...)
            r'_base\("([^"]+)"',
        ]),
    ],
}

## 動態組出來的標籤：整串才是玩家看到的字，regex 抓不到，只能列在這裡。
## 改到 map_catalog 裡這幾行時要記得同步。
EXTRA = {
    "map": [
        "長明燈（亮）", "長明燈",
        "橋下鳥巢（已顧）",
        "壁爐（暖）", "熄滅壁爐",
        "旗幟（兔爪）", "灰旗",
        "空武器架", "武器架（斷劍）",
        "行商頭領", "行商（待交信）",
        "許願淺池（已許）",
        "香爐（已燃）", "香爐",
    ],
}


def sources_for(domain: str) -> set:
    out = set()
    for rel, patterns in SOURCES[domain]:
        src = io.open(os.path.join(ROOT, rel), encoding="utf-8").read()
        for pat in patterns:
            for m in re.finditer(pat, src):
                out.add(m.group(1))
    out.update(EXTRA.get(domain, []))
    return out


def main() -> None:
    list_only = "--list" in sys.argv
    problems = []
    for domain in sorted(SOURCES):
        want = sources_for(domain)
        if not want:
            problems.append(("-", domain, "從程式裡一個原文都沒抓到 —— 這條檢查等於沒在檢查", []))
            continue
        for code in LOCALES:
            path = os.path.join(CONTENT, code, "%s.json" % domain)
            if not os.path.exists(path):
                problems.append((code, domain, "缺覆蓋檔", []))
                continue
            tbl = json.load(io.open(path, encoding="utf-8"))
            missing = sorted(s for s in want if not str(tbl.get(s, "")).strip())
            stale = sorted(k for k in tbl if k not in want)
            if missing:
                problems.append((code, domain, "漏翻 %d 條" % len(missing), missing))
            if stale:
                problems.append((code, domain, "殘留 %d 條（原文已經改掉或刪掉）" % len(stale), stale))

    if not problems:
        total = sum(len(sources_for(d)) for d in SOURCES)
        print("CONTENT_LOC_OK：%d 個原文 × %d 個語言都蓋滿了" % (total, len(LOCALES)))
        return

    for code, domain, what, items in problems:
        print("  [%s/%s] %s" % (code, domain, what))
        for s in items[:12]:
            print("      %s" % s)
        if len(items) > 12:
            print("      …還有 %d 條" % (len(items) - 12))
    print(
        "\n覆蓋表以原文當 key：原文改了就要同步改表，"
        "\n否則那句話會靜靜掉回中文，測試不會抓到。\n"
    )
    if not list_only:
        sys.exit(1)


if __name__ == "__main__":
    main()
