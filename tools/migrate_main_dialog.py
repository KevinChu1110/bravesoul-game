#!/usr/bin/env python3
"""把 main.gd 裡寫死的台詞搬進 data/dialogues/*.json，並產生新舊對拍的黃金樣本。

為什麼要有這支：台詞遷移最怕的不是「漏字」，是「掛錯位置」——
A 分支的台詞被綁到 B 分支的 key，文字集合照樣一條不差。
所以這支不是「改完就丟」的一次性腳本，而是**黃金樣本的產生器**：
它從遷移前的 main.gd（git 版本）機械取出每個呼叫點的實際輸出，
按呼叫順序編號存成 test_main_dialog_golden.json；
測試再拿遷移後的 main.gd + JSON 資料，逐一比對同一個順位是否吐出同樣的東西。
兩邊的資料來源完全獨立，所以「key 對調」這種錯會被抓出來。

用法（遷移已完成，平常不需要再跑）：
    python3 tools/migrate_main_dialog.py --old <遷移前的 main.gd> --apply
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, "game", "scripts", "main.gd")
DATA_DIR = os.path.join(ROOT, "game", "data", "dialogues")
GOLDEN = os.path.join(ROOT, "game", "scripts", "systems", "test_main_dialog_golden.json")

# ── 遷移名冊 ────────────────────────────────────────────────────────────────
# key 是 (遷移前 main.gd 的行號) → (資料檔, 台詞 key, 插值槽名稱依序)
# 插值槽名稱要對應該呼叫點裡「所有非字面值的 text」由上而下、由左而右的順序。
PLAN: dict[int, tuple[str, str, list[str]]] = {
    638: ("hub", "hub.event_no_reward_runs", []),
    644: ("hub", "hub.event_challenge_start", ["event"]),
    741: ("hub", "hub.candle_need_online", []),
    744: ("hub", "hub.candle_already_lit", []),
    751: ("hub", "hub.candle_lit", ["total"]),
    828: ("hub", "hub.hunt_abandoned", []),
    1131: ("hub", "hub.online_health_ok", ["msg"]),
    1133: ("hub", "hub.online_health_fail", ["msg"]),
    1452: ("hub", "shop.not_enough_gold", []),
    1458: ("hub", "shop.bought", ["item", "price"]),
    2262: ("hub", "hub.ng_plus_not_yet", []),

    2428: ("side", "side.guard_dog", []),
    2437: ("side", "side.training_need_weapon", []),
    2441: ("side", "side.training_daily_cap", []),
    2484: ("side", "side.training_result", ["msg", "power"]),
    2513: ("side", "side.weapon_rack_untasked", []),
    2517: ("side", "side.broken_blade_gone", []),
    2531: ("side", "side.amber_has_letter", []),
    2536: ("side", "side.amber_shop_open", []),
    2546: ("side", "side.ronin_guard_fire", []),
    2553: ("side", "side.ronin_gone", []),
    2557: ("side", "side.ronin_too_early", []),
    2636: ("side", "side.ronin_defeated", ["xp", "level_up"]),
    2695: ("side", "side.ding_debt_remind", []),

    2807: ("world", "world.inspect_object", ["label"]),
    2820: ("world", "world.miniboss_cleared", []),
    2833: ("world", "world.chest_empty", []),
    2856: ("world", "world.chest_open", ["found", "gold", "dust", "drop"]),
    2869: ("world", "world.skirmish_cleared", []),
    2944: ("world", "world.warehouse_keep", []),
    4484: ("world", "region.mist_locked", []),
    4489: ("world", "region.dojo_warn", ["power"]),
    4494: ("world", "region.forest_warn", ["power"]),
    4499: ("world", "region.coast_warn", ["power"]),

    3384: ("battle", "battle.wolf_win", []),
    3391: ("battle", "battle.wolf_lose", []),
    3398: ("battle", "battle.leo_lose", []),
    3406: ("battle", "battle.fog_lose", []),
    3414: ("battle", "battle.demon_lose", []),
    3422: ("battle", "battle.abo_lose", []),
    3430: ("battle", "battle.falcon_lose", []),
    3438: ("battle", "battle.boar_lose", []),
    3463: ("battle", "battle.rift_lose", ["tip"]),
    3555: ("battle", "battle.world_win", ["enemy", "gold", "extra"]),
    3561: ("battle", "battle.world_flee", []),

    3854: ("craft", "skill.learned", ["skill"]),
    3859: ("craft", "skill.not_yet", []),
    3865: ("craft", "skill.tutor_deny", []),
    3885: ("craft", "soul.equipped", []),
    3890: ("craft", "soul.ritual_not_enough", []),
    3940: ("craft", "soul.fused", ["soul"]),
    3945: ("craft", "soul.fuse_requirement", []),
    4026: ("craft", "forge.need_rusty_first", []),
    4094: ("craft", "forge.path_chosen", ["path", "play", "pro", "power"]),
    4108: ("craft", "forge.wood_sword_no_gold", []),
    4111: ("craft", "forge.wood_sword_owned", []),
    4127: ("craft", "forge.tier_max", []),
    4130: ("craft", "forge.no_gold", []),
    4151: ("craft", "forge.success", ["tier", "scrap"]),
    4157: ("craft", "forge.pity_break", []),
    4162: ("craft", "forge.failed", []),

    3113: ("chapter", "c6.refugee", []),
    3115: ("chapter", "c6.scroll_pile", []),
    3117: ("chapter", "c6.tower_gate", []),
    3230: ("chapter", "c0.shrine_stub", []),
    3232: ("chapter", "c0.field_west", []),
    3248: ("chapter", "c0.leave_without_sword", []),
    3311: ("chapter", "c0.road_east", []),
    3641: ("chapter", "c1.flag_paw", []),
    3643: ("chapter", "c1.flag_grey", []),
    3664: ("chapter", "c1.outer_ward", []),
    3672: ("chapter", "c1.save_stone", ["extra"]),
    3761: ("chapter", "c1.sprout_after_leo", []),
    3766: ("chapter", "c1.sprout_thanks", []),
    3805: ("chapter", "c1.sprout_wish", []),
    4168: ("chapter", "c1.wild_need_forge", []),
    4180: ("chapter", "c1.burnt_field", []),
    4189: ("chapter", "c1.tower_empty", []),
    4199: ("chapter", "c1.wild_shrine", []),
    4205: ("chapter", "c1.crate_empty", []),
    4219: ("chapter", "c1.leo_gate_cleared", []),
    4232: ("chapter", "c1.leo_win", []),
    4325: ("chapter", "c2.arrive", []),
    4347: ("chapter", "c2.lantern", []),
    4349: ("chapter", "c2.well_fog", []),
    4351: ("chapter", "c2.laundry", []),
    4353: ("chapter", "c2.cat_shadow", []),
    4358: ("chapter", "c2.shrine", []),
    4364: ("chapter", "c2.train_need_letter", []),
    4366: ("chapter", "c2.train_tip", []),
    4384: ("chapter", "c2.letter_reread", []),
    4411: ("chapter", "c2.fog_need_letter", []),
    4414: ("chapter", "c2.fog_cleared", []),
    4424: ("chapter", "c2.fog_win", []),
    4510: ("chapter", "c3.soft_warn", ["power"]),
    4540: ("chapter", "c3.arrive", []),
    4559: ("chapter", "c3.gate_bell", []),
    4562: ("chapter", "c3.dummy_done", []),
    4573: ("chapter", "c3.scroll_wall", []),
    4578: ("chapter", "c3.stone_garden", []),
    4602: ("chapter", "c3.abo_cleared", []),
    4693: ("chapter", "c4.arrive", []),
    4712: ("chapter", "c4.treehouse", []),
    4718: ("chapter", "c4.kite_freed", []),
    4730: ("chapter", "c4.stream", []),
    4732: ("chapter", "c4.owl_post", []),
    4738: ("chapter", "c4.arrow_path_done", []),
    4748: ("chapter", "c4.watch_tower", []),
    4755: ("chapter", "c4.herb_looted", []),
    4778: ("chapter", "c4.falcon_cleared", []),
    4789: ("chapter", "c4.falcon_win", []),
    4860: ("chapter", "c5.arrive", []),
    4879: ("chapter", "c5.dock", []),
    4884: ("chapter", "c5.boat_wreck", []),
    4886: ("chapter", "c5.net_rack", []),
    4888: ("chapter", "c5.runestone", []),
    4894: ("chapter", "c5.forge_tip_done", []),
    4906: ("chapter", "c5.cliff_path", []),
    4927: ("chapter", "c5.boar_cleared", []),
    4938: ("chapter", "c5.boar_win", []),
    5000: ("chapter", "c6.bell_not_rung", []),
    5002: ("chapter", "c6.path_not_open", []),
    5063: ("chapter", "c6.floor_shadow", []),
    5118: ("chapter", "c6.demon_win", []),
    5206: ("chapter", "post.rift_not_open", []),
    5331: ("chapter", "post.rift_win", ["mode", "wins", "extra"]),
}


# ── GDScript 片段的極簡剖析 ────────────────────────────────────────────────
STR_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"$', re.S)
# GDScript 的 % 格式規格；只認我們實際用到的幾種，遇到別的就讓它報錯
SPEC_RE = re.compile(r"%[-+ #0]*[0-9]*(?:\.[0-9]+)?[sd]")


def unescape(s: str) -> str:
    """GDScript 字面值 → 實際字串（只處理台詞裡真的會出現的跳脫）"""
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def split_top(text: str) -> list[str]:
    """依最外層逗號切開（字串與括號內的逗號不算）"""
    parts, depth, cur, instr, esc = [], 0, [], False, False
    for ch in text:
        if instr:
            cur.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                instr = False
            continue
        if ch == '"':
            instr = True
            cur.append(ch)
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return [p.strip() for p in parts]


def find_call(lines: list[str], start_idx: int) -> tuple[int, int, int, int]:
    """從 start_idx 這行的 _play_dialog 開始括號配對，回傳 (行,列,行,列) 含頭含尾"""
    col = lines[start_idx].index("_play_dialog(") + len("_play_dialog")
    depth, instr, esc = 0, False, False
    r, c = start_idx, col
    while r < len(lines):
        s = lines[r]
        c = col if r == start_idx else 0
        while c < len(s):
            ch = s[c]
            if instr:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    instr = False
            elif ch == '"':
                instr = True
            elif ch == "#":
                break
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth == 0:
                    return (start_idx, col, r, c)
            c += 1
        r += 1
    raise SystemExit("括號沒有收尾：line %d" % (start_idx + 1))


def parse_dict_literal(src: str) -> list[tuple[str, str]]:
    """{ "k": v, ... } → [(k, v 原始碼), ...]；順序保留"""
    src = src.strip()
    assert src.startswith("{") and src.endswith("}"), src[:60]
    out = []
    for item in split_top(src[1:-1]):
        instr, esc, pos = False, False, -1
        for i, ch in enumerate(item):
            if instr:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    instr = False
            else:
                if ch == '"':
                    instr = True
                elif ch == ":":
                    pos = i
                    break
        assert pos > 0, item
        k = STR_RE.match(item[:pos].strip())
        assert k, item
        out.append((k.group(1), item[pos + 1:].strip()))
    return out


def sample_for(spec: str, seq: int) -> str:
    """給插值槽一個**互不相同**的樣本值，順序掉換才抓得出來。

    一律用字串：黃金樣本走 JSON，數字型別在 Godot 這頭可能被讀成 float，
    「7」變成「7.0」會製造假失敗。反正真正要驗的是插槽有沒有對上位置。
    """
    return str(7 + seq * 11) if spec.endswith("d") else "«v%d»" % seq


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", help="遷移前的 main.gd（預設抓 git HEAD 版本）")
    ap.add_argument("--apply", action="store_true", help="真的改寫 main.gd 與寫出資料檔")
    args = ap.parse_args()

    if args.old:
        old_src = open(args.old, encoding="utf-8").read()
    else:
        old_src = subprocess.run(
            ["git", "-C", ROOT, "show", "HEAD:game/scripts/main.gd"],
            capture_output=True, text=True, check=True).stdout

    lines = old_src.split("\n")

    buckets: dict[str, dict] = {}
    golden: list[dict] = []
    edits: list[tuple[int, int, int, int, str]] = []
    seen_keys: set[str] = set()

    for i, ln in enumerate(lines):
        if "_play_dialog(" not in ln or ln.lstrip().startswith("func "):
            continue
        lineno = i + 1
        if lineno not in PLAN:
            continue
        bucket, key, names = PLAN[lineno]
        if key in seen_keys:
            raise SystemExit("key 重複：%s（line %d）" % (key, lineno))
        seen_keys.add(key)

        r0, c0, r1, c1 = find_call(lines, i)
        raw = lines[r0][c0:] if r0 == r1 else None
        if raw is None:
            raw = "\n".join([lines[r0][c0:]] + lines[r0 + 1:r1] + [lines[r1][:c1 + 1]])
        else:
            raw = lines[r0][c0:c1 + 1]
        args_src = split_top(raw[1:-1])
        arr_src = args_src[0]
        cb_src = args_src[1] if len(args_src) > 1 else None
        assert arr_src.startswith("[") and arr_src.endswith("]"), (lineno, arr_src[:60])

        entries, sample_vars, call_vars = [], {}, []
        slot = 0
        for elem in split_top(arr_src[1:-1]):
            item: dict[str, object] = {}
            for k, v in parse_dict_literal(elem):
                m = STR_RE.match(v)
                if m:
                    item[k] = unescape(m.group(1))
                    continue
                if k != "text":
                    raise SystemExit("line %d：非字面值只支援 text，出現 %s" % (lineno, k))
                # 兩種形式：`"字面值 %s" % 參數` 或整段都是執行期算出來的表達式
                fmt = None
                if v.startswith('"'):
                    q, esc2 = 1, False
                    while q < len(v):
                        if esc2:
                            esc2 = False
                        elif v[q] == "\\":
                            esc2 = True
                        elif v[q] == '"':
                            break
                        q += 1
                    rest = v[q + 1:].lstrip()
                    if rest.startswith("%"):
                        fmt = unescape(v[1:q])
                        argsrc = rest[1:].strip()
                if fmt is None:
                    name = names[slot]
                    slot += 1
                    item[k] = "{%s}" % name
                    call_vars.append((name, v))
                    sample_vars[name] = sample_for("%s", len(sample_vars))
                    continue
                specs = [m.group(0) for m in SPEC_RE.finditer(fmt)]
                if argsrc.startswith("[") and argsrc.endswith("]"):
                    exprs = split_top(argsrc[1:-1])
                else:
                    exprs = [argsrc]
                if len(specs) != len(exprs):
                    raise SystemExit("line %d：格式規格 %d 個但參數 %d 個" % (lineno, len(specs), len(exprs)))
                text, cursor, out = fmt, 0, []
                for spec, expr in zip(specs, exprs):
                    name = names[slot]
                    slot += 1
                    call_vars.append((name, expr))
                    sample_vars[name] = sample_for(spec, len(sample_vars))
                    out.append((spec, name))
                for spec, name in out:
                    text = text.replace(spec, "{%s}" % name, 1)
                item[k] = text
            if "{" in str(item.get("speaker", "")):
                raise SystemExit("line %d：speaker 不支援插值" % lineno)
            entries.append(item)
        if slot != len(names):
            raise SystemExit("line %d：名冊給了 %d 個槽，實際用掉 %d 個" % (lineno, len(names), slot))

        buckets.setdefault(bucket, {})[key] = entries

        # 黃金樣本：用**遷移前**的字面值直接算出期望輸出
        expect = []
        for item in entries:
            e = dict(item)
            t = e.get("text", "")
            for name, val in sample_vars.items():
                t = t.replace("{%s}" % name, str(val))
            e["text"] = t
            expect.append(e)
        golden.append({"key": key, "src_line": lineno, "vars": sample_vars, "expect": expect})

        # 產生新的呼叫碼
        indent = re.match(r"[\t ]*", lines[r0]).group(0)
        if call_vars:
            pairs = ", ".join('"%s": %s' % (n, e) for n, e in call_vars)
            call = 'DialogLines.lines("%s", {%s})' % (key, pairs)
        else:
            call = 'DialogLines.lines("%s")' % key
        tail = ")" if cb_src is None else ", %s)" % cb_src
        # 多行 lambda 的收尾括號跟原本一樣另起一行，才不會黏在 lambda 最後一句後面
        if cb_src is not None and "\n" in cb_src:
            tail = ", %s\n%s)" % (cb_src, indent)
        if call_vars and len(indent) + len("_play_dialog(") + len(call) > 110:
            body = "".join('\n%s\t"%s": %s,' % (indent, n, e) for n, e in call_vars)
            call = 'DialogLines.lines("%s", {%s\n%s})' % (key, body, indent)
        edits.append((r0, c0, r1, c1, "(%s%s" % (call, tail)))

    missing = set(PLAN) - {g["src_line"] for g in golden}
    if missing:
        raise SystemExit("名冊有 %d 個行號沒對到呼叫點：%s" % (len(missing), sorted(missing)))

    print("搬 %d 個呼叫點 · %d 個資料檔" % (len(golden), len(buckets)))
    if not args.apply:
        return 0

    # 由後往前改寫，行號才不會位移
    out_lines = list(lines)
    for r0, c0, r1, c1, text in sorted(edits, reverse=True):
        head = out_lines[r0][:c0]
        tail = out_lines[r1][c1 + 1:]
        out_lines[r0:r1 + 1] = (head + text + tail).split("\n")
    open(MAIN, "w", encoding="utf-8").write("\n".join(out_lines))

    os.makedirs(DATA_DIR, exist_ok=True)
    for name, data in buckets.items():
        with open(os.path.join(DATA_DIR, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    with open(GOLDEN, "w", encoding="utf-8") as f:
        json.dump(golden, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("已寫入 main.gd、data/dialogues/*.json 與黃金樣本")
    return 0


if __name__ == "__main__":
    sys.exit(main())
