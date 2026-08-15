# MEDIA · 外部配樂與過場素材匯入

把外部生成的音樂／影片（Google Flow、Veo，或任何來源）變成遊戲能用的資產。

兩支工具：

| 工具 | 做什麼 |
|------|--------|
| `tools/import_bgm.py` | 音樂 → 循環 BGM |
| `tools/import_cutscene.py` | 影片 → 過場影片，或抽格成靜態插畫 |

---

## 1. 配樂

### 為什麼需要工具，不能直接丟檔案

AI 生成的是「一首歌」，不是「一段可以無限循環的遊戲配樂」。直接放進遊戲，
播到結尾接回開頭時會有明顯斷點，玩家每隔幾分鐘就聽到一次。

`import_bgm.py` 處理三件事，其中第三件是關鍵：

1. 轉成 Godot 原生支援的壓縮格式
2. 響度正規化到 −16 LUFS，13 首曲子音量一致
3. **自動找循環點** —— 拿曲子結尾當參考，在前半段裡找出最相似的位置。
   從那裡接回去耳朵最不會察覺跳接，前面那段就成了一次性前奏。

### 用法

```bash
# 單首（檔名就是曲目 id）
python3 tools/import_bgm.py ~/Downloads/title.mp3

# 一整個資料夾
python3 tools/import_bgm.py ~/Downloads/flow_bgm/

# 先看它會挑哪個循環點，不寫檔
python3 tools/import_bgm.py ~/Downloads/title.mp3 --dry-run

# 已經知道前奏多長，手動指定
python3 tools/import_bgm.py boss_v3.mp3 --id boss --loop-offset 12.5
```

匯入後跑 `godot --path game --headless --import`，再跑
`TEST_FILTER=bgm bash tools/run_tests.sh`。

### 曲目 id（13 首）

`title` `village` `town` `mist` `dojo` `forest` `coast` `wild` `road`
`battle` `boss` `tower` `ending`

各首的地區感與速度見 `game/assets/audio/MANIFEST.md`。

### 相似度低於 0.5 怎麼辦

工具會提醒。那代表這首歌本來就沒有可循環的結構（例如一路推進到結尾就收），
無論從哪裡接回去都會聽出來。兩個做法：

- 請 Flow 重生一版，在提示裡明講要 **loopable / seamless loop**
- 用 `--loop-offset` 自己指定一個小節線上的時間點

### 換回程式合成的版本

`AudioManager` 看到同名的 `.ogg` 或 `.mp3` 就優先用它，找不到才用 `.wav`。
所以把 `.ogg`／`.mp3` 移走，就回到 `tools/gen_bgm.py` 產的原版。

### 為什麼可能輸出 .mp3 而不是 .ogg

Godot 原生支援 Ogg Vorbis 與 MP3 兩種，工具會挑這台機器編得出來的那個。
Homebrew 的 ffmpeg bottle 不一定帶 `libvorbis`（實測 8.1.2 就沒有），
沒有的話會退到 MP3——品質相當，不用特別處理。

---

## 2. 過場

### 兩條路，先想清楚要哪條

| | 真影片 | 靜態插畫 |
|---|--------|----------|
| 引擎支援 | 只吃 **Ogg Theora**，一定要轉檔 | 現成的過場系統就吃 |
| 檔案大小 | 大（Theora 壓縮效率差） | 小 |
| 風格風險 | **高** —— 寫實運鏡配 Q 版像素畫面很突兀 | 低，抽完可以再修 |
| 現在能不能跑 | 要有帶 libtheora 的 ffmpeg | 可以 |

遊戲是 Q 版像素風。除非在 Flow 的提示裡就把畫風鎖死，否則抽格當插畫
通常是比較穩的選擇——而且抽完的圖還能再進美術管線調色。

### 真影片

```bash
python3 tools/import_cutscene.py video ~/Downloads/opening.mp4 --name opening
```

輸出到 `game/assets/video/opening.ogv`，預設降到 720p、限位元率。
`--mute` 可以去掉聲音（配樂走 BGM 系統比較好控）。

用法：

```gdscript
CutscenePlayer.play([
    {"video": "opening", "speaker": "", "text": "", "hold": 0},
])
```

影片播完會自動進下一張，玩家也可以隨時按鍵跳過。

**影片檔缺席時**，過場會退回純底圖表現並在主控台留警告，不會中斷流程——
影片檔大、容易漏進版控或漏出 export，卡住主線的代價太高。

### 靜態插畫

```bash
# 平均抽 6 張（自動避開頭尾的黑場與淡出）
python3 tools/import_cutscene.py stills ~/Downloads/opening.mp4 --name opening --count 6

# 指定時間點，比自動挑準
python3 tools/import_cutscene.py stills opening.mp4 --name opening --at 0.5,3.2,7.8
```

輸出到 `game/assets/sprites/cutscenes/opening_1.png …`，工具會直接印出
可以貼進過場定義的那幾行。

### ffmpeg 缺 libtheora

`video` 模式會擋下來並給你三個選項。最快的是 `brew reinstall ffmpeg`，
裝完用 `ffmpeg -encoders | grep theora` 確認有 `E` 開頭那行。

---

## 3. 授權

Flow／Veo 產出物拿去商業出貨（itch 上架）之前，去確認你的訂閱方案對產出物的
商用條款。這件事工具管不到，但漏掉的代價比什麼都大。
