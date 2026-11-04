# Zuneyra 单音符图标 v4

日期：2026-11-04。使用内置 image_gen 编辑。状态：已应用到 iOS 和 macOS 的 AppIcon 资源。

用户要求恢复 v2 的莓红／珊瑚渐变背景与暖白图形，去掉声波，保留 v3 的单八分音符形态。

原稿：`zuneyra-icon-single-v4.png`。

编辑目标：`zuneyra-icon-wave-v3.png`。配色参考：`zuneyra-icon-music-v2.png`。

## 完整编辑提示词

Use case: logo-brand / precise-object-edit. Edit target: Image 1, the indigo-blue Zuneyra icon with a single orange musical note and three waveform bars. Reference image: Image 2, the previous raspberry/coral-red icon with ivory double notes; use Image 2 ONLY as the exact color, background lighting and material reference, NOT as a symbol or layout reference. User instructions: keep the original raspberry-red/coral color style; remove the waveform. Required edits to Image 1: remove ALL three separate waveform bars completely and reconstruct the background cleanly. Keep ONLY its single eighth-note shape with the broad oval notehead, stout upright stem, and elegant sweeping flag, preserving that recognizable single-note silhouette and refined smooth geometry. Recenter this one remaining musical note optically in the square and scale it for generous even padding, about 62 percent of the full image height. Recolor the background to match Image 2's saturated raspberry-red field with soft coral-red luminosity toward the top-right. Recolor the note to match Image 2's warm ivory / creamy white, with the same subtle satin tonal depth. No orange or blue remains. This must remain a SINGLE musical note with a flag, not a beamed pair or a quarter note. Crisp, minimal, polished and unmistakably musical. Keep square full-bleed opaque artwork, no external corner rounding, no border, no outer shadow, no typography, no watermark, no additional symbols, no waveform bars, no landscape, no sun, no disc, no monogram. Output ONE final app icon, not a comparison sheet or mockup.


## 应用资源

iOS 使用 1024 × 1024 不透明原稿；macOS 使用 16／32／128／256／512 pt 的 1x／2x 图标，适配透明边距和圆角轮廓。

重新导出：`swift scripts/generate-app-icons.swift docs/assets/zuneyra-icon-single-v4.png Zuneyra/Assets.xcassets/AppIcon.appiconset`。
