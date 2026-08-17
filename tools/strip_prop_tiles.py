#!/usr/bin/env python3
"""
Strip Prop Tiles for BraveSoul
Specifically removes isometric floor grids / ground tiles from key prop images (well, hut, forge, shrine, gate, etc.).
"""
from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PROPS_DIR = ROOT / "game/assets/sprites/props"

def is_ground_tile_color(r: int, g: int, b: int, a: int) -> bool:
    if a < 10:
        return True
    
    # 1. Dark grid lines and shadows
    if r < 40 and g < 40 and b < 40:
        return True
        
    # 2. Isometric stone/brick grid tiles (dark brown/grayish tones)
    # Range: R in [35, 110], G in [30, 100], B in [25, 90] with low saturation (R ~= G ~= B or R slightly higher)
    diff_rg = abs(r - g)
    diff_gb = abs(g - b)
    diff_rb = abs(r - b)
    
    if 30 <= r <= 115 and 25 <= g <= 105 and 20 <= b <= 95:
        if diff_rg <= 22 and diff_gb <= 22 and diff_rb <= 30:
            return True

    # 3. Dull brownish floor dirt
    if 40 <= r <= 120 and 35 <= g <= 105 and 25 <= b <= 85:
        if (r - b) > 5 and (r - g) <= 25 and diff_gb <= 20:
            return True

    return False

def clean_prop(name: str):
    p = PROPS_DIR / f"{name}.png"
    if not p.exists():
        return
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    px = im.load()

    # Flood fill from borders
    visited = set()
    queue = []
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))

    changed = False
    while queue:
        x, y = queue.pop(0)
        if (x, y) in visited:
            continue
        visited.add((x, y))

        r, g, b, a = px[x, y]
        if is_ground_tile_color(r, g, b, a):
            if a != 0:
                px[x, y] = (0, 0, 0, 0)
                changed = True
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                    queue.append((nx, ny))

    # Also crop tight bbox
    bbox = im.getbbox()
    if bbox:
        pad = 2
        im = im.crop((
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(w, bbox[2] + pad),
            min(h, bbox[3] + pad)
        ))
        changed = True

    if changed:
        im.save(p)
        print(f"Stripped ground tiles from {p.name}")

def main():
    props = ["hut", "well", "forge", "shrine", "gate", "rock", "crate", "barrel", "tree", "pine", "sign", "campfire", "tower"]
    for pr in props:
        clean_prop(pr)

if __name__ == "__main__":
    main()
