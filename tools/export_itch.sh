#!/usr/bin/env bash
## 翠嶺·兔勇者 · itch 出貨 export
## 用法：
##   ./tools/export_itch.sh           # 全部平台
##   ./tools/export_itch.sh mac       # 僅 macOS
##   ./tools/export_itch.sh win
##   ./tools/export_itch.sh linux
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
DIST="$ROOT/dist"
VERSION="${VERSION:-0.16.8}"
GODOT="${GODOT:-godot}"

TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
if [[ ! -d "$TEMPLATES" ]]; then
  echo "ERROR: 找不到 export templates：$TEMPLATES"
  echo "請先下載 Godot 4.7.1 export templates，或等本腳本同目錄的 install 流程完成。"
  echo "官方：https://godotengine.org/download 或 GitHub godot-builds 4.7.1-stable 的 .tpz"
  exit 1
fi

TARGET="${1:-all}"
mkdir -p "$DIST/windows" "$DIST/macos" "$DIST/linux" "$DIST/uploads"

# 出貨用 README 複製進各平台目錄
cp -f "$DIST/README.txt" "$DIST/windows/README.txt" 2>/dev/null || true
cp -f "$DIST/README.txt" "$DIST/macos/README.txt" 2>/dev/null || true
cp -f "$DIST/README.txt" "$DIST/linux/README.txt" 2>/dev/null || true

export_one() {
  local preset="$1"
  echo ""
  echo "======== Export: $preset ========"
  # --export-release 需要 preset 名稱完全一致
  "$GODOT" --headless --path "$GAME" --export-release "$preset" 2>&1
}

zip_win() {
  local out="$DIST/uploads/BraveSoul-${VERSION}-win.zip"
  rm -f "$out"
  (
    cd "$DIST/windows"
    # 單一 exe embed pck 時通常只有 .exe
    zip -9 -r "$out" . -x "*.import" -x ".*"
  )
  echo "→ $out ($(du -h "$out" | cut -f1))"
}

zip_mac() {
  local out="$DIST/uploads/BraveSoul-${VERSION}-mac.zip"
  # Godot mac export 已是 zip；若產生 .app 再壓
  if [[ -f "$DIST/macos/BraveSoul.zip" ]]; then
    cp -f "$DIST/macos/BraveSoul.zip" "$out"
    # 把 README 塞進 zip
    (
      cd "$DIST/macos"
      zip -9 "$out" README.txt 2>/dev/null || true
    )
  elif [[ -d "$DIST/macos/BraveSoul.app" ]]; then
    rm -f "$out"
    (
      cd "$DIST/macos"
      zip -9 -ry "$out" "BraveSoul.app" README.txt
    )
  else
    echo "WARN: macOS 產物未找到"
    return 1
  fi
  echo "→ $out ($(du -h "$out" | cut -f1))"
}

zip_linux() {
  local out="$DIST/uploads/BraveSoul-${VERSION}-linux.zip"
  rm -f "$out"
  (
    cd "$DIST/linux"
    chmod +x BraveSoul.x86_64 2>/dev/null || true
    zip -9 -r "$out" . -x "*.import" -x ".*"
  )
  echo "→ $out ($(du -h "$out" | cut -f1))"
}

case "$TARGET" in
  win|windows)
    export_one "Windows Desktop"
    zip_win
    ;;
  mac|macos)
    export_one "macOS"
    zip_mac
    ;;
  linux)
    export_one "Linux"
    zip_linux
    ;;
  all)
    export_one "Windows Desktop" || echo "Windows export failed (繼續)"
    zip_win || true
    export_one "macOS" || echo "macOS export failed (繼續)"
    zip_mac || true
    export_one "Linux" || echo "Linux export failed (繼續)"
    zip_linux || true
    ;;
  *)
    echo "用法: $0 [all|win|mac|linux]"
    exit 2
    ;;
esac

echo ""
echo "======== 完成 ========"
ls -lh "$DIST/uploads" 2>/dev/null || true
echo "上傳 itch：把 dist/uploads/*.zip 拖到專案頁 Downloads"
echo "文案見：release/ITCH_PAGE.md"
