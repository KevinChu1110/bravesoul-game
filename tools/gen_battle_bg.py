#!/usr/bin/env python3
"""戰鬥專屬背景：用 Gemini 產 23 張，蓋掉「退回地圖底圖」的暫代。

為什麼需要專屬背景
------------------
`maps/battle_*.png` 那七張本來是「主角＋敵人都畫好」的完成稿插圖被當背景用 ——
打雷歐的時候，背景裡有一隻比人還大的兔子在跟哥布林對砍，前景又疊一隻活的主角。
那七張已經搬到 `illustrations/duel_*.png`（圖本身是好的，只是不能當背景）。

現在每一場戰鬥會退到「那場仗實際發生的地方」的地圖底圖（見
`sprite_db.gd` 的 `BATTLE_BG_MAP`），所以沒有純黑畫面了，但那些底圖是
**俯視探索視角**，拿來當側視戰鬥背景會怪。這支腳本產的是側視、
留白正確的專屬背景，丟進 `maps/battle_<mode>.png` 就會自動蓋過去。

構圖要求（重要）
----------------
戰鬥畫面左右各站一個角色：玩家在左約 1/4 處、敵人在右約 3/4 處，
腳底大約在畫面 75% 高。所以背景要：
  · **完全沒有角色**（這正是舊圖壞掉的原因）
  · 左右兩側與下半部保持乾淨，細節往上半與遠景放
  · 中央可以有主體（門、祭壇、樹），但不要擋到兩個站位

用法
----
  .venv-asset/bin/python tools/gen_battle_bg.py             # 只產還沒有專屬圖的
  .venv-asset/bin/python tools/gen_battle_bg.py --force     # 全部重產
  .venv-asset/bin/python tools/gen_battle_bg.py --only leo,fog
  .venv-asset/bin/python tools/gen_battle_bg.py --list      # 只列現況，不呼叫 API

產完之後：
  1. 在 Godot 開一次專案讓它產生 .import
  2. `python3 tools/compress_sprites.py --import-mode --apply`
  3. `godot --path game --headless -s res://scripts/art/test_art.gd`
     會印出「N 種戰鬥有專屬圖」，數字要往上跑
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
GEN = ROOT / "game/assets/sprites/_gen_battle_bg"
STYLE_REF = ROOT / "web/media/gemini/keyart_hero.png"

# 跟 regen_visuals_v014.py 同一組風格詞，換成側視戰鬥鏡頭
STYLE = (
    "Premium 16-bit painterly pixel-art RPG, soft rounded pixels, warm atmospheric light, "
    "Chinese-European fantasy blend for game 勇者之魂 Brave Soul, cohesive with the reference key art, "
    "side-view battle stage backdrop, game-ready, "
    "NO characters, NO creatures, NO people, NO UI, NO text, NO logos, NO watermarks"
)

COMPOSITION = (
    "Composition: empty flat ground across the lower third where two fighters will stand "
    "(left quarter and right quarter must stay uncluttered), detail and interest in the upper half "
    "and far background, gentle vignette at the edges, nothing crossing the centre at ground level."
)

# (mode, 場景描述)。順序照章節，方便一批一批看。
JOBS: list[tuple[str, str]] = [
    # ── 主線 Boss ──
    ("wolf", "dusk dirt road at the edge of a burned village, broken fence, long shadows, first-fight tension"),
    ("leo", "knight fortress inner court before the throne hall, tall stone arches, torn banners, cold grey stone"),
    ("fog", "fog-drowned ninja village square, wooden walkways and shrine roofs fading into white mist, pale blue lanterns"),
    ("abo", "martial dojo inner hall, polished wood floor, paper screens, bamboo garden beyond, calm green light"),
    ("falcon", "forest clearing under a broken canopy, wind-bent trees, feathers drifting, sharp shafts of light"),
    ("boar", "storm-beaten viking coast, black rocks and spray, overturned longship ribs, cold teal sky"),
    ("demon", "top of the black tower, cracked obsidian floor, purple flame braziers, void sky and falling ash"),
    # ── 通關後裂縫 ──
    ("wrath", "black-purple flame rift, ring of fire scars on obsidian ground, ember rain, oppressive red glow"),
    ("tide", "drowned rift shore, black water with floating bloom pods, sunken pillars, sickly blue-green light"),
    ("statue", "rift hall of three broken stone idols, one eye faintly lit, dust shafts, ochre torchlight"),
    ("chrono", "time-cage rift, floating clock rings and frozen debris, cracked floor runes, violet chrono glow"),
    # ── 秘境小 Boss ──
    ("scar_lord", "heart of the blackflame scar, obsidian crater, vents of purple fire, ash-choked sky"),
    ("mirror_wraith", "hall of tall fog mirrors, silver reflections receding, cold white light, still air"),
    ("wreck_captain", "inside a broken hull on the shore, cracked ribs of timber, seawater pooling, grey daylight"),
    # ── 雜魚 ──
    ("ash_rat", "ash hunting field, bone markers and low purple flame vents, dusk haze"),
    ("road_bandit", "ruined roadside waystation, collapsed arch and cart wreck, overcast noon"),
    ("sewer_slime", "stone sewer chamber, arched pipes, shallow green water, dim lantern light"),
    ("fog_shade", "misty cliff ledge, pale rock and drifting fog, faint pine silhouettes"),
    ("bamboo_spirit", "bamboo grove training ground, tall green stalks, dappled light, raked sand"),
    ("forest_sprite", "high forest canopy platform, thick branches and moss, golden green light"),
    ("coast_raider", "shipwreck bay shingle beach, broken hull behind, gulls and cold sea spray"),
    ("scar_wisp", "cracked blackflame ground, thin purple wisps rising from fissures, ash sky"),
    ("black_ronin", "six-way dirt crossroads at dusk, waystones and lone signpost, long shadows on open plain"),
]


def run_image(prompt: str, out: Path, ref: Path | None) -> dict:
    out.parent.mkdir(parents=True, exist_ok=True)
    # 中間產物目錄要有 .gdignore，否則本機一開專案 Godot 會去 import 它們
    gd = out.parent / ".gdignore"
    if not gd.exists():
        gd.write_text("")
    cmd = [
        str(PY if PY.exists() else sys.executable),
        str(AG), "image",
        "--model", "gemini",
        "--size", "1K",
        "--aspect-ratio", "16:9",
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
                    data = {"ok": True}
                data["path"] = str(out)
                return data
            time.sleep(1.5 * attempt)
        except subprocess.TimeoutExpired:
            time.sleep(2)
    return {"ok": False, "path": str(out), "error": "failed"}


def gen_one(mode: str, detail: str, force: bool) -> dict:
    install = MAPS / f"battle_{mode}.png"
    work = GEN / f"battle_{mode}.png"
    if install.exists() and install.stat().st_size > 50_000 and not force:
        return {"ok": True, "skipped": True, "mode": mode}
    prompt = (
        f"Keep the same premium painterly pixel-fantasy color richness and soft lighting as the reference. "
        f"Change only the scene to a battle stage backdrop. {STYLE}. "
        f"Scene: {detail}. {COMPOSITION}"
    )
    res = run_image(prompt, work, STYLE_REF if STYLE_REF.exists() else None)
    if res.get("ok") is not False and work.exists():
        install.write_bytes(work.read_bytes())
        res["installed"] = str(install)
    res["mode"] = mode
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="已經有專屬圖也重產")
    ap.add_argument("--only", default="", help="逗號分隔的 mode，只產這幾張")
    ap.add_argument("--list", action="store_true", help="只列現況，不呼叫 API")
    args = ap.parse_args()

    want = {m.strip() for m in args.only.split(",") if m.strip()}
    jobs = [j for j in JOBS if not want or j[0] in want]
    if want:
        unknown = want - {j[0] for j in JOBS}
        if unknown:
            print("不認得這幾個 mode：%s" % ", ".join(sorted(unknown)))
            return 2

    if args.list:
        have = sum(1 for m, _ in JOBS if (MAPS / f"battle_{m}.png").exists())
        print("戰鬥背景 %d／%d 有專屬圖" % (have, len(JOBS)))
        for mode, _ in JOBS:
            p = MAPS / f"battle_{mode}.png"
            mark = "✓ 專屬" if p.exists() else "· 退回地圖底圖"
            print("  %-16s %s" % (mode, mark))
        return 0

    if not AG.exists():
        print("找不到產圖工具：%s" % AG)
        return 127

    ok = 0
    for mode, detail in jobs:
        res = gen_one(mode, detail, args.force)
        if res.get("skipped"):
            print("  skip %s（已有專屬圖，要重產請加 --force）" % mode)
            ok += 1
        elif res.get("ok") is not False:
            print("  ok   %s → %s" % (mode, res.get("installed", "?")))
            ok += 1
        else:
            print("  FAIL %s：%s" % (mode, res.get("error", "?")))
    print("\n%d／%d 完成。接著：" % (ok, len(jobs)))
    print("  1. 在 Godot 開一次專案產生 .import")
    print("  2. python3 tools/compress_sprites.py --import-mode --apply")
    print("  3. godot --path game --headless -s res://scripts/art/test_art.gd")
    return 0 if ok == len(jobs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
