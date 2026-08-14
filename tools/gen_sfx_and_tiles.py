#!/usr/bin/env python3
"""Generate procedural SFX (WAV) + 16/32px tiles. Run from repo root:
  python3 tools/gen_sfx_and_tiles.py
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "audio" / "sfx"
TILE = ROOT / "game" / "assets" / "sprites" / "tiles"
SR = 22050
rng = random.Random(42)


def write_wav(path: Path, samples: list[float], sr: int = SR) -> None:
    data = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s))
        data += struct.pack("<h", int(v * 32767))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data)
    print(" ", path.name, f"{len(samples)/sr:.3f}s")


def env(t, attack, decay, sustain=0.0, release=0.05, total=None):
    if t < attack:
        return t / max(1e-6, attack)
    if t < attack + decay:
        return 1.0 - (1.0 - sustain) * ((t - attack) / max(1e-6, decay))
    if total is None:
        return sustain
    if t > total - release:
        return sustain * max(0.0, (total - t) / max(1e-6, release))
    return sustain


def tone(freq, dur, vol=0.4, wave_fn="sin", attack=0.01, decay=0.05, sustain=0.3, release=0.08):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(t, attack, decay, sustain, release, dur)
        ph = 2 * math.pi * freq * t
        if wave_fn == "sin":
            s = math.sin(ph)
        elif wave_fn == "tri":
            s = 2 * abs(2 * ((freq * t) % 1) - 1) - 1
        elif wave_fn == "sq":
            s = 1.0 if math.sin(ph) > 0 else -1.0
        else:
            s = math.sin(ph + 2 * math.sin(ph * 0.5))
        out.append(s * e * vol)
    return out


def noise(dur, vol=0.3, attack=0.001, decay=0.08):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(t, attack, decay, 0.0, 0.02, dur)
        out.append((rng.random() * 2 - 1) * e * vol)
    return out


def mix(*tracks):
    m = max(len(t) for t in tracks)
    out = [0.0] * m
    for tr in tracks:
        for i, v in enumerate(tr):
            out[i] += v
    return [math.tanh(v) for v in out]


def pitch_sweep(f0, f1, dur, vol=0.35):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (t / dur)
        e = env(t, 0.005, 0.05, 0.2, 0.05, dur)
        out.append(math.sin(2 * math.pi * f * t) * e * vol)
    return out


def gen_sfx() -> None:
    print("sfx")
    write_wav(OUT / "parry.wav", mix(tone(1400, 0.18, 0.35), tone(2100, 0.14, 0.2), tone(880, 0.12, 0.15, "tri")))
    write_wav(OUT / "hit.wav", mix(noise(0.08, 0.25), tone(120, 0.1, 0.35), tone(80, 0.12, 0.2)))
    write_wav(OUT / "slash.wav", mix(pitch_sweep(600, 180, 0.16, 0.3), noise(0.12, 0.15)))
    write_wav(OUT / "fire.wav", mix(noise(0.35, 0.22, 0.02, 0.2), tone(90, 0.3, 0.12)))
    write_wav(OUT / "wind.wav", mix(pitch_sweep(900, 300, 0.22, 0.25), noise(0.25, 0.2, 0.01, 0.15)))
    write_wav(OUT / "rock.wav", mix(noise(0.18, 0.35), tone(60, 0.2, 0.4), tone(100, 0.12, 0.2, "sq")))
    write_wav(OUT / "clock.wav", mix(tone(1800, 0.06, 0.25), tone(900, 0.05, 0.15, "tri")))
    write_wav(OUT / "reveal.wav", mix(tone(660, 0.25, 0.3), tone(990, 0.22, 0.18), tone(1320, 0.2, 0.1)))
    write_wav(OUT / "break.wav", mix(noise(0.2, 0.4), tone(200, 0.15, 0.3, "sq"), pitch_sweep(400, 80, 0.18, 0.25)))
    write_wav(OUT / "stop.wav", mix(tone(880, 0.2, 0.25), tone(1174, 0.18, 0.15)))
    write_wav(OUT / "clash.wav", mix(noise(0.12, 0.35), tone(90, 0.15, 0.45), tone(300, 0.1, 0.2, "sq")))
    write_wav(OUT / "victory.wav", mix(tone(523, 0.18, 0.28), tone(659, 0.22, 0.22), tone(784, 0.28, 0.2)))
    write_wav(OUT / "defeat.wav", mix(pitch_sweep(400, 120, 0.4, 0.3), tone(150, 0.45, 0.2)))
    write_wav(OUT / "ui.wav", tone(880, 0.06, 0.2))
    write_wav(OUT / "interact.wav", mix(tone(600, 0.08, 0.22), tone(900, 0.07, 0.12, "tri")))
    write_wav(OUT / "step.wav", mix(noise(0.05, 0.18), tone(70, 0.05, 0.15)))
    write_wav(OUT / "warn.wav", mix(tone(440, 0.1, 0.2, "sq"), tone(330, 0.08, 0.15, "sq")))
    write_wav(OUT / "dodge.wav", mix(pitch_sweep(500, 1200, 0.1, 0.22), noise(0.08, 0.1)))
    write_wav(OUT / "battle_start.wav", mix(tone(200, 0.15, 0.25), tone(300, 0.18, 0.2), noise(0.1, 0.08)))


def _tile(fn, name: str) -> None:
    im = fn(1)
    TILE.mkdir(parents=True, exist_ok=True)
    im.save(TILE / f"{name}_16.png")
    im.resize((32, 32), Image.Resampling.NEAREST).save(TILE / f"{name}_32.png")
    print(" ", name)


def gen_tiles() -> None:
    print("tiles")

    def stone(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                n = r.randint(-12, 12)
                c = (110 + n, 108 + n, 118 + n, 255)
                if x % 8 == 0 or y % 8 == 0:
                    c = (70, 68, 75, 255)
                px[x, y] = c
        return im

    def grass(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                g = 70 + r.randint(0, 40)
                px[x, y] = (40 + r.randint(0, 20), g, 35 + r.randint(0, 15), 255)
        return im

    def dirt(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                n = r.randint(-15, 15)
                px[x, y] = (90 + n, 70 + n, 45 + n // 2, 255)
        return im

    def wood(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                band = int(8 * math.sin(y * 0.4))
                n = r.randint(-8, 8)
                c = (120 + band + n, 85 + band // 2 + n, 50 + n, 255)
                if y % 8 == 0:
                    c = (80, 55, 30, 255)
                px[x, y] = c
        return im

    def sand(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                n = r.randint(-10, 10)
                px[x, y] = (190 + n, 170 + n // 2, 110 + n // 2, 255)
        return im

    def mist(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                n = r.randint(-10, 10)
                px[x, y] = (70 + n, 75 + n, 95 + n, 255)
        return im

    def dark(seed=0):
        r = random.Random(seed)
        im = Image.new("RGBA", (16, 16))
        px = im.load()
        for y in range(16):
            for x in range(16):
                n = r.randint(-8, 8)
                px[x, y] = (45 + n, 40 + n, 55 + n, 255)
        return im

    for name, fn in [
        ("stone", stone),
        ("grass", grass),
        ("dirt", dirt),
        ("wood", wood),
        ("sand", sand),
        ("mist", mist),
        ("dark", dark),
    ]:
        _tile(fn, name)


if __name__ == "__main__":
    gen_sfx()
    gen_tiles()
    print("DONE")
