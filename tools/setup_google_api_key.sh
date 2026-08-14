#!/usr/bin/env bash
## 互動設定 GOOGLE_API_KEY 到 ~/.zshrc（不會印出完整 key、不會寫進 git）
set -euo pipefail

echo "=========================================="
echo "  設定 Google API Key（本機）"
echo "=========================================="
echo ""
echo "1) 開瀏覽器到：https://aistudio.google.com/apikey"
echo "2) 登入 Google → Create API key → 複製 key"
echo "3) 回到這裡，貼上後按 Enter（輸入時可能看不到字元，正常）"
echo ""
echo -n "請貼上你的 Google API Key: "
# -s = 不回顯，避免旁人看到
read -r KEY
echo ""

if [ -z "${KEY}" ]; then
  echo "錯誤：沒有輸入任何內容。"
  exit 1
fi

# 簡單檢查
if [ "${#KEY}" -lt 20 ]; then
  echo "錯誤：長度太短，不像 API key。請重試。"
  exit 1
fi

ZSHRC="${HOME}/.zshrc"
touch "$ZSHRC"

# 去掉舊的 GOOGLE_API_KEY 行，避免重複
if grep -q 'export GOOGLE_API_KEY=' "$ZSHRC" 2>/dev/null; then
  # macOS sed
  if sed --version >/dev/null 2>&1; then
    sed -i '/export GOOGLE_API_KEY=/d' "$ZSHRC"
  else
    sed -i '' '/export GOOGLE_API_KEY=/d' "$ZSHRC"
  fi
  echo "已移除 ~/.zshrc 裡舊的 GOOGLE_API_KEY 行。"
fi

echo "" >> "$ZSHRC"
echo "# Google AI Studio — bravesoul / godogen asset-gen ($(date +%Y-%m-%d))" >> "$ZSHRC"
echo "export GOOGLE_API_KEY=\"${KEY}\"" >> "$ZSHRC"

# 立刻在目前 shell 生效（對「執行此腳本的 shell」無效於父 shell，所以另外寫檔）
export GOOGLE_API_KEY="${KEY}"

echo ""
echo "完成！"
echo "  已寫入：${ZSHRC}"
echo "  金鑰長度：${#KEY} 字元（內容不顯示）"
echo ""
echo "接下來請你做這兩步："
echo "  1) 關掉這個終端，或執行："
echo "       source ~/.zshrc"
echo "  2) 確認（應顯示「已設定」）："
echo "       echo \${GOOGLE_API_KEY:+已設定}"
echo ""
echo "確認後在聊天跟我說：「key 設好了」即可，不要把 key 貼給我。"
