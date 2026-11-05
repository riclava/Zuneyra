# 开发指南

## 代码职责与数据约束

| 入口 | 职责 |
| --- | --- |
| `Zuneyra/AppSession.swift` | 统一启动任务，手机窗口与 CarPlay 等待同一初始化。 |
| `Zuneyra/MusicLibrary.swift` | `MusicRepository` actor：SQLite、导入、元数据和文件访问。 |
| `Zuneyra/PlayerStore.swift` | 主线程播放状态、系统媒体控制、队列与异步切歌。 |
| `Zuneyra/PlaybackQueue.swift` | 独立队列条目、顺序／随机／循环和快照。 |
| `Zuneyra/LibraryManagement.swift` | 管理操作的数据类型；管理入口见 `LibraryManagementView.swift`。 |
| `Zuneyra/ExtendedMetadata.swift`、`LegacyID3Metadata.swift` | 标签补读及保守的旧中文标签兼容。 |
| `Zuneyra/Lyrics.swift`、`ReplayGain.swift` | 歌词解析和增益处理。 |
| `Zuneyra/CarPlayController.swift` | 系统模板与共享播放器的连接。 |

普通导入的数据库、媒体、封面和任务清单位于私有 Application Support/Zuneyra；iOS Documents 只作为 Finder 传入目录。数据库 schema v2 保存歌曲 payload、独立 ID 和唯一内容哈希，歌单保存有序歌曲引用；v1 → v2 迁移及歌单修改使用事务。歌单成员唯一，队列条目允许重复歌曲。

维护时保留以下数据保护规则：

- 导入复制前持久化 ImportJobs。启动只清理任务清单拥有的未提交媒体，保留已提交与无清单的未知文件。批次历史与逐文件恢复日志不同，不保证中断批次有完整历史，也不提供自动续传。
- 删除使用私有 Trash 清单及数据库事务；启动按提交状态恢复或清理暂存文件。过期收藏更新不能复活已删除歌曲。引用模式绝不删除外部音频。
- 清理传入文件须同时核对传入文件和托管副本的实际哈希。备份恢复须验证路径、符号链接边界、全部媒体哈希及歌单引用，最后在单个数据库事务中合并。
- 元数据导入与重扫共用解析器。重扫校验内容哈希和读取前后的文件状态，保存前重读最新行，保留并发收藏、歌词及授权修改，不复活已删除记录。封面按内容哈希命名，旧缓存交由清理入口处理。
- 旧 ID3v1 中文兼容只在系统文本与原始 Latin-1 解释一致、GB18030 可无损回转且中文上下文明确时替换；保留有效 Unicode 和西文重音，不写回音频。FLAC 注释和图片采用有界读取；专辑按碟号再曲号排序。
- PlaybackSnapshot v2 保存条目身份、顺序、模式与进度，加载旧快照时迁移；恢复不自动播放。异步准备与 seek 使用请求版本，过期回调不能覆盖新选择或暂停意图。

## 音频与平台

生产播放后端为 AVQueuePlayer，预先准备下一首；AVAudioEngine 连续缓冲区调度仅为离线测试原型，不能据此宣称采样级无缝播放。

ReplayGain 使用 MediaToolbox 音频 tap 应用正负增益并限制削波。渲染回调不访问数据库、不做 I/O、不分配音频缓冲区、不加锁；覆盖浮点 32/64 位和小端整数 16/32 位 PCM，其他格式保持原信号。

Mac 引用使用只读安全作用域书签，访问时恢复授权。iOS 数据库及附属文件、媒体使用 `completeUntilFirstUserAuthentication`：安装或升级后先解锁打开一次，设备重启后也需先解锁一次；模拟器不等同于真机文件保护验证。

CarPlay 与手机共用 PlayerStore，连接不自动播放，断开暂停并保存。列表受系统条数限制并分页，不不断压入导航栈。`Configuration/AppInfo.plist` 显式注册场景。`Zuneyra` 为常规手机／Mac scheme；`Zuneyra-CarPlay` 使用专用配置，真机需要含 `com.apple.developer.carplay-audio` 的授权 profile。普通手机安装和模拟器构建不能证明已获该权限。授权和实车测试已[移出当前范围](release.md#当前范围)。

简体中文（zh-Hans）和英文（en）文案集中在 `Localizable.xcstrings`，维护数量、错误及辅助功能文本；已持久化的默认歌曲标签不随界面语言改写。隐私清单依据及公开草稿见[发布说明](release.md)。

## 界面与图标

颜色集中在 `SunsetTheme.swift`，沿用莓红／奶油色的唱片收藏室风格。页面与专辑标题使用系统衬线字体，正文使用系统字体，时长和计数使用等宽数字。页面水平边距 24 点、内容最大宽度 1100 点；具体颜色和尺寸以组件代码为准，避免在文档复制整份样式表。

真实封面优先，缺图由 `CoverArt` 按专辑稳定生成占位封套。弹窗共用 `CollectionSheetHeader`；隐藏系统工具栏的页面必须有可达的返回／关闭按钮。保持 Esc 和默认操作快捷键。搜索固定在音乐库顶部，播放时仍可输入。

Mac 侧栏宽 210 点，窗口最小 800×580。iOS 按当前窗口可用宽度适配：宽度至少 900 点、高度至少 560 点且非辅助功能字号时显示 210 点侧栏，否则使用顶部分类；切换宽度不重建导航栈。工具栏、搜索框及音乐库内容共用居中的 1100 点最大宽度，iPad 侧栏模式使用更紧凑的推荐卡片。iOS 主要操作目标至少 44 点。歌曲、艺术家和收藏页将批量选择放在列表「…」菜单。支持语义字号、长标题换行、辅助功能状态与减少动态效果；队列和管理空态填满可用空间。进度条辅助功能操作每次前后 10 秒。

图标唯一原稿为[单音符图标](assets/zuneyra-icon-single-v4.png)，由 image_gen 生成并经用户选定：莓红／珊瑚底色、暖白单音符。重新导出（仓库根目录执行）：

```sh
swift scripts/generate-app-icons.swift docs/assets/zuneyra-icon-single-v4.png Zuneyra/Assets.xcassets/AppIcon.appiconset
```

iOS 导出不透明满幅 1024 图；Mac 导出含透明边距和圆角的 1x／2x 资源。勿把预览截图当作图标源文件。

## 验证

仓库保留 `ZuneyraTests` 的 Swift Testing 单元／组件测试，界面采用人工验证。测试使用隔离临时音乐库与[生成音频](../ZuneyraTests/Fixtures/README.md)，不清理用户音乐。

在仓库根目录列出可用模拟器，选择 UUID 后运行：

```sh
xcrun simctl list devices available
ZUNEYRA_SIMULATOR_ID='<已安装的 iOS 模拟器 UUID>' bash scripts/verify-release.sh
```

脚本依次运行 macOS 测试、iOS 模拟器测试、CarPlay 模拟器构建和 macOS Release 构建。默认日志写入 `/tmp/zuneyra-verification`，可用 `ZUNEYRA_VERIFY_DIRECTORY` 修改；每项使用独立 OBJROOT/SYMROOT，避免 Xcode 全局构建目录冲突。脚本不会上传，也不使用分发签名。

截至 2026-11-05 的功能改动验证记录（文档整理未重跑应用测试）：

| 验证 | 已取得的结果 |
| --- | --- |
| macOS Debug / Apple Silicon | 76 项测试通过。 |
| iOS 26.5 / iPhone 17 Pro 模拟器 | 76 项测试通过。 |
| CarPlay scheme / iOS Simulator | 构建通过。 |
| macOS Release | 非分发签名构建通过，不等于商店归档或审核。 |

覆盖导入／删除中断恢复、备份往返和损坏拒绝、路径越界拒绝、Mac 引用保护、M3U8、歌词、多碟排序、增益 PCM 处理、队列和暂停恢复、旧库重扫与并发保护、英文资源，以及六格式解码和音频帧定位。10,000 曲目组件测量中库读取约 42–54 ms、搜索约 40–43 ms，不代表 UI 冷启动、内存峰值或真机性能。

2026-11-04 的 iPhone 15 / iOS 26.6.1 人工记录：用户确认短时后台、锁屏播放与锁屏控制正常，蓝牙输出正常，蓝牙断开和有线／USB-C 耳机拔出后暂停。专用演示启动与验收日志代码已移除，原始配件日志未入库。这些历史记录不证明所有设备或最新版本已全面复验。

最近英文 iPhone 界面检查过管理页、播放器和歌词页返回导航。后续界面复验使用正常启动和许可音频，关注浅／深色、窄屏、长标题、空态、搜索、选择模式、关闭／返回和辅助功能；仍保留的具体人工验收与发布准备统一见[发布范围](release.md#当前范围)。

2026-11-05 iPad 布局复验：iOS／macOS Debug 构建通过；13 英寸 iPad 横竖屏、11 英寸 iPad 在 834 点竖屏与 1210 点横屏间切换、iPhone 17 Pro Max 竖屏已观察。11 英寸 iPad 切换导航布局后保留专辑详情。重拍 4 张 iPad 横屏商店截图；实际分屏拖拽与最大动态字号仍需后续复验。

2026-11-05 本地化补齐：侧栏「私人收藏」加入中英文资源；窄屏「收藏」分类使用独立键，英文显示 Favorites，与歌曲操作 Favorite 分离；修正删除／恢复提示中无关名词错误跟随歌曲数量变为单数的问题。350 个资源键中，344 个有完整 en／zh-Hans 翻译，其余 6 个为品牌、格式、ReplayGain 与纯数字格式。逐条检查翻译状态、格式占位符及英文中的中文残留，未发现遗漏。iOS 与 macOS 均通过 `englishCatalogIncludesPluralForms()`，覆盖 0／1／2 首歌曲、中文侧栏及英文分类译文。

本轮实际英文界面抽查：iPhone 17 Pro Max 主页、导入进度、歌单空态和新建表单；iPad Pro 13 英寸主页、管理页和清理确认弹窗（取消，未执行清理）；macOS 主页、播放器和队列。已在 iPhone 观察修正后的 Favorites，并将 iPad 切回中文确认「私人收藏」。这些是界面抽查，不代表所有错误分支、最大动态字号或真机均已验收。当前不包含繁体中文；音乐标题、艺术家及歌词保留文件自身内容，系统日期／文件选择器还可能由系统语言决定。

### 可变窗口与折叠屏布局

布局规则集中在 `AdaptiveLayout.swift`，使用窗口／容器实际可用尺寸，不硬编码 Duo 机型或未经核实的屏幕规格。音乐库在 900×560 点以上启用侧栏；播放器在 600×360 点以上横向排列，900×560 点以上增加歌词／队列侧栏；辅助功能字号退回纵向布局。播放器判断尺寸不包含顶部标题栏，因此阈值指内容区域。迷你播放器在宽度 700 点以上增加上一首、进度与队列入口。

iOS 播放器使用全屏呈现，避免系统 sheet 的宽度上限使双栏无法触发；Mac 保留原有弹窗。播放器通过 AnyLayout 切换封面与控制的排列，侧栏收起时保留子视图身份并从命中测试与辅助功能树隐藏。窗口变化不重建 PlayerStore、音乐库导航栈或表单；专辑／歌曲列表通过稳定 ID 与 scrollPosition 保持可见项目。已有的管理与歌单表单继续使用可滚动布局。

Duo 专项验收仍需官方支持环境／真机：播放中折叠与展开、内外屏旋转、分屏缩放、搜索键盘与未提交歌单表单、列表滚动位置、歌词导入和队列排序，以及最大字号与 VoiceOver。通用窗口单元测试与 iPhone／iPad 模拟器检查不替代该验收。

2026-11-05 可变窗口适配验证：最终代码在 macOS 与 iOS 26.5 / iPhone 17 Pro 模拟器分别通过 77 项测试，日志为 `/tmp/zuneyra-duo-final-mac.log`、`/tmp/zuneyra-duo-final-ios.log`。完整验证脚本另通过 CarPlay 模拟器与 macOS Release 构建（在最后一处隐藏面板辅助功能修正前）；日志目录 `/tmp/zuneyra-duo-verify`。13 英寸 iPad 横竖屏检查了宽屏播放器与队列；11 英寸 iPad 播放中旋转，观察到封面／控制横向排列与队列双栏切换，歌曲保持、进度继续前进，检查后暂停播放。修正后再次检查辅助功能树，未选中的歌词面板不再暴露导入按钮。这些检查不代表 Duo 真机、实际分屏拖拽、全部表单或 VoiceOver 全流程验收完成。
