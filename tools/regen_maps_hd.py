#!/usr/bin/env python3
"""把探索底圖重出成高解析度版本。

起因：底圖原生 1376x768，但世界尺寸平均是它的 1.91 倍 —— 螢幕上看到的只有
原生解析度的 52%，所以「看起來不精緻」。

做法：Gemini 4K（16:9 出來是 5504x3072）→ LANCZOS 縮到 2633x1469 → WebP q95。

  · 2633x1469 是實測算出來的需求值：世界平均 1.91 倍放大，1376*1.91≈2633。
    再大就是浪費（螢幕看不到），4K 原檔留在 _gen_hd_maps/ 不進版控。
  · WebP q95 每張約 0.9MB，41 張約 36MB —— 比現在 41 張 PNG 的 62MB 還小，
    解析度卻是 1.9 倍。底圖不需要 alpha，用 PNG 純粹是浪費。

**構圖會漂移。** 以原圖當 --image 參考仍然是重新生成，不是放大：實測騎士堡
那張整體下移、牆變高、噴泉與水井都挪了位置。所以重出之後 walkmask 與實體
座標都要重新對 —— 這也是為什麼要先重出再排版，不然工白做兩次。

用法：
    python3 tools/regen_maps_hd.py --list          # 看會做哪些、多少錢
    python3 tools/regen_maps_hd.py town village    # 只做指定的
    python3 tools/regen_maps_hd.py                 # 全部
    python3 tools/regen_maps_hd.py --install-only  # 只把已生成的 4K 轉成 webp
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_GEN = ROOT / ".agents/skills/asset-gen/tools/asset_gen.py"
PY = ROOT / ".venv-asset/bin/python"
HD_DIR = ROOT / "game/assets/sprites/maps/_gen_hd_maps"   # 4K 原檔，不進版控
INSTALL = ROOT / "game/assets/sprites/maps"

OUT_W, OUT_H = 2633, 1469
WEBP_Q = 95
COST_CENTS_4K = 15

STYLE = (
    "Premium 16-bit painterly pixel-art RPG background, soft rounded pixels, "
    "warm atmospheric light, Chinese-European fantasy blend for 勇者之魂 Brave Soul, "
    "top-down oblique exploration view, game-ready scenic plate, "
    "NO UI, NO text, NO logos, NO watermarks, NO characters, NO people, NO rabbits, 16:9 wide"
)

## 保住構圖是關鍵 —— 重出之後所有 walkmask 與實體座標都要跟著對，
## 漂移越小要重排的越少。
KEEP = (
    "CRITICAL: reproduce the reference image's EXACT composition, camera framing, "
    "perspective angle, and the position and scale of every building, path and landmark. "
    "Do not move, add or remove anything. Do not zoom or crop. "
    "Only increase the rendering fidelity and detail density. "
    "Match the reference palette exactly."
)

SCENES: dict[str, str] = {
    "village": "burned rural village at soft dawn, thatch ruins, dirt paths, willow trees",
    "village_outskirts": "fields outside a burned village, scarecrow, dry pond, woodpile, fences",
    "village_mill": "rolling wheat fields with a giant broken windmill and miller's hut, dusk amber",
    "village_cave": "mountain cave mouth near a burned village, dark stone, glowing moss",
    "village_grave": "hilltop village graveyard at night, willow trees, stone markers, dim lanterns",
    "road": "dirt highway through hills at morning, milepost, distant fortress silhouette",
    "road_bridge": "stone arch bridge over a deep ravine on a dirt highway at dawn, mist in canyon",
    "road_inn": "half-collapsed roadside inn courtyard, broken sign, empty stables, cold hearth",
    "road_ruins": "ancient courier station ruins with broken columns and star-carved mosaic floor",
    "town": "knight fortress outer square, cobblestone plaza with dry fountain, market stalls, curtain wall with watchtowers, timber-framed houses",
    "town_market": "medieval lower-city market square with empty stalls, stone streets, fortress walls distant",
    "town_sewers": "dark stone sewer tunnels with pipes, moss, shallow water reflections, torch niches",
    "barracks_yard": "knight barracks training yard with sand ring, weapon racks, torn banners",
    "wild": "charred plain outside a fortress, blackened soil, dead trees, ash wind",
    "wild_ravine": "charred plain edge opening into a deep cracked ravine, rope bridge, blackened soil",
    "wild_leo_court": "stone lion courtyard before a fortress inner keep, torn honor banners, ash sky",
    "cross_north": "winding mountain path north of a crossroads, pine trees, cloud sea view",
    "cross_east": "dead tree plain path toward a dark wizard tower silhouette, ash wind, purple horizon",
    "caravan_camp": "merchant caravan camp with covered wagons, campfire, goods piles at dusk",
    "starfall_plain": "night plain under shooting stars, constellation lines etched on ground, soft blue glow",
    "blackflame_scar": "land scarred by black-purple flame, charred earth, obsidian cracks, ominous vents",
    "hunting_grounds": "hunting grounds at blackflame scar edge, ash dirt field, bone markers, hunting posts",
    "mist_village": "foggy village with wooden walkways, pale blue lanterns, sea of mist, shrine roofs",
    "mist_cliff": "foggy cliff overlook above a sea of mist, bell tower silhouette, pale blue lanterns",
    "mist_shrine": "inner fog shrine with white fox statue, incense smoke, prayer strips, silver light",
    "mist_mirror": "endless mirror corridor in fog, reflective floors, eerie symmetry, cool blue-violet",
    "dojo": "martial dojo courtyard with zen pond, wooden halls, stone garden, bamboo, soft green light",
    "dojo_inner": "martial dojo inner courtyard with zen pond, wooden halls, stone garden, quiet green",
    "dojo_bamboo": "dense bamboo forest path with stream stones and soft green light shafts",
    "dojo_peak": "mountain peak training platform above clouds, wind flags, sunrise gold and jade",
    "forest": "lush ranger forest path, moss stones, light shafts, green canopy",
    "forest_canopy": "tree canopy layer with rope bridges and nest platforms high above green forest",
    "forest_ruins": "ancient ranger stone ruins reclaimed by moss and roots inside deep forest",
    "forest_lake": "still forest lake with reed shore, log dock, mirror reflections, calm green-blue",
    "coast": "cold viking rocky coast, longships, distant cliffs, harsh wind, teal sea",
    "coast_harbor": "viking deep harbor with longship, wooden crane, warehouses, cold ocean",
    "coast_cave": "tidal sea cave with tide pools, crystals, pirate marks, ocean light from holes",
    "coast_wreck": "shipwreck bay with broken hull and mast on rocky shore, gulls sky, harsh wind",
    "tower": "camp at the foot of a black wizard tower, refugee fires, ash sky, looming spire",
    "tower_foyer": "dark wizard tower foyer, black stone pillars, sealing murals, purple torchlight",
    "tower_stairs": "spiral staircase shaft inside a black tower, narrow windows, ascending gloom",
    "tower_memory": "surreal memory chamber with floating orbs of light and throne shadow, violet haze",
}


def targets(argv: list[str]) -> list[str]:
    want = [a for a in argv if not a.startswith("-")]
    have = sorted(a for a in SCENES if (INSTALL / f"{a}_bg.png").exists())
    return [a for a in have if not want or a in want]


def generate(art: str) -> dict:
    HD_DIR.mkdir(parents=True, exist_ok=True)
    out = HD_DIR / f"{art}_bg.png"
    if out.exists() and out.stat().st_size > 1_000_000:
        return {"ok": True, "art": art, "skipped": True}
    ref = INSTALL / f"{art}_bg.png"
    prompt = f"{KEEP} Scene: {SCENES[art]}. {STYLE}."
    cmd = [str(PY if PY.exists() else sys.executable), str(ASSET_GEN), "image",
           "--model", "gemini", "--size", "4K", "--aspect-ratio", "16:9",
           "--image", str(ref), "--prompt", prompt, "-o", str(out)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=420)
    except subprocess.TimeoutExpired:
        return {"ok": False, "art": art, "error": "timeout"}
    if r.returncode == 0 and out.exists():
        return {"ok": True, "art": art}
    return {"ok": False, "art": art, "error": (r.stderr or r.stdout or "")[-300:]}


def install(art: str) -> bool:
    from PIL import Image
    src = HD_DIR / f"{art}_bg.png"
    if not src.exists():
        return False
    im = Image.open(src).convert("RGB").resize((OUT_W, OUT_H), Image.Resampling.LANCZOS)
    ## WebP：底圖不需要 alpha，PNG 純粹是浪費。q95 幾乎看不出差別。
    im.save(INSTALL / f"{art}_bg.webp", "WEBP", quality=WEBP_Q, method=6)
    return True


def main() -> int:
    arts = targets(sys.argv[1:])
    if "--list" in sys.argv:
        print("會重出 %d 張，4K 每張 %d¢ → 約 US$%.2f\n" %
              (len(arts), COST_CENTS_4K, len(arts) * COST_CENTS_4K / 100.0))
        for a in arts:
            print("  %-20s %s" % (a, SCENES[a][:70]))
        return 0
    if not os.environ.get("GOOGLE_API_KEY"):
        print("GOOGLE_API_KEY 沒設", file=sys.stderr)
        return 2

    ok = fail = 0
    for i, art in enumerate(arts, 1):
        if "--install-only" not in sys.argv:
            r = generate(art)
            tag = "skip" if r.get("skipped") else ("ok" if r["ok"] else "FAIL")
            print("[%2d/%d] %-20s %s %s" % (i, len(arts), art, tag,
                                            r.get("error", "")[:90]))
            if not r["ok"]:
                fail += 1
                continue
        if install(art):
            ok += 1
        else:
            fail += 1
    print("\n完成 %d，失敗 %d" % (ok, fail))
    return 1 if fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
