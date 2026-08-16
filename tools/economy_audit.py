#!/usr/bin/env python3
"""economy_audit.py · 《勇者之魂》金幣來源／消耗粗掃

不必完美解析 GDScript：用正則掃 add_gold(±N)、"gold": N、craft_recipes。
輸出表給平衡調整對帳用（經濟 0.15+）。

用法：
  python3 tools/economy_audit.py
  python3 tools/economy_audit.py --root .
  python3 tools/economy_audit.py --json   # 機器可讀摘要
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


# add_gold(15) / add_gold(-cost) / GameState.add_gold(gold_n)
RE_ADD_GOLD_LIT = re.compile(
    r"""(?:GameState\.)?add_gold\s*\(\s*(-?\d+)\s*\)"""
)
RE_ADD_GOLD_ANY = re.compile(
    r"""(?:GameState\.)?add_gold\s*\(\s*([^)]+?)\s*\)"""
)
# "gold": 80  /  'gold': 80  （JSON 與 GDScript 字典字面）
RE_GOLD_KV = re.compile(
    r"""["']gold["']\s*:\s*(-?\d+)"""
)
# gold_n := 12 + ...  或  gold := 40 + ...
RE_GOLD_ASSIGN = re.compile(
    r"""\bgold(?:_n)?\s*:?=\s*([^\n#;]+)"""
)


SKIP_DIR_NAMES = {
    ".git",
    "node_modules",
    ".godot",
    "dist",
    "screenshots",
    "__pycache__",
    "uploads",
}


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    return bool(parts & SKIP_DIR_NAMES)


def rel(root: Path, p: Path) -> str:
    try:
        return str(p.relative_to(root))
    except ValueError:
        return str(p)


def scan_text_file(path: Path) -> list[dict]:
    rows: list[dict] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return [{"kind": "error", "file": str(path), "msg": str(e)}]

    lines = text.splitlines()
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue

        for m in RE_ADD_GOLD_LIT.finditer(line):
            n = int(m.group(1))
            rows.append(
                {
                    "kind": "add_gold_lit",
                    "file": str(path),
                    "line": i,
                    "value": n,
                    "dir": "sink" if n < 0 else ("noop" if n == 0 else "source"),
                    "snippet": stripped[:120],
                }
            )

        # 非字面 add_gold(expr)
        for m in RE_ADD_GOLD_ANY.finditer(line):
            expr = m.group(1).strip()
            if re.fullmatch(r"-?\d+", expr):
                continue  # 已由 lit 收
            rows.append(
                {
                    "kind": "add_gold_expr",
                    "file": str(path),
                    "line": i,
                    "expr": expr,
                    "dir": "sink" if expr.lstrip().startswith("-") else "source_or_var",
                    "snippet": stripped[:120],
                }
            )

        for m in RE_GOLD_KV.finditer(line):
            n = int(m.group(1))
            # 跳過明顯是 state dump / 測試 fixture 的超常見 0
            rows.append(
                {
                    "kind": "gold_kv",
                    "file": str(path),
                    "line": i,
                    "value": n,
                    "snippet": stripped[:120],
                }
            )

        for m in RE_GOLD_ASSIGN.finditer(line):
            rhs = m.group(1).strip()
            if re.fullmatch(r"-?\d+", rhs):
                continue  # 與 kv / lit 重疊少報
            if "add_gold" in rhs:
                continue
            rows.append(
                {
                    "kind": "gold_assign",
                    "file": str(path),
                    "line": i,
                    "expr": rhs[:80],
                    "snippet": stripped[:120],
                }
            )

    return rows


def load_craft_recipes(equip_path: Path) -> list[dict]:
    if not equip_path.is_file():
        return []
    data = json.loads(equip_path.read_text(encoding="utf-8"))
    recipes = data.get("craft_recipes") or data.get("craft") or []
    out = []
    for r in recipes:
        out.append(
            {
                "base_id": r.get("base_id", "?"),
                "gold": int(r.get("gold", 0)),
                "need_tier": int(r.get("need_tier", 0)),
                "hint": str(r.get("hint", "")),
                "mats": r.get("mats", {}),
            }
        )
    return out


def forge_tier_cost_table(per_tier: int = 40, max_tier: int = 11) -> list[tuple[int, int]]:
    """升階費用：cost = per_tier * current_tier（從 T1 打到 max）。"""
    rows = []
    total = 0
    for t in range(1, max_tier):
        c = per_tier * t
        total += c
        rows.append((t, c, total))
    return rows


def print_table(headers: list[str], rows: list[list], widths: list[int] | None = None) -> None:
    if widths is None:
        widths = []
        for i, h in enumerate(headers):
            w = len(h)
            for r in rows:
                if i < len(r):
                    w = max(w, len(str(r[i])))
            widths.append(min(w, 56))
    fmt = "  ".join(f"{{:{w}}}" for w in widths)
    print(fmt.format(*headers))
    print(fmt.format(*["-" * w for w in widths]))
    for r in rows:
        cells = [str(r[i]) if i < len(r) else "" for i in range(len(headers))]
        cells = [c[: widths[i]] for i, c in enumerate(cells)]
        print(fmt.format(*cells))


def main() -> int:
    ap = argparse.ArgumentParser(description="BraveSoul gold economy audit")
    ap.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repo root (default: parent of tools/)",
    )
    ap.add_argument("--json", action="store_true", help="print JSON summary only")
    args = ap.parse_args()
    root: Path = args.root.resolve()

    scan_roots = [
        root / "game" / "scripts",
        root / "game" / "data",
    ]
    exts = {".gd", ".json"}

    all_rows: list[dict] = []
    for base in scan_roots:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file() or p.suffix not in exts:
                continue
            if should_skip(p):
                continue
            # 測試檔仍掃，但標記
            for row in scan_text_file(p):
                row["file"] = rel(root, p)
                row["is_test"] = "/test_" in row["file"] or row["file"].startswith("game/scripts/") and "test_" in Path(row["file"]).name
                all_rows.append(row)

    equip = root / "game" / "data" / "tables" / "equipment.json"
    recipes = load_craft_recipes(equip)
    recipe_sum = sum(r["gold"] for r in recipes)

    lit_sources = [r for r in all_rows if r.get("kind") == "add_gold_lit" and r["value"] > 0 and not r.get("is_test")]
    lit_sinks = [r for r in all_rows if r.get("kind") == "add_gold_lit" and r["value"] < 0 and not r.get("is_test")]
    exprs = [r for r in all_rows if r.get("kind") == "add_gold_expr" and not r.get("is_test")]
    gold_kvs = [r for r in all_rows if r.get("kind") == "gold_kv" and not r.get("is_test") and r["value"] != 0]
    assigns = [r for r in all_rows if r.get("kind") == "gold_assign" and not r.get("is_test")]

    summary = {
        "craft_recipes": recipes,
        "craft_recipes_gold_sum": recipe_sum,
        "add_gold_lit_sources": lit_sources,
        "add_gold_lit_sinks": lit_sinks,
        "add_gold_expr": exprs,
        "gold_kv_nonzero": gold_kvs,
        "gold_assign_expr": assigns,
        "forge_per_tier": 40,
        "note": "字面量加總只是靜態提示；動態公式見 gold_assign / add_gold_expr",
    }

    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0

    print("=" * 72)
    print("勇者之魂 · 經濟稽核（粗掃，非模擬）")
    print(f"root: {root}")
    print("=" * 72)

    print("\n## 1. 鍛造配方 craft_recipes（equipment.json）· 職系武器主 sink")
    if not recipes:
        print("  （找不到配方）")
    else:
        print_table(
            ["base_id", "gold", "need_T", "hint"],
            [[r["base_id"], r["gold"], r["need_tier"], r["hint"][:40]] for r in recipes],
        )
        print(f"\n  配方金幣合計（全做一遍）: {recipe_sum}")
        mid_high = [r for r in recipes if r["gold"] >= 150]
        print(f"  中高階（≥150 金）: {len(mid_high)} 條 · 合計 {sum(r['gold'] for r in mid_high)}")

    print("\n## 2. 升階鍛造 forge_cost = 40 × tier（T1→T11 理論最低）")
    forge_rows = forge_tier_cost_table(40, 11)
    print_table(
        ["from_T", "cost", "cumul"],
        [[a, b, c] for a, b, c in forge_rows],
    )
    print(f"  T1→T11 完美連升合計: {forge_rows[-1][2]}（失敗重試另加）")

    print("\n## 3. add_gold(字面量) · 來源")
    if not lit_sources:
        print("  （無）")
    else:
        print_table(
            ["gold", "file:line", "snippet"],
            [
                [r["value"], f"{r['file']}:{r['line']}", r["snippet"][:50]]
                for r in sorted(lit_sources, key=lambda x: -x["value"])
            ],
        )
        print(f"  字面來源加總（每點觸發一次，非通關期望）: {sum(r['value'] for r in lit_sources)}")

    print("\n## 4. add_gold(字面量) · 消耗（負數）")
    if not lit_sinks:
        print("  （無固定字面；升階／配方多為變數）")
    else:
        print_table(
            ["gold", "file:line", "snippet"],
            [
                [r["value"], f"{r['file']}:{r['line']}", r["snippet"][:50]]
                for r in sorted(lit_sinks, key=lambda x: x["value"])
            ],
        )

    print("\n## 5. add_gold(運算式) · 動態（任務／掉落／升階）")
    if not exprs:
        print("  （無）")
    else:
        print_table(
            ["dir", "expr", "file:line"],
            [
                [r["dir"], r["expr"][:40], f"{r['file']}:{r['line']}"]
                for r in exprs
            ],
        )

    print("\n## 6. \"gold\": N 字典欄（任務／寶箱／Boss 表）")
    # 聚合同檔
    by_file: dict[str, list[int]] = defaultdict(list)
    for r in gold_kvs:
        by_file[r["file"]].append(r["value"])
    if not by_file:
        print("  （無）")
    else:
        rows = []
        for f, vals in sorted(by_file.items(), key=lambda kv: -sum(kv[1])):
            rows.append([sum(vals), len(vals), min(vals), max(vals), f])
        print_table(["sum", "n", "min", "max", "file"], rows)

    print("\n## 7. gold / gold_n 指派式（公式）")
    if not assigns:
        print("  （無）")
    else:
        print_table(
            ["expr", "file:line"],
            [[r["expr"][:48], f"{r['file']}:{r['line']}"] for r in assigns],
        )

    print("\n## 8. 設計錨點（經濟 0.15）")
    print("  · 主 sink = 升階鍛造 + 中高階 craft_recipes（職系武器／甲）")
    print("  · 雜魚：8+hp/15，勝場≥25/40 軟上限 ×0.8/×0.6")
    print("  · 狩獵：30+10×波；裂縫基準 160（練習 ×0.35）")
    print("  · 每日：刷怪委託降、鍛造委託維持高")
    print("  · 目標：通關主線「需要鍛幾次」金幣大致夠；不鍛則溢出無意義")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
