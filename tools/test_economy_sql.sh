#!/usr/bin/env bash
## 經濟守門 SQL 的本機驗證
##
## 在本機起一個丟完即棄的 PostgreSQL，補上 Supabase 才有的 auth schema，
## 依序跑 supabase/schema.sql + supabase/economy.sql，然後用
## supabase/economy_test.sql 實際演一遍作弊情境。
##
## 為什麼要這樣做：這些規則的價值全在「擋不擋得住」，
## 光看 SQL 讀不出 least()/floor() 的邊界對不對，得真的跑。
##
## 用法：bash tools/test_economy_sql.sh
## 環境變數：PGBIN=/opt/homebrew/opt/postgresql@15/bin
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"

if [[ ! -x "$PGBIN/initdb" ]]; then
  echo "FATAL: 找不到 initdb（用 PGBIN=... 指定 PostgreSQL 的 bin 目錄）"
  exit 127
fi

TMP="$(mktemp -d)"
DATA="$TMP/data"
SOCK="$TMP/sock"
mkdir -p "$SOCK"

cleanup() {
  "$PGBIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== 起臨時資料庫 =="
"$PGBIN/initdb" -D "$DATA" -U postgres --no-sync >"$TMP/initdb.log" 2>&1 || {
  echo "FATAL: initdb 失敗"; tail -20 "$TMP/initdb.log"; exit 1
}
"$PGBIN/pg_ctl" -D "$DATA" -o "-k $SOCK -h ''" -w -l "$TMP/pg.log" start >/dev/null 2>&1 || {
  echo "FATAL: 資料庫起不來"; tail -20 "$TMP/pg.log"; exit 1
}

PSQL=("$PGBIN/psql" -h "$SOCK" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)

## Supabase 才有的東西：auth schema、auth.uid()、authenticated/anon 角色
"${PSQL[@]}" >"$TMP/stub.log" 2>&1 <<'SQL'
create schema if not exists auth;
create table auth.users (id uuid primary key);
-- 測試裡用 set_config('test.uid', ...) 來扮演不同玩家
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.uid', true), '')::uuid;
$$;
create role authenticated;
create role anon;
create role service_role;
SQL
if [[ $? -ne 0 ]]; then
  echo "FATAL: auth stub 建立失敗"; tail -20 "$TMP/stub.log"; exit 1
fi

echo "== 跑 schema.sql =="
if ! "${PSQL[@]}" -f "$ROOT/supabase/schema.sql" >"$TMP/schema.log" 2>&1; then
  echo "FAIL: schema.sql 有錯"; tail -30 "$TMP/schema.log"; exit 1
fi
echo "  ok"

echo "== 跑 economy.sql =="
if ! "${PSQL[@]}" -f "$ROOT/supabase/economy.sql" >"$TMP/economy.log" 2>&1; then
  echo "FAIL: economy.sql 有錯"; tail -40 "$TMP/economy.log"; exit 1
fi
echo "  ok"

echo "== 重跑一次（確認可重複執行）=="
if ! "${PSQL[@]}" -f "$ROOT/supabase/schema.sql" >"$TMP/schema2.log" 2>&1 \
  || ! "${PSQL[@]}" -f "$ROOT/supabase/economy.sql" >"$TMP/economy2.log" 2>&1; then
  echo "FAIL: 重跑失敗"; tail -30 "$TMP/schema2.log" "$TMP/economy2.log"; exit 1
fi
echo "  ok"

echo "== 演作弊情境 =="
if ! "${PSQL[@]}" -f "$ROOT/supabase/economy_test.sql" 2>&1 | tee "$TMP/test.log"; then
  echo "FAIL: 情境測試沒跑完"; exit 1
fi

if grep -q "ECON_SQL_FAIL" "$TMP/test.log"; then
  echo
  echo "TESTS FAILED"
  exit 1
fi
if ! grep -q "ECON_SQL_OK" "$TMP/test.log"; then
  echo
  echo "FAIL: 沒有印出結束哨兵"
  exit 1
fi

echo
echo "TESTS PASSED"
