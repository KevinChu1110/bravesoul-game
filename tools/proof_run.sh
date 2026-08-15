#!/usr/bin/env bash
## Godogen「證明優於宣稱」：import → smoke → 多階段截圖
## 環境變數：
##   PROOF_WINDOWED=1  用可見視窗截（macOS 上較容易有真畫面；無顯示器時勿開）
##   GODOT=godot       引擎指令
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
OUT="$ROOT/screenshots"
GODOT="${GODOT:-godot}"
mkdir -p "$OUT"
echo "# proof screenshots — not loaded by game" > "$OUT/.gdignore"

echo "== 1) import =="
"$GODOT" --path "$GAME" --headless --import 2>&1 | tail -8 || true

echo "== 2) smoke (no SCRIPT ERROR) =="
"$GODOT" --path "$GAME" --headless --quit-after 5 2>&1 | tee /tmp/bravesoul_smoke.log | tail -16
if grep -E "SCRIPT ERROR|Parse Error" /tmp/bravesoul_smoke.log; then
  echo "FAIL: script errors"
  exit 1
fi
echo "SMOKE OK"

echo "== 3) headless tests =="
## 跟 CI 跑的是同一支 runner（.github/workflows/game-ci.yml），本機先擋一次
"$ROOT/tools/run_tests.sh"

echo "== 4) spec-language check =="
## 擋開發用語洩漏到玩家面（CI 跑的是同一支）
python3 "$ROOT/tools/check_player_text.py"

echo "== 5) proof capture (multi-stage) =="
PROOF_ARGS=(--path "$GAME" --script res://scripts/dev/proof_capture.gd)
## 預設：本機有顯示器就用視窗截真畫面；CI / 無 GUI 才 headless
USE_WINDOWED="${PROOF_WINDOWED:-}"
if [[ -z "$USE_WINDOWED" ]]; then
  if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" || "$(uname)" == "Darwin" ]]; then
    USE_WINDOWED=1
  else
    USE_WINDOWED=0
  fi
fi
if [[ "$USE_WINDOWED" == "1" ]]; then
  echo "(windowed mode — real pixels)"
  "$GODOT" "${PROOF_ARGS[@]}" --resolution 1280x720 2>&1 | tee /tmp/bravesoul_proof.log | tail -40
else
  echo "(headless — may fallback composite if viewport empty)"
  "$GODOT" --headless "${PROOF_ARGS[@]}" 2>&1 | tee /tmp/bravesoul_proof.log | tail -40
fi

# 抄出 user:// 截圖
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata"
if [[ -d "$USER_DIR" ]]; then
  find "$USER_DIR" -name 'proof_*.png' -mtime -1 -print -exec cp -f {} "$OUT/" \; 2>/dev/null || true
fi

echo "== 6) screenshots =="
ls -la "$OUT" 2>/dev/null || true
if [[ -f "$OUT/proof_manifest.txt" ]]; then
  echo "--- manifest ---"
  cat "$OUT/proof_manifest.txt"
fi

# 基本閘門：至少 3 張 png
count=$(find "$OUT" -name 'proof_0*.png' 2>/dev/null | wc -l | tr -d ' ')
if [[ "${count:-0}" -lt 3 ]]; then
  echo "FAIL: expected >=3 proof_0*.png, got $count"
  exit 1
fi
echo "PROOF PNG count=$count OK"
echo "Godogen rule: review the PNGs — iterate on what you see, not the exit code alone."
