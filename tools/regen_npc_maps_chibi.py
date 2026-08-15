#!/usr/bin/env python3
"""0.14.8 以小白為錨：主 NPC 重產 + 核心地圖 chibi 化。

需 GOOGLE_API_KEY。風格鎖死 chibi 16-bit，禁止寫實。
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
ANCHOR = ROOT / "game" / "assets" / "sprites" / "player" / "rabbit_idle_x3.png"
GEN = ROOT / "game" / "assets" / "sprites" / "_gen_chibi_0148"
NPC_OUT = ROOT / "game" / "assets" / "sprites" / "npcs"
MAP_OUT = ROOT / "game" / "assets" / "sprites" / "maps"
MAP_BAK = MAP_OUT / "_backup_chibi_0148"

LOCK = (
    "CRITICAL STYLE LOCK: Match the reference chibi rabbit hero EXACTLY — "
    "warm 16-bit chibi pixel RPG, big-head short-body toy proportions, "
    "soft cel shading, limited cozy palette, chunky readable pixels, "
    "cute not realistic, NO photorealism, NO cinematic concept art, "
    "NO text, NO UI, NO logos. Same game 勇者之魂 Brave Soul."
)

# (id, description) — full body explore sprites
NPCS: list[tuple[str, str]] = [
    ("greybeard", "elderly chibi knight NPC grey beard, worn armor, grumpy kind, full body front 3/4"),
    ("ding", "chibi blacksmith NPC, apron, hammer at belt, soot smudges, full body"),
    ("star", "chibi stargazer sage NPC, star robes, gentle, full body"),
    ("maisui", "chibi young village traveler girl, cloak, full body"),
    ("sprout", "chibi orphan child with wooden practice sword, full body"),
    ("acha", "chibi martial tea master, green-brown robes, calm, full body"),
    ("fog_hide", "chibi ninja in pale fog cloak and mask, full body"),
    ("silk", "chibi elegant scribe woman with scrolls, full body"),
    ("amber", "chibi merchant woman with goods pack, full body"),
    ("ronin", "chibi dark ronin swordsman black cloak, full body"),
    ("knight_orphan", "chibi young knight orphan small armor, full body"),
    ("merchant", "chibi traveling merchant with hat, full body"),
    ("duanye", "chibi elderly scholar holding scroll, grey robes, full body"),
    ("wind_ear", "chibi forest ranger with green cloak and bow, full body"),
    ("tide_roar", "chibi viking sea captain blue cloak, full body"),
]

# core maps — chibi top-down plates
MAPS: list[tuple[str, str]] = [
    ("village", "burned rural village top-down oblique, cute toy houses thatch ruins dirt paths, dawn"),
    ("road", "dirt highway hills morning, cute milepost, distant tiny fortress silhouette"),
    ("town", "knight fortress lower city square, cute stone streets banners keep walls"),
    ("town_market", "cute medieval market stalls crates, knight walls distant"),
    ("crossroads", "six-way dirt crossroads cute waystones path signs open plain"),
    ("mist_village", "foggy cute ninja village wooden walkways pale lanterns mist sea"),
    ("mist_shrine", "cute fog shrine white fox statue incense prayer strips silver light"),
    ("dojo", "cute martial dojo courtyard zen pond wooden halls bamboo garden"),
    ("dojo_peak", "cute mountain peak training platform above soft cloud sea sunrise"),
    ("forest", "cute lush ranger forest path moss light shafts green canopy"),
    ("forest_lake", "cute still forest lake reed shore log dock reflections"),
    ("coast", "cute cold rocky coast tiny longships cliffs teal sea"),
    ("coast_harbor", "cute viking harbor wooden cranes warehouses longship dock"),
    ("coast_wreck", "cute shipwreck bay broken hull rocky shore"),
    ("tower_foyer", "cute dark wizard tower foyer purple torchlight black stone"),
    ("blackflame_scar", "cute land scar purple black flame vents ash, still chibi not horror-real"),
    ("starfall_plain", "cute night plain soft stars constellation glow camp feel"),
    ("caravan_camp", "cute merchant caravan wagons campfire dusk"),
    ("hunting_grounds", "cute ash hunting field posts bone markers dusk"),
    ("barracks_yard", "cute knight barracks sand ring weapon racks banners"),
]


def run_image(prompt: str, out: Path, aspect: str = "1:1") -> bool:
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
        aspect,
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
            if r.returncode == 0 and out.exists() and out.stat().st_size > 20000:
                return True
            time.sleep(1.2 * attempt)
        except subprocess.TimeoutExpired:
            time.sleep(2)
    return False


def matte_green(src: Path, dest: Path, max_side: int = 192) -> bool:
    from PIL import Image

    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if (g - r > 35 and g - b > 35 and g > 90) or (g > 180 and r < 100 and b < 100):
                px[x, y] = (r, g, b, 0)
            elif g > 140 and r < 120 and b < 120 and (g - max(r, b)) > 25:
                px[x, y] = (r, g, b, 0)
    bb = im.getbbox()
    if not bb:
        return False
    pad = 8
    im = im.crop((max(0, bb[0] - pad), max(0, bb[1] - pad), min(w, bb[2] + pad), min(h, bb[3] + pad)))
    # bottom-align into square-ish canvas
    long = max(im.size)
    if long > max_side:
        s = max_side / long
        im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.Resampling.LANCZOS)
    # prefer taller portrait for NPCs
    tw = max(im.size[0], int(max_side * 0.7))
    th = max(im.size[1], max_side)
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.paste(im, ((tw - im.size[0]) // 2, th - im.size[1]), im)
    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest)
    return True


def gen_npcs() -> list:
    results = []
    work_dir = GEN / "npc"
    for nid, detail in NPCS:
        work = work_dir / f"{nid}_raw.png"
        print(f"NPC {nid} ...", flush=True)
        prompt = (
            f"{LOCK} Same chibi world as the reference rabbit. "
            f"Full-body NPC character sprite, front 3/4, solid pure green #00FF00 background. "
            f"Character: {detail}. No weapons oversized; cute readable."
        )
        ok = run_image(prompt, work, "1:1")
        if not ok:
            print(f"  FAIL {nid}", flush=True)
            results.append({"id": nid, "ok": False})
            continue
        dest = NPC_OUT / f"{nid}.png"
        # backup
        if dest.exists():
            bak = GEN / "npc_backup"
            bak.mkdir(parents=True, exist_ok=True)
            (bak / f"{nid}.png").write_bytes(dest.read_bytes())
        matte_green(work, dest, max_side=192)
        print(f"  OK {nid} {dest.stat().st_size}", flush=True)
        results.append({"id": nid, "ok": True, "path": str(dest)})
        time.sleep(0.2)
    return results


def gen_maps() -> list:
    results = []
    work_dir = GEN / "maps"
    MAP_BAK.mkdir(parents=True, exist_ok=True)
    for mid, detail in MAPS:
        work = work_dir / f"{mid}_bg.png"
        print(f"MAP {mid} ...", flush=True)
        prompt = (
            f"{LOCK} Exploration map background plate ONLY — no player characters, no rabbits, no UI. "
            f"Top-down oblique cute chibi pixel world, toy-like landmarks, soft painterly pixels, "
            f"readable paths, 16:9 wide. Scene: {detail}."
        )
        ok = run_image(prompt, work, "16:9")
        if not ok:
            print(f"  FAIL {mid}", flush=True)
            results.append({"id": mid, "ok": False})
            continue
        dest = MAP_OUT / f"{mid}_bg.png"
        if dest.exists():
            (MAP_BAK / f"{mid}_bg.png").write_bytes(dest.read_bytes())
        # install as-is (no green matte for maps)
        dest.write_bytes(work.read_bytes())
        print(f"  OK {mid} {dest.stat().st_size}", flush=True)
        results.append({"id": mid, "ok": True, "path": str(dest)})
        time.sleep(0.25)
    return results


def main() -> int:
    if not ANCHOR.exists():
        print("missing anchor", ANCHOR, file=sys.stderr)
        return 1
    GEN.mkdir(parents=True, exist_ok=True)
    all_r = []
    print("=== NPCs ===", flush=True)
    all_r += gen_npcs()
    print("=== MAPS chibi ===", flush=True)
    all_r += gen_maps()
    summary = GEN / "summary.json"
    summary.write_text(json.dumps(all_r, indent=2, ensure_ascii=False))
    ok = sum(1 for r in all_r if r.get("ok"))
    print(f"done {ok}/{len(all_r)} {summary}", flush=True)
    return 0 if ok > len(all_r) // 2 else 1


if __name__ == "__main__":
    raise SystemExit(main())
