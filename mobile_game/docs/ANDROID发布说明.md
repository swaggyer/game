# Android 安装包

当前包名 `org.starlantern.island`，版本 1.3.0（versionCode 14），仅包含 arm64-v8a 原生库。最低 Android 7.0（API 24），目标 API 36，由官方预编译模板提供。APK 为 release 导出并使用本机生成的独立密钥签名，可在支持 arm64 的 Android 设备上安装；它不是 Google Play 商店提交用的 AAB。

安装文件：`builds/android/StarLanternIsland-v1.3.0-arm64.apk`。GitHub 发布页也提供同名文件。Android 设备首次从浏览器或文件管理器安装时，需要允许该应用安装未知来源软件。

构建使用 Godot 4.7.2 官方模板、Temurin OpenJDK 17.0.21、Android SDK Platform 35、Build Tools 35.0.1。采用预编译原生模板，不使用自定义 Gradle/native 编译。工具下载已按官方校验值验证。脚本在导出后运行 `apksigner verify`、`zipalign -c -P 16` 和 `aapt dump badging` 检查签名、对齐及 AndroidManifest。

本机重新构建：

```powershell
& 'E:\game\StarLanternIsland\mobile_game\tools\build_android.ps1'
```

本地工具链在 `E:/game/.build-toolchain`，不会提交到仓库。独立签名私钥及密码记录保存在该目录的 `credentials` 子目录，构建脚本会重复使用现有密钥，以便后续版本覆盖安装。请保留该目录的私有备份；不要将私钥、密码或该目录上传到公开仓库。不同签名的同包名应用不能直接覆盖安装。

字体使用 Noto Sans SC 与内嵌符号后备字体，授权及来源位于 `assets/font-license`，APK 中包含这些授权文件。当前已进行桌面原生运行、触控逻辑和 APK 静态校验；尚未进行 Android 真机试玩，设备兼容性以真机验证为准。
