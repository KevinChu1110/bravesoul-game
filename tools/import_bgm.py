#!/usr/bin/env python3
"""
把外部配樂（Flow music／任何來源）匯入成遊戲能用的循環 BGM。

為什麼需要這支：AI 生成的曲子是「一首歌」，不是「一段可以無限循環的遊戲配樂」。
直接丟進遊戲會在接回開頭時聽到明顯的斷點。這支做三件事：

  1. 轉成 Ogg Vorbis（Godot 原生支援，體積遠小於 WAV）
  2. 響度正規化，讓 13 首曲子音量一致，玩家不用一直調音量
  3. **自動找循環點** —— 找出一個時間點，讓「曲子結尾」接回那裡時聽起來最連續，
     前面那段當一次性前奏。結果寫進 loops.json 給 AudioManager 讀。

第 3 點是這支工具真正的價值，其他兩件事 ffmpeg 一行就能做。

用法
  # 單首（檔名就是曲目 id）
  python3 tools/import_bgm.py ~/Downloads/title.mp3

  # 一整個資料夾，檔名對應 id（title.mp3 / village.wav / boss.m4a …）
  python3 tools/import_bgm.py ~/Downloads/flow_bgm/

  # 指定 id、手動指定循環點（已經知道前奏多長時）
  python3 tools/import_bgm.py boss_take3.mp3 --id boss --loop-offset 12.5

  # 只想看看它會挑哪個循環點，先不寫檔
  python3 tools/import_bgm.py ~/Downloads/title.mp3 --dry-run

曲目 id（13 首）
  title village town mist dojo forest coast wild road battle boss tower ending

匯入後
  程式合成的 .wav 會留著當後備；AudioManager 看到同名 .ogg 就優先用 .ogg，
  所以想聽回原本的版本，把 .ogg 移走即可。
"""
from __future__ import annotations

import argparse
import array
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BGM_DIR = ROOT / "game" / "assets" / "audio" / "bgm"
LOOPS_JSON = BGM_DIR / "loops.json"

TRACK_IDS = [
    "title", "village", "town", "mist", "dojo", "forest", "coast",
    "wild", "road", "battle", "boss", "tower", "ending",
]

AUDIO_SUFFIXES = {".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg", ".opus", ".wma", ".aiff"}

# 轉檔設定
OGG_QUALITY = 6        # ~192kbps，配樂夠用且體積合理
MP3_QUALITY = 3        # libmp3lame VBR，約 175kbps
TARGET_LUFS = -16.0    # 遊戲配樂常見響度；比串流的 -14 略低，留空間給音效

# 循環點分析設定
ANALYSIS_RATE = 4000   # 分析用的降取樣率（純 Python 跑得動）
WINDOW_SEC = 1.0       # 比對窗長度
SEARCH_STEP_SEC = 0.05 # 候選點間隔
MIN_INTRO_SEC = 2.0    # 循環點至少要在這之後（避免整首都當前奏）
MAX_INTRO_FRAC = 0.5   # 循環點不超過全曲這個比例


def die(msg: str) -> None:
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def need_ffmpeg() -> None:
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        die("找不到 ffmpeg／ffprobe，請先 `brew install ffmpeg`")


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def duration_of(path: Path) -> float:
    p = run([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(path),
    ])
    try:
        return float(p.stdout.strip())
    except ValueError:
        die(f"讀不出 {path.name} 的長度：{p.stderr.strip()[:200]}")
        return 0.0


def decode_for_analysis(path: Path, tmp: Path) -> tuple[array.array, int]:
    """降成低取樣率單聲道，純 Python 才跑得動相關性分析。"""
    out = tmp / "analysis.wav"
    p = run([
        "ffmpeg", "-y", "-v", "error", "-i", str(path),
        "-ac", "1", "-ar", str(ANALYSIS_RATE), "-c:a", "pcm_s16le", str(out),
    ])
    if p.returncode != 0 or not out.exists():
        die(f"解碼失敗：{p.stderr.strip()[:300]}")
    with wave.open(str(out), "rb") as w:
        raw = w.readframes(w.getnframes())
    samples = array.array("h")
    samples.frombytes(raw)
    return samples, ANALYSIS_RATE


def find_loop_offset(samples: array.array, rate: int) -> tuple[float, float]:
    """
    找出最適合的循環起點。

    做法：取曲子結尾的一段當「參考窗」，在前半段裡滑動比對，
    找出跟結尾最像的位置——從那裡接回去，耳朵最不會察覺跳接。
    比對用正規化相關性（比單純的差值平方穩，音量不同也比得出來）。

    回傳 (循環起點秒數, 相似度 0~1)。相似度低於 0.5 時多半是這首歌
    本來就沒有可循環的結構，會在輸出時提醒。
    """
    n = len(samples)
    win = int(WINDOW_SEC * rate)
    if n < win * 4:
        return 0.0, 0.0

    # 參考窗＝結尾往前一個窗（跳過最後 0.1 秒，AI 生成的常有淡出尾巴）
    tail_end = n - int(0.1 * rate)
    tail_start = tail_end - win
    if tail_start <= 0:
        return 0.0, 0.0
    ref = samples[tail_start:tail_end]

    ref_mean = sum(ref) / win
    ref_dev = [s - ref_mean for s in ref]
    ref_norm = math.sqrt(sum(d * d for d in ref_dev))
    if ref_norm == 0:
        return 0.0, 0.0

    lo = int(MIN_INTRO_SEC * rate)
    hi = min(int(n * MAX_INTRO_FRAC), tail_start - win)
    if hi <= lo:
        return 0.0, 0.0

    step = max(1, int(SEARCH_STEP_SEC * rate))
    best_score = -2.0
    best_pos = lo

    for pos in range(lo, hi, step):
        seg = samples[pos:pos + win]
        seg_mean = sum(seg) / win
        dot = 0.0
        sq = 0.0
        for i in range(win):
            d = seg[i] - seg_mean
            dot += d * ref_dev[i]
            sq += d * d
        if sq <= 0:
            continue
        score = dot / (math.sqrt(sq) * ref_norm)
        if score > best_score:
            best_score = score
            best_pos = pos

    return best_pos / rate, max(0.0, best_score)


def measure_loudness(path: Path) -> float | None:
    """用 ffmpeg 的 loudnorm 量一遍，拿到整首的 LUFS。"""
    p = run([
        "ffmpeg", "-hide_banner", "-i", str(path),
        "-af", "loudnorm=print_format=json", "-f", "null", "-",
    ])
    text = p.stderr
    start = text.rfind("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        return float(json.loads(text[start:end + 1])["input_i"])
    except (ValueError, KeyError):
        return None


def _has_encoder(name: str) -> bool:
    p = run(["ffmpeg", "-hide_banner", "-encoders"])
    return any(
        line.split()[1] == name
        for line in p.stdout.splitlines()
        if len(line.split()) > 1
    )


def pick_encoder() -> tuple[str, str, list[str]]:
    """
    選一個這台機器真的編得出來的格式。

    Godot 原生吃 Ogg Vorbis 與 MP3 兩種，所以有得選。Homebrew 的 ffmpeg
    不一定帶 libvorbis（實測 8.1.2 的 bottle 就沒有），沒有的話退到 MP3
    比用 ffmpeg 內建那顆品質很差的 vorbis 編碼器好得多。

    回傳 (副檔名, 說明, ffmpeg 編碼參數)
    """
    if _has_encoder("libvorbis"):
        return "ogg", "Ogg Vorbis", ["-c:a", "libvorbis", "-q:a", str(OGG_QUALITY)]
    if _has_encoder("libmp3lame"):
        return "mp3", "MP3（這台的 ffmpeg 沒有 libvorbis）", [
            "-c:a", "libmp3lame", "-q:a", str(MP3_QUALITY),
        ]
    if _has_encoder("vorbis"):
        return "ogg", "Ogg Vorbis（ffmpeg 內建編碼器，品質較差）", [
            "-c:a", "vorbis", "-strict", "-2", "-b:a", "192k",
        ]
    die(
        "這台的 ffmpeg 編不出 Ogg Vorbis 也編不出 MP3。\n"
        "  修法：brew reinstall ffmpeg（或裝一個帶 libvorbis 的建置）"
    )
    return "", "", []


def encode_audio(src: Path, dst: Path, gain_db: float, enc_args: list[str]) -> None:
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src)]
    if abs(gain_db) > 0.05:
        cmd += ["-af", f"volume={gain_db:.2f}dB"]
    cmd += enc_args + ["-ac", "2", str(dst)]
    p = run(cmd)
    if p.returncode != 0 or not dst.exists():
        die(f"轉檔失敗：{p.stderr.strip()[:300]}")


def load_loops() -> dict:
    if not LOOPS_JSON.exists():
        return {}
    try:
        data = json.loads(LOOPS_JSON.read_text())
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        print(f"  警告：{LOOPS_JSON.name} 內容壞了，重新建立")
        return {}


def save_loops(loops: dict) -> None:
    ordered = {k: round(float(loops[k]), 3) for k in TRACK_IDS if k in loops}
    LOOPS_JSON.write_text(json.dumps(ordered, indent="\t", ensure_ascii=False) + "\n")


def resolve_id(src: Path, explicit: str | None) -> str:
    if explicit:
        if explicit not in TRACK_IDS:
            die(f"沒有這個曲目 id：{explicit}\n可用：{' '.join(TRACK_IDS)}")
        return explicit
    stem = src.stem.lower()
    if stem in TRACK_IDS:
        return stem
    # 容忍 title_v2 / boss-final 這類命名
    for tid in TRACK_IDS:
        if stem.startswith(tid + "_") or stem.startswith(tid + "-"):
            return tid
    die(
        f"從檔名 `{src.name}` 認不出曲目 id。\n"
        f"請把檔名改成曲目 id，或用 --id 指定。可用：{' '.join(TRACK_IDS)}"
    )
    return ""


def import_one(src: Path, args, loops: dict, enc: tuple[str, str, list[str]]) -> bool:
    track_id = resolve_id(src, args.id)
    dur = duration_of(src)
    print(f"\n── {src.name} → {track_id}（{dur:.1f} 秒）")

    if dur < 5.0:
        print("  警告：不到 5 秒，當背景樂會一直重頭播")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        if args.loop_offset is not None:
            offset = float(args.loop_offset)
            score = -1.0
            print(f"  循環起點：{offset:.2f} 秒（手動指定）")
        else:
            print("  分析循環點…", end="", flush=True)
            samples, rate = decode_for_analysis(src, tmp)
            offset, score = find_loop_offset(samples, rate)
            print(f" 起點 {offset:.2f} 秒，相似度 {score:.2f}")
            if score < 0.5:
                print(
                    "  警告：相似度偏低，這首可能沒有可循環的結構。\n"
                    "        建議請 Flow 重生一版「可無縫循環／loopable」的，"
                    "或用 --loop-offset 手動指定。"
                )

        if offset >= dur:
            print(f"  警告：循環起點 {offset:.2f} 超過曲長，改用 0")
            offset = 0.0

        gain = 0.0
        if not args.no_normalize:
            lufs = measure_loudness(src)
            if lufs is None:
                print("  警告：量不到響度，跳過正規化")
            else:
                gain = TARGET_LUFS - lufs
                gain = max(-20.0, min(20.0, gain))
                print(f"  響度 {lufs:.1f} LUFS → 調整 {gain:+.1f} dB")

        if args.dry_run:
            print("  （dry-run，沒有寫檔）")
            return False

        ext, _label, enc_args = enc
        dst = BGM_DIR / f"{track_id}.{ext}"
        encode_audio(src, dst, gain, enc_args)
        size_kb = dst.stat().st_size / 1024
        print(f"  寫入 {dst.relative_to(ROOT)}（{size_kb:.0f} KB）")
        ## 同一首不要同時留兩種格式，否則 AudioManager 只會用到其中一個
        for other in ("ogg", "mp3"):
            if other == ext:
                continue
            stale = BGM_DIR / f"{track_id}.{other}"
            if stale.exists():
                stale.unlink()
                (BGM_DIR / f"{track_id}.{other}.import").unlink(missing_ok=True)
                print(f"  移除同名舊檔 {stale.name}")

    loops[track_id] = offset
    return True


def main() -> None:
    ap = argparse.ArgumentParser(
        description="把外部配樂匯入成遊戲能用的循環 BGM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("source", type=Path, help="音檔或整個資料夾")
    ap.add_argument("--id", help="曲目 id（單檔時可用，預設從檔名判斷）")
    ap.add_argument(
        "--loop-offset", type=float,
        help="手動指定循環起點（秒）；不給就自動分析",
    )
    ap.add_argument("--no-normalize", action="store_true", help="不做響度正規化")
    ap.add_argument("--dry-run", action="store_true", help="只分析不寫檔")
    args = ap.parse_args()

    need_ffmpeg()
    if not args.source.exists():
        die(f"找不到 {args.source}")
    BGM_DIR.mkdir(parents=True, exist_ok=True)

    if args.source.is_dir():
        sources = sorted(
            p for p in args.source.iterdir()
            if p.is_file() and p.suffix.lower() in AUDIO_SUFFIXES
        )
        if not sources:
            die(f"{args.source} 裡沒有音檔")
        if args.id:
            die("--id 只能用在單一檔案")
    else:
        sources = [args.source]

    enc = pick_encoder()
    if not args.dry_run:
        print(f"輸出格式：{enc[1]}")

    loops = load_loops()
    written = 0
    for src in sources:
        if import_one(src, args, loops, enc):
            written += 1

    if written and not args.dry_run:
        save_loops(loops)
        print(f"\n循環點寫入 {LOOPS_JSON.relative_to(ROOT)}")
        print(f"完成 {written} 首。")
        print("接著跑：godot --path game --headless --import")
        print("然後：TEST_FILTER=bgm bash tools/run_tests.sh")
    elif args.dry_run:
        print("\n（dry-run 結束，沒有動任何檔案）")


if __name__ == "__main__":
    main()
