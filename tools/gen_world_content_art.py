#!/usr/bin/env python3
"""Generate mini-boss sprites, landmark banners, and a few portraits for 0.9.1."""
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
GEN = ROOT / "game/assets/sprites/_gen_content"
BOSS_DIR = ROOT / "game/assets/sprites/bosses"
MAP_DIR = ROOT / "game/assets/sprites/maps"
PORT_DIR = ROOT / "game/assets/sprites/portraits"

# kind: boss | banner | portrait
JOBS = [
    # Mini-boss full body ~ square-ish game portrait style
    ("boss", "scar_lord", "pixel art boss character, black-purple flame humanoid without face, cracked obsidian armor, menacing silhouette, solid dark gray background, game sprite, no text", "1:1", None),
    ("boss", "mirror_wraith", "pixel art boss, ghostly mirror wraith, translucent silver-blue figure holding a cracked mirror, fog particles, solid dark gray background, game sprite, no text", "1:1", None),
    ("boss", "wreck_captain", "pixel art boss, undead viking ship captain made of driftwood and seafoam, captain hat, no face only shadows, solid dark gray background, game sprite, no text", "1:1", None),
    # Banners 960x220-ish → generate 16:9 then crop/resize
    ("banner", "village", "pixel art wide decorative banner landscape strip, burned rural village night, soft smoke, no characters no text, 16-bit painterly", "16:9", "village"),
    ("banner", "road", "pixel art wide banner, dirt highway at dawn toward stone walls, mileposts, no characters no text", "16:9", "road"),
    ("banner", "wild", "pixel art wide banner, scorched plains outside fortress, ash sky, no characters no text", "16:9", "wild"),
    ("banner", "caravan_camp", "pixel art wide banner, merchant wagons campfire dusk, no characters no text", "16:9", "caravan_camp"),
    ("banner", "starfall_plain", "pixel art wide banner, night plain under meteor shower, blue glow, no characters no text", "16:9", "starfall_plain"),
    ("banner", "blackflame_scar", "pixel art wide banner, land scarred by black purple flame, ominous, no characters no text", "16:9", "blackflame_scar"),
    ("banner", "crossroads", "pixel art wide banner, six-way dirt crossroads signpost heart of fantasy continent, no characters no text", "16:9", "road"),
    # Portraits
    ("portrait", "caravan_chief", "pixel art character portrait bust, weathered traveling merchant chief, warm cloak, kind eyes, solid soft beige background, chinese fantasy, no text", "3:4", None),
    ("portrait", "scar_lord", "pixel art character portrait bust, faceless blackflame scar lord, purple cracks, solid dark background, no text", "3:4", None),
    ("portrait", "mirror_wraith", "pixel art character portrait bust, mirror wraith with cracked glass face, silver blue, solid dark background, no text", "3:4", None),
    ("portrait", "wreck_captain", "pixel art character portrait bust, undead sea captain driftwood beard seafoam, solid dark teal background, no text", "3:4", None),
]


def run_gen(prompt: str, out: Path, ar: str, ref: Path | None) -> dict:
    GEN.mkdir(parents=True, exist_ok=True)
    if out.exists() and out.stat().st_size > 30_000:
        return {"ok": True, "skipped": True, "path": str(out)}
    cmd = [
        str(PY if PY.exists() else sys.executable),
        str(ASSET_GEN),
        "image",
        "--model", "gemini",
        "--size", "1K",
        "--aspect-ratio", ar,
        "--prompt", prompt,
        "-o", str(out),
    ]
    if ref and ref.exists():
        cmd.extend(["--image", str(ref)])
        cmd[cmd.index("--prompt") + 1] = (
            f"Same pixel art style as reference. New content only: {prompt}"
        )
    for attempt in range(1, 4):
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if r.returncode == 0 and out.exists():
            try:
                data = json.loads(r.stdout.strip().splitlines()[-1])
            except Exception:
                data = {"ok": True}
            data["path"] = str(out)
            return data
        err = (r.stderr or r.stdout or "")[-300:]
        if "503" in err or "high demand" in err.lower():
            time.sleep(8 * attempt)
            continue
        return {"ok": False, "error": err}
    return {"ok": False, "error": "retries"}


def install(kind: str, name: str, src: Path) -> None:
    from PIL import Image

    im = Image.open(src).convert("RGBA")
    if kind == "boss":
        # target ~220x240 like existing
        im.thumbnail((240, 260), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (220, 240), (0, 0, 0, 0))
        x = (220 - im.width) // 2
        y = (240 - im.height) // 2
        canvas.paste(im, (x, y), im)
        dest = BOSS_DIR / f"{name}.png"
        canvas.save(dest)
        # simple icon
        icon = canvas.copy()
        icon.thumbnail((56, 64), Image.Resampling.LANCZOS)
        ic = Image.new("RGBA", (56, 64), (0, 0, 0, 0))
        ic.paste(icon, ((56 - icon.width) // 2, (64 - icon.height) // 2), icon)
        ic.save(BOSS_DIR / f"{name}_icon.png")
    elif kind == "banner":
        im = im.resize((960, 220), Image.Resampling.LANCZOS)
        dest = MAP_DIR / f"{name}_banner.png"
        im.save(dest)
    elif kind == "portrait":
        im = im.resize((384, 480), Image.Resampling.LANCZOS)
        dest = PORT_DIR / f"{name}.png"
        im.save(dest)


def main() -> int:
    if not os.environ.get("GOOGLE_API_KEY"):
        print("GOOGLE_API_KEY missing", file=sys.stderr)
        return 2
    ok = fail = skip = cost = 0
    for kind, name, prompt, ar, ref_key in JOBS:
        out = GEN / f"{kind}_{name}.png"
        print(f"==> {kind}/{name}", flush=True)
        ref = MAP_DIR / f"{ref_key}_bg.png" if ref_key else None
        res = run_gen(prompt, out, ar, ref)
        if res.get("skipped"):
            skip += 1
            print("  skip", flush=True)
        elif res.get("ok"):
            ok += 1
            cost += int(res.get("cost_cents") or 7)
            print("  OK", flush=True)
        else:
            fail += 1
            print("  FAIL", res.get("error", "")[:160], flush=True)
            continue
        try:
            install(kind, name, out)
        except Exception as e:
            print("  install err", e, flush=True)
            fail += 1
        time.sleep(1.2)
    print(json.dumps({"ok": ok, "fail": fail, "skip": skip, "cost_cents_est": cost}))
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
