# 从 Mac Finder 向 iPhone 导入音乐

## 使用步骤

1. 将包含本功能的新版 Zuneyra 安装到 iPhone，并打开一次。
2. 用数据线连接 Mac 与 iPhone，解锁设备并在需要时选择“信任”。
3. 在 Finder 侧栏选中 iPhone，进入“文件”页，找到 Zuneyra。
4. 把音频文件或包含音乐的文件夹拖到 Zuneyra，等待 Finder 传输结束。
5. 打开 iPhone 上的 Zuneyra，或切到后台后再回到前台，应用会自动导入新音乐。
6. 如果传输时 Zuneyra 已在前台，点右上角“＋”→“导入电脑传入的音乐”进行检查。

支持导入的扩展名：MP3、M4A、AAC、ALAC、FLAC、WAV、AIF、AIFF；文件仍须通过系统音频解码验证。隐藏文件、非音乐文件和符号链接不会参与自动导入。

如果 Finder 尚未显示 Zuneyra，确认安装的是包含新配置的版本，打开应用一次，再重新连接设备或重新进入“文件”页。此入口属于 iPhone 应用文件共享，与 Mac 版应用的音乐库相互独立。

## 文件和存储

Finder 和 iPhone“文件”App 能看到的是 Zuneyra 的 Documents 目录。应用数据库、导入记录与实际播放使用的副本位于私有 Application Support 目录。

导入成功后保留 Documents 原文件，不移动、不删除。删除 Finder 中的传入原文件不会删除音乐库已保存的播放副本；保留两份会占用额外空间。应用不会自动处理原文件删除和音乐库删除的同步。

已成功导入或按内容判定为重复的文件，会记录路径、大小与修改时间。文件未变化时，下次扫描不再导入或弹出重复报告。修改后的文件会重新检查；内容相同但文件名不同的音乐由现有 SHA-256 去重逻辑处理。失败文件保留并在之后的扫描中重试。

导入前观察文件大小和修改时间是否稳定，并在协调读取复制后再次检查。观察期间发生变化的文件延后处理；这不能替代 Finder 的传输完成状态，因此请等待传输结束再打开应用或手动检查。

## 平台配置与验收

`UIFileSharingEnabled = YES` 启用 Finder 文件共享；`LSSupportsOpeningDocumentsInPlace = YES` 同时允许系统本地文件提供器展示 Documents 内容。参考 Apple 的 [UIFileSharingEnabled](https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled) 与 [Launch Services Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)。

自动化测试覆盖嵌套目录导入、原文件保留、跨启动处理记录、改名重复文件、损坏文件修复重试、文件变化时延后处理，以及应用加载和再次扫描时的音乐库刷新。模拟器可验证在 Documents 放入文件后的导入流程；Finder 的实际设备列表显示、USB 传输与“信任”流程需物理 iPhone 验证。
