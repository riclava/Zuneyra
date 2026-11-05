# Zuneyra 中英文 App Store 截图

2026-11-05，使用当前修正后的应用实际拍摄，音乐来自 /Users/ricl/Downloads/zhoujielun。音乐库显示 408 首歌曲、69 张专辑。

共 24 张：zh-Hans（简体中文）与 en（英文），每种语言含 iPhone、iPad、macOS 各 4 张。

| 平台 | 尺寸 | 方向 |
| --- | --- | --- |
| iPhone | 1320 × 2868 | 竖屏 |
| iPad | 2752 × 2064 | 横屏 |
| macOS | 2560 × 1600 | 横屏 |

每组顺序：01-library 音乐库、02-album 专辑、03-player 播放器、04-queue 播放队列。

所有交付截图均为无透明通道的 RGB PNG。iPad 已转正；Mac 裁去系统标题栏与控制标记，保留完整应用内容。未改写应用画面。歌名、艺术家和封面保留来源文件原始内容；排序随语言区域规则不同。英文 iPad 的系统日期也已切换为英文。

manifest.json 记录正式截图的尺寸与 SHA-256。24 张截图已上传 App Store Connect 的英文（美国）与简体中文版本草稿，尚未提交审核。

## Duo 补充截图

2026-11-05 使用 Xcode 27.2 的 iPhone Duo / iOS 27.2 模拟器重新验证布局。`zh-Hans/iphone-duo`、`en/iphone-duo` 各 4 张：外屏收藏页、内屏收藏页、内屏播放器与队列、外屏播放器。内屏横向 2853×2007，外屏竖向 1398×2034，原生 RGB JPEG，未缩放或改写界面。导入 63 首歌曲、7 张专辑。`duo-manifest.json` 记录尺寸与 SHA-256。这 8 张已上传至 App Store Connect iOS 1.0 草稿的 iPhone Duo 栏位；英文（美国）与简体中文均确认显示 4 of 10 App Screenshots。尚未提交审核。

上传后刷新时，后台各设备资源栏出现 “There was an error loading your assets. Try again later.”，因此刷新后的持久状态暂未复核；上传当时两语言均显示 4/10。

后续复核：两语言第 4 张外屏播放器曾卡在处理状态，已分别移除版本引用并重新上传。中英文各 4 张均已生成可见预览，确认无云朵占位。
