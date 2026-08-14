#!/usr/bin/env python3
"""0.14 視覺大修：用 Gemini 重產核心地圖底圖 + prop 套件 + 探索 NPC。

風格錨定：web/media/gemini/keyart_hero.png（與官網一致的 painterly pixel）
成本：約 7¢/張 × N；預設只跑「核心包」。

用法：
  .venv-asset/bin/python tools/regen_visuals_v014.py            # 核心
  .venv-asset/bin/python tools/regen_visuals_v014.py --all-maps  # 全部 map bg
  .venv-asset/bin/python tools/regen_visuals_v014.py --props-only
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = ROOT / ".venv-asset/bin/python"
AG = ROOT / ".agents/skills/asset-gen/tools/asset_gen.py"
MAPS = ROOT / "game/assets/sprites/maps"
PROPS = ROOT / "game/assets/sprites/props"
NPCS = ROOT / "game/assets/sprites/npcs"
GEN = ROOT / "game/assets/sprites/_gen_v014"
STYLE_REF = ROOT / "web/media/gemini/keyart_hero.png"

STYLE = (
    "Premium 16-bit painterly pixel-art RPG, soft rounded pixels, warm atmospheric light, "
    "Chinese-European fantasy blend for game 勇者之魂 Brave Soul, cohesive with the reference key art, "
    "top-down oblique exploration view, game-ready, NO UI, NO text, NO logos, NO watermarks"
)

# (art_id, scene detail) — 核心六域 + 常見次場景
CORE_MAPS: list[tuple[str, str]] = [
    ("village", "burned rural village at soft dawn, thatch ruins, dirt paths, willow trees, emotional home village plate"),
    ("road", "dirt highway through hills at morning, milepost, distant fortress silhouette, travel atmosphere"),
    ("town", "knight fortress lower city square, stone streets, banners, keep walls, ash-grey sky"),
    ("town_market", "medieval market square with stalls, crates, knight walls distant, busy but empty of people"),
    ("crossroads", "six-way dirt crossroads with waystones and path signs, open plain, cloud sky"),
    ("mist_village", "foggy ninja village with wooden walkways, pale blue lanterns, sea of mist, shrine roofs"),
    ("mist_shrine", "inner fog shrine white fox statue, incense, prayer strips, cool silver light"),
    ("dojo", "martial dojo courtyard zen pond wooden halls stone garden bamboo, soft green light"),
    ("dojo_peak", "mountain peak training platform above cloud sea, wind flags, sunrise gold and jade"),
    ("forest", "lush ranger forest path moss stones light shafts green canopy"),
    ("forest_lake", "still forest lake reed shore log dock mirror reflections calm green-blue"),
    ("coast", "cold viking rocky coast longships distant cliffs harsh wind teal sea"),
    ("coast_harbor", "deep viking harbor wooden cranes warehouses longship dock cold ocean"),
    ("coast_wreck", "shipwreck bay broken hull rocky shore gulls sky harsh wind"),
    ("tower_foyer", "dark wizard tower foyer black stone pillars purple torchlight sealing murals"),
    ("blackflame_scar", "land scarred by black-purple flame obsidian cracks ash sky ominous vents"),
    ("starfall_plain", "night plain shooting stars constellation glow soft blue grass lonely quiet"),
    ("caravan_camp", "merchant caravan camp wagons campfire goods piles warm dusk orange vs cool blue"),
    ("hunting_grounds", "ash hunting field bone markers posts purple flame vents distant dusk"),
    ("barracks_yard", "knight barracks sand training ring weapon racks torn banners"),
]

# props as solid magenta BG for rembg (or solid green)
PROP_JOBS: list[tuple[str, str]] = [
    ("tree", "single stylized pixel oak tree for top-down RPG, full canopy, solid #00FF00 background"),
    ("pine", "single stylized pixel pine tree top-down RPG, solid #00FF00 background"),
    ("rock", "pixel art rock boulder cluster top-down RPG, solid #00FF00 background"),
    ("barrel", "wooden barrel pixel prop top-down RPG, solid #00FF00 background"),
    ("crate", "wooden crate pixel prop top-down RPG, solid #00FF00 background"),
    ("lantern", "hanging paper lantern pixel prop, soft glow, solid #00FF00 background"),
    ("sign", "wooden waystone signpost pixel prop, solid #00FF00 background"),
    ("well", "stone village well pixel prop top-down, solid #00FF00 background"),
    ("campfire", "campfire with logs pixel prop, orange flame, solid #00FF00 background"),
    ("forge", "small blacksmith anvil and forge pixel prop, solid #00FF00 background"),
    ("shrine", "small fox shrine stone pixel prop, solid #00FF00 background"),
    ("boat", "small longboat pixel prop top-down side, solid #00FF00 background"),
    ("hut", "small thatch hut building pixel prop top-down, solid #00FF00 background"),
    ("gate", "stone arch gate pixel prop, solid #00FF00 background"),
    ("banner", "torn knight banner on pole pixel prop, solid #00FF00 background"),
]

NPC_JOBS: list[tuple[str, str]] = [
    ("greybeard", "chibi pixel elderly knight with grey beard and armor, full body front 3/4, solid #00FF00 background, 勇者之魂 style"),
    ("ding", "chibi pixel blacksmith with hammer apron soot, full body, solid #00FF00 background"),
    ("star", "chibi pixel stargazer sage with robes and star amulet, full body, solid #00FF00 background"),
    ("maisui", "chibi pixel young village girl traveler cloak, full body, solid #00FF00 background"),
    ("sprout", "chibi pixel orphan child with wooden practice sword, full body, solid #00FF00 background"),
    ("acha", "chibi pixel martial master green robe bamboo staff, full body, solid #00FF00 background"),
    ("fog_hide", "chibi pixel ninja in pale fog cloak mask, full body, solid #00FF00 background"),
    ("silk", "chibi pixel elegant scribe woman with scrolls, full body, solid #00FF00 background"),
    ("amber", "chibi pixel merchant woman with pack of goods, full body, solid #00FF00 background"),
    ("ronin", "chibi pixel dark flame ronin swordsman black cloak, full body, solid #00FF00 background"),
    ("knight_orphan", "chibi pixel young knight orphan small armor, full body, solid #00FF00 background"),
    ("merchant", "chibi pixel traveling merchant with cart hat, full body, solid #00FF00 background"),
]


def run_image(prompt: str, out: Path, ref: Path | None = None, aspect: str = "16:9") -> dict:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(PY if PY.exists() else sys.executable),
        str(AG),
        "image",
        "--model", "gemini",
        "--size", "1K",
        "--aspect-ratio", aspect,
        "--prompt", prompt,
        "-o", str(out),
    ]
    if ref and ref.exists():
        cmd.extend(["--image", str(ref)])
    log = out.with_suffix(".log")
    for attempt in range(1, 4):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            log.write_text((r.stdout or "") + "\n" + (r.stderr or ""))
            if r.returncode == 0 and out.exists() and out.stat().st_size > 20_000:
                try:
                    data = json.loads((r.stdout or "").strip().splitlines()[-1])
                except Exception:
                    data = {"ok": True, "path": str(out)}
                data["path"] = str(out)
                return data
            time.sleep(1.5 * attempt)
        except subprocess.TimeoutExpired:
            time.sleep(2)
    return {"ok": False, "path": str(out), "error": "failed"}


def gen_map(art_id: str, detail: str, force: bool = False) -> dict:
    install = MAPS / f"{art_id}_bg.png"
    work = GEN / "maps" / f"{art_id}_bg.png"
    if install.exists() and install.stat().st_size > 50_000 and not force:
        # still regenerate if force_core? we always regen core pack when --force
        pass
    if work.exists() and work.stat().st_size > 50_000 and not force:
        install.write_bytes(work.read_bytes())
        return {"ok": True, "skipped": True, "path": str(install), "art_id": art_id}

    prompt = (
        f"Keep the same premium painterly pixel-fantasy color richness and soft lighting as the reference. "
        f"Change only the scene to an exploration map background. {STYLE}. "
        f"Scene (no characters): {detail}."
    )
    ref = STYLE_REF if STYLE_REF.exists() else None
    # also try existing map as weak ref if style ref missing
    if ref is None and (MAPS / f"{art_id}_bg.png").exists():
        ref = MAPS / f"{art_id}_bg.png"
    res = run_image(prompt, work, ref=ref, aspect="16:9")
    if res.get("ok") is not False and work.exists():
        # backup old
        if install.exists():
            bak = MAPS / "_backup_v014"
            bak.mkdir(exist_ok=True)
            (bak / f"{art_id}_bg.png").write_bytes(install.read_bytes())
        install.write_bytes(work.read_bytes())
        res["installed"] = str(install)
        res["art_id"] = art_id
        return res
    res["art_id"] = art_id
    return res


def gen_prop(name: str, detail: str, force: bool = False) -> dict:
    work = GEN / "props" / f"{name}.png"
    install = PROPS / f"{name}.png"
    if install.exists() and install.stat().st_size > 15_000 and not force:
        return {"ok": True, "skipped": True, "path": str(install), "name": name}
    prompt = (
        f"{STYLE}. Isolated single prop sprite, centered, {detail}. "
        f"Bold readable silhouette for top-down RPG, high contrast."
    )
    res = run_image(prompt, work, ref=STYLE_REF if STYLE_REF.exists() else None, aspect="1:1")
    if work.exists() and work.stat().st_size > 10_000:
        # try rembg if available
        clean = GEN / "props_clean" / f"{name}.png"
        clean.parent.mkdir(parents=True, exist_ok=True)
        rembg = ROOT / ".agents/skills/asset-gen/tools/rembg_matting.py"
        if rembg.exists():
            subprocess.run(
                [str(PY if PY.exists() else sys.executable), str(rembg), str(work), "-o", str(clean)],
                capture_output=True, text=True, timeout=120,
            )
            src = clean if clean.exists() and clean.stat().st_size > 5_000 else work
        else:
            src = work
        install.write_bytes(src.read_bytes())
        res["installed"] = str(install)
        res["name"] = name
        return res
    res["name"] = name
    return res


def gen_npc(name: str, detail: str, force: bool = False) -> dict:
    work = GEN / "npcs" / f"{name}.png"
    install = NPCS / f"{name}.png"
    if install.exists() and install.stat().st_size > 15_000 and not force:
        return {"ok": True, "skipped": True, "path": str(install), "name": name}
    prompt = (
        f"{STYLE}. Isolated chibi character sprite, full body, facing camera slightly 3/4, "
        f"centered, readable at small size, {detail}."
    )
    res = run_image(prompt, work, ref=STYLE_REF if STYLE_REF.exists() else None, aspect="1:1")
    if work.exists() and work.stat().st_size > 10_000:
        clean = GEN / "npcs_clean" / f"{name}.png"
        clean.parent.mkdir(parents=True, exist_ok=True)
        rembg = ROOT / ".agents/skills/asset-gen/tools/rembg_matting.py"
        if rembg.exists():
            subprocess.run(
                [str(PY if PY.exists() else sys.executable), str(rembg), str(work), "-o", str(clean)],
                capture_output=True, text=True, timeout=120,
            )
            src = clean if clean.exists() and clean.stat().st_size > 5_000 else work
        else:
            src = work
        install.parent.mkdir(parents=True, exist_ok=True)
        install.write_bytes(src.read_bytes())
        res["installed"] = str(install)
        res["name"] = name
        return res
    res["name"] = name
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--all-maps", action="store_true")
    ap.add_argument("--props-only", action="store_true")
    ap.add_argument("--npcs-only", action="store_true")
    ap.add_argument("--maps-only", action="store_true")
    args = ap.parse_args()

    if not AG.exists():
        print("asset_gen missing", file=sys.stderr)
        return 1

    results = []
    maps = CORE_MAPS
    if args.all_maps:
        # extend from gen_world_maps JOBS if present
        maps = CORE_MAPS

    if not args.props_only and not args.npcs_only:
        print(f"=== maps {len(maps)} ===")
        for art_id, detail in maps:
            print("MAP", art_id, "...")
            r = gen_map(art_id, detail, force=args.force)
            print(" ", "OK" if r.get("ok") is not False and not r.get("error") else "FAIL",
                  r.get("skipped") and "skip" or "", art_id, r.get("cost_cents", ""))
            results.append(r)
            time.sleep(0.3)

    if not args.maps_only and not args.npcs_only:
        print(f"=== props {len(PROP_JOBS)} ===")
        for name, detail in PROP_JOBS:
            print("PROP", name, "...")
            r = gen_prop(name, detail, force=args.force)
            print(" ", "OK" if (r.get("ok") is not False and not r.get("error")) or r.get("skipped") else "FAIL", name)
            results.append(r)
            time.sleep(0.2)

    if not args.maps_only and not args.props_only:
        print(f"=== npcs {len(NPC_JOBS)} ===")
        for name, detail in NPC_JOBS:
            print("NPC", name, "...")
            r = gen_npc(name, detail, force=args.force)
            print(" ", "OK" if (r.get("ok") is not False and not r.get("error")) or r.get("skipped") else "FAIL", name)
            results.append(r)
            time.sleep(0.2)

    summary = GEN / "summary.json"
    GEN.mkdir(parents=True, exist_ok=True)
    summary.write_text(json.dumps(results, indent=2, ensure_ascii=False))
    ok = sum(1 for r in results if r.get("skipped") or r.get("installed") or r.get("ok") is True)
    print(f"done okish={ok}/{len(results)} summary={summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
