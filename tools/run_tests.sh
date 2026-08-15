#!/usr/bin/env bash
## 勇者之魂 · 無頭測試 runner
##
## 每個 scripts/**/test_*.gd 都是 `extends SceneTree`，
## 用 `godot --headless -s res://...` 跑，結尾 print 一個 XXX_OK / XXX_FAIL 哨兵並 quit(0/1)。
##
## 這支 runner 對每個測試檢查三件事，任一不過就算 FAIL：
##   1. 行程 exit code == 0
##   2. 輸出含 _OK 哨兵、且不含 _FAIL
##   3. 輸出沒有 SCRIPT ERROR / Parse Error / Compile Error
##
## 第 3 點是關鍵：測試腳本編譯失敗時，Godot 會「退回去跑主場景」而不是收工，
## 於是行程永遠不結束。所以每個測試都套 watchdog 超時。
##
## 環境變數：
##   GODOT=godot           引擎指令
##   TEST_TIMEOUT=120      單一測試上限秒數
##   TEST_FILTER=formulas  只跑檔名含該字串的測試
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
GODOT="${GODOT:-godot}"
TIMEOUT="${TEST_TIMEOUT:-120}"
FILTER="${TEST_FILTER:-}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "FATAL: 找不到 godot（用 GODOT=/path/to/godot 指定）"
  exit 127
fi

## macOS 沒有 coreutils 的 timeout，自己做 watchdog
run_guarded() {
  local secs="$1" logfile="$2"; shift 2
  "$@" >"$logfile" 2>&1 &
  local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local wd=$!
  wait "$pid"; local code=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return $code
}

## 不用 mapfile：macOS 內建 /bin/bash 還是 3.2
TESTS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ -n "$FILTER" && "$line" != *"$FILTER"* ]]; then continue; fi
  TESTS+=("$line")
done < <(cd "$GAME" && find scripts -name "test_*.gd" | sort)

if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "FATAL: 沒有找到任何測試（filter='$FILTER'）"
  exit 1
fi

LOGDIR="$(mktemp -d)"
trap 'rm -rf "$LOGDIR"' EXIT

echo "== 無頭測試 · ${#TESTS[@]} 個 · 單項上限 ${TIMEOUT}s =="
FAILED=()
for t in "${TESTS[@]}"; do
  name="$(basename "$t" .gd)"
  log="$LOGDIR/$name.log"
  run_guarded "$TIMEOUT" "$log" "$GODOT" --path "$GAME" --headless -s "res://$t"
  code=$?

  reason=""
  if [[ $code -eq 137 || $code -eq 124 ]]; then
    reason="逾時 ${TIMEOUT}s（測試沒有 quit — 多半是編譯失敗後退回跑主場景）"
  elif grep -qE "SCRIPT ERROR|Parse Error|Compile Error" "$log"; then
    reason="有 script error：$(grep -m1 -E 'SCRIPT ERROR|Parse Error|Compile Error' "$log" | tr -d '\r')"
  elif grep -qE "[A-Z_]+_FAIL" "$log"; then
    reason="斷言失敗：$(grep -m1 -E '[A-Z_]+_FAIL' "$log")"
  elif ! grep -qE "[A-Z_]+_OK" "$log"; then
    reason="沒有印出 _OK 哨兵（exit=$code）"
  elif [[ $code -ne 0 ]]; then
    reason="exit code = $code"
  fi

  if [[ -n "$reason" ]]; then
    echo "  FAIL  $name — $reason"
    FAILED+=("$name")
    ## 失敗時把 log 尾巴印出來，CI 上才查得到
    echo "        ---- 最後 20 行 ----"
    tail -20 "$log" | sed 's/^/        /'
    echo "        --------------------"
  else
    echo "  ok    $name  $(grep -oE '[A-Z_]+_OK' "$log" | tail -1)"
  fi
done

echo
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "TESTS FAILED (${#FAILED[@]}/${#TESTS[@]}): ${FAILED[*]}"
  exit 1
fi
echo "TESTS PASSED (${#TESTS[@]}/${#TESTS[@]})"
