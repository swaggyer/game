param(
    [string]$GodotRoot = 'E:\Godot',
    [string]$ToolchainRoot = 'E:\game\.build-toolchain'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $GodotRoot 'Godot_v4.7.2-stable_win64_console.exe'
$javaRoot = (Get-ChildItem -LiteralPath (Join-Path $ToolchainRoot 'jdk') -Directory | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe')} | Select-Object -First 1).FullName
if (-not $javaRoot) {throw 'A complete OpenJDK 17 is required.'}
$sdkRoot = Join-Path $ToolchainRoot 'android-sdk'
$buildTools = Join-Path $sdkRoot 'build-tools\35.0.1'
foreach ($required in @($engine,(Join-Path $javaRoot 'bin\keytool.exe'),(Join-Path $buildTools 'apksigner.bat'),(Join-Path $buildTools 'zipalign.exe'),(Join-Path $sdkRoot 'platform-tools\adb.exe'))) {
    if (-not (Test-Path -LiteralPath $required)) {throw "Missing build tool: $required"}
}
$credentialsRoot = Join-Path $ToolchainRoot 'credentials'
New-Item -ItemType Directory -Force -Path $credentialsRoot | Out-Null
$credentialsPath = Join-Path $credentialsRoot 'starlantern-android-signing.json'
if (-not (Test-Path -LiteralPath $credentialsPath)) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $taskRandom = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $taskPassword = -join ($taskRandom | ForEach-Object {$alphabet[$_ % $alphabet.Length]})
    $signing = @{keystore=(Join-Path $credentialsRoot 'starlantern-android-release.jks');alias='starlantern';password=$taskPassword}
    & (Join-Path $javaRoot 'bin\keytool.exe') -genkeypair -keystore $signing.keystore -alias $signing.alias -keyalg RSA -keysize 2048 -validity 10000 -storepass $signing.password -keypass $signing.password -dname 'CN=Star Lantern Island, OU=Mobile Game, O=Star Lantern Island' -storetype PKCS12
    if ($LASTEXITCODE -ne 0) {throw 'Could not create Android signing key.'}
    [System.IO.File]::WriteAllText($credentialsPath,($signing | ConvertTo-Json),[System.Text.UTF8Encoding]::new($false))
}
$signing = Get-Content -LiteralPath $credentialsPath -Raw | ConvertFrom-Json
$env:JAVA_HOME = $javaRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$env:ANDROID_USER_HOME = Join-Path $ToolchainRoot 'android-user'
$env:PATH = (Join-Path $javaRoot 'bin')+';'+$env:PATH
$env:APPDATA = Join-Path $ToolchainRoot 'godot-data'
$env:LOCALAPPDATA = Join-Path $ToolchainRoot 'godot-local'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $signing.keystore
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $signing.alias
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $signing.password
$settingsRoot = Join-Path $env:APPDATA 'Godot'
New-Item -ItemType Directory -Force -Path $settingsRoot | Out-Null
$settings = '[gd_resource type="EditorSettings" format=3]'+"`n`n[resource]`n"+'export/android/java_sdk_path = "'+$javaRoot.Replace('\','/')+'"'+"`n"+'export/android/android_sdk_path = "'+$sdkRoot.Replace('\','/')+'"'+"`n"
[System.IO.File]::WriteAllText((Join-Path $settingsRoot 'editor_settings-4.7.tres'),$settings,[System.Text.UTF8Encoding]::new($false))
$outputRoot = Join-Path $projectRoot 'builds\android'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$apk = Join-Path $outputRoot 'StarLanternIsland-v1.5.0-arm64.apk'
try {
    & $engine --headless --audio-driver Dummy --editor --path $projectRoot --import --quit
    if ($LASTEXITCODE -ne 0) {throw 'Android asset import failed.'}
    & $engine --headless --audio-driver Dummy --path $projectRoot --export-release Android $apk
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $apk)) {throw 'Android APK export failed.'}
    & (Join-Path $buildTools 'apksigner.bat') verify --verbose --print-certs $apk
    if ($LASTEXITCODE -ne 0) {throw 'APK signature verification failed.'}
    & (Join-Path $buildTools 'zipalign.exe') -c -P 16 -v 4 $apk
    if ($LASTEXITCODE -ne 0) {throw 'APK alignment verification failed.'}
    & (Join-Path $buildTools 'aapt.exe') dump badging $apk
    if ($LASTEXITCODE -ne 0) {throw 'APK manifest validation failed.'}
    Get-FileHash -LiteralPath $apk -Algorithm SHA256 | Format-List
} finally {
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
}
