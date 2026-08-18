#!/usr/bin/env python3
"""可走區遮罩的檢查與預覽。

`game/data/walkmask.json` 用正規化多邊形描出每張底圖哪裡能站。這支做三件事：

  1. 把多邊形疊回底圖存成預覽圖 —— 標 41 張圖靠肉眼看疊圖比在遊戲裡試快得多
  2. 檢查每張地圖的**出生點與所有實體**在不在可走區內
     —— 這條是真正的門檻。實體座標與底圖是各自獨立畫的：騎士堡 22 個實體
     有 17 個（鐵匠、星讀、存檔石、出口…）落在照底圖描出來的可走區外。
     照著底圖描遮罩會把玩家跟這些 NPC 隔開，遊戲直接不能玩。
  3. 報告哪些 art 還沒標（那些會退回舊的百分比方塊，不算壞掉但也不算做完）

用法：
    python3 tools/check_walkmask.py            # 檢查 + 產預覽圖到 screenshots/walkmask/
    python3 tools/check_walkmask.py --check    # 只檢查，不產圖（CI 用）
    python3 tools/check_walkmask.py town       # 只看指定的 art
    python3 tools/check_walkmask.py --example  # 連 _ 開頭的範例一起看（會報實體站不到）
    python3 tools/check_walkmask.py --grid town village   # 產座標格線圖，用來描多邊形
"""

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASK = os.path.join(ROOT, "game/data/walkmask.json")
BG_DIR = os.path.join(ROOT, "game/assets/sprites/maps")
OUT_DIR = os.path.join(ROOT, "screenshots/walkmask")
CATALOG = os.path.join(ROOT, "game/scripts/world/map_catalog.gd")

## map_catalog 的 _base 預設 origin
ORIGIN = (40.0, 80.0)


def load_mask(include_examples=False):
    d = json.load(io.open(MASK, encoding="utf-8"))
    out = {}
    for k, v in d.items():
        if not isinstance(v, dict):
            continue          # _comment 那種說明文字
        if k.startswith("_"):
            ## 底線開頭＝範例／停用，載入器不會吃，但預覽時可以看
            if include_examples:
                out[k.lstrip("_").replace("example_", "")] = v
            continue
        out[k] = v
    return out


def load_maps():
    """回傳 [(map_fn, w, h, spawn_x, spawn_y, art)]"""
    src = io.open(CATALOG, encoding="utf-8").read()
    pat = (r'static func (_[a-z0-9_]+)\(\) -> Dictionary:\s*\n\s*var m := _base\('
           r'"[^"]+",\s*Color\([^)]*\),\s*([\d.]+),\s*([\d.]+),\s*'
           r'Vector2\(([\d.]+),\s*([\d.]+)\),\s*"([a-z0-9_]+)"\)')
    out = []
    for m in re.finditer(pat, src):
        fn, w, h, sx, sy, art = m.groups()
        out.append((fn, float(w), float(h), float(sx), float(sy), art))
    return out


def load_entities():
    """map_fn → [(id, x, y, w, h, label)]"""
    src = io.open(CATALOG, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'static func (_[a-z0-9_]+)\(\) -> Dictionary:', src):
        fn = m.group(1)
        nxt = src.find("static func ", m.end())
        blk = src[m.end(): nxt if nxt > 0 else len(src)]
        out[fn] = [(a, float(b), float(c), float(d), float(e), f)
                   for a, b, c, d, e, f in re.findall(
                       r'_e\("([a-z0-9_]+)",\s*([\d.]+),\s*([\d.]+),'
                       r'\s*([\d.]+),\s*([\d.]+),\s*"([^"]+)"', blk)]
    return out


def point_in_poly(pt, poly):
    x, y = pt
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            xint = (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def walkable(uv, entry):
    walk = entry.get("walk", [])
    if not walk:
        return True
    if not any(point_in_poly(uv, p) for p in walk):
        return False
    return not any(point_in_poly(uv, p) for p in entry.get("block", []))


def make_grid(arts):
    """產帶 0.0~1.0 座標格線的底圖，描 walk 多邊形時對著它讀座標。"""
    from PIL import Image, ImageDraw
    out = os.path.join(ROOT, "screenshots/walkgrid")
    os.makedirs(out, exist_ok=True)
    for art in arts:
        bg = os.path.join(BG_DIR, "%s_bg.webp" % art)
        if not os.path.exists(bg):
            bg = os.path.join(BG_DIR, "%s_bg.png" % art)
        if not os.path.exists(bg):
            print("  跳過 %s（沒有底圖）" % art)
            continue
        im = Image.open(bg).convert("RGB")
        im = im.resize((960, int(960 * im.height / im.width)), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        W, H = im.size
        for i in range(1, 10):
            x, y = W * i // 10, H * i // 10
            d.line([(x, 0), (x, H)], fill=(255, 60, 60))
            d.line([(0, y), (W, y)], fill=(255, 60, 60))
            d.text((x + 2, 2), "%.1f" % (i / 10.0), fill=(255, 255, 0))
            d.text((2, y + 2), "%.1f" % (i / 10.0), fill=(0, 255, 255))
        im.save(os.path.join(out, "%s.png" % art))
    print("格線圖 → screenshots/walkgrid/")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if "--grid" in sys.argv:
        allarts = sorted({m[5] for m in load_maps()})
        make_grid(args or allarts)
        return
    check_only = "--check" in sys.argv
    mask = load_mask(include_examples="--example" in sys.argv)
    maps = load_maps()

    arts = sorted({m[5] for m in maps})
    todo = [a for a in arts if a not in mask]
    problems = []

    ## 1a) 實體必須構得到 —— 站不到就等於那個 NPC／出口消失了
    ents = load_entities()
    for fn, w, h, sx, sy, art in maps:
        if art not in mask or (args and art not in args):
            continue
        bad = []
        for eid, ex, ey, ew, eh, label in ents.get(fn, []):
            uv = ((ex + ew / 2 - ORIGIN[0]) / w, (ey + eh - ORIGIN[1]) / h)
            if not walkable(uv, mask[art]):
                bad.append("%s（%s）" % (eid, label))
        if bad:
            problems.append("%s（art=%s）有 %d 個實體站不到：%s%s"
                            % (fn, art, len(bad), "、".join(bad[:5]),
                               "…" if len(bad) > 5 else ""))

    ## 1b) 出生點必須在可走區內
    for fn, w, h, sx, sy, art in maps:
        if art not in mask:
            continue
        if args and art not in args:
            continue
        uv = ((sx - ORIGIN[0]) / w, (sy - ORIGIN[1]) / h)
        if not walkable(uv, mask[art]):
            problems.append(
                "%s（art=%s）的出生點 uv=(%.3f, %.3f) 不在可走區內 —— 一開場就會卡住"
                % (fn, art, uv[0], uv[1]))

    ## 2) 可走區不能小到沒東西可走
    for art, entry in sorted(mask.items()):
        if args and art not in args:
            continue
        hit = sum(1 for gy in range(40) for gx in range(70)
                  if walkable(((gx + 0.5) / 70.0, (gy + 0.5) / 40.0), entry))
        frac = hit / (70 * 40)
        if frac < 0.06:
            problems.append("%s 的可走區只有 %.1f%%，幾乎沒地方站" % (art, frac * 100))
        elif frac > 0.92:
            problems.append("%s 的可走區有 %.1f%%，等於沒擋" % (art, frac * 100))

    ## 3) 預覽圖
    if not check_only:
        try:
            from PIL import Image, ImageDraw
        except ImportError:
            print("（沒有 PIL，跳過預覽圖）")
        else:
            os.makedirs(OUT_DIR, exist_ok=True)
            for art, entry in sorted(mask.items()):
                if args and art not in args:
                    continue
                ## 重出的高解析版是 .webp，還沒重出的是 .png
                bg = os.path.join(BG_DIR, "%s_bg.webp" % art)
                if not os.path.exists(bg):
                    bg = os.path.join(BG_DIR, "%s_bg.png" % art)
                if not os.path.exists(bg):
                    problems.append("%s 沒有對應的 %s_bg.png" % (art, art))
                    continue
                im = Image.open(bg).convert("RGB")
                im = im.resize((900, int(900 * im.height / im.width)))
                W, H = im.size
                ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                d = ImageDraw.Draw(ov)
                for poly in entry.get("walk", []):
                    d.polygon([(p[0] * W, p[1] * H) for p in poly],
                              fill=(60, 230, 90, 90), outline=(60, 255, 90, 255))
                for poly in entry.get("block", []):
                    d.polygon([(p[0] * W, p[1] * H) for p in poly],
                              fill=(240, 60, 60, 110), outline=(255, 80, 80, 255))
                ## 出生點
                for fn, w, h, sx, sy, a in maps:
                    if a != art:
                        continue
                    u = (sx - ORIGIN[0]) / w
                    v = (sy - ORIGIN[1]) / h
                    cx, cy = u * W, v * H
                    ok = walkable((u, v), entry)
                    col = (80, 200, 255, 255) if ok else (255, 40, 40, 255)
                    d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=col,
                              outline=(0, 0, 0, 255))
                im = Image.alpha_composite(im.convert("RGBA"), ov)
                im.convert("RGB").save(os.path.join(OUT_DIR, "%s.png" % art))
            print("預覽圖 → screenshots/walkmask/")

    print("\n已標 %d／%d 個 art" % (len(mask), len(arts)))
    if todo:
        print("尚未標（會退回舊的百分比方塊）：%s" % " ".join(todo))
    if problems:
        print("\n有問題：")
        for p in problems:
            print("  · %s" % p)
        sys.exit(1)
    print("WALKMASK_OK")


if __name__ == "__main__":
    main()
