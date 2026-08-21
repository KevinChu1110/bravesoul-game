#!/usr/bin/env python3
"""
從 map_catalog 慣例產一份可在 Godot 編輯器打開的地圖場景骨架。

  python3 tools/scaffold_map_scene.py village
  python3 tools/scaffold_map_scene.py coast --art coast --size 3000x1674 --spawn 400,900

產物：game/scenes/maps/<id>.tscn
記得在 map_scene_registry.gd 的 SCENES 登錄（或靠慣例路徑自動發現）。
"""
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "game" / "scenes" / "maps"
MAPS = ROOT / "game" / "assets" / "sprites" / "maps"

# 從 map_catalog 抄的常用尺寸／出生點（骨架用；以編輯器微調為準）
PRESETS = {
    "village": ("village", (2800, 1562), (880, 1173)),
    "town": ("town", (3200, 1785), (792, 1293)),
    "mist_village": ("mist_village", (3000, 1674), (220, 850)),
    "road": ("road", (3000, 1674), (400, 900)),
    "wild": ("wild", (3000, 1674), (600, 1000)),
    "dojo": ("dojo", (2800, 1562), (500, 900)),
    "forest": ("forest", (3000, 1674), (500, 1000)),
    "coast": ("coast", (3000, 1674), (500, 1000)),
    "blackflame_scar": ("blackflame_scar", (3000, 1674), (500, 1000)),
}


def pick_bg(art: str) -> str:
    webp = MAPS / f"{art}_bg.webp"
    png = MAPS / f"{art}_bg.png"
    if webp.exists():
        return f"res://assets/sprites/maps/{art}_bg.webp"
    if png.exists():
        return f"res://assets/sprites/maps/{art}_bg.png"
    return f"res://assets/sprites/maps/{art}_bg.webp"


def write_tscn(map_id: str, art: str, size: tuple[int, int], spawn: tuple[int, int]) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bg = pick_bg(art)
    path = OUT_DIR / f"{map_id}.tscn"
    body = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/world/map_stage.gd" id="1_stage"]
[ext_resource type="Texture2D" path="{bg}" id="2_bg"]

[node name="MapStage" type="Node2D"]
script = ExtResource("1_stage")
map_id = "{map_id}"
art_id = "{art}"
world_size = Vector2({size[0]}, {size[1]})

[node name="EditorPreview" type="Sprite2D" parent="."]
modulate = Color(1, 1, 1, 0.4)
texture = ExtResource("2_bg")
centered = false

[node name="Decor" type="Node2D" parent="."]

[node name="Markers" type="Node2D" parent="."]

[node name="Spawn" type="Marker2D" parent="Markers"]
position = Vector2({spawn[0]}, {spawn[1]})
gizmo_extents = 20.0
'''
    path.write_text(body)
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("map_id")
    ap.add_argument("--art", default="")
    ap.add_argument("--size", default="", help="WxH")
    ap.add_argument("--spawn", default="", help="x,y")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    mid = args.map_id
    art, size, spawn = PRESETS.get(mid, (mid, (3000, 1674), (500, 1000)))
    if args.art:
        art = args.art
    if args.size and "x" in args.size:
        w, h = args.size.lower().split("x", 1)
        size = (int(w), int(h))
    if args.spawn and "," in args.spawn:
        x, y = args.spawn.split(",", 1)
        spawn = (int(x), int(y))

    out = OUT_DIR / f"{mid}.tscn"
    if out.exists() and not args.force:
        print(f"已存在 {out}（加 --force 覆蓋）")
        return 1
    path = write_tscn(mid, art, size, spawn)
    print(f"寫入 {path.relative_to(ROOT)}")
    print("在 Godot 開啟該場景即可預覽底圖與 Spawn 標記。")
    print("若要用慣例自動掛載，檔名保持 map_id.tscn 即可。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
