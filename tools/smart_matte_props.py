#!/usr/bin/env python3
"""
Smart Matte Props for BraveSoul
Detects and strips dark gray isometric grid tiles/backgrounds from AI-generated prop sprites.
"""
from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PROPS_DIR = ROOT / "game/assets/sprites/props"
BOSSES_DIR = ROOT / "game/assets/sprites/bosses"

def is_grid_or_bg(r: int, g: int, b: int, a: int) -> bool:
    if a < 10:
        return True
    
    # Grid lines / dark gray floor / isometric tile colors:
    # Usually low saturation (r, g, b close to each other), brightness between 15 and 90
    max_diff = max(abs(r - g), abs(g - b), abs(r - b))
    brightness = (r + g + b) / 3.0
    
    # Solid black/dark background
    if brightness < 32:
        return True
        
    # Dark gray tiles / isometric grid floor:
    # r,g,b in [20, 85] and max_diff <= 15
    if 18 <= r <= 88 and 18 <= g <= 88 and 18 <= b <= 88 and max_diff <= 16:
        return True
        
    # Checkerboard / tile grid pattern colors (slightly brownish-gray dark tiles)
    if 25 <= r <= 70 and 25 <= g <= 70 and 20 <= b <= 65 and max_diff <= 14:
        return True

    return False

def matte_file(p: Path) -> bool:
    if not p.exists() or p.suffix.lower() != ".png":
        return False
    try:
        im = Image.open(p).convert("RGBA")
    except Exception:
        return False

    w, h = im.size
    px = im.load()
    
    # 1. Flood fill from borders using is_grid_or_bg
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
        if is_grid_or_bg(r, g, b, a):
            if a != 0:
                px[x, y] = (0, 0, 0, 0)
                changed = True
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                    queue.append((nx, ny))

    # 2. Trim bounding box
    bbox = im.getbbox()
    if bbox:
        pad = 2
        crop_box = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(w, bbox[2] + pad),
            min(h, bbox[3] + pad)
        )
        im = im.crop(crop_box)
        changed = True

    if changed:
        im.save(p)
        print(f"Smart matted: {p.name}")
        return True
    return False

def main():
    count = 0
    for d in [PROPS_DIR, BOSSES_DIR]:
        for p in d.glob("*.png"):
            if p.name.endswith("_icon.png") or p.name.startswith("_"):
                continue
            if matte_file(p):
                count += 1
    print(f"Finished smart matting on {count} images.")

if __name__ == "__main__":
    main()
