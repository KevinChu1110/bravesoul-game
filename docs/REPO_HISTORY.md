# Repo 歷史重寫紀錄

2026-08-16 用 `git filter-repo` 把 173 個生成物從**全部歷史**移除。
`.git` 從 **439 MB → 230.6 MB**（−48%）。

這份文件寫兩件事：**做了什麼**，以及**別人怎麼跟上**。

---

## 一、為什麼要重寫

`git rm --cached` 只讓**之後**的 clone 變小 —— 歷史裡的 blob 還在，
`.git` 一點都不會縮。那 173 個檔（89.77 MB 的 PNG）從初始 commit
`0789bcd` 就在版控裡，等於每個 clone 都要拉一次它們的完整歷史，
而它們對玩家一點用都沒有：出貨那份早就複製到正式目錄，
`export_presets.cfg` 也把它們排除在打包外，重跑 `tools/regen_*.py` 就能再生。

被移除的路徑（判斷依據見 [ASSETS.md](ASSETS.md)）：

```
game/assets/sprites/_gen_content
game/assets/sprites/_gen_skirmish
game/assets/sprites/maps/_gen
game/assets/sprites/maps/_gen_world
game/assets/sprites/maps/_backup_20260813
```

---

## 二、實際跑的指令

```bash
# 先備份：filter-repo 之後回不去，這份 bundle 是唯一的退路
git bundle create ../bravesoul-pre-filter-repo.bundle --all
git bundle verify ../bravesoul-pre-filter-repo.bundle

git filter-repo --force --invert-paths \
  --path game/assets/sprites/_gen_content \
  --path game/assets/sprites/_gen_skirmish \
  --path game/assets/sprites/maps/_gen \
  --path game/assets/sprites/maps/_gen_world \
  --path game/assets/sprites/maps/_backup_20260813
```

### 兩個會踩到的坑

1. **`.gdignore` 會一起被洗掉。** `--path <目錄>` 是整個路徑，
   目錄裡的 `.gdignore` 標記檔也算在內。洗完要手動補回來並重新 commit，
   否則本機一開專案 Godot 就會去 import 那三百多 MB 的中間產物。

2. **`origin` remote 會被移除。** 這是 filter-repo 刻意的保護，
   避免你手一滑把重寫過的歷史推上去。要推的話得自己加回來：

   ```bash
   git remote add origin https://github.com/KevinChu1110/bravesoul-game.git
   ```

---

## 三、推上遠端（尚未執行）

歷史重寫過，每一個 commit 的 SHA 都變了，所以**只能 force push**：

```bash
git push --force-with-lease origin main
```

推之前確認：

- [ ] 沒有其他分支或 PR 在跑（重寫時只有 `main`，無其他分支）
- [ ] 沒有別台機器有未推的 commit —— force push 會讓它們對不上
- [ ] 備份 bundle 還在（`../bravesoul-pre-filter-repo.bundle`）

## 四、其他 clone 怎麼跟上

**不要 `git pull`。** 歷史對不上，pull 會把舊的 blob 全部合併回來，
瘦身的成果當場歸零。正確做法是重新 clone：

```bash
git clone https://github.com/KevinChu1110/bravesoul-game.git
```

舊 clone 裡如果有未推的 commit，先 `git format-patch` 出來，
在新 clone 上 `git am` 回去。

## 五、退路

```bash
git clone ../bravesoul-pre-filter-repo.bundle bravesoul-restored
```

bundle 記錄了重寫前的完整歷史（`git bundle verify` 驗過）。
確定遠端也推上去、其他 clone 都換過之後，才可以刪掉它。
