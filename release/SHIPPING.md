# 出貨檢查清單 · itch 0.6

## 一次完成（repo 內）

- [x] `game/export_presets.cfg`（Win / macOS / Linux）
- [x] `tools/export_itch.sh` 一鍵 export + zip
- [x] `dist/README.txt` 玩家說明
- [x] `release/ITCH_PAGE.md` 商店文案
- [x] Godot **export templates 4.7.1** 已安裝
- [x] 跑 `./tools/export_itch.sh` 產出 `dist/uploads/*.zip`（Win / macOS / Linux）
- [ ] 本機開 build 點「新的旅途」進村（煙測）
- [ ] 截圖 5～7 張（必含雷歐戰）
- [ ] 在 itch 建專案 → 貼文案 → 上傳 zip → 公開

### 產物（v0.6.0）

路徑：`dist/uploads/`

| 檔案 | 約略大小 |
|------|----------|
| `Cuiling-BraveSoul-0.6.0-win.zip` | ~53 MB |
| `Cuiling-BraveSoul-0.6.0-mac.zip` | ~75 MB（universal 簽章 ad-hoc） |
| `Cuiling-BraveSoul-0.6.0-linux.zip` | ~44 MB |

macOS 首次開啟：右鍵 → 打開，或系統設定允許未識別開發者。

## 本機安裝 templates（若腳本下載失敗）

1. 開啟 Godot 編輯器 → Editor → Manage Export Templates  
2. 下載 **4.7.1 stable**  
3. 或手動：

```bash
# 解壓後目錄應為：
# ~/Library/Application Support/Godot/export_templates/4.7.1.stable/
# 內含 version.txt 與 linux_release.x86_64 等
```

## 打包指令

```bash
cd /Users/kevin.chu/develop/sideprojects/bravesoul-game
chmod +x tools/export_itch.sh
./tools/export_itch.sh          # 三平台
./tools/export_itch.sh mac      # 只打 Mac（本機先測）
```

產物：

```
dist/uploads/Cuiling-BraveSoul-0.6.0-win.zip
dist/uploads/Cuiling-BraveSoul-0.6.0-mac.zip
dist/uploads/Cuiling-BraveSoul-0.6.0-linux.zip
```

## itch 上傳

1. https://itch.io/game/new  
2. 標題：**翠嶺·兔勇者**  
3. 描述：貼 `release/ITCH_PAGE.md`  
4. Uploads：三個 zip，勾對應 OS  
5. 定價：PWYW 或 Free  
6. Visibility: Restricted（給朋友）→ 再 Public  

## 可選：butler CLI

```bash
# brew install butler 或 https://itch.io/docs/butler/
butler push dist/uploads/Cuiling-BraveSoul-0.6.0-win.zip you/cuiling-bravesoul:windows --userversion 0.6.0
butler push dist/uploads/Cuiling-BraveSoul-0.6.0-mac.zip you/cuiling-bravesoul:osx --userversion 0.6.0
butler push dist/uploads/Cuiling-BraveSoul-0.6.0-linux.zip you/cuiling-bravesoul:linux --userversion 0.6.0
```

（`you/cuiling-bravesoul` 改成你的 itch 帳號／專案名）

## 煙測最少步驟

1. 標題 → 新的旅途 → 村內能走  
2. 狼戰能打完  
3. Esc 暫停 → 存檔 → 回標題 → 繼續  
4. （可選）進 C1 廣場、開技能／戰魂面板  
