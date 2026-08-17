#!/usr/bin/env python3
"""把每張地圖的世界尺寸校正成跟它的底圖同長寬比。

問題：底圖是用 STRETCH_SCALE 拉滿 FLOOR_RECT 的，但世界尺寸是隨手訂的
（town 3200x1500 = 2.13，底圖 1376x768 = 1.79）。差 19%，畫面上每棟房子
都被橫向拉寬 —— 平均 24%，最誇張的 road 是 +83%。房子變成扁的，
石板變成橢圓，怎麼看都不對。

做法：保留寬度（橫向是主要行走軸，實體分布也以橫向為主），
把高度改成 寬 / 底圖長寬比。然後把所有實體與出生點按「腳底的正規化位置」
重新換算，相對位置完全不變 —— 只有畫面不再被拉扁。

    腳底 v = (y + h - OY) / 舊高    →    新 y = OY + v * 新高 - h

用法：
    python3 tools/fix_map_aspect.py --dry-run   # 只報告
    python3 tools/fix_map_aspect.py             # 實際改 map_catalog.gd
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "game/scripts/world/map_catalog.gd")
BG = os.path.join(ROOT, "game/assets/sprites/maps")
OX, OY = 40.0, 80.0

BASE_RE = (r'(var m := _base\("[^"]+",\s*Color\([^)]*\),\s*)([\d.]+)(,\s*)([\d.]+)'
           r'(,\s*Vector2\()([\d.]+)(,\s*)([\d.]+)(\),\s*")([a-z0-9_]+)("\))')


def img_aspect(art):
    from PIL import Image
    p = os.path.join(BG, "%s_bg.png" % art)
    if not os.path.exists(p):
        return None
    w, h = Image.open(p).size
    return w / float(h)


def main():
    dry = "--dry-run" in sys.argv
    src = io.open(CAT, encoding="utf-8").read()
    out = []
    changed = 0
    skipped = []

    ## 逐張地圖處理：先改 _base 的高度，再按比例挪同一個區塊裡的實體
    parts = re.split(r'(?=static func _[a-z0-9_]+\(\) -> Dictionary:)', src)
    for blk in parts:
        m = re.search(BASE_RE, blk)
        if not m:
            out.append(blk)
            continue
        W, H = float(m.group(2)), float(m.group(4))
        sx, sy = float(m.group(6)), float(m.group(8))
        art = m.group(10)
        ar = img_aspect(art)
        if ar is None:
            skipped.append(art)
            out.append(blk)
            continue
        newH = round(W / ar)
        if abs(newH - H) < 1.0:
            out.append(blk)
            continue

        fn = re.match(r'static func (_[a-z0-9_]+)', blk).group(1)
        print("  %-24s %-12s → %-12s（高 %+d，橫向拉伸 %+.0f%% → 0%%）"
              % (fn, "%dx%d" % (W, H), "%dx%d" % (W, newH), newH - H,
                 ((W / H) / ar - 1) * 100))
        changed += 1

        ## _base：高度與出生點
        new_sy = round(OY + (sy - OY) / H * newH)
        blk = blk[:m.start()] + (m.group(1) + m.group(2) + m.group(3) + str(newH)
                                 + m.group(5) + m.group(6) + m.group(7) + str(new_sy)
                                 + m.group(9) + m.group(10) + m.group(11)) + blk[m.end():]

        ## 實體：保持腳底的正規化位置
        def fix_e(em):
            eid, x, y, w, h, rest = em.groups()
            v = (float(y) + float(h) - OY) / H
            ny = round(OY + v * newH - float(h))
            return '_e("%s", %s, %d, %s, %s,%s' % (eid, x, ny, w, h, rest)

        blk = re.sub(r'_e\("([a-z0-9_]+)",\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),(.*)',
                     fix_e, blk)
        out.append(blk)

    if skipped:
        print("\n（沒有底圖，跳過：%s）" % " ".join(sorted(set(skipped))))
    print("\n共校正 %d 張地圖" % changed)
    if not dry:
        io.open(CAT, "w", encoding="utf-8").write("".join(out))
    else:
        print("（--dry-run，沒有寫檔）")


if __name__ == "__main__":
    main()
