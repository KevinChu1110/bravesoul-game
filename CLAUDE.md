# Brave Soul · AI 契約（對齊「AI × Godot RPG」實作心法）

> 靈感來源：[新手的第一個 AI x RPG 實作指南](https://www.youtube.com/watch?v=jHNoc3Vhex0)（臭臭虎）  
> 執行細節與測試哨兵見 [AGENTS.md](AGENTS.md)；產品北辰見 [docs/PRODUCT_BRIDGE.md](docs/PRODUCT_BRIDGE.md)。

## 你與專案的契約

1. **先問再大改**  
   涉及存檔結構、付費產圖、正式區／公開文案、刪系統、改經濟曲線 → 先用選項問清楚。

2. **跑起來才算數**  
   不要只報「編譯過」。改玩法／UI 至少跑對應 `test_*.gd` 或證明截圖流程。

3. **原作北辰，禁止做偏**  
   勇者之魂／聚魂 Online／Soul fighter 考據優先於「自己覺得酷」。  
   抽魂＝聚魂、部位破壞、能量、拜訪鑰匙、四地區、飾品六槽——名稱與精神勿另造第三套。

4. **降 AI 感**  
   - 禁止空泛勵志（「踏上命運」「傳說的開始」「你終將」之類套話）。  
   - 角色說話要短、有口吻；系統字要像工具提示，不像文案生成器。  
   - 美術風格鎖 chibi／既有 palette；不要無提示混寫實／Q 版／暗黑。

5. **Godot 優先於純碼硬編畫面**  
   新地圖／擺設能放場景或 TileMap 就別只堆 `ColorRect`。  
   程式地圖（`map_catalog.gd`）仍可維護，但新內容優先可在編輯器預覽。

6. **美術／音訊要可追溯**  
   產圖走 `$asset-gen`；付費 API 先問。  
   BGM／SFX 進 `game/assets/audio/`，地區曲用 `AudioManager.map_to_bgm`，勿每場景硬播檔名。

7. **主動釐清缺口**  
   規格含糊時問：範圍、要不要動存檔、要不要對齊原作數字。  
   不要默默發明虔誠度軟保底、西式星座戰魂、主線鎖肝抽卡。

## 建議工作流（精簡）

見 [docs/WORKFLOW_AI_RPG.md](docs/WORKFLOW_AI_RPG.md)。
