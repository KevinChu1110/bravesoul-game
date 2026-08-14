#!/usr/bin/env python3
"""以小白為唯一風格錨，重產裝備 icon + 武器／防具／飾品疊層。

強制 chibi 16-bit，禁止寫實靜物。需 GOOGLE_API_KEY。
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = ROOT / ".venv-asset" / "bin" / "python"
AG = ROOT / ".agents" / "skills" / "asset-gen" / "tools" / "asset_gen.py"
# 唯一風格錨：已定稿的小白
ANCHOR = ROOT / "game" / "assets" / "sprites" / "player" / "rabbit_idle_x3.png"
GEN = ROOT / "game" / "assets" / "sprites" / "_gen_style_lock"
EQ_OUT = ROOT / "game" / "assets" / "sprites" / "equipment"
WPN_OUT = ROOT / "game" / "assets" / "sprites" / "player" / "weapons"
ARM_OUT = ROOT / "game" / "assets" / "sprites" / "player" / "armor"
ACC_OUT = ROOT / "game" / "assets" / "sprites" / "player" / "accessories"
WEB_EQ = ROOT / "web" / "media" / "equipment"

# 鎖定：跟小白同一宇宙，禁止半寫實
LOCK = (
    "CRITICAL STYLE LOCK: Match the reference rabbit hero EXACTLY — "
    "warm 16-bit chibi pixel RPG, big-head short-body toy proportions, "
    "soft cel shading, limited cozy palette, chunky readable pixels, "
    "cute not realistic, NO photorealism, NO metallic PBR, NO cinematic concept art, "
    "NO museum weapon photo, NO text, NO UI, NO logos. "
    "Same game: 勇者之魂 Brave Soul."
)

EQUIP: list[tuple[str, str]] = [
    ("rusty_blade", "chibi pixel item icon: tiny rusty short sword, toy-like, cute proportions"),
    ("meager_edge", "chibi pixel item icon: simple humble iron short sword starter weapon, toy-like"),
    ("knight_saber", "chibi pixel item icon: cute knight saber curved blade, toy RPG prop"),
    ("gale_edge", "chibi pixel item icon: slender wind sword pale blue edge, cute not epic-real"),
    ("dawn_blade", "chibi pixel item icon: golden dawn longsword simplified cute glow, still chibi toy style"),
    ("star_fang", "chibi pixel item icon: short star dagger purple crystal pommel, cute"),
    ("nebula_needle", "chibi pixel item icon: thin magic needle blade purple sparkles, chibi"),
    ("hunt_claw", "chibi pixel item icon: dual hunting claws bone steel, cute chunky"),
    ("void_quill", "chibi pixel item icon: dark purple feather blade, cute chibi prop"),
    ("iron_cudgel", "chibi pixel item icon: heavy iron club mace, chunky cute"),
    ("bastion_blade", "chibi pixel item icon: thick heavy defense sword, chunky chibi"),
    ("anchor_axe", "chibi pixel item icon: war axe with anchor motif, cute chunky"),
    ("ash_mail", "chibi pixel item icon: grey scale mail armor piece torso, cute"),
    ("knight_plate", "chibi pixel item icon: knight plate cuirass, cute chibi armor icon"),
    ("star_veil", "chibi pixel item icon: purple star cloak folded, cute fabric"),
    ("star_pendant", "chibi pixel item icon: tiny star pendant jewel, cute accessory"),
    ("oak_charm", "chibi pixel item icon: wooden oak charm amulet, cute"),
    ("blade_ring", "chibi pixel item icon: metal ring with tiny blade motif, cute"),
]

WEAPONS: list[tuple[str, str]] = [
    ("sword", "tiny chibi held sword matching rabbit hero hand scale, diagonal, solid #00FF00 background"),
    ("bow", "tiny chibi bow and arrow rabbit-hand scale, solid #00FF00 background"),
    ("magic", "tiny chibi magic staff star tip rabbit scale, solid #00FF00 background"),
    ("fist", "tiny chibi knuckle wraps rabbit scale, solid #00FF00 background"),
    ("axe", "tiny chibi battle axe rabbit scale, solid #00FF00 background"),
    ("hammer", "tiny chibi war hammer rabbit scale, solid #00FF00 background"),
    ("spear", "tiny chibi spear rabbit scale, solid #00FF00 background"),
    ("gun", "tiny chibi fantasy flintlock rabbit scale, solid #00FF00 background"),
    ("dart", "tiny chibi throwing darts rabbit scale, solid #00FF00 background"),
    ("crystal", "tiny chibi floating crystal orb rabbit scale, solid #00FF00 background"),
]

ARMOR: list[tuple[str, str]] = [
    ("plate", "chibi armor overlay for the reference rabbit body proportions: iron plate chest and shoulders only, no head no legs, solid #00FF00 background"),
    ("leather", "chibi armor overlay for reference rabbit: brown leather vest only, no head, solid #00FF00 background"),
    ("veil", "chibi armor overlay for reference rabbit: purple star cloak on shoulders/back only, no head, solid #00FF00 background"),
    ("cloth", "chibi armor overlay for reference rabbit: simple green tunic, no head, solid #00FF00 background"),
]

ACC: list[tuple[str, str]] = [
    ("pendant", "tiny chibi star pendant accessory, solid #00FF00 background"),
    ("ring", "tiny chibi gold battle ring, solid #00FF00 background"),
]


def run_image(prompt: str, out: Path) -> bool:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(PY if PY.exists() else sys.executable),
        str(AG),
        "image",
        "--model",
        "gemini",
        "--size",
        "1K",
        "--aspect-ratio",
        "1:1",
        "--prompt",
        prompt,
        "-o",
        str(out),
    ]
    if ANCHOR.exists():
        cmd.extend(["--image", str(ANCHOR)])
    log = out.with_suffix(".log")
    for attempt in range(1, 4):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            log.write_text((r.stdout or "") + "\n" + (r.stderr or ""))
            if r.returncode == 0 and out.exists() and out.stat().st_size > 15000:
                return True
            time.sleep(1.2 * attempt)
        except subprocess.TimeoutExpired:
            time.sleep(2)
    return False


def matte_green_or_dark(src: Path, dest: Path, max_side: int) -> bool:
    from PIL import Image

    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # green screen
            if (g - r > 35 and g - b > 35 and g > 90) or (g > 180 and r < 100 and b < 100):
                px[x, y] = (r, g, b, 0)
            # dark charcoal card bg
            elif r < 50 and g < 50 and b < 58:
                px[x, y] = (r, g, b, 0)
    bb = im.getbbox()
    if not bb:
        return False
    pad = 6
    im = im.crop((max(0, bb[0] - pad), max(0, bb[1] - pad), min(w, bb[2] + pad), min(h, bb[3] + pad)))
    long = max(im.size)
    if long > max_side:
        s = max_side / long
        im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.Resampling.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest)
    return True


def web_card(src: Path, dest: Path, size: int = 256) -> None:
    from PIL import Image, ImageDraw

    im = Image.open(src).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), (42, 38, 48, 255))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([10, 10, size - 10, size - 10], radius=22, fill=(52, 48, 58, 255))
    im.thumbnail((size - 56, size - 56), Image.Resampling.LANCZOS)
    ox = (size - im.size[0]) // 2
    oy = (size - im.size[1]) // 2
    canvas.paste(im, (ox, oy), im)
    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest)


def gen_equip() -> list:
    results = []
    work_dir = GEN / "equip"
    for name, detail in EQUIP:
        work = work_dir / f"{name}.png"
        print(f"EQ {name} ...", flush=True)
        prompt = (
            f"{LOCK} Use the reference ONLY for style and proportions of the rabbit world. "
            f"Generate a single chibi pixel inventory ITEM ICON on solid dark charcoal #2a2630. "
            f"Subject: {detail}. Centered, large, readable at small size."
        )
        ok = run_image(prompt, work)
        if not ok:
            print(f"  FAIL {name}", flush=True)
            results.append({"name": name, "ok": False})
            continue
        clean = work_dir / f"{name}_clean.png"
        matte_green_or_dark(work, clean, max_side=200)
        src = clean if clean.exists() else work
        EQ_OUT.mkdir(parents=True, exist_ok=True)
        # game: transparent
        dest_g = EQ_OUT / f"{name}.png"
        dest_g.write_bytes(src.read_bytes())
        # web card
        web_card(src, WEB_EQ / f"{name}.png", 256)
        print(f"  OK {name} {dest_g.stat().st_size}", flush=True)
        results.append({"name": name, "ok": True})
        time.sleep(0.2)
    return results


def gen_overlays(jobs: list[tuple[str, str]], out_dir: Path, max_side: int, tag: str) -> list:
    results = []
    work_dir = GEN / tag
    for name, detail in jobs:
        work = work_dir / f"{name}.png"
        print(f"{tag.upper()} {name} ...", flush=True)
        prompt = (
            f"{LOCK} Same character art style as the reference rabbit. "
            f"{detail}. Isolated, centered, solid pure green #00FF00 background."
        )
        ok = run_image(prompt, work)
        if not ok:
            print(f"  FAIL {name}", flush=True)
            results.append({"name": name, "ok": False})
            continue
        clean = work_dir / f"{name}_clean.png"
        matte_green_or_dark(work, clean, max_side=max_side)
        out_dir.mkdir(parents=True, exist_ok=True)
        dest = out_dir / f"{name}.png"
        dest.write_bytes((clean if clean.exists() else work).read_bytes())
        print(f"  OK {name} {dest.stat().st_size}", flush=True)
        results.append({"name": name, "ok": True})
        time.sleep(0.2)
    return results


def main() -> int:
    if not ANCHOR.exists():
        print("missing style anchor", ANCHOR, file=sys.stderr)
        return 1
    if not AG.exists():
        print("missing asset_gen", file=sys.stderr)
        return 1
    GEN.mkdir(parents=True, exist_ok=True)
    all_r: list = []
    print("=== style lock equip (anchor=小白) ===", flush=True)
    all_r += gen_equip()
    print("=== weapons ===", flush=True)
    all_r += gen_overlays(WEAPONS, WPN_OUT, 64, "wpn")
    WEB_W = WEB_EQ / "weapons"
    WEB_W.mkdir(parents=True, exist_ok=True)
    for name, _ in WEAPONS:
        p = WPN_OUT / f"{name}.png"
        if p.exists():
            web_card(p, WEB_W / f"{name}.png", 160)
    print("=== armor ===", flush=True)
    all_r += gen_overlays(ARMOR, ARM_OUT, 96, "arm")
    WEB_A = WEB_EQ / "armor"
    WEB_A.mkdir(parents=True, exist_ok=True)
    for name, _ in ARMOR:
        p = ARM_OUT / f"{name}.png"
        if p.exists():
            web_card(p, WEB_A / f"{name}.png", 160)
    print("=== accessories ===", flush=True)
    all_r += gen_overlays(ACC, ACC_OUT, 48, "acc")
    summary = GEN / "summary.json"
    summary.write_text(json.dumps(all_r, indent=2, ensure_ascii=False))
    ok = sum(1 for r in all_r if r.get("ok"))
    print(f"done {ok}/{len(all_r)}", summary, flush=True)
    return 0 if ok >= len(all_r) // 2 else 1


if __name__ == "__main__":
    raise SystemExit(main())
