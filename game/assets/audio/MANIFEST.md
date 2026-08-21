# Audio Manifest

## SFX (`sfx/`)
Procedural one-shots for combat / UI.

## BGM (`bgm/`) · 地區差異化編曲

每首有獨立 **鼓型／主奏音色／和弦／BPM／EQ**，聽感不該再「全部一個樣」。

| id | 地區感 | BPM | 主奏 | 鼓 | 特徵 |
|----|--------|-----|------|----|------|
| title | 英雄主題 | 118 | brass | drive | 辨識度最高 |
| village | 翠谷村 | 92 | flute | 無 | 溫暖、慢、木笛 |
| town | 騎士堡 | 112 | horn | 軍鼓 march | 行進號角 |
| road | 荒路 | 108 | pulse | soft | 趕路步伐 |
| wild | 荒野 | 120 | pulse | drive | 不安 Phrygian |
| mist | 霧隱 | 72 | choir | 無 | 稀疏長音 |
| dojo | 道場 | 126 | pulse | march | 短促打擊 |
| forest | 森林 | 98 | bell | soft | 鐘／琶音 |
| coast | 海岸 | 104 | flute | soft | 浪湧低頻 |
| battle | 雜魚戰 | 148 | power | battle | 最密最快 |
| boss | Boss | 128 | power | battle | 厚重儀式 |
| tower | 塔 | 88 | choir | soft | 低沉 |
| ending | 終章 | 96 | brass | soft | 收束大調 |

重產合成 WAV：`python3 tools/gen_bgm.py`  
烤成可替換壓縮曲＋循環：`python3 tools/bake_placeholder_bgm.py`  
Suno／外部成品：`python3 tools/import_bgm.py <file> --id <曲目>`  

優先順序：`.ogg`／`.mp3`（真配樂槽）→ `.wav`（程式合成後備）。

### 2026-08-21 · Suno 真曲已入庫
帳號 `guanrung1110` 產的 `bravesoul_*` 已下載並 `import_bgm` 覆蓋 13 首。  
來源 uuid 見 `SUNO_SOURCES.json`。多數曲循環相似度偏低（Suno 歌曲結構），若聽得出接縫可再產 loopable 版或手動 `--loop-offset`。
