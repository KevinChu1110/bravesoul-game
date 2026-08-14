#!/usr/bin/env python3
"""Bake boss combat poses from standing art.
  python3 tools/gen_boss_poses.py
Output: game/assets/sprites/bosses/poses/<name>/{idle,telegraph,attack,recover}.png
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "game" / "assets" / "sprites" / "bosses"
BOSSES = [
    "wolf", "leo", "fog", "abo", "demon", "falcon", "boar",
    "wrath", "tide", "statue", "echo", "chrono",
]


def fit_canvas(im: Image.Image, w: int, h: int) -> Image.Image:
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    im.thumbnail((w, h), Image.Resampling.LANCZOS)
    c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    c.paste(im, ((w - im.width) // 2, h - im.height), im)
    return c


def rotate_about_bottom(im: Image.Image, angle: float) -> Image.Image:
    w, h = im.size
    pad = int(max(w, h) * 0.25)
    big = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    big.paste(im, (pad, pad), im)
    cx, cy = pad + w // 2, pad + h - 4
    rot = big.rotate(angle, resample=Image.Resampling.BICUBIC, center=(cx, cy), expand=False)
    bb = rot.getbbox()
    if not bb:
        return im
    return fit_canvas(rot.crop(bb), w, h)


def add_edge_glow(im: Image.Image, color=(255, 80, 40, 180), expand=5) -> Image.Image:
    alpha = im.split()[3]
    mask = alpha.point(lambda a: 255 if a > 20 else 0)
    outline = mask.filter(ImageFilter.MaxFilter(expand))
    ring = ImageChops.subtract(outline, mask)
    glow_layer = Image.new("RGBA", im.size, color)
    glow_layer.putalpha(ring)
    out = Image.alpha_composite(Image.new("RGBA", im.size, (0, 0, 0, 0)), glow_layer)
    return Image.alpha_composite(out, im)


def lunge(im: Image.Image, dx: int = -18) -> Image.Image:
    w, h = im.size
    c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    c.paste(im, (dx, 0), im)
    return c


def squash(im: Image.Image, sy: float = 0.92, sx: float = 1.08) -> Image.Image:
    w, h = im.size
    nw, nh = max(1, int(w * sx)), max(1, int(h * sy))
    return fit_canvas(im.resize((nw, nh), Image.Resampling.LANCZOS), w, h)


def brighten(im: Image.Image, f: float = 1.15) -> Image.Image:
    rgb = ImageEnhance.Brightness(im.convert("RGB")).enhance(f)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.08)
    out = rgb.convert("RGBA")
    out.putalpha(im.split()[3])
    return out


def make_poses(src: Image.Image) -> dict:
    idle = fit_canvas(src, 220, 240)
    tele = add_edge_glow(brighten(rotate_about_bottom(idle, 8), 1.12), (255, 200, 60, 160), 5)
    atk = add_edge_glow(
        brighten(lunge(squash(rotate_about_bottom(idle, -12), 0.9, 1.12), -22), 1.2),
        (255, 70, 50, 200),
        5,
    )
    rec = brighten(squash(idle, 0.94, 1.04), 0.95)
    return {"idle": idle, "telegraph": tele, "attack": atk, "recover": rec}


def main() -> None:
    for name in BOSSES:
        p = ROOT / f"{name}.png"
        if not p.exists():
            print("skip", name)
            continue
        out_dir = ROOT / "poses" / name
        out_dir.mkdir(parents=True, exist_ok=True)
        for k, im in make_poses(Image.open(p)).items():
            im.save(out_dir / f"{k}.png")
        print("ok", name)


if __name__ == "__main__":
    main()
