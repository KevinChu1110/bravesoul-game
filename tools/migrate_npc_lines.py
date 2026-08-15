#!/usr/bin/env python3
"""把 npc_lines.gd 的硬編碼台詞轉成 data/npc_lines/*.json。

一次性遷移腳本，保留下來當作「當初怎麼搬的」的證據。

刻意用機器轉而不是手抄：61 條中文台詞手抄出錯很難用肉眼發現，
腳本最後會做 round-trip 驗證（從 JSON 抽回來的文字集合必須跟 .gd 完全一致）。

用法：
    python3 tools/migrate_npc_lines.py            # 轉換並驗證
    python3 tools/migrate_npc_lines.py --check    # 只驗證，不寫檔
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "game" / "scripts" / "systems" / "npc_lines.gd"
OUT_DIR = ROOT / "game" / "data" / "npc_lines"

LINE_RE = re.compile(r'\{"speaker": "([^"]*)", "text": "([^"]*)"\}')
FUNC_RE = re.compile(r"^static func (\w+)\(\) -> Array:$")
IF_RE = re.compile(r"^\tif (.+):$")
# `return [` 開一段台詞；`return []` 是空台詞的預設規則。
# 後者可能帶行尾註解（例如 `return []  ## 走主線對話`），別漏掉。
RETURN_OPEN_RE = re.compile(r"^\t+return \[$")
RETURN_EMPTY_RE = re.compile(r"^\t+return \[\]\s*(##.*)?$")


def parse_condition(expr: str) -> dict:
    """把 `GameState.has_flag("a") and GameState.ng_plus > 0` 轉成 when 物件。

    實際資料只用到兩種原子條件與 and，沒有 or / not / 其他比較。
    遇到不認得的形式就直接爆掉，不要猜 —— 猜錯會靜靜地產出錯的內容。
    """
    when: dict = {}
    for part in expr.split(" and "):
        part = part.strip()
        m = re.fullmatch(r'GameState\.has_flag\("([^"]+)"\)', part)
        if m:
            when.setdefault("flags", []).append(m.group(1))
            continue
        if part == "GameState.ng_plus > 0":
            when["ng_plus_min"] = 1
            continue
        raise SystemExit(f"看不懂的條件式：{part!r}（schema 需要擴充，不要硬猜）")
    return when


def parse_source(text: str) -> dict:
    """回傳 {npc_id: {speaker, rules}}。"""
    npcs: dict = {}
    cur_id = None
    cur_rules: list = []
    pending_when: dict | None = None
    buf: list | None = None

    for raw in text.splitlines():
        m = FUNC_RE.match(raw)
        if m:
            if cur_id:
                npcs[cur_id] = cur_rules
            cur_id = m.group(1)
            cur_rules = []
            pending_when = None
            buf = None
            continue
        if cur_id is None:
            continue

        m = IF_RE.match(raw)
        if m:
            pending_when = parse_condition(m.group(1))
            continue

        if RETURN_EMPTY_RE.match(raw):
            cur_rules.append({"when": pending_when or {}, "lines": []})
            pending_when = None
            buf = None
            continue

        if RETURN_OPEN_RE.match(raw):
            buf = []
            continue

        m = LINE_RE.search(raw)
        if m and buf is not None:
            buf.append((m.group(1), m.group(2)))
            continue

        if raw.strip() == "]" and buf is not None:
            cur_rules.append({"when": pending_when or {}, "_pairs": buf})
            pending_when = None
            buf = None

    if cur_id:
        npcs[cur_id] = cur_rules
    return npcs


def build(npc_id: str, rules: list) -> dict:
    speakers = {sp for r in rules for sp, _ in r.get("_pairs", [])}
    if len(speakers) > 1:
        raise SystemExit(f"{npc_id} 有多個說話者 {speakers}，schema 假設每個 NPC 只有一個")
    speaker = speakers.pop() if speakers else ""

    out_rules = []
    for r in rules:
        out_rules.append({
            "when": r["when"],
            "lines": [t for _, t in r.get("_pairs", [])],
        })
    return {"id": npc_id, "speaker": speaker, "rules": out_rules}


def main() -> None:
    check_only = "--check" in sys.argv
    src = SRC.read_text(encoding="utf-8")
    parsed = parse_source(src)

    if len(parsed) != 10:
        raise SystemExit(f"預期 10 個 NPC，實際解析到 {len(parsed)}：{list(parsed)}")

    docs = {nid: build(nid, rules) for nid, rules in parsed.items()}

    # round-trip：JSON 裡的文字集合必須跟原始碼完全一致，一條都不能掉
    src_texts = sorted(t for _, t in LINE_RE.findall(src))
    json_texts = sorted(
        line for d in docs.values() for r in d["rules"] for line in r["lines"]
    )
    if src_texts != json_texts:
        only_src = set(src_texts) - set(json_texts)
        only_json = set(json_texts) - set(src_texts)
        raise SystemExit(
            f"round-trip 不一致！\n  只在 .gd：{only_src}\n  只在 JSON：{only_json}"
        )
    print(f"round-trip OK：{len(src_texts)} 條台詞完全一致")

    for nid, doc in sorted(docs.items()):
        n_rules = len(doc["rules"])
        n_lines = sum(len(r["lines"]) for r in doc["rules"])
        print(f"  {nid:20s} speaker={doc['speaker']:6s} rules={n_rules} lines={n_lines}")

    if check_only:
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for nid, doc in docs.items():
        path = OUT_DIR / f"{nid}.json"
        path.write_text(
            json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(f"已寫出 {len(docs)} 個檔到 {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
