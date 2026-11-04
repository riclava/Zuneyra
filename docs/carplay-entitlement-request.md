# CarPlay Audio 权限申请准备

本文件是申请材料草稿，不代表已经提交或获批。账号成员资格、应用标识、团队和联系信息由提交人核对，不填入猜测值。

## 申请与配置步骤

1. 使用有权限管理该应用的 Apple Developer 账号打开 [CarPlay Contact Us](https://developer.apple.com/contact/carplay/)，选择 Audio 类别。
2. 核对 App 名称 `Zuneyra`、Bundle ID `com.hyperits.app.Zuneyra`，填写所属团队、开发者联系信息、产品说明。尚未上架时说明目前为开发中，不编造 App Store 链接。
3. 按 Apple 页面要求提交材料并审阅相应 CarPlay Entitlement Addendum。提交及同意协议应由账号持有人完成。Apple 根据其标准审核，没有可保证的通过结果或周期。
4. 获批后，到 Certificates, Identifiers & Profiles → Identifiers 选择该明确 App ID，在 Additional Capabilities 中启用 CarPlay Audio App（CarPlay framework）。若该项不存在，先确认批准的团队及标识是否一致。
5. 创建／更新包含 CarPlay Audio 的 development profile；发布归档还需要匹配的 distribution profile。
6. 下载并在 `Zuneyra-CarPlay` scheme 的 CarPlay 配置中选择该 profile。按 [Apple 官方说明](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements) 配置签名；使用专用 profile 时关闭对应配置的自动签名并明确选择匹配项。
7. 检查最终签名和 embedded profile 均含 Boolean `com.apple.developer.carplay-audio = true`，再开始真实车机测试。

当前工程已准备 entitlement、CarPlay 场景、专用构建配置和共享 scheme。当前安装 profile 缺少该权限，尚不能据此完成真实车机验收。

## 英文产品说明草稿

可根据申请表字数限制调整；只描述目前已实现的能力：

> Zuneyra is a native offline music player for iPhone and Mac. Users import their own local audio files using the file picker, folders, or Finder file sharing. The app stores managed local copies and provides albums, artists, favorites, and user-created playlists without requiring a streaming subscription.
>
> We are requesting the CarPlay Audio entitlement to let users browse and play their existing offline music in a vehicle. The CarPlay interface uses Apple's list, tab bar, and Now Playing templates. It shares the iPhone app's playback queue, supports playback controls, shuffle and repeat, and presents concise empty-library and unavailable-file messages. Connecting or reconnecting does not automatically start playback. Disconnecting pauses playback to avoid unexpected output through the phone speaker.
>
> The implementation uses the CarPlay framework and has been tested in the iOS simulator. Testing with physical CarPlay systems will follow entitlement approval and provisioning configuration.

## 提交前应由账号持有人补齐

- 开发者账号／团队信息及联系信息。
- 应用当前发布状态与真实 App Store 链接（如已有）。
- 申请表要求的产品网站、隐私政策、演示或截图（按实际情况填写）。
- 对申请页面条款及附录的审阅与接受。

不将本地安装成功、模拟器可见图标或本文件的存在视为 Apple 授权。
