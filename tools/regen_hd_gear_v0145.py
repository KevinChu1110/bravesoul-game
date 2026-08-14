#!/usr/bin/env python3
"""0.14.5 Gemini 精繪：裝備 icon、武器疊層、防具、NPC。
需 GOOGLE_API_KEY。約 7¢/張。
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = ROOT / ".venv-asset/bin/python"
AG = ROOT / ".agents/skills/asset-gen/tools/asset_gen.py"
REF = ROOT / "web/media/gemini/keyart_hero.png"
GEN = ROOT / "game/assets/sprites/_gen_hd_v0145"
EQ_OUT = ROOT / "game/assets/sprites/equipment"
WPN_OUT = ROOT / "game/assets/sprites/player/weapons"
ARM_OUT = ROOT / "game/assets/sprites/player/armor"
ACC_OUT = ROOT / "game/assets/sprites/player/accessories"
NPC_OUT = ROOT / "game/assets/sprites/npcs"
WEB_EQ = ROOT / "web/media/equipment"

STYLE = (
    "Premium 16-bit painterly pixel-art for game 勇者之魂 Brave Soul, "
    "soft rounded pixels, rich color, high contrast readable silhouette, "
    "cohesive with reference key art, NO text, NO logos, NO UI, NO watermarks"
)

EQUIP: list[tuple[str, str]] = [
    ("rusty_blade", "old rusty short sword weapon icon, chipped blade, worn leather wrap, item icon centered"),
    ("meager_edge", "simple iron short sword '微末之刃' style starter blade, clean humble steel, item icon"),
    ("knight_saber", "knight cavalry saber curved blade polished steel gold hilt, item icon"),
    ("gale_edge", "swift wind-themed slender sword with pale blue edge streaks, item icon"),
    ("dawn_blade", "legendary dawn longsword glowing warm gold-white edge, ornate hilt, item icon"),
    ("star_fang", "short star dagger with purple crystal pommel and constellation etchings, item icon"),
    ("nebula_needle", "thin magical needle-blade weapon with nebula purple-blue shimmer, item icon"),
    ("hunt_claw", "dual hunting claws weapon bone and steel, savage, item icon"),
    ("void_quill", "void feather blade quill weapon dark purple ethereal edge, item icon"),
    ("iron_cudgel", "heavy iron bone club mace crude powerful, item icon"),
    ("bastion_blade", "thick bastion greatblade heavy defense-oriented sword, item icon"),
    ("anchor_axe", "heavy war axe with anchor motif iron, item icon"),
    ("ash_mail", "ash-grey scale mail armor torso piece, item icon"),
    ("knight_plate", "damaged knight plate cuirass armor with crest, item icon"),
    ("star_veil", "flowing star-silk cloak purple with sparkles armor cloak, item icon"),
    ("star_pendant", "small star-dust pendant jewel accessory glowing soft blue, item icon"),
    ("oak_charm", "wooden oak heart charm amulet accessory, item icon"),
    ("blade_ring", "metal battle ring with tiny blade motif accessory, item icon"),
]

WEAPONS: list[tuple[str, str]] = [
    ("sword", "chibi-scale held sword for top-down rabbit hero, diagonal, solid #00FF00 background"),
    ("bow", "chibi-scale wooden bow and arrow, solid #00FF00 background"),
    ("magic", "chibi-scale magic staff with glowing star crystal tip, solid #00FF00 background"),
    ("fist", "chibi-scale combat knuckle wraps gloves, solid #00FF00 background"),
    ("axe", "chibi-scale battle axe, solid #00FF00 background"),
    ("hammer", "chibi-scale war hammer, solid #00FF00 background"),
    ("spear", "chibi-scale long spear, solid #00FF00 background"),
    ("gun", "chibi-scale fantasy flintlock pistol, solid #00FF00 background"),
    ("dart", "chibi-scale throwing darts kunai set, solid #00FF00 background"),
    ("crystal", "chibi-scale floating magic crystal orb, solid #00FF00 background"),
]

ARMOR: list[tuple[str, str]] = [
    ("plate", "chibi rabbit-sized iron plate armor overlay chest shoulders, solid #00FF00 background, no head"),
    ("leather", "chibi rabbit-sized brown leather vest armor overlay, solid #00FF00 background, no head"),
    ("veil", "chibi rabbit-sized flowing purple star cloak veil overlay, solid #00FF00 background, no head"),
    ("cloth", "chibi rabbit-sized green cloth tunic armor overlay, solid #00FF00 background, no head"),
]

ACC: list[tuple[str, str]] = [
    ("pendant", "tiny star pendant jewelry accessory icon, solid #00FF00 background"),
    ("ring", "tiny golden battle ring accessory icon, solid #00FF00 background"),
]

NPCS: list[tuple[str, str]] = [
    ("duanye", "chibi pixel elderly scholar holding ancient scroll, grey robes, full body front 3/4, solid #00FF00 background"),
    ("wind_ear", "chibi pixel forest ranger elf-like with green cloak feather earring, full body, solid #00FF00 background"),
    ("tide_roar", "chibi pixel viking sea captain blue cloak and wave motif, full body, solid #00FF00 background"),
]


def run_image(prompt: str, out: Path, aspect: str = "1:1") -> bool:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(PY if PY.exists() else sys.executable),
        str(AG), "image",
        "--model", "gemini", "--size", "1K",
        "--aspect-ratio", aspect,
        "--prompt", prompt,
        "-o", str(out),
    ]
    if REF.exists():
        cmd.extend(["--image", str(REF)])
    log = out.with_suffix(".log")
    for attempt in range(1, 4):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            log.write_text((r.stdout or "") + "\n" + (r.stderr or ""))
            if r.returncode == 0 and out.exists() and out.stat().st_size > 20000:
                return True
            time.sleep(1.2 * attempt)
        except subprocess.TimeoutExpired:
            time.sleep(2)
    return False


def green_matte(src: Path, dest: Path, max_side: int = 256) -> bool:
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if (g - r > 40 and g - b > 40 and g > 100) or (g > 200 and r < 80 and b < 80):
                px[x, y] = (r, g, b, 0)
    bb = im.getbbox()
    if not bb:
        return False
    pad = 8
    im = im.crop((max(0, bb[0] - pad), max(0, bb[1] - pad), min(w, bb[2] + pad), min(h, bb[3] + pad)))
    long = max(im.size)
    if long > max_side:
        s = max_side / long
        im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.Resampling.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest)
    return True


def card_bg(src: Path, dest: Path, size: int = 256, bg=(42, 38, 48, 255)) -> None:
    from PIL import Image, ImageDraw
    im = Image.open(src).convert("RGBA")
    # if still opaque green-ish corners, matte first to temp
    canvas = Image.new("RGBA", (size, size), bg)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([8, 8, size - 8, size - 8], radius=24, fill=(bg[0] + 10, bg[1] + 10, bg[2] + 12, 255))
    im.thumbnail((size - 48, size - 48), Image.Resampling.LANCZOS)
    ox = (size - im.size[0]) // 2
    oy = (size - im.size[1]) // 2
    canvas.paste(im, (ox, oy), im)
    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest)


def gen_batch(jobs: list[tuple[str, str]], work_dir: Path, install_dir: Path, kind: str, max_side: int, card: bool) -> list:
    results = []
    for name, detail in jobs:
        work = work_dir / f"{name}.png"
        print(f"GEN {kind} {name} ...", flush=True)
        prompt = (
            f"Keep premium painterly pixel style of the reference. {STYLE}. "
            f"Isolated single subject, centered. {detail}."
        )
        if "green" in detail or "#00FF00" in detail:
            pass
        else:
            # equip icons: dark soft bg in prompt for cleaner web cards
            if kind == "equip":
                prompt += " Solid dark charcoal gray background #2a2630, not checkerboard."
        ok = run_image(prompt, work)
        if not ok:
            print(f"  FAIL {name}", flush=True)
            results.append({"name": name, "ok": False})
            continue
        clean = work_dir / f"{name}_clean.png"
        if "#00FF00" in detail or "green" in detail.lower() or kind in ("weapon", "armor", "acc", "npc"):
            green_matte(work, clean, max_side=max_side)
            src = clean if clean.exists() else work
        else:
            # equip: try corner matte dark bg
            from PIL import Image
            im = Image.open(work).convert("RGBA")
            # keep as-is for equip full card gen
            src = work
            green_matte(work, clean, max_side=max_side)  # may no-op if no green
            if clean.exists() and clean.stat().st_size > 5000:
                # check transparency
                t = Image.open(clean)
                if t.mode == "RGBA":
                    src = clean
        install = install_dir / f"{name}.png"
        if card:
            card_bg(src, install, size=256)
            # also write transparent for game if clean
            if clean.exists():
                green_matte(work, install_dir / f"{name}.png", max_side=max_side)
        else:
            from shutil import copyfile
            if src.exists():
                install.write_bytes(src.read_bytes())
            else:
                install.write_bytes(work.read_bytes())
        print(f"  OK {name} -> {install} ({install.stat().st_size})", flush=True)
        results.append({"name": name, "ok": True, "path": str(install)})
        time.sleep(0.25)
    return results


def main() -> int:
    GEN.mkdir(parents=True, exist_ok=True)
    all_r = []
    print("=== equipment icons ===", flush=True)
    # equip: generate on dark bg then save both game (cropped) and web card
    eq_work = GEN / "equip"
    for name, detail in EQUIP:
        work = eq_work / f"{name}.png"
        print(f"GEN equip {name} ...", flush=True)
        prompt = (
            f"Keep premium painterly pixel style of the reference. {STYLE}. "
            f"Game inventory item icon, single centered object, solid dark charcoal background #2a2630. "
            f"{detail}."
        )
        ok = run_image(prompt, work)
        if not ok:
            print("  FAIL", name, flush=True)
            all_r.append({"name": name, "ok": False})
            continue
        # matte near-dark bg
        from PIL import Image
        im = Image.open(work).convert("RGBA")
        px = im.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                # dark charcoal bg
                if r < 55 and g < 55 and b < 65:
                    px[x, y] = (r, g, b, 0)
                if g - r > 40 and g - b > 40 and g > 100:
                    px[x, y] = (r, g, b, 0)
        bb = im.getbbox()
        if bb:
            im = im.crop(bb)
        long = max(im.size)
        if long > 220:
            s = 220 / long
            im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.Resampling.LANCZOS)
        EQ_OUT.mkdir(parents=True, exist_ok=True)
        game_path = EQ_OUT / f"{name}.png"
        im.save(game_path)
        # web card with dark frame
        card_bg(game_path, WEB_EQ / f"{name}.png", size=256, bg=(42, 38, 48, 255))
        print(f"  OK {name}", game_path.stat().st_size, flush=True)
        all_r.append({"name": name, "ok": True})
        time.sleep(0.25)

    print("=== weapons ===", flush=True)
    all_r += gen_batch(WEAPONS, GEN / "wpn", WPN_OUT, "weapon", 64, card=False)
    # also web weapons
    WEB_W = WEB_EQ / "weapons"
    WEB_W.mkdir(parents=True, exist_ok=True)
    for name, _ in WEAPONS:
        p = WPN_OUT / f"{name}.png"
        if p.exists():
            card_bg(p, WEB_W / f"{name}.png", size=160, bg=(40, 36, 42, 255))

    print("=== armor ===", flush=True)
    all_r += gen_batch(ARMOR, GEN / "arm", ARM_OUT, "armor", 96, card=False)
    WEB_A = WEB_EQ / "armor"
    WEB_A.mkdir(parents=True, exist_ok=True)
    for name, _ in ARMOR:
        p = ARM_OUT / f"{name}.png"
        if p.exists():
            card_bg(p, WEB_A / f"{name}.png", size=160, bg=(36, 40, 48, 255))

    print("=== accessories ===", flush=True)
    all_r += gen_batch(ACC, GEN / "acc", ACC_OUT, "acc", 48, card=False)

    print("=== npcs ===", flush=True)
    all_r += gen_batch(NPCS, GEN / "npc", NPC_OUT, "npc", 192, card=False)

    summary = GEN / "summary.json"
    summary.write_text(json.dumps(all_r, indent=2, ensure_ascii=False))
    ok = sum(1 for r in all_r if r.get("ok"))
    print(f"done {ok}/{len(all_r)}", summary, flush=True)
    return 0 if ok > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
