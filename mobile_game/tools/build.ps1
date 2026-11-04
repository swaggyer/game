param([string]$GodotRoot = 'E:\Godot')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$consoleEngine = Join-Path $GodotRoot 'Godot_v4.7.2-stable_win64_console.exe'
$windowEngine = Join-Path $GodotRoot 'Godot_v4.7.2-stable_win64.exe'
$buildRoot = Join-Path $projectRoot 'builds'
$savedAppData = $env:APPDATA
$savedLocalData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $projectRoot 'tests\export_data'
    $env:LOCALAPPDATA = Join-Path $projectRoot 'tests\localdata'
    & $consoleEngine --headless --path $projectRoot --export-pack 'Windows Desktop' (Join-Path $buildRoot 'StarLanternIsland.pck')
    if ($LASTEXITCODE -ne 0) { throw 'Godot resource export failed.' }
    Copy-Item -LiteralPath $windowEngine -Destination (Join-Path $buildRoot 'StarLanternIsland.exe')
    Write-Output 'Portable Windows build ready in builds.'
} finally {
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalData
}
