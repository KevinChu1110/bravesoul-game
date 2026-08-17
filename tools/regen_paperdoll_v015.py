#!/usr/bin/env python3
"""完整紙娃娃：每件裝備 base_id 一張疊層（武器／防具／飾品）。

輸出：
  game/assets/sprites/player/paperdoll/weapon/{base_id}.png
  game/assets/sprites/player/paperdoll/armor/{base_id}.png
  game/assets/sprites/player/paperdoll/accessory/{base_id}.png

風格錨：小白 rabbit_idle_x3.png。需 GOOGLE_API_KEY。
用法：
  zsh -lic 'cd .../bravesoul-game && .venv-asset/bin/python tools/regen_paperdoll_v015.py'
  zsh -lic '... python tools/regen_paperdoll_v015.py --only rusty_blade,meager_edge'
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = ROOT / ".venv-asset" / "bin" / "python"
AG = ROOT / ".agents" / "skills" / "asset-gen" / "tools" / "asset_gen.py"
ANCHOR = ROOT / "game" / "assets" / "sprites" / "player" / "rabbit_idle_x3.png"
GEN = ROOT / "game" / "assets" / "sprites" / "_gen_paperdoll"
PD = ROOT / "game" / "assets" / "sprites" / "player" / "paperdoll"
EQ_OUT = ROOT / "game" / "assets" / "sprites" / "equipment"
WEB_EQ = ROOT / "web" / "media" / "equipment"

LOCK = (
    "CRITICAL STYLE LOCK: Match the reference white chibi rabbit hero EXACTLY — "
    "warm 16-bit chibi pixel RPG, big-head short-body toy proportions, "
    "soft cel shading, limited cozy palette, chunky readable pixels, "
    "cute not realistic, NO photorealism, NO metallic PBR, NO cinematic concept art, "
    "NO text, NO UI, NO logos, NO full character body. "
    "Same game: 勇者之魂 Brave Soul."
)

# (base_id, slot, prompt detail) — 全部裝備表
JOBS: list[tuple[str, str, str]] = [
    # —— 劍 ——
    ("rusty_blade", "weapon", "tiny chibi held rusty short sword only, brown spots, diagonal grip bottom-right, solid #00FF00 background, no rabbit"),
    ("meager_edge", "weapon", "tiny chibi held simple iron short sword starter, clean, diagonal, solid #00FF00 background, no rabbit"),
    ("knight_saber", "weapon", "tiny chibi held curved knight saber silver, diagonal, solid #00FF00 background, no rabbit"),
    ("gale_edge", "weapon", "tiny chibi held slender wind blade pale blue edge, diagonal, solid #00FF00 background, no rabbit"),
    ("dawn_blade", "weapon", "tiny chibi held golden dawn longsword soft glow still toy-like, diagonal, solid #00FF00 background, no rabbit"),
    # —— 弓 ——
    ("reed_bow", "weapon", "tiny chibi held reed short bow with arrow, toy RPG, solid #00FF00 background, no rabbit"),
    ("hawk_longbow", "weapon", "tiny chibi held tall hawk longbow feather motif, solid #00FF00 background, no rabbit"),
    # —— 法／星途刃 ——
    ("star_rod", "weapon", "tiny chibi held short star staff crystal tip purple, solid #00FF00 background, no rabbit"),
    ("star_fang", "weapon", "tiny chibi held short star dagger purple pommel, solid #00FF00 background, no rabbit"),
    ("nebula_needle", "weapon", "tiny chibi held thin nebula needle blade purple sparks, solid #00FF00 background, no rabbit"),
    ("hunt_claw", "weapon", "tiny chibi dual hunting claws bone steel chunky, solid #00FF00 background, no rabbit"),
    ("void_quill", "weapon", "tiny chibi dark purple feather quill blade, solid #00FF00 background, no rabbit"),
    # —— 拳 ——
    ("wrap_gloves", "weapon", "tiny chibi fist wraps bandages only, solid #00FF00 background, no rabbit"),
    ("iron_knuckle", "weapon", "tiny chibi iron knuckle dusters chunky, solid #00FF00 background, no rabbit"),
    # —— 斧 ——
    ("notch_axe", "weapon", "tiny chibi hand axe notched blade, solid #00FF00 background, no rabbit"),
    ("split_greataxe", "weapon", "tiny chibi large greataxe chunky cute, solid #00FF00 background, no rabbit"),
    ("anchor_axe", "weapon", "tiny chibi war axe with anchor motif, solid #00FF00 background, no rabbit"),
    # —— 鎚／鐵骨 ——
    ("anvil_hammer", "weapon", "tiny chibi small anvil war hammer, solid #00FF00 background, no rabbit"),
    ("iron_cudgel", "weapon", "tiny chibi heavy iron cudgel club, solid #00FF00 background, no rabbit"),
    ("bastion_blade", "weapon", "tiny chibi thick bastion heavy sword, solid #00FF00 background, no rabbit"),
    # —— 槍 ——
    ("ash_spear", "weapon", "tiny chibi ash wood spear, solid #00FF00 background, no rabbit"),
    ("knight_pike", "weapon", "tiny chibi knight long pike, solid #00FF00 background, no rabbit"),
    # —— 銃 ——
    ("flint_gun", "weapon", "tiny chibi fantasy flintlock pistol, solid #00FF00 background, no rabbit"),
    ("blackpowder_rifle", "weapon", "tiny chibi fantasy blackpowder long rifle, solid #00FF00 background, no rabbit"),
    # —— 鏢 ——
    ("mist_darts", "weapon", "tiny chibi throwing darts fan set, solid #00FF00 background, no rabbit"),
    ("shadow_chakram", "weapon", "tiny chibi shadow chakram ring blade, solid #00FF00 background, no rabbit"),
    # —— 水晶 ——
    ("shard_focus", "weapon", "tiny chibi floating crystal shard focus orb, solid #00FF00 background, no rabbit"),
    ("prism_scepter", "weapon", "tiny chibi prism scepter crystal staff, solid #00FF00 background, no rabbit"),
    # —— 防具（只軀幹甲／披風，對齊小白比例）——
    ("ash_mail", "armor", "chibi armor overlay torso only for reference rabbit proportions: grey ash scale mail chest shoulders, NO head NO legs NO full body, solid #00FF00 background"),
    ("knight_plate", "armor", "chibi armor overlay torso only: silver knight plate cuirass pauldrons, NO head NO legs, solid #00FF00 background"),
    ("star_veil", "armor", "chibi armor overlay: purple star veil cloak on shoulders and back only, NO head, solid #00FF00 background"),
    # —— 飾品 ——
    ("star_pendant", "accessory", "tiny chibi star pendant jewel necklace charm only, solid #00FF00 background"),
    ("oak_charm", "accessory", "tiny chibi wooden oak charm amulet only, solid #00FF00 background"),
    ("blade_ring", "accessory", "tiny chibi metal blade-motif ring only, solid #00FF00 background"),
]

# 缺 icon 的也補 inventory icon
ICON_JOBS: list[tuple[str, str]] = [
    ("reed_bow", "chibi pixel item icon: reed short bow, toy RPG on dark #2a2630"),
    ("hawk_longbow", "chibi pixel item icon: longbow with hawk feather, toy on dark #2a2630"),
    ("star_rod", "chibi pixel item icon: short star staff, toy on dark #2a2630"),
    ("wrap_gloves", "chibi pixel item icon: training fist wraps, toy on dark #2a2630"),
    ("iron_knuckle", "chibi pixel item icon: iron knuckles, toy on dark #2a2630"),
    ("notch_axe", "chibi pixel item icon: notched hand axe, toy on dark #2a2630"),
    ("split_greataxe", "chibi pixel item icon: greataxe, toy on dark #2a2630"),
    ("anvil_hammer", "chibi pixel item icon: small war hammer, toy on dark #2a2630"),
    ("ash_spear", "chibi pixel item icon: wooden spear, toy on dark #2a2630"),
    ("knight_pike", "chibi pixel item icon: knight pike, toy on dark #2a2630"),
    ("flint_gun", "chibi pixel item icon: flintlock gun fantasy, toy on dark #2a2630"),
    ("blackpowder_rifle", "chibi pixel item icon: long rifle fantasy, toy on dark #2a2630"),
    ("mist_darts", "chibi pixel item icon: throwing darts, toy on dark #2a2630"),
    ("shadow_chakram", "chibi pixel item icon: chakram ring, toy on dark #2a2630"),
    ("shard_focus", "chibi pixel item icon: crystal focus shard, toy on dark #2a2630"),
    ("prism_scepter", "chibi pixel item icon: prism scepter, toy on dark #2a2630"),
]


def run_image(prompt: str, out: Path, refs: list[Path] | None = None) -> bool:
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
    ## --image = 風格參考（小白）
    if refs:
        for r in refs:
            if r.exists():
                cmd += ["--image", str(r)]
                break
    log = out.with_suffix(".log")
    for attempt in range(1, 4):
        try:
            r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=180)
            log.write_text((r.stdout or "") + "\n" + (r.stderr or ""))
            if r.returncode == 0 and out.exists() and out.stat().st_size > 8000:
                return True
            time.sleep(1.2 * attempt)
        except subprocess.TimeoutExpired:
            print("  timeout", out.name, flush=True)
            time.sleep(2)
    print((log.read_text() if log.exists() else "")[-300:], flush=True)
    return False


def matte_green(src: Path, dest: Path, max_side: int) -> bool:
    from PIL import Image

    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # pure-ish green screen
            if g > 140 and g > r + 40 and g > b + 40:
                px[x, y] = (0, 0, 0, 0)
            elif r < 50 and g < 50 and b < 50 and a > 200:
                # keep dark metal
                pass
    bb = im.getbbox()
    if not bb:
        return False
    pad = 4
    im = im.crop((max(0, bb[0] - pad), max(0, bb[1] - pad), min(w, bb[2] + pad), min(h, bb[3] + pad)))
    long = max(im.size)
    if long > max_side:
        s = max_side / long
        im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.Resampling.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest)
    return True


def matte_dark_icon(src: Path, dest: Path, max_side: int = 200) -> bool:
    from PIL import Image

    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r < 55 and g < 55 and b < 60:
                px[x, y] = (0, 0, 0, 0)
    bb = im.getbbox()
    if not bb:
        return False
    im = im.crop(bb)
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


def max_side_for(slot: str) -> int:
    if slot == "weapon":
        return 72
    if slot == "armor":
        return 96
    return 48


def gen_paperdoll(only: set[str] | None) -> list:
    results = []
    for base_id, slot, detail in JOBS:
        if only and base_id not in only:
            continue
        out_dir = PD / slot
        dest = out_dir / f"{base_id}.png"
        work = GEN / slot / f"{base_id}.png"
        print(f"PD {slot}/{base_id} ...", flush=True)
        prompt = (
            f"{LOCK} Use reference only for chibi style scale of the rabbit world. "
            f"{detail}. Isolated single object, centered."
        )
        ok = run_image(prompt, work, refs=[ANCHOR] if ANCHOR.exists() else None)
        if not ok:
            results.append({"id": base_id, "ok": False})
            continue
        clean = GEN / slot / f"{base_id}_clean.png"
        matte_green(work, clean, max_side_for(slot))
        src = clean if clean.exists() else work
        out_dir.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(src.read_bytes())
        # 同步 inventory icon（若尚無）
        icon = EQ_OUT / f"{base_id}.png"
        if not icon.exists() or icon.stat().st_size < 500:
            icon.write_bytes(src.read_bytes())
            web_card(src, WEB_EQ / f"{base_id}.png", 256)
        print(f"  OK {dest} ({dest.stat().st_size})", flush=True)
        results.append({"id": base_id, "ok": True})
        time.sleep(0.15)
    return results


def gen_missing_icons(only: set[str] | None) -> list:
    results = []
    for base_id, detail in ICON_JOBS:
        if only and base_id not in only:
            continue
        dest = EQ_OUT / f"{base_id}.png"
        if dest.exists() and dest.stat().st_size > 800 and not only:
            continue
        work = GEN / "icon" / f"{base_id}.png"
        print(f"ICON {base_id} ...", flush=True)
        prompt = f"{LOCK} {detail}. Centered large readable icon."
        ok = run_image(prompt, work, refs=[ANCHOR] if ANCHOR.exists() else None)
        if not ok:
            results.append({"id": base_id, "ok": False})
            continue
        clean = GEN / "icon" / f"{base_id}_clean.png"
        matte_dark_icon(work, clean)
        src = clean if clean.exists() else work
        EQ_OUT.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(src.read_bytes())
        web_card(src, WEB_EQ / f"{base_id}.png", 256)
        print(f"  OK icon {base_id}", flush=True)
        results.append({"id": base_id, "ok": True})
        time.sleep(0.15)
    return results


def verify_against_table() -> int:
    table = ROOT / "game" / "data" / "tables" / "equipment.json"
    data = json.loads(table.read_text())
    missing = []
    for bid, defn in data.get("bases", {}).items():
        slot = str(defn.get("slot", "weapon"))
        p = PD / slot / f"{bid}.png"
        if not p.exists():
            missing.append(f"{slot}/{bid}")
    print("missing paperdoll:", len(missing))
    for m in missing:
        print(" ", m)
    return len(missing)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma base_ids")
    ap.add_argument("--icons-only", action="store_true")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    only = {x.strip() for x in args.only.split(",") if x.strip()} or None

    if args.verify:
        return 1 if verify_against_table() else 0

    if not ANCHOR.exists():
        print("missing anchor", ANCHOR, file=sys.stderr)
        return 1
    if not AG.exists():
        print("missing asset_gen", AG, file=sys.stderr)
        return 1
    if not PY.exists():
        print("missing venv python", PY, file=sys.stderr)
        return 1

    GEN.mkdir(parents=True, exist_ok=True)
    all_r: list = []
    if not args.icons_only:
        print("=== paperdoll per base_id ===", flush=True)
        all_r += gen_paperdoll(only)
    print("=== missing icons ===", flush=True)
    all_r += gen_missing_icons(only)
    ok_n = sum(1 for r in all_r if r.get("ok"))
    print(f"done ok={ok_n}/{len(all_r)}", flush=True)
    verify_against_table()
    return 0 if ok_n == len(all_r) or ok_n > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
