#!/usr/bin/env python3
"""
Batch Matte Sprites for BraveSoul (勇者之魂)
Removes solid gray/black grid backgrounds from props and boss sprites, converting them to clean transparent PNGs.
"""
from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PROPS_DIR = ROOT / "game/assets/sprites/props"
BOSSES_DIR = ROOT / "game/assets/sprites/bosses"
NPCS_DIR = ROOT / "game/assets/sprites/npcs"

def matte_image(file_path: Path) -> bool:
    if not file_path.exists() or file_path.suffix.lower() != ".png":
        return False
    
    try:
        im = Image.open(file_path).convert("RGBA")
    except Exception as e:
        print(f"Error opening {file_path}: {e}")
        return False

    w, h = im.size
    px = im.load()

    # Determine background color from corners
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    
    # Check if corners are already transparent
    transparent_corners = sum(1 for c in corners if c[3] < 10)
    if transparent_corners >= 3:
        # Already transparent corners, but check if there's an internal background block or grid
        # Let's perform a flood fill or color threshold from edge pixels
        pass

    # Flood fill background from border pixels
    visited = set()
    queue = []

    # Add all border pixels to queue
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))

    def is_bg_pixel(r, g, b, a):
        if a < 15:
            return True
        # Check dark gray / dark grid colors: r,g,b all between 20 and 95, low saturation
        max_diff = max(abs(r - g), abs(g - b), abs(r - b))
        brightness = (r + g + b) / 3.0
        if max_diff < 18 and (brightness < 100 or (30 <= r <= 95 and 30 <= g <= 95 and 30 <= b <= 95)):
            return True
        # Check pure dark background or green screen
        if (g - r > 35 and g - b > 35 and g > 80) or (r < 40 and g < 40 and b < 40):
            return True
        return False

    # Perform flood fill from border
    modified = False
    while queue:
        x, y = queue.pop(0)
        if (x, y) in visited:
            continue
        visited.add((x, y))
        
        r, g, b, a = px[x, y]
        if is_bg_pixel(r, g, b, a):
            if a != 0:
                px[x, y] = (r, g, b, 0)
                modified = True
            
            # Check neighbors
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                    queue.append((nx, ny))

    # Also crop empty border transparent space if modified or has transparent alpha
    bbox = im.getbbox()
    if bbox and (bbox != (0, 0, w, h)):
        # Crop tight bbox with 2px padding
        pad = 2
        crop_box = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(w, bbox[2] + pad),
            min(h, bbox[3] + pad)
        )
        im = im.crop(crop_box)
        modified = True

    if modified:
        im.save(file_path)
        print(f"Matted & cleaned: {file_path.name}")
        return True
    return False

def main():
    count = 0
    dirs = [PROPS_DIR, BOSSES_DIR, NPCS_DIR]
    for d in dirs:
        if not d.exists():
            continue
        print(f"Processing directory: {d.name}...")
        for p in d.glob("*.png"):
            if p.name.endswith("_icon.png") or p.name.startswith("_"):
                continue
            if matte_image(p):
                count += 1
    print(f"Done! Cleaned {count} sprite files.")

if __name__ == "__main__":
    main()
