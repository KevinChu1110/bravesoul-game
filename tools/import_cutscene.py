#!/usr/bin/env python3
"""
把外部影片（Google Flow／Veo 產的 mp4）匯入成遊戲能用的過場素材。

兩條路，選一條或都用：

  video  轉成 Ogg Theora 播真影片
         Godot 內建只吃 Ogg Theora，所以一定要轉。Theora 壓縮效率差，
         1080p 會很肥，這支預設降到 720p 並限位元率。
         需要帶 libtheora 的 ffmpeg——沒有的話這支會直接告訴你怎麼裝。

  stills 抽關鍵格當靜態插畫，餵現有的過場系統（底圖＋字幕）
         不用改引擎、檔案小、風格好控，而且用你現在的 ffmpeg 就能跑。
         遊戲是像素／Q 版風，寫實運鏡放進去容易突兀，這條通常更安全。

用法
  # 轉成可播的影片（放進 assets/video/<name>.ogv）
  python3 tools/import_cutscene.py video ~/Downloads/opening.mp4 --name opening

  # 抽 6 張關鍵格當底圖（放進 assets/sprites/cutscenes/<name>_1.png …）
  python3 tools/import_cutscene.py stills ~/Downloads/opening.mp4 --name opening --count 6

  # 指定時間點抽格，比自動挑準
  python3 tools/import_cutscene.py stills opening.mp4 --name opening --at 0.5,3.2,7.8

抽完之後怎麼用
  CutscenePlayer.play([
      {"bg": "res://assets/sprites/cutscenes/opening_1.png", "speaker": "…", "text": "…"},
      {"video": "opening", "hold": 0},
  ])
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO_DIR = ROOT / "game" / "assets" / "video"
STILLS_DIR = ROOT / "game" / "assets" / "sprites" / "cutscenes"

# Theora 輸出設定：過場不是動作遊戲畫面，720p 夠用，換來可接受的檔案大小
VIDEO_HEIGHT = 720
VIDEO_BITRATE = "1800k"
AUDIO_BITRATE = "128k"

# 遊戲以 1280x720 為基準解析度
STILL_WIDTH = 1280


def die(msg: str) -> None:
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def need_ffmpeg() -> None:
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        die("找不到 ffmpeg／ffprobe，請先 `brew install ffmpeg`")


def has_encoder(name: str) -> bool:
    p = run(["ffmpeg", "-hide_banner", "-encoders"])
    return any(
        line.split()[1] == name
        for line in p.stdout.splitlines()
        if len(line.split()) > 1
    )


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


def cmd_video(args) -> None:
    if not has_encoder("libtheora"):
        die(
            "這台的 ffmpeg 沒有 libtheora，編不出 Godot 能播的 Ogg Theora。\n"
            "\n"
            "  Godot 4 內建影片只支援 Ogg Theora，沒得選。三個辦法：\n"
            "    1. 換一個帶 libtheora 的 ffmpeg：brew reinstall ffmpeg\n"
            "       （裝完用 `ffmpeg -encoders | grep theora` 確認有 E 開頭那行）\n"
            "    2. brew install ffmpeg2theora，再自己轉\n"
            "    3. 改走靜態插畫：python3 tools/import_cutscene.py stills …\n"
            "       —— 這條今天就能跑，而且對像素風的畫面一致性更友善"
        )

    VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    dst = VIDEO_DIR / f"{args.name}.ogv"
    dur = duration_of(args.source)
    print(f"── {args.source.name} → {dst.name}（{dur:.1f} 秒）")

    cmd = [
        "ffmpeg", "-y", "-v", "error", "-i", str(args.source),
        "-vf", f"scale=-2:{VIDEO_HEIGHT}",
        "-c:v", "libtheora", "-b:v", VIDEO_BITRATE,
        "-c:a", "libvorbis", "-b:a", AUDIO_BITRATE,
        str(dst),
    ]
    if args.mute:
        cmd = [c for c in cmd if c not in ("-c:a", "libvorbis", "-b:a", AUDIO_BITRATE)]
        cmd.insert(-1, "-an")

    p = run(cmd)
    if p.returncode != 0 or not dst.exists():
        die(f"轉檔失敗：{p.stderr.strip()[:400]}")

    size_mb = dst.stat().st_size / 1024 / 1024
    print(f"  寫入 {dst.relative_to(ROOT)}（{size_mb:.1f} MB）")
    if size_mb > 20:
        print("  警告：超過 20 MB。Theora 壓縮效率差，考慮縮短長度或改走 stills。")
    print("\n用法：")
    print(f'  CutscenePlayer.play([{{"video": "{args.name}", "hold": 0}}])')
    print("接著跑：godot --path game --headless --import")


def pick_times(dur: float, count: int) -> list[float]:
    """平均取樣，但避開頭尾——AI 生成的影片開頭常是黑場、結尾常在淡出。"""
    lo, hi = dur * 0.06, dur * 0.94
    if count == 1:
        return [(lo + hi) / 2]
    step = (hi - lo) / (count - 1)
    return [lo + step * i for i in range(count)]


def cmd_stills(args) -> None:
    STILLS_DIR.mkdir(parents=True, exist_ok=True)
    dur = duration_of(args.source)

    if args.at:
        try:
            times = [float(t) for t in args.at.split(",") if t.strip()]
        except ValueError:
            die("--at 要是用逗號分隔的秒數，例如 0.5,3.2,7.8")
        bad = [t for t in times if t < 0 or t >= dur]
        if bad:
            die(f"這些時間點超出影片長度 {dur:.1f} 秒：{bad}")
    else:
        times = pick_times(dur, args.count)

    print(f"── {args.source.name}（{dur:.1f} 秒）→ 抽 {len(times)} 張")

    written = []
    for i, t in enumerate(times, start=1):
        dst = STILLS_DIR / f"{args.name}_{i}.png"
        p = run([
            "ffmpeg", "-y", "-v", "error",
            "-ss", f"{t:.3f}", "-i", str(args.source),
            "-frames:v", "1",
            "-vf", f"scale={STILL_WIDTH}:-2",
            str(dst),
        ])
        if p.returncode != 0 or not dst.exists():
            die(f"第 {i} 張抽格失敗（{t:.2f} 秒）：{p.stderr.strip()[:200]}")
        kb = dst.stat().st_size / 1024
        print(f"  {t:6.2f} 秒 → {dst.name}（{kb:.0f} KB）")
        written.append(dst)

    print("\n用法（貼進過場定義，字幕自己填）：")
    for dst in written:
        rel = dst.relative_to(ROOT / "game")
        print(f'  {{"bg": "res://{rel}", "speaker": "", "text": ""}},')
    print("\n接著跑：godot --path game --headless --import")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="把外部影片匯入成過場素材",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = ap.add_subparsers(dest="mode", required=True)

    v = sub.add_parser("video", help="轉成 Ogg Theora 播真影片")
    v.add_argument("source", type=Path)
    v.add_argument("--name", required=True, help="輸出檔名（不含副檔名）")
    v.add_argument("--mute", action="store_true", help="去掉聲音（配樂另外走 BGM）")
    v.set_defaults(func=cmd_video)

    s = sub.add_parser("stills", help="抽關鍵格當靜態插畫")
    s.add_argument("source", type=Path)
    s.add_argument("--name", required=True, help="輸出檔名前綴")
    s.add_argument("--count", type=int, default=5, help="抽幾張（預設 5）")
    s.add_argument("--at", help="指定時間點，逗號分隔的秒數")
    s.set_defaults(func=cmd_stills)

    args = ap.parse_args()
    need_ffmpeg()
    if not args.source.exists():
        die(f"找不到 {args.source}")
    if args.mode == "stills" and args.count < 1:
        die("--count 至少要 1")
    args.func(args)


if __name__ == "__main__":
    main()
