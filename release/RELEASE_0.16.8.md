# 勇者之魂 0.16.8

## 這包重點

- **探索空間感**：41 張 scenic 地圖補齊站立帶、加深遠近、FG／MG 前後景遮擋
- **穿模熱點**：村／堡／霧隱／市集／客棧／道場／塔… walkmask block 全面補上
- **可走區**：出生點與實體仍全綠（`check_walkmask` 通過）

## 下載檔

`dist/uploads/`

- `BraveSoul-0.16.8-win.zip`
- `BraveSoul-0.16.8-mac.zip`
- `BraveSoul-0.16.8-linux.zip`

## 相對 0.15.0 的大方向

（0.15→0.16 區間累積）技能雙武器／多段 FX、防具紙娃娃、Boss 簽名姿、Shorts／故事素材，以及本版地圖空間修復。

## 已知限制

- 部分 MG 切片為批次估算，單一地圖若遮擋過寬／過窄可再微調
- macOS 仍為 ad-hoc 簽名：首次請右鍵 → 打開
- itch 上傳需本機手動（或之後裝 butler）

## 本機跑

```bash
cd game && godot .
```
