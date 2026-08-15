#!/usr/bin/env python3
"""
貼圖瘦身 —— 分兩個互不相干的槓桿，因為它們省的是不同東西。

槓桿 A：源 PNG 無損重壓（--lossless）
  影響 repo 大小與 CI clone/import 時間，不影響玩家下載的包。
  主要收益不是「重新壓縮」，而是**丟掉沒用的 alpha 通道**：
  美術產出的背景有 99 張是 RGBA、但整張 alpha 全 255，等於白白多背一個通道。
  轉成 RGB 對可見像素是 bit 級相同，不是有損。

槓桿 B：Godot 匯入格式（--import-mode）
  影響玩家下載的包，不影響源檔，也不用改任何一行 GDScript。
  Godot 的 compress/mode=0（無損）會把貼圖以 WebP 無損塞進 .ctex；
  mode=1（有損）改用 WebP 有損。實測 63 張地圖背景 48.5MB → 9.0MB。
  只對「大張的手繪背景」開有損 —— 小圖是像素風、又走 nearest 過濾，
  有損壓縮的塊狀瑕疵會直接看得出來，所以維持無損。

為什麼不整批轉成 .webp 檔：貼圖路徑是在 GDScript 裡用 "%s.png" 組出來的
（見 scripts/art/sprite_db.gd），換副檔名要動程式。槓桿 B 拿到同樣的包體收益
而且零程式碼風險。

用法
  # 只量不改（預設），先看報告再決定
  python3 tools/compress_sprites.py

  # 真的寫檔
  python3 tools/compress_sprites.py --lossless --apply
  python3 tools/compress_sprites.py --import-mode --apply

  # 反悔：把所有貼圖的匯入設定改回無損
  python3 tools/compress_sprites.py --import-mode --quality 0 --apply

可重複執行：兩個槓桿都是冪等的。源 PNG 壓不動就跳過，
.import 已經是目標設定就跳過，所以排進 CI 或 pre-commit 都不會一直產生 diff。
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("需要 Pillow：pip3 install Pillow")

ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "game" / "assets" / "sprites"

## 生成中間產物與備份，不是出貨資產，一律不碰。
## 命名規則跟 .gitignore／export_presets.cfg 的 exclude_filter 是同一套，改的話三邊要一起改。
SKIP_PREFIXES = ("_gen", "_backup")

## 長邊超過這個值才視為「大張手繪圖」，才允許有損。
## 512 這個門檻剛好把 maps/ 的 63 張背景與橫幅全部收進來，其餘 245 張小圖全部排除。
LOSSY_MIN_EDGE = 512

## 就算夠大也不開有損的目錄 —— 這幾類是像素風或有硬邊 alpha，
## 有損 WebP 會在邊緣糊掉一圈，比省下的體積更礙眼。
LOSSY_DENY_DIRS = ("tiles", "fx", "player")

## 0.9 是實測挑出來的：地圖背景 PSNR 約 40dB（肉眼分不出），體積剩 1/5。
## 再往下掉到 0.85 只多省 2MB，但橫幅那種大面積漸層開始出現帶狀色階。
DEFAULT_QUALITY = 0.9


def shipping_pngs() -> list[Path]:
    """出貨用的貼圖 —— 排掉所有生成／備份目錄。"""
    out = []
    for p in SPRITES.rglob("*.png"):
        rel = p.relative_to(SPRITES)
        if any(part.startswith(SKIP_PREFIXES) for part in rel.parts):
            continue
        out.append(p)
    return sorted(out)


def _mb(n: int) -> str:
    return "%.2f MB" % (n / 1048576)


# ─── 槓桿 A：源 PNG 無損重壓 ──────────────────────────────────────

def _shrink_png(path: Path) -> tuple[Path, int, int, bool]:
    """回傳（檔案, 原大小, 重壓後大小, 是否丟掉了冗餘 alpha）。純計算，不寫檔。"""
    orig = path.stat().st_size
    im = Image.open(path)
    im.load()
    dropped = False
    if im.mode == "RGBA" and im.getchannel("A").getextrema()[0] == 255:
        ## alpha 整張都是不透明 —— 這個通道沒有承載任何資訊
        im = im.convert("RGB")
        dropped = True
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return path, orig, buf.tell(), dropped


def run_lossless(apply: bool) -> None:
    files = shipping_pngs()
    with ProcessPoolExecutor() as ex:
        results = list(ex.map(_shrink_png, files, chunksize=4))

    ## 只有省超過 1% 才動它。差幾百 bytes 的重壓不值得在 git 裡留一筆 diff，
    ## 也是冪等的關鍵 —— 跑第二次時所有檔案都會落在這個門檻底下而被跳過。
    todo = [r for r in results if r[2] < r[1] * 0.99]
    orig = sum(r[1] for r in results)
    after = sum(r[2] if r in todo else r[1] for r in results)
    dropped = sum(1 for r in todo if r[3])

    print("── 槓桿 A：源 PNG 無損重壓 ──")
    print("  掃描 %d 檔 %s" % (len(results), _mb(orig)))
    print("  可壓 %d 檔（其中 %d 檔是丟掉全不透明的 alpha）" % (len(todo), dropped))
    print("  重壓後 %s，省 %s（%.1f%%）" % (_mb(after), _mb(orig - after),
                                            100 * (orig - after) / orig if orig else 0))
    if not todo:
        print("  沒有可壓的檔，跳過。")
        return
    if not apply:
        print("  （dry-run，沒有寫檔。要真的寫加 --apply）")
        return

    for path, _, _, _ in todo:
        im = Image.open(path)
        im.load()
        if im.mode == "RGBA" and im.getchannel("A").getextrema()[0] == 255:
            im = im.convert("RGB")
        im.save(path, "PNG", optimize=True)
    print("  已重寫 %d 檔。" % len(todo))


# ─── 槓桿 B：Godot 匯入壓縮模式 ────────────────────────────────────

def wants_lossy(path: Path) -> bool:
    rel = path.relative_to(SPRITES)
    if rel.parts[0] in LOSSY_DENY_DIRS:
        return False
    with Image.open(path) as im:
        return max(im.size) >= LOSSY_MIN_EDGE


def _patch_import(text: str, mode: int, quality: float) -> str:
    text = re.sub(r"^compress/mode=\d+$", "compress/mode=%d" % mode, text, flags=re.M)
    return re.sub(r"^compress/lossy_quality=[\d.]+$",
                  "compress/lossy_quality=%s" % quality, text, flags=re.M)


def run_import_mode(apply: bool, quality: float) -> None:
    files = shipping_pngs()
    changed: list[Path] = []
    missing: list[Path] = []
    n_lossy = 0

    for png in files:
        imp = png.with_suffix(".png.import")
        if not imp.exists():
            ## .import 是 Godot 開專案時生成的；沒有就代表這台機器還沒 import 過。
            missing.append(png)
            continue
        lossy = quality > 0 and wants_lossy(png)
        n_lossy += lossy
        text = imp.read_text(encoding="utf-8")
        want = _patch_import(text, 1 if lossy else 0, quality if lossy else 0.7)
        if want != text:
            changed.append(imp)
            if apply:
                imp.write_text(want, encoding="utf-8")

    print("── 槓桿 B：Godot 匯入壓縮模式 ──")
    print("  貼圖 %d 張，其中 %d 張走有損（quality=%s），%d 張維持無損"
          % (len(files), n_lossy, quality, len(files) - n_lossy))
    if missing:
        print("  ⚠ %d 張還沒有 .import（這台機器沒 import 過，先在 Godot 開一次專案）" % len(missing))
    print("  需要改寫的 .import：%d 個" % len(changed))
    if not changed:
        print("  匯入設定已經是目標狀態，跳過。")
        return
    if not apply:
        print("  （dry-run，沒有寫檔。要真的寫加 --apply）")
        return
    print("  已改寫 %d 個 .import —— 下次開 Godot 會重新匯入這批貼圖。" % len(changed))


# ─── 量測報告 ────────────────────────────────────────────────────

def _measure(path: Path):
    """量一張圖在各種封裝格式下的位元組數。放模組層是因為 ProcessPoolExecutor 要 pickle 它。"""
    orig = path.stat().st_size
    im = Image.open(path)
    im.load()
    out = {}
    for tag, kw in (("wl", dict(lossless=True, quality=100, method=4)),
                    ("w90", dict(quality=90, method=4))):
        buf = io.BytesIO()
        im.save(buf, "WEBP", **kw)
        out[tag] = buf.tell()
    return path, orig, out, max(im.size)


def run_scan() -> None:
    """先量再改：把「哪些檔多大、換成各種格式後多大」攤開來。"""
    files = shipping_pngs()

    with ProcessPoolExecutor() as ex:
        rows = list(ex.map(_measure, files, chunksize=4))

    ## 依 sprites/ 底下第一層目錄彙總，這樣才看得出錢花在哪
    groups: dict[str, list[int]] = {}
    for path, orig, out, _ in rows:
        d = path.relative_to(SPRITES).parts[0]
        g = groups.setdefault(d, [0, 0, 0, 0])
        g[0] += 1
        g[1] += orig
        g[2] += out["wl"]
        g[3] += out["w90"]

    print("── 出貨貼圖現況 ──")
    print("  %-12s %5s %11s %11s %11s" % ("目錄", "檔數", "源 PNG", "封裝(無損)", "封裝(q90)"))
    for d, g in sorted(groups.items(), key=lambda kv: -kv[1][1]):
        print("  %-12s %5d %11s %11s %11s"
              % (d, g[0], _mb(g[1]), _mb(g[2]), _mb(g[3])))

    ## 「封裝後」= .ctex 裡實際存的位元組，也就是玩家要下載的量。
    ## Godot 現況是 mode=0，所以「封裝(無損)」那欄就是今天的包體貼圖大小。
    src = sum(r[1] for r in rows)
    now = sum(r[2]["wl"] for r in rows)
    plan = sum(r[2]["w90"] if wants_lossy(r[0]) else r[2]["wl"] for r in rows)
    print()
    print("  源 PNG 合計        %s" % _mb(src))
    print("  包體貼圖 現況      %s" % _mb(now))
    print("  包體貼圖 分級後    %s   省 %s（%.1f%%）"
          % (_mb(plan), _mb(now - plan), 100 * (now - plan) / now if now else 0))
    print()
    print("  下一步：--lossless 瘦源檔（省 repo）／--import-mode 瘦包體（省玩家下載）")


def main() -> None:
    ap = argparse.ArgumentParser(description="貼圖瘦身：源 PNG 無損重壓 + Godot 匯入壓縮模式")
    ap.add_argument("--lossless", action="store_true", help="槓桿 A：重壓源 PNG（無損）")
    ap.add_argument("--import-mode", action="store_true", help="槓桿 B：調 .import 的壓縮模式")
    ap.add_argument("--quality", type=float, default=DEFAULT_QUALITY,
                    help="槓桿 B 的有損品質 0~1；給 0 代表全部改回無損（預設 %s）" % DEFAULT_QUALITY)
    ap.add_argument("--apply", action="store_true", help="真的寫檔；不給就只是 dry-run")
    args = ap.parse_args()

    if not SPRITES.is_dir():
        sys.exit("找不到 %s" % SPRITES)

    if not args.lossless and not args.import_mode:
        run_scan()
        return
    if args.lossless:
        run_lossless(args.apply)
    if args.import_mode:
        run_import_mode(args.apply, args.quality)


if __name__ == "__main__":
    main()
