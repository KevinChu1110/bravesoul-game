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
import re
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
    """
    轉 Ogg Theora。優先用 ffmpeg 的 libtheora，沒有就用獨立的 ffmpeg2theora。

    注意：homebrew-core 的 ffmpeg formula **依賴裡根本沒有 theora**，
    所以 `brew reinstall ffmpeg` 不會解決問題（別再試了）。
    正解是 `brew install ffmpeg2theora`。
    """
    use_ffmpeg = has_encoder("libtheora")
    use_f2t = shutil.which("ffmpeg2theora") is not None
    if not use_ffmpeg and not use_f2t:
        die(
            "這台編不出 Godot 能播的 Ogg Theora（Godot 4 內建影片只支援這個格式）。\n"
            "\n"
            "  修法：brew install ffmpeg2theora\n"
            "\n"
            "  註：homebrew-core 的 ffmpeg 依賴裡沒有 theora，\n"
            "      `brew reinstall ffmpeg` 沒有用，別浪費時間。\n"
            "\n"
            "  或改走靜態插畫（不需要 theora，今天就能跑）：\n"
            "      python3 tools/import_cutscene.py stills …"
        )

    VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    dst = VIDEO_DIR / f"{args.name}.ogv"
    dur = duration_of(args.source)
    print(f"── {args.source.name} → {dst.name}（{dur:.1f} 秒）")

    if use_ffmpeg:
        cmd = [
            "ffmpeg", "-y", "-v", "error", "-i", str(args.source),
            "-vf", f"scale=-2:{VIDEO_HEIGHT}",
            "-c:v", "libtheora", "-b:v", VIDEO_BITRATE,
        ]
        cmd += ["-an"] if args.mute else ["-c:a", "libvorbis", "-b:a", AUDIO_BITRATE]
        cmd += [str(dst)]
    else:
        print("  （用 ffmpeg2theora；這台的 ffmpeg 沒有 libtheora）")
        cmd = [
            "ffmpeg2theora", str(args.source),
            "-o", str(dst),
            "--videoquality", "7",
            "--max_size", f"x{VIDEO_HEIGHT}",
        ]
        if args.mute:
            cmd.append("--noaudio")

    p = run(cmd)
    if p.returncode != 0 or not dst.exists():
        die(f"轉檔失敗：{(p.stderr or p.stdout).strip()[:400]}")

    size_mb = dst.stat().st_size / 1024 / 1024
    print(f"  寫入 {dst.relative_to(ROOT)}（{size_mb:.1f} MB）")
    if size_mb > 20:
        print("  警告：超過 20 MB。Theora 壓縮效率差，考慮縮短長度或改走 stills。")
    print("\n用法：")
    print(f'  CutscenePlayer.play([{{"video": "{args.name}", "hold": 0}}])')
    print("接著跑：godot --path game --headless --import")


def read_scenes() -> list[tuple[str, int, str]]:
    """
    從 main.gd 讀出每段過場的插畫 id、張數、目前用的地圖底圖。

    刻意用讀的而不是在這裡寫一份表：表會過期，而過期的表比沒有表更糟——
    照著它去生圖，生出來的檔名對不上就不會亮，還很難查。
    """
    main_gd = ROOT / "game" / "scripts" / "main.gd"
    if not main_gd.exists():
        die(f"找不到 {main_gd}")
    lines = main_gd.read_text().splitlines()

    out: list[tuple[str, int, str]] = []
    for i, line in enumerate(lines):
        m = re.search(r'_cutscene_art\("([^"]+)", \[', line)
        if not m:
            continue
        depth = 0
        close = i
        for k in range(i, len(lines)):
            depth += lines[k].count("[") - lines[k].count("]")
            if depth <= 0:
                close = k
                break
        seg = "\n".join(lines[i:close + 1])
        n = len(re.findall(r'"speaker"\s*:', seg))
        bgs = list(dict.fromkeys(re.findall(r'"bg"\s*:\s*"([^"]*)"', seg)))
        out.append((m.group(1), n, "／".join(bgs)))
    return out


def cmd_scenes(_args) -> None:
    scenes = read_scenes()
    if not scenes:
        die("main.gd 裡找不到任何過場（_cutscene_art 的寫法可能改了）")

    done = 0
    print(f"共 {len(scenes)} 段過場，{sum(n for _, n, _ in scenes)} 張插畫\n")
    print(f"{'插畫 id':<18} {'張數':>4}  {'狀態':<10} 目前底圖")
    print("─" * 62)
    for sid, n, bgs in scenes:
        have = sum(
            1 for i in range(1, n + 1)
            if (STILLS_DIR / f"{sid}_{i}.png").exists()
        )
        done += have
        state = "全有" if have == n else ("尚無" if have == 0 else f"{have}/{n}")
        print(f"{sid:<18} {n:>4}  {state:<10} {bgs}")
    total = sum(n for _, n, _ in scenes)
    print("─" * 62)
    print(f"已完成 {done}/{total} 張\n")
    print("生完某一段之後：")
    print("  python3 tools/import_cutscene.py stills <影片> --name c0_open --count 4")
    print("沒有插畫的段落會安靜退回地圖底圖，可以一段一段補。")


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

    scenes = {sid: n for sid, n, _ in read_scenes()}
    if args.name in scenes:
        want = scenes[args.name]
        print(f"\n『{args.name}』這段過場需要 {want} 張，你給了 {len(written)} 張。")
        if len(written) < want:
            print(f"  少的 {want - len(written)} 張會退回地圖底圖，補齊再跑一次就好。")
        elif len(written) > want:
            print(f"  多的 {len(written) - want} 張不會用到（也不礙事）。")
        print("接著跑：godot --path game --headless --import")
        print("檔名對得上，遊戲會自動用——不用改任何程式。")
    else:
        print("\n這批圖不屬於任何一段過場，要用的話自己貼進過場定義：")
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

    n = sub.add_parser("scenes", help="列出十四段過場的插畫 id 與完成度")
    n.set_defaults(func=cmd_scenes)

    args = ap.parse_args()
    if args.mode == "scenes":
        args.func(args)
        return

    need_ffmpeg()
    if not args.source.exists():
        die(f"找不到 {args.source}")
    if args.mode == "stills":
        if args.count < 1:
            die("--count 至少要 1")
        known = {sid for sid, _, _ in read_scenes()}
        if known and args.name not in known:
            print(
                f"提醒：`{args.name}` 不在過場清單裡，這批圖不會自動掛到任何一段。\n"
                f"      清單看 `python3 tools/import_cutscene.py scenes`。\n"
                f"      （只是要一批散圖的話，忽略這行即可。）\n"
            )
    args.func(args)


if __name__ == "__main__":
    main()
