# 星灯岛 iOS 构建与发布说明

当前交付采用用户已选择的「Xcode 工程 + 未签名构建」方案，不需要提供 Apple 证书。仓库中的 macOS 工作流会先导出工程，再用 Xcode 实际编译 iPhoneOS arm64 Release App，并封装为 `StarLanternIsland-unsigned.ipa`。**未签名 IPA 不能直接安装到普通 iPhone，也不能直接提交 TestFlight / App Store。**

## 交付文件的含义

| 文件 | 内容 | 能否直接安装 iPhone |
| --- | --- | --- |
| `StarLanternIsland-iOS-Xcode.zip` | 完整 Xcode 工程、Godot 库和游戏数据，可在 Mac 上继续配置和签名 | 不能；需要 Xcode 编译、签名 |
| `StarLanternIsland-unsigned.ipa` | macOS/Xcode 编译的真实设备 App，包含 `Payload/StarLanternIsland.app`，没有 Apple 签名 | 不能；需要匹配的证书和描述文件重新签名 |
| 后续的签名开发 / Ad Hoc IPA | 使用有效证书和包含目标设备的描述文件 | 可以，限描述文件允许的设备 |
| 后续的 TestFlight 构建 | 签名后上传 App Store Connect，由 TestFlight 分发 | 通过 TestFlight 安装 |

把工程 ZIP 改名为 IPA 不会产生可执行 App。本构建脚本会验证 `Payload/`、非空 Mach-O 可执行文件、arm64 架构、`iphoneos` 平台和游戏 PCK，并确认 App 没有代码签名。Apple 的 [Ad Hoc 描述文件要求](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)和 [TestFlight 流程](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)分别适用于之后的真机分发。

## 平台与版本

- 固定使用 **Godot 4.7.2 stable 标准版**及同版本导出模板；本项目使用 GDScript，不需要 Mono/.NET 模板。
- 完整 iOS 编译需要 **macOS + Xcode + iPhoneOS SDK**。GitHub Actions 使用 `macos-15`，脚本优先选择镜像已有的 Xcode 26.3、26.2 或 26.1.1，回退到系统 Xcode，并在日志记录实际版本；也可以设置 `DEVELOPER_DIR`。参见 [Godot iOS 导出指南](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html)及 [GitHub macOS 15 镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)。
- 本版本 iOS 模板的最低目标为 **iOS 15.0**；正式支持范围还要以实际设备测试为准。版本依据：[Godot 4.7.2 iOS 导出器源码](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/ios/export/export_plugin.h)。
- Windows 可以在安装同版本 `ios.zip` 模板后为本 GDScript 项目导出 Xcode 工程；实际 App 和 IPA 编译留给 Mac。此处依据 4.7.2 的实现：工程导出先完成，项目模式在调用 Xcode 之前返回；非 macOS 不执行原生打包。参见 [4.7.2 Apple 导出实现](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform_apple_embedded.cpp)。

`application/export_project_only=true` 的输出文件名使用 **`.xcodeproj`**，例如 `StarLanternIsland.xcodeproj`；不能照搬旧版教程中的 `ios.zip` 输出名。此处以 [4.7.2 导出器的扩展名实现](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform_apple_embedded.h)和 [iOS 导出选项](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformios.html)为准。

## 从 GitHub 构建

1. 打开仓库 [swaggyer/game](https://github.com/swaggyer/game)，进入 **Actions → Mobile iOS unsigned build → Run workflow**，选择包含最新源代码的分支。更新 `main` 中的 `mobile_game/` 或工作流，以及推送 `v*` 标签，也会触发构建。
2. 等待 `iOS device build (unsigned)` 完成。首次需要下载约 1.35 GB 编辑器和模板，并编译原生 App；以该次运行的绿色结果和日志判断成功。
3. 在该次运行底部的 **Artifacts** 下载工程、未签名 IPA、构建证据。Actions 下载通常会再包一层 ZIP；解压后才是上述文件。日志和产物默认保留 30 天；成功后工程与 IPA 也会自动附加到 v1.2.1 GitHub Release。
4. 对照构建证据中的 `SHA256SUMS` 校验文件。`BUILD-INFO.json` 会记录源提交、Godot/Xcode/SDK、设备架构和 `signed=false`。

工作流位置为仓库根目录 `.github/workflows/mobile-build.yml`，实际脚本为 `mobile_game/tools/build_ios.sh`。工作流使用仓库内容写权限附加 Release 文件，不使用任何 Apple Secrets。Actions 的产物下载入口要求登录 GitHub，Release 提供公开下载；参见 [upload-artifact 官方说明](https://github.com/actions/upload-artifact)。

脚本固定下载 [Godot 官方 4.7.2 发布](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)，并在解压和执行前检查以下官方 SHA256；修改版本时必须同时更换文件名、模板目录和校验值，不能跳过校验。

```text
Godot_v4.7.2-stable_macos.universal.zip
c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e

Godot_v4.7.2-stable_export_templates.tpz
f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011
```

校验值来源：[官方 Release 资产列表](https://github.com/godotengine/godot-builds/releases/expanded_assets/4.7.2-stable)。脚本只安装该模板包内的 `ios.zip` 和单独附带的 ICU 数据；中文字体随游戏一起导出。

## 在自己的 Mac 重现

安装并启动一次 Xcode，完成其许可确认及平台组件安装。将仓库放在路径和工程名称不含空格的位置，然后执行：

```bash
git clone https://github.com/swaggyer/game.git
cd game
bash mobile_game/tools/build_ios.sh
```

输出位于 `mobile_game/builds/ios/`。可选环境变量：

```bash
DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer \
IOS_OUTPUT_DIR="$PWD/mobile_game/builds/ios" \
bash mobile_game/tools/build_ios.sh
```

脚本先运行 Godot 资源导入和 `--export-release "iOS" .../StarLanternIsland.xcodeproj`，再执行以下原生构建形式；项目与 Scheme 由脚本实际生成和查询：

```bash
xcodebuild -project StarLanternIsland.xcodeproj \
  -scheme StarLanternIsland -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER= PROVISIONING_PROFILE= build
```

## iOS 导出配置约定

`export_presets.cfg` 的 iOS preset 名为 `iOS`。关键设置如下，实际配置以仓库文件为准：

| 设置 | 当前值 / 用途 |
| --- | --- |
| `application/export_project_only` | `true`；由独立的 Xcode 步骤编译 |
| `application/app_store_team_id` | `0000000000`；仅满足工程生成字段，**不是真实 Apple Team，不用于签名** |
| `application/bundle_identifier` | `org.starlantern.island`；正式签名时需在自己的 Apple 团队注册并匹配 |
| `application/short_version` | `1.2.1`；不能继承带 `-hud-layout-fix` 后缀的项目描述版本 |
| `application/version` | `13`；后续上传新构建要递增 |
| `application/min_ios_version` | `15.0` |
| `architectures/arm64` | `true`；构建真实设备版本 |
| 导出资源 | 全资源；额外包含动态读取的 `data/*.json` 和美术 manifest JSON |
| 排除资源 | `builds/*,docs/*,tests/*` |

Godot 的签名资料可能写入 `.godot/export_credentials.cfg`，该文件不应提交到 Git。资源筛选与凭证文件说明见 [Godot 项目导出文档](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html)。

## 以后需要安装到 iPhone 时

### 自己的设备，使用 Xcode

1. 在 Mac 解压整个工程 ZIP，保留 `.xcodeproj` 旁的资源和库；用 Xcode 打开 `.xcodeproj`。
2. 在 **Xcode → Settings → Accounts** 登录自己的 Apple Account，在目标的 **Signing & Capabilities** 将占位 Team 替换为自己的 Team，填写自己的唯一 Bundle Identifier，并开启自动签名。
3. 连接并信任 iPhone，按系统要求开启 Developer Mode，选择该设备，使用 Xcode Run 编译和安装。这个过程会重新生成带有效签名的 App，不是直接安装现有 unsigned IPA。
4. 免费账号的 Personal Team 可用于个人设备测试，但描述文件会在短期内过期，需要重新构建。长期测试和分发按 Apple Developer Program 的能力办理。参见 [Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

### Ad Hoc / TestFlight 分发

Ad Hoc 需要 Apple Developer Program、匹配 App ID 的分发证书，以及包含每台测试设备 UDID 的 Ad Hoc 描述文件。TestFlight 需要 App Store Connect 中的 App 记录和签名构建，按其流程上传和邀请测试者；不是公开下载一个 unsigned IPA。具体要求见 [Ad Hoc 官方步骤](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)及 [TestFlight 官方步骤](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

在 Xcode 配置有效签名后，选择真实设备的通用目标，执行 **Product → Archive → Organizer → Distribute App**，再按需要选择测试分发或 App Store Connect。导出选项由当前 Xcode 生成；不要把不同 Xcode 版本的 `ExportOptions.plist` 原样套用。

### 将来给 CI 增加签名时需要的资料

当前工作流没有签名步骤，也不需要现在提供这些资料。维护者以后启用签名时，应使用 GitHub Repository / Environment Secrets：

| 建议 Secret | 所需内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | 导出的 `.p12` 的 Base64；必须同时包含匹配的证书和私钥 |
| `P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `BUILD_PROVISION_PROFILE_BASE64` | 与 Team、Bundle ID、证书及分发方式匹配的 `.mobileprovision` 的 Base64 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串使用的随机密码 |
| `APPLE_TEAM_ID` | 真实的 10 字符 Team ID；属于配置，不是私钥 |

只有 `.cer` 文件不够：私钥通常在创建 CSR 的 Mac 钥匙串中，必须由持有者连同证书一起导出 `.p12`。参见 [Apple CSR 说明](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/)和 [GitHub 官方 Xcode 签名工作流](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。App Store Connect 的 `.p8` API Key、Key ID 和 Issuer ID 可用于后续上传认证，**不代替 App 的代码签名证书和私钥**。这些文件、密码和编码内容都不应进入仓库或普通日志。

## 当前项目兼容性检查与尚待实机验证的内容

源码检查确认：游戏是 GDScript / 2D Compatibility 渲染，资源使用 `res://`、存档使用 `user://`；没有 C#、GDExtension、Windows DLL 或必须依赖 Windows 绝对路径的运行时组件。中文 TTF、PNG、WAV 随项目打包；移动 UI 显式处理触摸和拖动，横屏画布支持比例扩展。动态 JSON 必须保留在导出筛选中。

Mac CI 的绿色构建只能证明导出、链接和封装完成。iPhone / iPad 上还要检查：刘海和 Home 指示条附近的按钮安全区域、多点触控、切入后台后的暂停和音频、中文显示、存档升级，以及地图着色器和大量敌人 / 机关的帧率。当前 UI 没有统一使用 `DisplayServer.get_display_safe_area()`，正式发布前需重点验证长屏设备的边缘控件。发布图标和导出的 `PrivacyInfo.xcprivacy` 也应按最终实际使用审阅。

Windows 工作区无法运行 Xcode；本说明和脚本本身不代表已完成 iOS 真机测试。请以对应 GitHub Actions 运行记录、构建证据与后续设备测试结果为准。
