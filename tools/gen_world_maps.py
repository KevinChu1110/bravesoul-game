#!/usr/bin/env python3
"""Batch-generate unique exploration map backgrounds for the expanded world (0.9).

Uses Gemini via asset_gen. Requires GOOGLE_API_KEY.
Style-anchored with --image parent bg when available.
Cost: ~7¢ each (1K) × N maps.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_GEN = ROOT / ".agents/skills/asset-gen/tools/asset_gen.py"
PY = ROOT / ".venv-asset/bin/python"
OUT_DIR = ROOT / "game/assets/sprites/maps/_gen_world"
INSTALL_DIR = ROOT / "game/assets/sprites/maps"
MAPS_DIR = INSTALL_DIR

STYLE = (
    "16-bit pixel art RPG exploration background, top-down oblique view, "
    "soft painterly pixels, Chinese fantasy world 翠嶺大陸, atmospheric lighting, "
    "no UI, no text, no logos, no characters, no rabbits, game-ready seamless scenic plate, "
    "readable large landmarks, 16:9 wide"
)

# (art_id, prompt, ref_art_id or None)
JOBS: list[tuple[str, str, str | None]] = [
    ("village_mill", "rolling wheat fields with a giant broken windmill and miller's hut, dusk amber light, rural ruin", "village"),
    ("village_cave", "mountain cave mouth near a burned village, dark stone, glowing moss, eerie torchless entrance", "village"),
    ("village_grave", "hilltop village graveyard at night, willow trees, stone markers, dim lanterns, melancholic", "village"),
    ("road_bridge", "stone arch bridge over a deep ravine on a dirt highway at dawn, mist in canyon", "road"),
    ("road_inn", "half-collapsed roadside inn courtyard, broken sign, empty stables, cold hearth smoke", "road"),
    ("road_ruins", "ancient courier station ruins with broken columns and star-carved mosaic floor", "road"),
    ("town_market", "medieval lower-city market square with empty stalls, stone streets, knight fortress walls in distance", "town"),
    ("town_sewers", "dark stone sewer tunnels with pipes, moss, shallow water reflections, torch niches", "town"),
    ("barracks_yard", "knight barracks training yard with sand ring, weapon racks, torn banners", "town"),
    ("wild_ravine", "charred plain edge opening into a deep cracked ravine, rope bridge, blackened soil", "wild"),
    ("wild_leo_court", "stone lion courtyard before a fortress inner keep, torn honor banners, ash sky", "wild"),
    ("cross_north", "winding mountain path north of a crossroads, pine trees, cloud sea view", "road"),
    ("cross_east", "dead tree plain path toward a dark wizard tower silhouette, ash wind, purple horizon", "road"),
    ("caravan_camp", "traveling merchant caravan camp with covered wagons, campfire, goods piles at dusk", "road"),
    ("starfall_plain", "night plain under a sky of shooting stars and constellation lines etched on ground, soft blue glow", "road"),
    ("blackflame_scar", "land scarred by black purple flame, charred earth, obsidian cracks, ominous vents", "tower"),
    ("hunting_grounds", "hunting grounds at blackflame scar edge, ash dirt field, bone markers, hunting posts, purple flame vents distant, dusk", "blackflame_scar"),
    ("mist_cliff", "foggy cliff overlook above a sea of mist, bell tower silhouette, pale blue lanterns", "mist_village"),
    ("mist_shrine", "inner fog shrine with white fox statue, incense smoke, prayer strips, soft silver light", "mist_village"),
    ("mist_mirror", "endless mirror corridor in fog, reflective floors, eerie symmetry, cool blue-violet", "mist_village"),
    ("dojo_inner", "martial dojo inner courtyard with zen pond, wooden halls, stone garden, quiet green", "dojo"),
    ("dojo_bamboo", "dense bamboo forest path with stream stones and soft green light shafts", "dojo"),
    ("dojo_peak", "mountain peak training platform above clouds, wind flags, sunrise gold and jade", "dojo"),
    ("forest_canopy", "tree canopy layer with rope bridges and nest platforms high above green forest", "forest"),
    ("forest_ruins", "ancient ranger stone ruins reclaimed by moss and roots inside deep forest", "forest"),
    ("forest_lake", "still forest lake with reed shore, log dock, mirror reflections, calm green-blue", "forest"),
    ("coast_harbor", "viking deep harbor with longship, wooden crane, warehouses, cold ocean", "coast"),
    ("coast_cave", "tidal sea cave with tide pools, crystals, pirate marks, ocean light from holes", "coast"),
    ("coast_wreck", "shipwreck bay with broken hull and mast on rocky shore, gulls sky, harsh wind", "coast"),
    ("tower_foyer", "dark wizard tower foyer, black stone pillars, sealing murals, purple torchlight", "tower"),
    ("tower_stairs", "spiral staircase shaft inside a black tower, narrow windows, ascending gloom", "tower"),
    ("tower_memory", "surreal memory chamber with floating orbs of light and throne shadow, violet haze", "tower"),
]


def run_one(art_id: str, detail: str, ref: str | None) -> dict:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{art_id}_bg.png"
    if out.exists() and out.stat().st_size > 50_000:
        return {"ok": True, "path": str(out), "skipped": True, "art_id": art_id}

    prompt = f"{STYLE}. Scene: {detail}."
    cmd = [
        str(PY if PY.exists() else sys.executable),
        str(ASSET_GEN),
        "image",
        "--model", "gemini",
        "--size", "1K",
        "--aspect-ratio", "16:9",
        "--prompt", prompt,
        "-o", str(out),
    ]
    if ref:
        ref_path = MAPS_DIR / f"{ref}_bg.png"
        if ref_path.exists():
            cmd.extend(["--image", str(ref_path)])
            cmd[cmd.index("--prompt") + 1] = (
                f"Keep the same pixel-art style, palette family and painterly look as the reference. "
                f"Change only the scene content: {detail}. {STYLE}."
            )

    log = OUT_DIR / f"{art_id}.log"
    for attempt in range(1, 4):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            log.write_text((r.stdout or "") + "\n" + (r.stderr or ""))
            if r.returncode == 0 and out.exists():
                try:
                    data = json.loads(r.stdout.strip().splitlines()[-1])
                except Exception:
                    data = {"ok": True, "path": str(out)}
                data["art_id"] = art_id
                data["attempt"] = attempt
                return data
            err = (r.stderr or r.stdout or "")[-400:]
            if "503" in err or "high demand" in err.lower() or "RESOURCE" in err:
                time.sleep(8 * attempt)
                continue
            return {"ok": False, "art_id": art_id, "error": err, "attempt": attempt}
        except subprocess.TimeoutExpired:
            time.sleep(5)
            continue
    return {"ok": False, "art_id": art_id, "error": "max retries"}


def install(art_id: str) -> None:
    src = OUT_DIR / f"{art_id}_bg.png"
    if not src.exists():
        return
    # resize to 1280x720 with PIL
    try:
        from PIL import Image
    except ImportError:
        dest = INSTALL_DIR / f"{art_id}_bg.png"
        dest.write_bytes(src.read_bytes())
        return
    im = Image.open(src).convert("RGBA")
    im = im.resize((1280, 720), Image.Resampling.LANCZOS)
    dest = INSTALL_DIR / f"{art_id}_bg.png"
    im.save(dest, "PNG")


def main() -> int:
    if not os.environ.get("GOOGLE_API_KEY"):
        print("GOOGLE_API_KEY not set", file=sys.stderr)
        return 2
    only = set(sys.argv[1:]) if len(sys.argv) > 1 else None
    ok_n = fail_n = skip_n = 0
    cost = 0
    for art_id, detail, ref in JOBS:
        if only and art_id not in only:
            continue
        print(f"==> {art_id}", flush=True)
        res = run_one(art_id, detail, ref)
        if res.get("skipped"):
            print(f"  skip existing", flush=True)
            skip_n += 1
            install(art_id)
            continue
        if res.get("ok"):
            ok_n += 1
            cost += int(res.get("cost_cents") or 7)
            install(art_id)
            print(f"  OK {res.get('path')}", flush=True)
        else:
            fail_n += 1
            print(f"  FAIL {res.get('error', '')[:200]}", flush=True)
        time.sleep(1.5)
    print(json.dumps({"ok": ok_n, "fail": fail_n, "skip": skip_n, "cost_cents_est": cost}))
    return 0 if fail_n == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
