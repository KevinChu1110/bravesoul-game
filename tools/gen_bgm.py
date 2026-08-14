#!/usr/bin/env python3
"""
翠嶺·兔勇者 BGM — 地區差異化編曲
每個 map 有獨立：BPM／調性／鼓型／主奏音色／和弦進行／密度
→ 聽得出「這是村子／霧／海岸／Boss…」
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parents[1] / "game" / "assets" / "audio" / "bgm"

# ─── 各地區身分卡 ─────────────────────────────────────────
# bars, root_midi, mode, bpm, energy, region_id
TRACKS = {
    # 標題：英雄銅管主題，中快，辨識度最高
    "title":   (16, 60, "major",  118, 0.90, "title"),
    # 翠谷村：慢一點、溫暖、幾乎無鼓、木笛感
    "village": (16, 65, "major",   92, 0.55, "village"),
    # 騎士堡：進行曲軍鼓 + 號角
    "town":    (16, 62, "mixo",   112, 0.78, "town"),
    # 荒路：穩定步伐低音 + 旅途動機
    "road":    (16, 57, "dorian", 108, 0.72, "road"),
    # 荒野：不安切分、偏暗
    "wild":    (12, 58, "phryg",  120, 0.80, "wild"),
    # 霧隱：極慢、稀疏、長延音、幾乎無鼓
    "mist":    (16, 53, "minor",   72, 0.40, "mist"),
    # 道場：規律打擊、短促音型
    "dojo":    (12, 64, "dorian", 126, 0.82, "dojo"),
    # 森林：高音空靈、琶音、輕
    "forest":  (16, 67, "major",   98, 0.58, "forest"),
    # 海岸：搖擺節奏、開闊五度
    "coast":   (16, 59, "mixo",   104, 0.68, "coast"),
    # 戰鬥：最快最密
    "battle":  (16, 55, "minor",  148, 1.00, "battle"),
    # Boss：厚重慢一點但巨大
    "boss":    (16, 50, "phryg",  128, 1.00, "boss"),
    # 塔：低沉儀式
    "tower":   (16, 52, "minor",   88, 0.62, "tower"),
    # 終章：溫暖大調、情緒收束
    "ending":  (18, 60, "major",   96, 0.70, "ending"),
}


def midi_hz(m: float) -> float:
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))


def scale(mode: str) -> list[int]:
    return {
        "major":  [0, 2, 4, 5, 7, 9, 11],
        "minor":  [0, 2, 3, 5, 7, 8, 10],
        "dorian": [0, 2, 3, 5, 7, 9, 10],
        "mixo":   [0, 2, 4, 5, 7, 9, 10],
        "phryg":  [0, 1, 3, 5, 7, 8, 10],
    }.get(mode, [0, 2, 3, 5, 7, 8, 10])


def chords_for(region: str, mode: str) -> list[list[int]]:
    """各地區專用和弦進行（聽感差異的核心之一）。"""
    tables = {
        "title":   [[0, 4, 7, 12], [5, 9, 12, 17], [7, 11, 14, 19], [0, 4, 7, 11]],  # I IV V I7
        "village": [[0, 4, 7], [5, 9, 12], [0, 4, 9], [5, 7, 12]],                  # 溫柔
        "town":    [[0, 4, 7, 12], [7, 11, 14], [0, 4, 7], [5, 9, 12, 16]],          # 號角感
        "road":    [[0, 3, 7], [5, 8, 12], [7, 10, 14], [0, 3, 7, 10]],
        "wild":    [[0, 1, 7], [3, 7, 10], [5, 8, 12], [0, 3, 7]],                   # 不安
        "mist":    [[0, 3, 7, 10], [8, 12, 15], [5, 8, 12], [0, 3, 7]],              # 懸浮
        "dojo":    [[0, 3, 7], [2, 5, 9], [0, 3, 7], [5, 8, 12]],
        "forest":  [[0, 4, 7, 11], [2, 5, 9], [4, 7, 11], [5, 9, 12]],               # 明亮
        "coast":   [[0, 4, 7], [7, 11, 14], [9, 12, 16], [5, 9, 12]],
        "battle":  [[0, 3, 7], [0, 3, 7, 10], [5, 8, 12], [7, 10, 14, 17]],
        "boss":    [[0, 1, 7, 12], [3, 7, 10], [5, 8, 12, 15], [0, 3, 7, 12]],
        "tower":   [[0, 3, 7], [8, 12, 15], [0, 3, 7, 10], [5, 8, 12]],
        "ending":  [[0, 4, 7, 12], [5, 9, 12], [7, 11, 14], [0, 4, 7, 16]],
    }
    return tables.get(region, [[0, 4, 7], [5, 9, 12], [7, 11, 14], [0, 4, 7]])


# 各地區「樂器開關」
REGION = {
    # drums: none|soft|march|drive|battle
    # lead: flute|brass|horn|pulse|power|bell|choir
    # bass: soft|walk|drive|pulse|none
    # pad: warm|thin|dark|bright|none
    # stabs: bool, arp: bool, sidechain: float, bright: float cutoff factor
    "title":   dict(drums="drive", lead="brass", bass="drive", pad="bright", stabs=True,  arp=False, sc=0.18, bright=1.2, crash=True),
    "village": dict(drums="none",  lead="flute", bass="soft",  pad="warm",   stabs=False, arp=True,  sc=0.0,  bright=0.85, crash=False),
    "town":    dict(drums="march", lead="horn",  bass="walk",  pad="thin",   stabs=True,  arp=False, sc=0.12, bright=1.05, crash=True),
    "road":    dict(drums="soft",  lead="pulse", bass="walk",  pad="thin",   stabs=False, arp=False, sc=0.10, bright=0.95, crash=False),
    "wild":    dict(drums="drive", lead="pulse", bass="drive", pad="dark",   stabs=True,  arp=False, sc=0.15, bright=0.9, crash=False),
    "mist":    dict(drums="none",  lead="choir", bass="none",  pad="dark",   stabs=False, arp=False, sc=0.0,  bright=0.55, crash=False),
    "dojo":    dict(drums="march", lead="pulse", bass="pulse", pad="none",   stabs=True,  arp=False, sc=0.14, bright=1.0, crash=False),
    "forest":  dict(drums="soft",  lead="bell",  bass="soft",  pad="bright", stabs=False, arp=True,  sc=0.05, bright=1.15, crash=False),
    "coast":   dict(drums="soft",  lead="flute", bass="walk",  pad="warm",   stabs=False, arp=True,  sc=0.08, bright=1.1, crash=False),
    "battle":  dict(drums="battle",lead="power", bass="drive", pad="thin",   stabs=True,  arp=False, sc=0.25, bright=1.35, crash=True),
    "boss":    dict(drums="battle",lead="power", bass="drive", pad="dark",   stabs=True,  arp=False, sc=0.22, bright=1.15, crash=True),
    "tower":   dict(drums="soft",  lead="choir", bass="soft",  pad="dark",   stabs=False, arp=False, sc=0.05, bright=0.6, crash=False),
    "ending":  dict(drums="soft",  lead="brass", bass="soft",  pad="warm",   stabs=False, arp=True,  sc=0.08, bright=1.0, crash=True),
}


def soft_clip(x: float, thr: float = 0.9) -> float:
    ax = abs(x)
    if ax <= thr:
        return x
    s = 1.0 if x >= 0 else -1.0
    return s * (thr + (1.0 - thr) * math.tanh((ax - thr) / max(1e-6, 1.0 - thr)))


def one_pole_lp(xs: list[float], cutoff: float) -> list[float]:
    if not xs:
        return xs
    rc = 1.0 / (2.0 * math.pi * max(30.0, cutoff))
    a = (1.0 / SR) / (rc + 1.0 / SR)
    y = xs[0]
    out = []
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def one_pole_hp(xs: list[float], cutoff: float) -> list[float]:
    if not xs:
        return xs
    rc = 1.0 / (2.0 * math.pi * max(20.0, cutoff))
    a = rc / (rc + 1.0 / SR)
    y = 0.0
    xp = xs[0]
    out = []
    for x in xs:
        y = a * (y + x - xp)
        xp = x
        out.append(y)
    return out


def env_adsr(i: int, n: int, a: float, d: float, s: float, r: float) -> float:
    if n <= 0:
        return 0.0
    as_, ds_, rs_ = int(a * SR), int(d * SR), int(r * SR)
    if i < as_:
        return i / as_ if as_ else 1.0
    t2 = i - as_
    if t2 < ds_:
        return 1.0 - (1.0 - s) * (t2 / ds_ if ds_ else 1.0)
    if i > n - rs_:
        return s * ((n - i) / rs_ if rs_ else 0.0)
    return s


def place(buf: list[float], layer: list[float], at: int) -> None:
    for i, v in enumerate(layer):
        j = at + i
        if 0 <= j < len(buf):
            buf[j] += v


def voice_sine(freq, n, amp, a=0.01, d=0.05, s=0.7, r=0.08):
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        e = env_adsr(i, n, a, d, s, r)
        out[i] = math.sin(ph) * amp * e
        ph += 2 * math.pi * freq / SR
    return out


def voice_tri(freq, n, amp, a=0.01, d=0.08, s=0.6, r=0.1):
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        e = env_adsr(i, n, a, d, s, r)
        tri = (2.0 / math.pi) * math.asin(max(-1.0, min(1.0, math.sin(ph))))
        out[i] = tri * amp * e
        ph += 2 * math.pi * freq / SR
    return out


def voice_soft_saw(freq, n, amp, a=0.02, d=0.08, s=0.55, r=0.1):
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        e = env_adsr(i, n, a, d, s, r)
        raw = math.sin(ph) + 0.4 * math.sin(2 * ph) + 0.18 * math.sin(3 * ph)
        out[i] = raw * 0.65 * amp * e
        ph += 2 * math.pi * freq / SR
    return out


def voice_power(freq, n, amp, a=0.006, d=0.05, s=0.6, r=0.06):
    out = [0.0] * n
    ph = 0.0
    ph2 = 0.03
    for i in range(n):
        e = env_adsr(i, n, a, d, s, r)
        raw = (
            math.sin(ph) + 0.5 * math.sin(2 * ph) + 0.25 * math.sin(3 * ph)
            + 0.65 * math.sin(ph2) + 0.2 * math.sin(2 * ph2)
        )
        out[i] = math.tanh(raw * 1.4) * 0.42 * amp * e
        ph += 2 * math.pi * freq / SR
        ph2 += 2 * math.pi * freq * 1.004 / SR
    return out


def voice_flute(freq, n, amp):
    """村子／海岸：氣鳴感 soft sine + 輕噪。"""
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        e = env_adsr(i, n, 0.03, 0.1, 0.55, 0.15)
        breath = random.uniform(-1, 1) * 0.04 * e
        out[i] = (math.sin(ph) + 0.12 * math.sin(2 * ph) + breath) * amp * e
        ph += 2 * math.pi * freq / SR
    return out


def voice_bell(freq, n, amp):
    """森林：鐘／鐵琴感。"""
    out = [0.0] * n
    ph = [0.0, 0.0, 0.0]
    ratios = [1.0, 2.76, 5.4]
    for i in range(n):
        t = i / SR
        e = math.exp(-2.8 * t) * (1.0 if i > 0.002 * SR else i / (0.002 * SR))
        s = 0.0
        for k, r in enumerate(ratios):
            s += (0.7 if k == 0 else 0.25 / k) * math.sin(ph[k])
            ph[k] += 2 * math.pi * freq * r / SR
        out[i] = s * amp * e
    return out


def voice_choir(freq, n, amp):
    """霧／塔：慢攻長音，多 detune。"""
    out = [0.0] * n
    phs = [0.0, 0.0, 0.0, 0.0]
    dets = [1.0, 1.004, 0.996, 1.008]
    for i in range(n):
        e = env_adsr(i, n, 0.2, 0.3, 0.7, 0.35)
        s = 0.0
        for k, d in enumerate(dets):
            s += math.sin(phs[k])
            phs[k] += 2 * math.pi * freq * d / SR
        out[i] = (s / 4.0) * amp * e
    return out


def voice_kick(n, amp):
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 130.0 * math.exp(-t * 20.0) + 38.0
        e = math.exp(-t * 15.0)
        ph += 2 * math.pi * f / SR
        out[i] = math.sin(ph) * amp * e
    return out


def voice_hat(n, amp):
    out = [random.uniform(-1, 1) * amp * math.exp(-45.0 * i / max(1, n)) for i in range(n)]
    return one_pole_hp(out, 5500.0)


def voice_snare(n, amp):
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        e = math.exp(-14.0 * t)
        noise = random.uniform(-1, 1)
        ph += 2 * math.pi * 180.0 / SR
        out[i] = (0.35 * math.sin(ph) + 0.65 * noise) * amp * e
    return one_pole_hp(out, 400.0)


def voice_crash(n, amp):
    out = [random.uniform(-1, 1) * amp * math.exp(-4.0 * i / max(1, n)) for i in range(n)]
    return one_pole_hp(one_pole_lp(out, 9500.0), 1500.0)


def lead_voice(kind: str, freq: float, n: int, amp: float) -> list[float]:
    if kind == "flute":
        return voice_flute(freq, n, amp)
    if kind == "bell":
        return voice_bell(freq, n, amp * 1.1)
    if kind == "choir":
        return voice_choir(freq, n, amp * 0.9)
    if kind == "horn":
        return voice_soft_saw(freq, n, amp, a=0.04, d=0.1, s=0.65, r=0.12)
    if kind == "brass":
        return voice_power(freq, n, amp * 0.95, a=0.01, d=0.06, s=0.6, r=0.08)
    if kind == "power":
        return voice_power(freq, n, amp, a=0.004, d=0.04, s=0.65, r=0.05)
    if kind == "pulse":
        return voice_soft_saw(freq, n, amp, a=0.005, d=0.04, s=0.5, r=0.06)
    return voice_sine(freq, n, amp)


# ─── 各地區專屬旋律動機 ───────────────────────────────────

def motif_for(region: str, bar_i: int) -> list[tuple[int, float]]:
    """(degree 0..6 or 7=高八度主音 or -1 rest, beats)."""
    lib = {
        "title": [
            [(0, 0.5), (2, 0.5), (4, 0.5), (5, 0.5), (7, 1.5), (5, 0.5)],
            [(4, 0.5), (5, 0.5), (7, 1), (5, 1), (4, 1)],
            [(2, 0.5), (4, 0.5), (5, 0.5), (7, 0.5), (5, 0.5), (4, 0.5), (2, 1)],
            [(0, 1), (4, 0.5), (5, 0.5), (7, 1), (-1, 0.5), (5, 0.5)],
        ],
        "village": [
            [(0, 1), (2, 1), (4, 1.5), (-1, 0.5)],
            [(5, 1), (4, 1), (2, 1), (0, 1)],
            [(2, 0.5), (4, 0.5), (5, 1), (4, 1), (2, 1)],
            [(0, 2), (-1, 1), (4, 1)],
        ],
        "town": [
            [(0, 0.5), (0, 0.5), (4, 1), (5, 1), (7, 1)],
            [(5, 0.5), (4, 0.5), (2, 1), (0, 1), (2, 1)],
            [(4, 1), (5, 1), (7, 1), (5, 1)],
            [(0, 0.5), (4, 0.5), (5, 0.5), (4, 0.5), (2, 1), (0, 1)],
        ],
        "road": [
            [(0, 1), (2, 1), (3, 1), (5, 1)],
            [(5, 0.5), (3, 0.5), (2, 1), (0, 1.5), (-1, 0.5)],
            [(2, 1), (3, 1), (5, 1), (3, 1)],
            [(0, 1.5), (2, 0.5), (3, 1), (0, 1)],
        ],
        "wild": [
            [(0, 0.5), (1, 0.5), (0, 0.5), (3, 0.5), (5, 1), (3, 1)],
            [(5, 0.5), (3, 0.5), (1, 1), (0, 1), (-1, 1)],
            [(3, 0.5), (5, 0.5), (7, 1), (5, 1), (3, 1)],
            [(0, 1), (1, 0.5), (0, 0.5), (3, 1), (-1, 1)],
        ],
        "mist": [
            [(0, 2), (-1, 1), (3, 1)],
            [(5, 3), (-1, 1)],
            [(3, 2), (0, 2)],
            [(-1, 1), (7, 2), (5, 1)],
        ],
        "dojo": [
            [(0, 0.5), (2, 0.5), (3, 0.5), (5, 0.5), (3, 0.5), (2, 0.5), (0, 1)],
            [(5, 0.5), (3, 0.5), (2, 0.5), (0, 0.5), (2, 1), (3, 1)],
            [(0, 0.5), (3, 0.5), (5, 1), (3, 1), (0, 1)],
            [(2, 0.5), (3, 0.5), (5, 0.5), (3, 0.5), (2, 1), (-1, 1)],
        ],
        "forest": [
            [(4, 0.5), (5, 0.5), (7, 1), (5, 0.5), (4, 0.5), (2, 1)],
            [(0, 0.5), (2, 0.5), (4, 0.5), (5, 0.5), (4, 1), (2, 1)],
            [(5, 1), (7, 1), (5, 1), (4, 1)],
            [(2, 0.5), (0, 0.5), (-1, 0.5), (4, 0.5), (5, 1), (4, 1)],
        ],
        "coast": [
            [(0, 1), (4, 1), (5, 1), (4, 1)],
            [(2, 0.5), (4, 0.5), (5, 1), (7, 1), (5, 1)],
            [(5, 1), (4, 1), (2, 1), (0, 1)],
            [(0, 1.5), (-1, 0.5), (4, 1), (5, 1)],
        ],
        "battle": [
            [(0, 0.25), (0, 0.25), (2, 0.5), (3, 0.5), (5, 0.5), (7, 0.5), (5, 0.5), (3, 0.5), (0, 0.5)],
            [(5, 0.5), (7, 0.5), (5, 0.5), (3, 0.5), (2, 0.5), (0, 0.5), (2, 1)],
            [(0, 0.5), (3, 0.5), (5, 0.5), (7, 0.5), (5, 1), (3, 1)],
            [(7, 0.5), (5, 0.5), (3, 0.5), (2, 0.5), (0, 1), (-1, 0.5), (0, 0.5)],
        ],
        "boss": [
            [(0, 1), (1, 0.5), (0, 0.5), (3, 1), (5, 1)],
            [(5, 0.5), (3, 0.5), (1, 1), (0, 1.5), (-1, 0.5)],
            [(3, 0.5), (5, 0.5), (7, 1), (5, 1), (3, 1)],
            [(0, 0.5), (3, 0.5), (5, 1), (7, 1), (5, 1)],
        ],
        "tower": [
            [(0, 2), (3, 1), (2, 1)],
            [(-1, 1), (5, 2), (3, 1)],
            [(0, 1), (3, 1), (5, 1), (3, 1)],
            [(0, 3), (-1, 1)],
        ],
        "ending": [
            [(0, 1), (2, 0.5), (4, 0.5), (5, 1), (4, 1)],
            [(2, 1), (4, 1), (7, 1), (5, 1)],
            [(4, 0.5), (5, 0.5), (4, 1), (2, 1), (0, 1)],
            [(0, 2), (4, 1), (0, 1)],
        ],
    }
    m = lib.get(region, lib["title"])
    return m[bar_i % len(m)]


def section_gain(bar: int, bars: int, region: str) -> float:
    q = bars / 4.0
    # 霧／村／塔：起伏溫和
    if region in ("mist", "village", "tower", "forest"):
        if bar < q:
            return 0.55 + 0.25 * (bar / max(1, q))
        if bar < 3 * q:
            return 0.85 + 0.1 * math.sin(bar)
        return 0.75
    # 戰鬥／Boss／標題：副歌炸
    if region in ("battle", "boss", "title"):
        if bar < q:
            return 0.6 + 0.25 * (bar / max(1, q))
        if bar < bars // 2:
            return 0.85
        return 1.25
    if bar < q:
        return 0.6 + 0.3 * (bar / max(1, q))
    if bar < bars // 2:
        return 0.9
    return 1.1


def render_track(bars, root, mode, bpm, energy, region: str) -> list[float]:
    random.seed(hash(region) % 10000 + root * 13 + bars)
    cfg = REGION[region]
    beat = 60.0 / bpm
    bar_sec = beat * 4.0
    n = int(bars * bar_sec * SR)
    buf = [0.0] * n
    sc = scale(mode)
    chords = chords_for(region, mode)
    phrase = 4

    for bar in range(bars):
        bar_start = int(bar * bar_sec * SR)
        g = section_gain(bar, bars, region) * energy
        chord = chords[bar % len(chords)]
        half = bar >= bars // 2

        # ── drums ──
        dkind = cfg["drums"]
        if dkind != "none":
            if cfg["crash"] and bar == bars // 2:
                place(buf, voice_crash(int(0.5 * SR), 0.18 * g), bar_start)
            for b in range(4):
                if dkind == "soft":
                    if b in (0, 2):
                        place(buf, voice_kick(int(0.15 * SR), 0.14 * g), bar_start + int(b * beat * SR))
                    if b in (1, 3) and region not in ("forest", "coast"):
                        place(buf, voice_hat(int(0.04 * SR), 0.03 * g), bar_start + int(b * beat * SR))
                elif dkind == "march":
                    # 軍鼓感：每拍 snare-ish + 強拍 kick
                    if b in (0, 2):
                        place(buf, voice_kick(int(0.16 * SR), 0.22 * g), bar_start + int(b * beat * SR))
                    place(buf, voice_snare(int(0.09 * SR), (0.16 if b in (1, 3) else 0.06) * g),
                          bar_start + int(b * beat * SR))
                    place(buf, voice_hat(int(0.03 * SR), 0.04 * g), bar_start + int((b + 0.5) * beat * SR))
                elif dkind == "drive":
                    if b in (0, 2) or (half and b == 1):
                        place(buf, voice_kick(int(0.18 * SR), 0.28 * g), bar_start + int(b * beat * SR))
                    if b in (1, 3):
                        place(buf, voice_snare(int(0.1 * SR), 0.18 * g), bar_start + int(b * beat * SR))
                    for sub in (0.0, 0.5):
                        place(buf, voice_hat(int(0.03 * SR), 0.05 * g), bar_start + int((b + sub) * beat * SR))
                elif dkind == "battle":
                    place(buf, voice_kick(int(0.16 * SR), 0.32 * g), bar_start + int(b * beat * SR))
                    place(buf, voice_kick(int(0.08 * SR), 0.12 * g), bar_start + int((b + 0.5) * beat * SR))
                    if b in (1, 3):
                        place(buf, voice_snare(int(0.1 * SR), 0.22 * g), bar_start + int(b * beat * SR))
                    for sub in (0.0, 0.25, 0.5, 0.75):
                        place(buf, voice_hat(int(0.028 * SR), 0.055 * g * (1.0 if sub in (0, 0.5) else 0.5)),
                              bar_start + int((b + sub) * beat * SR))

        # ── bass ──
        bkind = cfg["bass"]
        if bkind != "none":
            notes = []
            if bkind == "soft":
                notes = [(chord[0] - 12, 2.0, 0.0), (chord[0] - 12, 1.5, 2.0)]
            elif bkind == "walk":
                notes = [(chord[0] - 12, 1.0, float(b)) for b in range(4)]
            elif bkind == "pulse":
                notes = [(chord[0] - 12, 0.45, b * 0.5) for b in range(8)]
            else:  # drive
                for b in range(8):
                    deg = (chord[0] if b % 4 < 3 else chord[min(2, len(chord) - 1)]) - 12
                    notes.append((deg, 0.45, b * 0.5))
            for deg, beats, atb in notes:
                freq = midi_hz(root + deg)
                length = int(beats * beat * SR)
                amp = (0.12 if bkind == "soft" else 0.2) * g
                if bkind == "soft":
                    layer = voice_sine(freq, length, amp, a=0.02, d=0.08, s=0.7, r=0.1)
                else:
                    layer = voice_soft_saw(freq, length, amp, a=0.004, d=0.04, s=0.7, r=0.05)
                place(buf, layer, bar_start + int(atb * beat * SR))
                if bkind == "drive":
                    place(buf, voice_sine(freq * 0.5, length, amp * 0.45, a=0.005, d=0.04, s=0.7, r=0.06),
                          bar_start + int(atb * beat * SR))

        # ── pad ──
        pkind = cfg["pad"]
        if pkind != "none":
            pad_len = int(bar_sec * SR)
            base_amp = {"warm": 0.055, "thin": 0.03, "dark": 0.05, "bright": 0.04}.get(pkind, 0.04)
            if half:
                base_amp *= 1.15
            for vi, deg in enumerate(chord[:3]):
                freq = midi_hz(root + deg)
                amp = base_amp * g * (0.7 if vi else 1.0)
                if pkind == "dark":
                    layer = voice_choir(freq, pad_len, amp * 0.85) if vi == 0 else voice_sine(freq, pad_len, amp * 0.5, a=0.15, d=0.2, s=0.7, r=0.2)
                elif pkind == "warm":
                    layer = voice_sine(freq, pad_len, amp, a=0.12, d=0.15, s=0.7, r=0.18)
                elif pkind == "bright":
                    layer = voice_tri(freq, pad_len, amp * 0.8, a=0.08, d=0.12, s=0.55, r=0.12)
                else:
                    layer = voice_sine(freq, pad_len, amp * 0.7, a=0.1, d=0.12, s=0.55, r=0.15)
                place(buf, layer, bar_start)

        # ── stabs（地區限定）──
        if cfg["stabs"]:
            for b in (0, 2) if region not in ("battle", "boss") else range(4):
                at = bar_start + int(b * beat * SR)
                length = int(0.2 * beat * SR)
                for deg in (chord[0], chord[0] + 7):
                    freq = midi_hz(root + deg + 12)
                    place(buf, voice_power(freq, length, 0.05 * g, a=0.002, d=0.04, s=0.25, r=0.04), at)

        # ── arp（村／林／海／終章）──
        if cfg["arp"]:
            pat = [0, 1, 2, 1, 2, 3] if len(chord) > 3 else [0, 1, 2, 1]
            step = 4.0 / len(pat)
            for k, idx in enumerate(pat):
                if idx >= len(chord):
                    continue
                at = bar_start + int(k * step * beat * SR)
                freq = midi_hz(root + chord[idx] + (12 if region in ("forest", "coast") else 0))
                length = int(step * beat * SR * 0.9)
                if region == "forest":
                    place(buf, voice_bell(freq, length, 0.045 * g), at)
                elif region == "village":
                    place(buf, voice_tri(freq, length, 0.04 * g, a=0.005, d=0.05, s=0.3, r=0.08), at)
                else:
                    place(buf, voice_sine(freq, length, 0.04 * g, a=0.005, d=0.04, s=0.35, r=0.06), at)

        # ── 主旋律（各地區音色 + 動機）──
        lead_g = g * (1.15 if half else 0.9)
        if region in ("battle", "boss", "title"):
            lead_g *= 1.2
        if region in ("mist", "tower"):
            lead_g *= 0.85
        motif = motif_for(region, bar % phrase)
        t_beat = 0.0
        for deg, beats in motif:
            if deg >= 0:
                if deg >= 7:
                    sc_deg = sc[0] + 12
                else:
                    sc_deg = sc[deg % len(sc)]
                # 音域：霧偏低、林/海偏高、戰鬥更高
                oct = 12
                if region in ("mist", "tower"):
                    oct = 0
                elif region in ("forest", "coast", "village"):
                    oct = 12
                elif region in ("battle", "boss", "title"):
                    oct = 12
                freq = midi_hz(root + sc_deg + oct)
                length = int(beats * beat * SR)
                amp = 0.14 * lead_g
                if region in ("battle", "boss"):
                    amp = 0.18 * lead_g
                if region == "village":
                    amp = 0.11 * lead_g
                at = bar_start + int(t_beat * beat * SR)
                place(buf, lead_voice(cfg["lead"], freq, length, amp), at)
                # 戰鬥／標題／Boss 再疊八度
                if region in ("battle", "boss", "title") and half:
                    place(buf, lead_voice(cfg["lead"], freq * 2, length, amp * 0.4), at)
            t_beat += beats

        # ── 句尾 fill：僅戰鬥／標題／城鎮 ──
        if (bar + 1) % phrase == 0 and region in ("battle", "boss", "title", "town", "dojo"):
            run = [0, 2, 4, 5, 7, 5, 4, 2]
            for k, di in enumerate(run):
                sc_deg = sc[0] + 12 if di >= 7 else sc[di % len(sc)]
                freq = midi_hz(root + sc_deg + 12)
                place(buf, voice_power(freq, int(0.15 * beat * SR), 0.09 * g * (0.5 + 0.5 * k / 8), a=0.002, d=0.02, s=0.3, r=0.03),
                      bar_start + int((2.0 + k * 0.22) * beat * SR))

        # ── 霧特效：偶爾高音碎響 ──
        if region == "mist" and bar % 3 == 1:
            for k in range(3):
                f = midi_hz(root + 24 + random.choice([0, 3, 7, 12]))
                place(buf, voice_sine(f, int(0.4 * SR), 0.03 * g, a=0.05, d=0.1, s=0.3, r=0.2),
                      bar_start + int((0.5 + k * 1.1) * beat * SR))

        # ── 海岸：低頻浪湧 ──
        if region == "coast":
            for i in range(int(bar_sec * SR)):
                j = bar_start + i
                if j < n:
                    t = i / SR
                    buf[j] += 0.04 * g * math.sin(2 * math.pi * 0.35 * t) * math.sin(2 * math.pi * 55 * t)

    # ── sidechain ──
    sc = cfg["sc"]
    if sc > 0:
        bs = int(beat * SR)
        for i in range(n):
            pos = (i % max(1, bs)) / max(1, bs)
            duck = 1.0 - sc * math.exp(-pos * 12.0)
            buf[i] *= 0.88 + 0.12 * duck

    # ── 地區混響感 ──
    delay_sec = 0.22 if region in ("mist", "tower", "forest") else 0.12 if region in ("village", "coast", "ending") else 0.09
    fb = 0.28 if region in ("mist", "tower") else 0.14 if region in ("forest", "coast") else 0.08
    dly = int(delay_sec * SR)
    delayed = [0.0] * n
    for i in range(n):
        delayed[i] = buf[i]
        if i >= dly:
            delayed[i] += delayed[i - dly] * fb
    buf = delayed

    # ── EQ 按地區 ──
    buf = one_pole_hp(buf, 40.0 if region in ("mist", "tower") else 55.0)
    cut = 2200.0 * cfg["bright"] + 1500.0 * energy
    if region in ("battle", "boss", "title"):
        cut = min(7200.0, cut + 1500)
    if region in ("mist", "tower"):
        cut = min(cut, 2800.0)
    buf = one_pole_lp(buf, cut)

    # 輕壓縮
    rms = 0.0
    out = [0.0] * n
    for i, x in enumerate(buf):
        rms = 0.998 * rms + 0.002 * (x * x)
        level = math.sqrt(max(rms, 1e-12))
        gain = max(0.6, min(1.8, 0.14 / (level + 0.08)))
        out[i] = soft_clip(x * gain, 0.92)

    xfade = int(0.1 * SR)
    for i in range(xfade):
        w = i / xfade
        out[i] = out[i] * w + out[n - xfade + i] * (1.0 - w)

    peak = max(1e-9, max(abs(x) for x in out))
    # 戰鬥略響、霧略柔
    target = 0.40 if region in ("battle", "boss", "title") else 0.32 if region in ("mist", "village") else 0.36
    g = target / peak
    return [soft_clip(x * g, 0.95) for x in out]


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        raw = bytearray()
        for x in samples:
            raw += struct.pack("<h", int(max(-1, min(1, x)) * 32767))
        w.writeframes(raw)


def main() -> None:
    print(f"Region-distinct BGM → {OUT}")
    for name, (bars, root, mode, bpm, energy, region) in TRACKS.items():
        print(f"  {name:8s} [{region:7s}] bpm={bpm:3.0f} {mode:6s} …", end=" ", flush=True)
        samples = render_track(bars, root, mode, bpm, energy, region)
        path = OUT / f"{name}.wav"
        write_wav(path, samples)
        print(f"{len(samples)/SR:4.1f}s  {path.stat().st_size//1024}KB")
    print("Done. Restart Godot / Reimport BGM.")


if __name__ == "__main__":
    main()
