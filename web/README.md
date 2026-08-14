# 官網 · GitHub Pages

靜態站原始檔在此目錄。推上 GitHub 並啟用 Pages 後即可公開。

## 網址會長怎樣

| 類型 | 範例 |
|------|------|
| 專案頁（常見） | `https://你的帳號.github.io/bravesoul-game/` |
| 使用者頁 | `https://你的帳號.github.io/`（需把 `web/` 當另一 repo 根目錄） |

本 repo 預設走 **專案頁 + Actions 部署 `web/`**。

## 一次設定（約 5 分鐘）

### 1. 建立遠端並推送

若本機尚未建 repo：

```bash
cd /Users/kevin.chu/develop/sideprojects/bravesoul-game
git init
git add .
git commit -m "Initial: 翠嶺·兔勇者 + GitHub Pages"
# 在 GitHub 新建空 repo（例如 bravesoul-game），再：
git branch -M main
git remote add origin git@github.com:你的帳號/bravesoul-game.git
git push -u origin main
```

### 2. 開啟 GitHub Pages

1. GitHub 開該 repo → **Settings → Pages**
2. **Build and deployment → Source** 選 **GitHub Actions**
3. 推送或到 **Actions** 手動跑 workflow：**Deploy GitHub Pages**

Workflow 檔：`.github/workflows/github-pages.yml`  
觸發：`main`/`master` 上 `web/**` 變更，或 `workflow_dispatch`。

### 3. 等綠色勾

Actions 成功後，Pages 網址會出現在 Settings → Pages，或 environment `github-pages`。

## 本機預覽

```bash
cd web
python3 -m http.server 8080
# 瀏覽器開 http://127.0.0.1:8080/
```

## 自訂

| 檔案 | 用途 |
|------|------|
| `index.html` | 首頁（itch／GitHub 連結可改） |
| `404.html` | 迷路頁，會跳回首頁 |
| `.nojekyll` | 告訴 Pages 不要用 Jekyll 處理 |

### 綁自己的網域（可選）

1. 在 `web/` 加 `CNAME` 檔，內容一行：`cuiling.example.com`
2. DNS 設 CNAME 指到 `你的帳號.github.io`
3. Settings → Pages 勾選 custom domain + HTTPS

## 注意

- 不要把 Supabase **service_role** 寫進官網  
- publishable／anon key 只給**遊戲客戶端**，不必放官網  
- itch 下載連結：有專案後改 `index.html` 裡的 itch URL  
