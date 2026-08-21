#!/usr/bin/env python3
"""
把程式合成的 .wav 烤成「真配樂槽位」壓縮檔（OGG 或 MP3）＋ loops.json。

目的（對齊 AI×RPG 工作流／Suno 可替換）：
  - 遊戲優先播 .ogg／.mp3；之後你丟 Suno／Flow 成品，用 import_bgm.py 同名覆蓋即可
  - 現在先有循環點與響度一致的占位真曲格式，聽感與體積都比裸 WAV 接近正式配樂

用法
  python3 tools/bake_placeholder_bgm.py
  python3 tools/bake_placeholder_bgm.py --regen-wav   # 先重跑 gen_bgm 再烤
  python3 tools/bake_placeholder_bgm.py --only title,village,battle
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BGM_DIR = ROOT / "game" / "assets" / "audio" / "bgm"
GEN = ROOT / "tools" / "gen_bgm.py"
IMPORT = ROOT / "tools" / "import_bgm.py"

TRACK_IDS = [
    "title", "village", "town", "mist", "dojo", "forest", "coast",
    "wild", "road", "battle", "boss", "tower", "ending",
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--regen-wav", action="store_true", help="先執行 gen_bgm.py")
    ap.add_argument("--only", default="", help="逗號分隔曲目 id")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    ids = TRACK_IDS
    if args.only.strip():
        ids = [x.strip() for x in args.only.split(",") if x.strip()]
        bad = [x for x in ids if x not in TRACK_IDS]
        if bad:
            print(f"未知 id：{bad}", file=sys.stderr)
            return 1

    if args.regen_wav:
        print("── regen wav via gen_bgm.py")
        r = subprocess.run([sys.executable, str(GEN)], cwd=str(ROOT))
        if r.returncode != 0:
            return r.returncode

    ok = 0
    for tid in ids:
        wav = BGM_DIR / f"{tid}.wav"
        if not wav.exists():
            print(f"SKIP {tid}: 沒有 {wav.name}")
            continue
        cmd = [sys.executable, str(IMPORT), str(wav), "--id", tid]
        if args.dry_run:
            cmd.append("--dry-run")
        print(f"\n══ bake {tid}")
        r = subprocess.run(cmd, cwd=str(ROOT))
        if r.returncode == 0:
            ok += 1
        else:
            print(f"FAIL {tid}", file=sys.stderr)

    print(f"\n完成 {ok}/{len(ids)} 首。Suno 成品之後：")
    print("  python3 tools/import_bgm.py ~/Downloads/suno_title.mp3 --id title")
    print("  godot --path game --headless --import")
    print("  godot --path game --headless -s res://scripts/art/test_bgm.gd")
    return 0 if ok == len(ids) else 1


if __name__ == "__main__":
    raise SystemExit(main())
