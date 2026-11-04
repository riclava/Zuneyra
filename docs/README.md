# Zuneyra 文档

- [产品与技术设计文档](./design.md)：iOS、macOS、CarPlay 的产品定位、功能范围、交互、架构、数据模型、播放与文件管理、验收标准和实施路线。

当前设计版本为 v0.1，更新于 2026-11-04。文档中的功能和性能指标是拟实施方案与验收目标，不代表已经实现或测得。

当前仅保留 `ZuneyraTests` 的 Swift Testing 单元与组件测试；界面、布局和设备交互采用手动验收。UI 测试 target、界面自动化用例及专用启动模式已移除。各实现文档中的历史验证记录和截图不代表仍有对应自动化套件。

- [私人唱片收藏室视觉约定](./ui-visual-system.md)：与 App icon 呼应的覆盆子红与奶油色、编辑式排版、封面布局及界面验收记录。

- [第一阶段实现记录](./implementation.md)：运行方式、已实现功能与当前边界。

- [Finder 文件共享导入](./finder-import.md)：从 Mac 向 iPhone 拖入音乐的步骤与文件管理规则。

- [中文标签与播放中搜索修复](./metadata-compatibility.md)：本地样本分析、兼容策略和搜索栏回归验证。

- [音乐库管理与存储清理](./library-management.md)：多选删除、传入文件与封面清理、导入记录及失败重试。

- [播放队列与播放模式](./playback-queue.md)：下一首与追加、排序移除、随机循环、暂停恢复与文件丢失处理。

- [本地歌单](./playlists.md)：创建与编辑、歌曲添加入口、播放与 SQLite 升级规则。

- [音乐库与播放器 UI / UX 优化](./ui-ux-refinement.md)：固定分类、搜索与排序、专辑播放顺序、播放器层级、深色与大字号适配及回归覆盖。

- [iPhone 真机播放验收](./device-playback-validation.md)：后台、锁屏、蓝牙与耳机路由实测记录。

- [CarPlay 首版](./carplay.md)：车载浏览、系统播放、连接恢复、构建方式与验收状态。

- [CarPlay 权限申请准备](./carplay-entitlement-request.md)：Apple 申请步骤、英文说明草稿与获批后的签名配置。
