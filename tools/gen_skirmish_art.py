#!/usr/bin/env python3
"""Generate dedicated skirmish enemy battle sprites (small)."""
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
GEN = ROOT / "game/assets/sprites/_gen_skirmish"
BOSS = ROOT / "game/assets/sprites/bosses"

JOBS = [
    ("ash_rat", "pixel art game enemy sprite, ash-covered rat with ember eyes, full body, solid dark gray background, cute-scary chibi, no text"),
    ("road_bandit", "pixel art game enemy sprite, ragged highway bandit with broken sword, full body, solid dark gray background, chibi RPG, no text"),
    ("sewer_slime", "pixel art game enemy sprite, green slime blob with drip eyes, full body, solid dark gray background, chibi RPG, no text"),
    ("fog_shade", "pixel art game enemy sprite, translucent blue fog ghost shade, full body, solid dark gray background, chibi RPG, no text"),
    ("bamboo_spirit", "pixel art game enemy sprite, bamboo martial spirit with leaf fists, green, full body, solid dark gray background, chibi RPG, no text"),
    ("forest_sprite", "pixel art game enemy sprite, wind fairy sprite with leaf wings, full body, solid dark gray background, chibi RPG, no text"),
    ("coast_raider", "pixel art game enemy sprite, viking coastal raider with axe, full body, solid dark gray background, chibi RPG, no text"),
    ("scar_wisp", "pixel art game enemy sprite, black-purple flame wisp spirit, full body, solid dark gray background, chibi RPG, no text"),
]


def main() -> int:
    if not os.environ.get("GOOGLE_API_KEY"):
        print("no key", file=sys.stderr)
        return 2
    from PIL import Image

    GEN.mkdir(parents=True, exist_ok=True)
    ok = fail = cost = 0
    for name, prompt in JOBS:
        out = GEN / f"{name}.png"
        print(f"==> {name}", flush=True)
        if out.exists() and out.stat().st_size > 20000:
            print("  skip", flush=True)
        else:
            cmd = [
                str(PY if PY.exists() else sys.executable),
                str(ASSET_GEN),
                "image",
                "--model",
                "gemini",
                "--size",
                "1K",
                "--aspect-ratio",
                "1:1",
                "--prompt",
                prompt + ", single centered subject, game-ready",
                "-o",
                str(out),
            ]
            done = False
            for attempt in range(1, 4):
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
                if r.returncode == 0 and out.exists():
                    done = True
                    cost += 7
                    break
                if "503" in (r.stderr or ""):
                    time.sleep(6 * attempt)
            if not done:
                fail += 1
                print("  FAIL", flush=True)
                continue
            print("  OK", flush=True)
        try:
            im = Image.open(out).convert("RGBA")
            im.thumbnail((200, 220), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (180, 200), (0, 0, 0, 0))
            canvas.paste(im, ((180 - im.width) // 2, (200 - im.height) // 2), im)
            dest = BOSS / f"{name}.png"
            canvas.save(dest)
            icon = canvas.copy()
            icon.thumbnail((48, 56), Image.Resampling.LANCZOS)
            ic = Image.new("RGBA", (48, 56), (0, 0, 0, 0))
            ic.paste(icon, ((48 - icon.width) // 2, (56 - icon.height) // 2), icon)
            ic.save(BOSS / f"{name}_icon.png")
            ok += 1
        except Exception as e:
            print("  install", e)
            fail += 1
        time.sleep(1.0)
    print(json.dumps({"ok": ok, "fail": fail, "cost_cents_est": cost}))
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
