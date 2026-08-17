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

## 以「原文」當 key 的 domain：從哪個檔、用哪些 regex 抓原文
SOURCES = {
    "cosmetic": [
        ("game/scripts/systems/title_catalog.gd", [
            r'\{"flag": "cosmetic\.\w+", "name": "([^"]+)"\}',
        ]),
    ],
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


## 以 id 當 key 的目錄：domain → (檔案, 常數名, id 欄位, 要翻的欄位)
## 這些是 {id: {name/desc/...}} 的結構，比對到「每個 id 的每個欄位」。
CATALOGS = {
    "skill": ("game/scripts/systems/skill_system.gd", "const CATALOG",
              "id", ("name", "desc", "lv2", "lv3", "unlock_hint")),
    "title": ("game/scripts/systems/title_catalog.gd", "const ENTRIES",
              "flag", ("name", "desc")),
    "guild": ("game/scripts/systems/guild_system.gd", "const GUILDS",
              "id", ("name", "motto")),
    "enemy": ("game/scripts/world/world_content.gd", None, "id", ("name",)),
    "quest": ("game/scripts/systems/quest_system.gd", None, "id", ("name", "desc")),
    "item": ("game/scripts/systems/inventory_system.gd", None, None, ("name", "desc")),
}

HAN = re.compile(r"[\u4e00-\u9fff]")


def _block(rel: str, const_name: str) -> str:
    src = io.open(os.path.join(ROOT, rel), encoding="utf-8").read()
    if const_name is None:
        return src
    i = src.index(const_name)
    rest = src[i + len(const_name):]
    m = re.search(r"\n(const |func |static func )", rest)
    return src[i: i + len(const_name) + (m.start() if m else len(rest))]


def catalog_want(domain: str) -> dict:
    """回傳 {id: {欄位: 原文}}，只收含中文的欄位（其餘已經是數值或英文 id）"""
    rel, const_name, idkey, fields = CATALOGS[domain]
    body = _block(rel, const_name)
    want = {}
    if idkey is None:
        ## inventory 是 {"id": {...}} 的巢狀結構，頂層 key 就是 id
        for m in re.finditer(r'^\t"(\w+)":\s*\{(.*?)^\t\},', body, re.M | re.S):
            d = dict(re.findall(r'"(\w+)"\s*:\s*"([^"]*)"', m.group(2)))
            got = {f: d[f] for f in fields if f in d and HAN.search(d[f])}
            if got:
                want[m.group(1)] = got
        return want
    for blk in re.finditer(r"\{([^{}]*)\}", body):
        d = dict(re.findall(r'"(\w+)"\s*:\s*"([^"]*)"', blk.group(1)))
        if idkey not in d:
            continue
        got = {f: d[f] for f in fields if f in d and HAN.search(d[f])}
        if got:
            want.setdefault(d[idkey], {}).update(got)
    return want


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

    for domain in sorted(CATALOGS):
        want = catalog_want(domain)
        if not want:
            problems.append(("-", domain, "從程式裡一筆原文都沒抓到 —— 這條檢查等於沒在檢查", []))
            continue
        for code in LOCALES:
            path = os.path.join(CONTENT, code, "%s.json" % domain)
            if not os.path.exists(path):
                problems.append((code, domain, "缺覆蓋檔", []))
                continue
            tbl = json.load(io.open(path, encoding="utf-8"))
            missing = []
            for i, fields in sorted(want.items()):
                got = tbl.get(i, {})
                if not isinstance(got, dict):
                    missing.append("%s（整筆型別錯了）" % i)
                    continue
                for f in fields:
                    if not str(got.get(f, "")).strip():
                        missing.append("%s.%s" % (i, f))
            stale = sorted(k for k in tbl if k not in want)
            if missing:
                problems.append((code, domain, "漏翻 %d 條" % len(missing), missing))
            if stale:
                problems.append((code, domain, "殘留 %d 筆（原文已經改掉或刪掉）" % len(stale), stale))

    if not problems:
        total = sum(len(sources_for(d)) for d in SOURCES)
        total += sum(len(v) for d in CATALOGS for v in [catalog_want(d)])
        print("CONTENT_LOC_OK：%d 條原文 × %d 個語言都蓋滿了" % (total, len(LOCALES)))
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
