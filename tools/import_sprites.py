#!/usr/bin/env python3
"""
Bake engine-ready 2D sprites for 翠嶺·兔勇者.

Source: sideprojects/bravesoul/bravesoul/bot/assets (legacy Discord bot)
Output: game/assets/sprites/

Usage:
  python3 tools/import_sprites.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
LEG = ROOT.parent / "bravesoul" / "bravesoul" / "bot" / "assets"
if not LEG.exists():
    LEG = Path("/Users/kevin.chu/develop/sideprojects/bravesoul/bravesoul/bot/assets")
OUT = ROOT / "game" / "assets" / "sprites"


def ensure_rgba(im: Image.Image) -> Image.Image:
    return im if im.mode == "RGBA" else im.convert("RGBA")


def trim_alpha(im: Image.Image, pad: int = 4) -> Image.Image:
    im = ensure_rgba(im)
    bbox = im.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    l, t = max(0, l - pad), max(0, t - pad)
    r, b = min(im.width, r + pad), min(im.height, b + pad)
    return im.crop((l, t, r, b))


def fit_canvas(im: Image.Image, w: int, h: int, bottom: bool = True) -> Image.Image:
    im = ensure_rgba(im)
    im.thumbnail((w, h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = (w - im.width) // 2
    y = (h - im.height) if bottom else (h - im.height) // 2
    canvas.paste(im, (x, y), im)
    return canvas


def nearest_scale(im: Image.Image, factor: int) -> Image.Image:
    return im.resize((im.width * factor, im.height * factor), Image.Resampling.NEAREST)


def save(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG")
    print(f"  {path.relative_to(OUT.parent.parent)} {im.size}")


def pixel_chibi(palette: dict, ear: bool = False, hat: str | None = None, prop: str | None = None) -> Image.Image:
    W, H = 32, 40
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1):
            for x in range(x0, x1):
                if 0 <= x < W and 0 <= y < H:
                    px[x, y] = c

    skin = palette.get("skin", (240, 220, 200, 255))
    hair = palette.get("hair", (60, 50, 45, 255))
    cloth = palette.get("cloth", (90, 100, 120, 255))
    accent = palette.get("accent", (180, 140, 80, 255))
    outline = (30, 25, 28, 255)
    rect(10, 18, 22, 32, cloth)
    rect(10, 8, 22, 18, skin)
    rect(10, 6, 22, 10, hair)
    px[13, 12] = outline
    px[18, 12] = outline
    rect(11, 32, 15, 38, palette.get("leg", (50, 45, 55, 255)))
    rect(17, 32, 21, 38, palette.get("leg", (50, 45, 55, 255)))
    rect(7, 20, 10, 28, skin)
    rect(22, 20, 25, 28, skin)
    if ear:
        rect(11, 2, 14, 8, skin)
        rect(18, 2, 21, 8, skin)
        rect(12, 3, 13, 7, (255, 180, 180, 255))
        rect(19, 3, 20, 7, (255, 180, 180, 255))
    if hat == "beard":
        rect(12, 14, 20, 18, (180, 180, 185, 255))
        rect(9, 5, 23, 9, (100, 100, 110, 255))
    if hat == "hood":
        rect(9, 5, 23, 12, (70, 75, 100, 255))
    if hat == "bandana":
        rect(10, 7, 22, 10, accent)
    if hat == "viking":
        rect(9, 4, 23, 9, (90, 70, 50, 255))
        rect(8, 5, 10, 8, (200, 200, 210, 255))
        rect(22, 5, 24, 8, (200, 200, 210, 255))
    if hat == "star":
        rect(14, 3, 18, 6, (220, 200, 100, 255))
    if hat == "apron":
        rect(12, 22, 20, 30, (180, 160, 140, 255))
    if prop == "hammer":
        rect(24, 16, 27, 28, (80, 70, 60, 255))
        rect(22, 14, 29, 17, (140, 140, 150, 255))
    if prop == "tea":
        rect(24, 22, 28, 27, (200, 180, 120, 255))
    if prop == "bow":
        rect(24, 14, 26, 30, (90, 70, 50, 255))
    return nearest_scale(im, 2)


def prop_icon(kind: str) -> Image.Image:
    W, H = 32, 32
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if kind == "sword":
        d.rectangle([14, 4, 17, 26], fill=(160, 160, 170, 255))
        d.rectangle([10, 22, 21, 25], fill=(120, 90, 50, 255))
    elif kind == "save":
        d.ellipse([4, 6, 28, 28], fill=(90, 110, 130, 255), outline=(200, 220, 230, 255))
    elif kind == "flag":
        d.rectangle([8, 4, 11, 28], fill=(80, 70, 60, 255))
        d.polygon([(11, 5), (26, 10), (11, 16)], fill=(180, 160, 70, 255))
    elif kind == "fire":
        d.polygon([(16, 6), (22, 18), (16, 16), (10, 18)], fill=(240, 120, 40, 255))
    elif kind == "exit":
        d.rectangle([6, 8, 26, 28], fill=(70, 60, 50, 255), outline=(140, 120, 90, 255))
        d.polygon([(16, 12), (24, 20), (16, 20)], fill=(200, 180, 100, 255))
    elif kind == "camp":
        d.polygon([(4, 24), (16, 8), (28, 24)], fill=(100, 80, 40, 255))
    elif kind == "tower":
        d.rectangle([10, 8, 22, 28], fill=(100, 95, 90, 255))
        d.polygon([(8, 8), (16, 2), (24, 8)], fill=(80, 75, 70, 255))
    elif kind == "bell":
        d.ellipse([8, 10, 24, 26], fill=(180, 160, 80, 255))
    elif kind == "tea":
        d.ellipse([8, 14, 24, 28], fill=(160, 120, 80, 255))
    elif kind == "herb":
        d.ellipse([10, 16, 22, 28], fill=(60, 120, 50, 255))
    elif kind == "nest":
        d.ellipse([4, 16, 28, 28], fill=(90, 70, 40, 255))
    elif kind == "cliff":
        d.polygon([(4, 28), (10, 10), (22, 12), (28, 28)], fill=(110, 90, 70, 255))
    elif kind == "dock":
        d.rectangle([4, 18, 28, 26], fill=(100, 80, 50, 255))
    elif kind == "forge":
        d.rectangle([6, 14, 26, 28], fill=(80, 50, 40, 255))
        d.ellipse([10, 8, 22, 18], fill=(240, 100, 40, 255))
    elif kind == "path":
        d.polygon([(8, 20), (16, 8), (24, 20), (20, 20), (20, 28), (12, 28), (12, 20)], fill=(160, 140, 90, 255))
    else:
        d.rectangle([8, 8, 24, 24], fill=(120, 120, 130, 255))
    return nearest_scale(im, 2)


def ring_fx(color, name, spokes=False):
    S = 128
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S // 2
    for r in range(48, 56):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color)
    if spokes:
        for ang in range(0, 360, 45):
            rad = math.radians(ang)
            x2 = cx + int(50 * math.cos(rad))
            y2 = cy + int(50 * math.sin(rad))
            d.line([cx, cy, x2, y2], fill=color, width=2)
    save(im, OUT / f"fx/{name}.png")


def main() -> None:
    if not LEG.exists():
        raise SystemExit(f"Legacy assets not found: {LEG}")

    print("player")
    rabbit = trim_alpha(Image.open(LEG / "hero_rabbit.png"))
    idle = fit_canvas(rabbit, 48, 64, bottom=True)
    save(idle, OUT / "player/rabbit_idle.png")
    save(nearest_scale(idle, 3), OUT / "player/rabbit_idle_x3.png")
    for i, dy in enumerate([0, -2, 0, 2]):
        frame = fit_canvas(rabbit, 48, 64, bottom=True)
        shifted = Image.new("RGBA", (48, 64), (0, 0, 0, 0))
        if i % 2 == 1:
            sq = frame.resize((48, 60), Image.Resampling.LANCZOS)
            shifted.paste(sq, (0, 4 + dy), sq)
        else:
            shifted.paste(frame, (0, dy), frame)
        save(shifted, OUT / f"player/rabbit_walk_{i}.png")
        save(nearest_scale(shifted, 3), OUT / f"player/rabbit_walk_{i}_x3.png")
    save(fit_canvas(rabbit, 160, 200, bottom=True), OUT / "player/rabbit_battle.png")

    print("bosses")
    for key, fname in {
        "wolf": "wolf.png",
        "leo": "boss_lion.png",
        "fog": "boss_fox.png",
        "abo": "boss_panda.png",
        "demon": "boss_demon.png",
        "falcon": "boss_falcon.png",
        "boar": "boss_boar.png",
    }.items():
        im = trim_alpha(Image.open(LEG / fname))
        save(fit_canvas(im, 220, 240), OUT / f"bosses/{key}.png")
        save(fit_canvas(im, 56, 64), OUT / f"bosses/{key}_icon.png")

    print("maps")
    for key, fname in {
        "town": "bg_knight_keep.png",
        "wild": "bg_knight_keep.png",
        "mist_village": "bg_ninja_village.png",
        "dojo": "bg_monk_dojo.png",
        "forest": "bg_ranger_forest.png",
        "coast": "bg_viking_coast.png",
        "tower": "bg_mage_tower.png",
    }.items():
        im = Image.open(LEG / fname).convert("RGB").resize((960, 540), Image.Resampling.LANCZOS)
        save(im.convert("RGBA"), OUT / f"maps/{key}_bg.png")

    for key, fname in {
        "town": "area_knight_keep.png",
        "mist_village": "area_ninja_village.png",
        "dojo": "area_monk_dojo.png",
        "forest": "area_ranger_forest.png",
        "coast": "area_viking_coast.png",
        "tower": "area_mage_tower.png",
    }.items():
        im = Image.open(LEG / fname).convert("RGBA").resize((960, 220), Image.Resampling.LANCZOS)
        save(im, OUT / f"maps/{key}_banner.png")

    base = Image.open(LEG / "bg_knight_keep.png").convert("RGB").resize((960, 540), Image.Resampling.LANCZOS)
    night = Image.blend(ImageEnhance.Brightness(base).enhance(0.45), Image.new("RGB", base.size, (80, 30, 20)), 0.35)
    save(night.convert("RGBA"), OUT / "maps/village_bg.png")
    dawn = Image.blend(ImageEnhance.Brightness(base).enhance(0.75), Image.new("RGB", base.size, (40, 70, 100)), 0.25)
    save(dawn.convert("RGBA"), OUT / "maps/road_bg.png")

    for key, fname in {
        "wolf": "battle_knight_keep_1.png",
        "leo": "battle_knight_keep_2.png",
        "fog": "battle_ninja_village_1.png",
        "abo": "battle_monk_dojo_1.png",
        "demon": "battle_mage_tower_1.png",
        "falcon": "battle_ranger_forest_1.png",
        "boar": "battle_viking_coast_1.png",
    }.items():
        p = LEG / fname
        if not p.exists():
            continue
        im = ImageEnhance.Brightness(Image.open(p).convert("RGB").resize((1280, 720), Image.Resampling.LANCZOS)).enhance(0.55)
        save(im.convert("RGBA"), OUT / f"maps/battle_{key}.png")

    print("npcs")
    npcs = {
        "maisui": dict(skin=(245, 210, 190, 255), hair=(90, 55, 40, 255), cloth=(180, 90, 70, 255), ear=True),
        "greybeard": dict(skin=(220, 200, 180, 255), hair=(90, 90, 100, 255), cloth=(100, 105, 120, 255), hat="beard"),
        "ding": dict(skin=(210, 160, 130, 255), hair=(40, 35, 35, 255), cloth=(90, 70, 55, 255), hat="apron", prop="hammer"),
        "star": dict(skin=(230, 210, 220, 255), hair=(50, 45, 80, 255), cloth=(70, 80, 140, 255), hat="star"),
        "sprout": dict(skin=(250, 220, 200, 255), hair=(60, 120, 50, 255), cloth=(100, 160, 90, 255)),
        "fog_hide": dict(skin=(200, 200, 220, 255), hair=(40, 40, 50, 255), cloth=(80, 90, 120, 255), hat="hood"),
        "acha": dict(skin=(240, 210, 180, 255), hair=(50, 40, 35, 255), cloth=(160, 120, 90, 255), prop="tea"),
        "wind_ear": dict(skin=(220, 200, 180, 255), hair=(70, 110, 80, 255), cloth=(60, 100, 70, 255), hat="bandana", prop="bow"),
        "tide_roar": dict(skin=(200, 160, 130, 255), hair=(80, 50, 40, 255), cloth=(100, 70, 50, 255), hat="viking"),
        "duanye": dict(skin=(210, 200, 190, 255), hair=(50, 45, 40, 255), cloth=(70, 60, 80, 255), hat="hood"),
    }
    for name, conf in npcs.items():
        ear = conf.pop("ear", False)
        hat = conf.pop("hat", None)
        prop = conf.pop("prop", None)
        save(pixel_chibi(conf, ear=ear, hat=hat, prop=prop), OUT / f"npcs/{name}.png")

    print("props")
    for k in ["sword", "save", "flag", "fire", "exit", "camp", "tower", "bell", "tea", "herb", "nest", "cliff", "dock", "forge", "path"]:
        save(prop_icon(k), OUT / f"props/{k}.png")

    print("fx")
    ring_fx((255, 120, 40, 220), "fire_ring")
    ring_fx((120, 220, 255, 220), "time_clock", spokes=True)
    ring_fx((180, 220, 255, 200), "wind_cut")
    ring_fx((200, 160, 80, 220), "rockfall")
    ring_fx((100, 255, 140, 200), "safe_zone")
    im = Image.new("RGBA", (160, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, a in enumerate([40, 120, 200, 120, 40]):
        y = 8 + i * 6
        d.rectangle([10, y, 150, y + 3], fill=(200, 230, 255, a))
    save(im, OUT / "fx/wind_cut_line.png")
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for x, y, r in [(30, 20, 8), (60, 10, 12), (90, 25, 7), (50, 40, 10)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(120, 100, 80, 230))
    save(im, OUT / "fx/rockfall_rocks.png")
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 8, 88, 88], outline=(255, 230, 100, 255), width=4)
    save(im, OUT / "fx/parry_flash.png")

    lines = ["# Sprite Manifest\n\nGenerated by `tools/import_sprites.py`.\n\n"]
    for sub in ["player", "bosses", "npcs", "maps", "fx", "props"]:
        lines.append(f"## {sub}\n")
        for f in sorted((OUT / sub).glob("*.png")):
            im = Image.open(f)
            lines.append(f"- `{f.name}` {im.size[0]}×{im.size[1]}\n")
        lines.append("\n")
    (OUT / "MANIFEST.md").write_text("".join(lines), encoding="utf-8")
    print("DONE")


if __name__ == "__main__":
    main()
