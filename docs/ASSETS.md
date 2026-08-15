# 資產管理

`game/assets/` 有 426 MB，其中 406 MB 是貼圖。這份文件講兩件事：
**什麼該進版控**，以及**貼圖怎麼壓**。

量測日期 2026-08-16，v0.14.9。數字用 `python3 tools/compress_sprites.py` 可重新產生。

---

## 一、什麼該追蹤、什麼不該

### 出貨資產（追蹤）

`game/assets/sprites/` 底下這幾個目錄是遊戲實際載入的貼圖，**全部要進 git**：

| 目錄 | PNG 數 | 源 PNG |
|---|---:|---:|
| `maps/` | 63 | 71.80 MB |
| `portraits/` | 25 | 4.77 MB |
| `bosses/` | 93 | 4.74 MB |
| `props/` | 30 | 1.15 MB |
| `equipment/` | 18 | 0.71 MB |
| `npcs/` | 15 | 0.57 MB |
| `player/` | 32 | 0.56 MB |
| `tiles/` | 24 | 0.06 MB |
| `fx/` | 8 | 0.01 MB |
| **合計** | **308** | **84.37 MB** |

**每張 PNG 旁邊的 `.png.import` 也要一起進 git。** 那個檔案裡有 `uid://`，
GDScript 與場景是靠 uid 認貼圖的；沒進版控的話 CI 每次會重新生一組不同的 uid，
既拖慢 import 也讓匯入結果不可重現。

### 生成中間產物（不追蹤）

`tools/` 底下那些產圖腳本（`gen_*.py`、`regen_*.py`）的原始輸出與換版前的備份，
命名一律是 `_gen*` / `_backup*`：

```
game/assets/sprites/_gen_chibi_0148/    _gen_content/     _gen_hd_v0145/
                    _gen_hero/          _gen_skirmish/    _gen_style_lock/
                    _gen_v014/
game/assets/sprites/maps/_gen/          maps/_gen_world/
                    maps/_backup_20260813/  maps/_backup_chibi_0148/
                    maps/_backup_v014/
game/assets/sprites/player/_backup_hero/
```

這些**不進版控**，理由是：

1. 出貨要用的那份已經被複製到正式目錄了。
   `_gen_content/banner_crossroads.png` → `maps/crossroads_banner.png`、
   `_gen_skirmish/ash_rat.png` → `bosses/ash_rat.png`，只是改了名字。
2. `game/export_presets.cfg` 的 `exclude_filter` 早就把它們排除在打包外，
   留在 repo 裡對玩家一點用都沒有。
3. 重跑對應的 `tools/regen_*.py` 就能再生。

### 命名規則寫在三個地方

`_gen*` / `_backup*` 這套前綴，同時被三個檔案讀：

- `.gitignore` —— 不進版控
- `game/export_presets.cfg` 的 `exclude_filter` —— 不進安裝包
- `tools/compress_sprites.py` 的 `SKIP_PREFIXES` —— 壓縮工具不碰

**新增目錄命名時三邊要一致**，否則會出現「壓縮工具去壓一批不會出貨的圖」
或「中間產物被打進安裝包」。

### `.gdignore`

每個生成目錄裡放一個空的 `.gdignore`，Godot 看到就整個目錄跳過不 import。
沒有它的話，本機開專案要多 import 三百多 MB 的中間產物。

`.gdignore` 本身要進版控。`.gitignore` 裡的排除寫成 `目錄/**` 而不是 `目錄/`
就是為了這個 —— git 沒辦法把「已被排除的目錄」底下的檔案再放行，
只排除內容才留得住 `!**/.gdignore` 這條例外。

### ⚠ 目前還有 89.77 MB 的生成物是被追蹤的

`.gitignore` 對**已經追蹤**的檔案沒有效果。以下 173 個檔案是在規則加上去之前
就進了版控，要手動退出來：

| 目錄 | 檔數 | 大小 |
|---|---:|---:|
| `maps/_gen_world` | 93 | 46.06 MB |
| `_gen_content` | 28 | 17.18 MB |
| `maps/_gen` | 18 | 14.80 MB |
| `maps/_backup_20260813` | 18 | 6.48 MB |
| `_gen_skirmish` | 16 | 5.25 MB |
| **合計** | **173** | **89.77 MB** |

```bash
git rm -r --cached game/assets/sprites/_gen_content \
                   game/assets/sprites/_gen_skirmish \
                   game/assets/sprites/maps/_gen \
                   game/assets/sprites/maps/_gen_world \
                   game/assets/sprites/maps/_backup_20260813
```

`--cached` 只從索引移除，磁碟上的檔案留著。做完之後
`game/assets` 的追蹤量從 194.1 MB 降到 104.3 MB（−46%），CI 的 clone 與
import 都少掉將近一半。

注意這只讓**之後**的 clone 變小；歷史裡的 blob 還在，`.git` 不會縮。
真要縮就得 `git filter-repo` 重寫歷史，那是另一件事，要挑沒有其他分支在跑的時機做。

### 另外有 61 個 `.import` 該補進版控

這些 PNG 已經追蹤了，但它們的 `.import` 沒有 —— 主要在 `equipment/`、`props/`、
`player/weapons/`。補進去：

```bash
git add game/assets/sprites/**/*.png.import
```

---

## 二、貼圖壓縮

工具是 `tools/compress_sprites.py`。**預設只量不改**，直接跑就是一份現況報告：

```bash
python3 tools/compress_sprites.py
```

它分兩個槓桿，省的是完全不同的東西：

### 槓桿 A：源 PNG 無損重壓（`--lossless`）

省 **repo 與 CI**，不影響玩家下載的包。

主要收益不是重新壓縮，而是**丟掉沒用的 alpha 通道**：308 張出貨貼圖裡有 88 張
是 RGBA、但整張 alpha 全 255，等於白白多背一個通道。轉成 RGB 對可見像素是
bit 級相同，不是有損。

實測 84.37 MB → 77.23 MB，**省 7.14 MB（8.5%）**。

**目前刻意沒套用。** 重寫 247 個 PNG 會在 git 歷史裡多出約 77 MB 的新 blob，
只為了讓 checkout 少 7 MB —— 對 repo 總大小是淨虧。
這件事值得做，但要跟上面那個 `filter-repo` 重寫歷史併成同一次做。

### 槓桿 B：Godot 匯入壓縮模式（`--import-mode`）—— 已套用

省 **玩家下載的包**，不動源檔，也不用改任何一行 GDScript。

Godot 的 `compress/mode=0`（無損）會把貼圖以 WebP 無損塞進 `.ctex`；
`mode=1`（有損）改用 WebP 有損。改的是 `.import` 檔，源 PNG 原封不動。

分級規則（寫在 `tools/compress_sprites.py` 最上面的常數）：

- **長邊 ≥ 512 才走有損**，quality 0.9。這個門檻剛好把 `maps/` 的 63 張
  背景與橫幅全部收進來，其餘 245 張小圖全部排除。
- **`tiles/`、`fx/`、`player/` 一律無損**，就算夠大也不開。這幾類是像素風、
  又走 nearest 過濾（`project.godot` 的 `default_texture_filter=0`），
  有損 WebP 會在硬邊 alpha 周圍糊掉一圈，比省下的體積更礙眼。

實測封裝後的貼圖量：

| | 大小 |
|---|---:|
| 現況（全部無損） | 57.09 MB |
| 分級後 | 17.59 MB |
| **省** | **39.50 MB（69.2%）** |

上表是用 WebP 直接量的推估值。實際拿 Godot 4.7 跑過一次對照
（獨立的空專案，避免動到 `game/.godot` 的快取）：`village_bg.png`
匯出的 `.ctex` 從 1,263,162 bytes 掉到 303,942 bytes，**−75.9%**，
跟推估一致。

品質實測（PSNR，對照原圖）：背景 40.4–41.7 dB，橫幅 34.4–39.3 dB。
40 dB 以上肉眼分不出差別。quality 再往下調到 0.85 只多省 2 MB，
但橫幅那種大面積漸層開始出現帶狀色階，不划算。

反悔的話一行就回去：

```bash
python3 tools/compress_sprites.py --import-mode --quality 0 --apply
```

### 為什麼不整批改成 `.webp` 檔

貼圖路徑是在 GDScript 裡用 `"%s.png"` 組出來的（見
`game/scripts/art/sprite_db.gd`、`explore_view.gd`），換副檔名要動程式。
槓桿 B 拿到同樣的包體收益，而且零程式碼風險。

### 工具的性質

兩個槓桿都是**冪等**的 —— 源 PNG 壓不動就跳過，`.import` 已經是目標設定就跳過。
排進 CI 或 pre-commit 都不會一直產生 diff。不加 `--apply` 永遠只是 dry-run。

---

## 三、加新貼圖時的檢查清單

1. 產圖腳本的原始輸出丟在 `_gen*` 目錄 —— 不會進 git，也不會被 Godot import。
2. 出貨那份複製到 `sprites/` 下的正式目錄，改成程式在用的檔名。
3. 在 Godot 開一次專案讓它產生 `.import`。
4. `git add` 時 **PNG 和 `.import` 要成對**。
5. 跑 `python3 tools/compress_sprites.py --import-mode --apply`，
   讓新的大圖也套上分級壓縮。
6. `git add -A game/assets` 現在是安全的 —— 加上排除規則後，未追蹤檔從
   832 個掉到 74 個（61 個該補的 `.import` ＋ 13 個 `.gdignore`），
   生成的 PNG 一張都進不來。規則改動之後可以用
   `git add -An game/assets` 再驗一次。
