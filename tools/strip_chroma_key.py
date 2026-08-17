#!/usr/bin/env python3
"""把 chroma key 背景（洋紅／青色那種）轉成真正的透明。

起因：props/pine.png 的背景是 RGB(254,1,250)、props/boat.png 是 (4,253,254)，
alpha 卻是 255 —— 生圖工具用綠幕思路填了一個「等一下會被去掉」的顏色，
但那一步沒做。遊戲裡就直接畫出兩個亮色方塊（沉船灣那張截圖看得很清楚）。

smart_matte_props.py 只認深灰格線背景，抓不到這種。

做法刻意用**從邊界往內 flood fill**，不是全圖比色替換：
物件本身若有同色像素（船帆上的高光、樹上的花），全圖替換會把它一起挖成洞。
只有「從畫布邊緣連得到」的那一片才是背景。

順便處理去背後的色邊（fringe）：邊界像素若還混著 key 色，把那個色分量
拉回鄰近不透明像素的平均色，不然放大後會看到一圈螢光邊。

用法：
    python3 tools/strip_chroma_key.py                     # 掃 props/ 自動找
    python3 tools/strip_chroma_key.py a.png b.png         # 指定檔案
    python3 tools/strip_chroma_key.py --dry-run           # 只報告不寫檔
"""

import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = ["game/assets/sprites/props", "game/assets/sprites/bosses",
             "game/assets/sprites/npcs", "game/assets/sprites/player"]

## 容差：AI 生圖的「純色」背景其實會有 ±10 的雜訊
TOL = 60
## 判定成 chroma key 的門檻：飽和度高（RGB 極差大）才算，避免誤殺深灰底圖
MIN_SATURATION = 100


def is_chroma(px):
    r, g, b, a = px
    return a > 250 and (max(r, g, b) - min(r, g, b)) >= MIN_SATURATION


def close(c1, c2, tol=TOL):
    return (abs(c1[0] - c2[0]) <= tol and abs(c1[1] - c2[1]) <= tol
            and abs(c1[2] - c2[2]) <= tol)


def strip(path: Path, dry=False):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()

    ## 四角取眾數當 key 色 —— 單看一角可能剛好踩到雜訊
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    keyed = [c for c in corners if is_chroma(c)]
    if len(keyed) < 3:
        return None
    key = keyed[0]

    ## 從邊界 flood fill：只有連得到畫布邊緣的同色區塊才是背景
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if close(px[x, y], key) and px[x, y][3] > 0:
                q.append((x, y)); seen[y * w + x] = 1
    for y in range(h):
        for x in (0, w - 1):
            if close(px[x, y], key) and px[x, y][3] > 0 and not seen[y * w + x]:
                q.append((x, y)); seen[y * w + x] = 1

    removed = 0
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        removed += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                if px[nx, ny][3] > 0 and close(px[nx, ny], key):
                    seen[ny * w + nx] = 1
                    q.append((nx, ny))

    ## 去色邊：還留著的像素若明顯偏 key 色，用鄰近乾淨像素的顏色補
    fringe = 0
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if c[3] == 0:
                continue
            if not close(c, key, TOL + 40):
                continue
            near = []
            for dx in (-2, -1, 0, 1, 2):
                for dy in (-2, -1, 0, 1, 2):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        n = px[nx, ny]
                        if n[3] > 200 and not close(n, key, TOL + 40):
                            near.append(n)
            if near:
                r = sum(n[0] for n in near) // len(near)
                g = sum(n[1] for n in near) // len(near)
                b = sum(n[2] for n in near) // len(near)
                px[x, y] = (r, g, b, c[3])
                fringe += 1
            else:
                px[x, y] = (0, 0, 0, 0)
                removed += 1

    if not dry:
        im.save(path)
    return key, removed, fringe, w * h


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    dry = "--dry-run" in sys.argv
    if args:
        targets = [Path(a) if Path(a).is_absolute() else ROOT / a for a in args]
    else:
        targets = []
        for d in SCAN_DIRS:
            targets += sorted((ROOT / d).rglob("*.png"))

    hit = 0
    for p in targets:
        if "_gen" in str(p) or "_backup" in str(p):
            continue
        r = strip(p, dry)
        if r is None:
            continue
        key, removed, fringe, total = r
        hit += 1
        print("  %-42s key=RGB%-16s 去掉 %5.1f%%　修色邊 %d 點"
              % (p.relative_to(ROOT), str(key[:3]), removed / total * 100, fringe))
    if hit == 0:
        print("沒有找到 chroma key 背景的圖")
    elif dry:
        print("\n（--dry-run，沒有寫檔）")


if __name__ == "__main__":
    main()
