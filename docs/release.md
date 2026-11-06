# 发布范围与材料

更新：2026-11-05。以下可用于准备提审；本轮没有发布网站、上传构建、提交 CarPlay 申请或接受账号协议。

## 当前范围

当前发布面向 iOS／iPadOS 与原生 macOS。按 2026-11-05 的产品决定，以下内容已从当前需求、开发待办和发布验收门槛中移除，运营阶段按需考虑，不安排当前排期：

- CarPlay 授权申请与实车测试。
- 长时间播放、续航、耗电和温度验证。
- 最低系统兼容性专项验证。
- 采样级无缝播放的录音与波形边界验证。

既有实现和构建配置保留；移出范围不表示验收通过。公开产品说明不承诺 CarPlay 或采样级无缝播放。部署目标仍为 iOS 17／macOS 14。

当前仍保留的验收与发布准备：

- iPhone Duo：已实现按可用窗口尺寸自适应的布局；内外屏切换、分屏、播放连续性与辅助功能仍需官方支持环境／真机专项验收，不宣称已通过 Duo 认证。

- 电话／闹钟中断、多型号蓝牙与 USB DAC，以及 ReplayGain 真实输出链路的响度与峰值复验。
- iPad 大屏、VoiceOver 全流程与最大动态字号；Mac 源文件移动、卷卸载、授权撤销的系统交互复验。
- 真实支持邮箱、隐私政策托管 URL、产品网站、App Store 截图、分发签名、TestFlight／商店提交。

构建和测试证据集中在[开发指南](development.md#验证)，上述人工验收未因文档整理而变为通过。

## 产品说明

**名称**：Zuneyra

**副标题候选**：你的私人离线音乐库 / Your personal offline music

**简体中文描述**

把自己的音乐收藏带在身边。Zuneyra 是适用于 iPhone、iPad 和 Mac 的本地音乐播放器。导入音乐后，按专辑、艺术家或歌曲浏览，建立歌单，收藏喜欢的音乐，并随时调整播放队列。

支持本地歌词、随机与循环、播放位置恢复，以及音乐库备份和 M3U8 歌单迁移。在 Mac 上，可选择复制导入，或直接引用自己的音乐文件夹。无需创建账号，也无需订阅音乐服务。

**English description**

Keep your own music collection close. Zuneyra is a local music player for iPhone, iPad, and Mac. Import your audio, browse albums and artists, build playlists, save favorites, and arrange your play queue.

Read local lyrics, use shuffle and repeat, restore your playback position, and transfer your collection with library backups and M3U8 playlists. On Mac, copy music into your library or link your own music folders. No account or music subscription is required.

## 审核操作说明草稿

应用首次启动为空音乐库，不包含第三方音乐。可用自有或许可音频通过系统文件选择器导入；iOS 也可通过 Finder 文件共享传入。管理入口提供存储、备份和歌单迁移。测试不需要登录账号。背景音频用于用户主动播放的音乐。

备份恢复选择 `.zuneyra-backup` 文件夹；该文件夹需包含 `manifest.json` 和 `Media`。M3U8 导入选择包含歌单与相对路径音频的文件夹。

## 隐私说明草稿

Zuneyra 在设备上保存用户导入的音乐、歌曲标签、封面、歌词、收藏、歌单和播放进度。Mac 文件夹引用所需的授权书签保存在设备的应用数据中。应用不提供账号系统，不包含广告、行为分析或开发者运营的数据上传服务。

选择系统文件提供器时，该提供器可能按自身设置下载或同步文件。用户主动导出的音乐库备份和歌单包含相应音频及收藏信息，保存位置由用户选择。锁屏与系统媒体界面会显示正在播放的曲目信息。系统诊断与 Apple 服务由其自身设置及政策控制。

删除音乐库歌曲会移除应用拥有的音频副本；引用的原始文件和 Finder 传入文件仅由各自明确操作处理。卸载应用可能删除应用保存的音乐与元数据，用户可以先导出备份。

发布前需填写真实开发者／运营主体、隐私联系邮箱，并将最终隐私说明托管到可公开访问的 URL。本草稿不填入虚构联系方式。

## 隐私清单依据

`PrivacyInfo.xcprivacy` 为当前应用代码声明 UserDefaults 的 CA92.1，以及应用容器／用户明确授权文件元数据的 C617.1、3B52.1。依据 [Apple API 使用理由文档](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。发布时仍需对最终归档依赖和代码重新核对。

## 截图拍摄清单

使用具有许可的封面与音频：专辑库、专辑详情、正在播放、歌词、歌单、备份管理。分别检查中文／英文、iPhone／iPad／Mac；不把单元测试空白库截图当作商店宣传素材。


## 2026-11-05 分发上传记录

iOS 与 macOS 的 1.0（1）均已通过 Xcode App Store Connect 分发上传。源代码为 `0db41e6`，归档位于 `/tmp/zuneyra-submit/ios-final.xcarchive` 和 `/tmp/zuneyra-submit/mac-final.xcarchive`。日志 `/tmp/zuneyra-submit-ios-upload.log` 与 `/tmp/zuneyra-submit-mac-upload.log` 均显示 `Upload succeeded`、`EXPORT SUCCEEDED`。两个平台已关联构建并回答加密合规问题。

中英文说明、关键词、支持 URL、审核联系人及无需登录的审核说明已填写。分类为 Music，年龄分级 4+。隐私问卷已保存“不收集数据”，尚待用户确认 Apple 发布承诺；价格及地区待用户指定，尚未提交审核。

公开支持页：
- https://castorworks.github.io/zuneyra/
- https://castorworks.github.io/zuneyra/zh/

公开隐私政策：
- https://castorworks.github.io/zuneyra/privacy/
- https://castorworks.github.io/zuneyra/zh/privacy/

内容已推送至 `castorworks/castorworks.github.io` 并验证 GitHub Pages 部署成功及 HTTP 200；隐私文档另保存在 `castorworks/Privacy/Zuneyra`。


## 2026-11-06 正式提审

用户已确认发布“不收集数据”的隐私标签，两个平台免费，全部可用地区。隐私标签已发布，价格基准为 USD 0.00，所有地区对应价格为 0。可用性设置为所有 175 个国家或地区及未来新增地区（实际销售仍由 Apple 的地区要求决定）。

- iOS 1.0（1）：Waiting for Review；提交记录 `ff087d15-cc16-40e1-99cc-7f9ad73b79ac`。
- macOS 1.0（1）：Waiting for Review；提交记录 `afe9c6fd-3747-4c7f-bf1e-0bbcad588bec`。

后台 App Review 列表已确认两个平台均等待审核，草稿数为 0。沿用现有审核通过后自动发布设置。截图凭证：`/tmp/zuneyra-both-submitted.jpg`。
