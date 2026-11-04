# Zuneyra 音符图标 v2

日期：2026-11-04。使用内置 image_gen 生成。状态：历史版本，现已由单音符 v4 替代。

根据用户反馈，以明确的双八分音符为唯一主体，莓红与珊瑚红背景搭配暖白音符。用户已否定日落、唱片与字母 Z 作为图标概念，后续迭代遵循此约束。

原稿：`zuneyra-icon-music-v2.png`。

## 生成提示词

Use case: logo-brand. Create a single exceptionally polished app icon for Zuneyra, an offline music player for iOS and macOS. The user's explicit design correction: the icon MUST unmistakably depict a musical notation symbol; remove ALL sunset, sun, vinyl record, disc, circular record, letter Z, or monogram concepts. Primary subject: one bold, beautiful BEAMED PAIR OF EIGHTH NOTES (two oval note heads connected by two stems and one top beam). Refine its geometry with slightly rounded ends, clean confident proportions, generous negative space, and a subtle forward energetic slant. The music symbol is solid warm ivory, extremely legible at 32px, centered and fills approximately 58-62 percent of the canvas. A tiny amount of restrained soft dimensional relief can enrich the ivory symbol, but it must remain a clean graphic mark, not an ornate sculpture. Background: opaque saturated raspberry-red field with a smooth tasteful coral-red luminosity toward one corner; elegant vivid contemporary music app identity. Strong immediate silhouette, high contrast, professional and approachable. Composition: exactly ONE square edge-to-edge full-bleed icon master artwork. NO outer rounded corner mask (OS will apply it). No borders, no surrounding margins, no environment, no device mockup, no presentation layout, no captions, no text, no letters, no extra badges, no equalizer, no headphones, no play triangle, no watermarks, no stars, no suns, no landscape, no circles or discs. Avoid clutter, avoid neon glow, avoid excessive glossy 3D. The only foreground symbol is the unmistakable musical eighth-note pair. Aim for carefully crafted original geometry rather than copying any existing app icon.

## 应用资源

资源目录（相对项目根目录）：`Zuneyra/Assets.xcassets/AppIcon.appiconset`。iOS 使用 1024 × 1024 不透明原稿；macOS 使用带透明边距和圆角轮廓的 16／32／128／256／512 pt、1x／2x 图标。两端均使用已确认的同一音符图案。

重新导出：在项目根目录运行 `swift scripts/generate-app-icons.swift docs/assets/zuneyra-icon-music-v2.png Zuneyra/Assets.xcassets/AppIcon.appiconset`。
