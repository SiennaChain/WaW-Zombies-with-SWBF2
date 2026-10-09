# Puts a release together: a folder a player unpacks anywhere and runs the
# launcher from, and a zip of it.
#
#   Zombies with Battlefront II.exe   the launcher (tools/launcher)
#   wawbf_launcher.ini                its settings, as the example has them
#   README.txt, Settings.cmd, Uninstall.cmd
#   files\waw\                        -> World at War's folder
#       d3d9.dll, wawbf.ini
#   files\swbf2\                      -> Battlefront II's GameData
#       d3d9.dll, wawbf.ini, addon\WAW\...
#   files\mods\swbf2_<map>\           -> %LOCALAPPDATA%\Activision\CoDWaW\mods
#       mod.ff, weapons\...
#
# The launcher copies "files" into the games the first time it is run from
# there (and again whenever they differ), and takes them out again with
# /uninstall: tools/launcher/main.cpp.
#
# Everything in it is built here, from the repo, by the three builds: cmake
# (the two bridges and the launcher), swbf2\arena\build.ps1 (the arena) and
# waw\mod\build.ps1 (each map's mod). The last two are told to put what they
# make straight into the release and not into the games: nothing is taken
# from whatever happens to be installed on this PC, which may be a test
# set-up, or nothing at all. They need what they always need (the Battlefront
# II mod tools, a dump of World at War's own files); what else they are given
# is theirs to default. -NoBuild skips all three and gathers what the last
# run left.
#
# The two wawbf.ini are the repo's examples, which are kept as what a release
# is installed with. Nothing of a test set-up can come along by accident: the
# settings that would be one are checked for before anything is gathered.
param(
    [string]$Version = 'alpha1',
    [string[]]$Maps = @('nazi_zombie_prototype'),
    [string]$Out = '',
    [switch]$NoBuild,
    [switch]$NoZip
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Out) { $Out = Join-Path $repo 'dist' }
$name = "Zombies-with-Battlefront-II-$Version"
$root = Join-Path $Out $name
# Where the arena and the mods are built to, and gathered from.
$stage = Join-Path $repo 'build\stage'
$addon = Join-Path $stage 'addon\WAW'

if (-not $NoBuild) {
    $cmake = Get-Command cmake -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $cmake) { $cmake = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
    if (-not $cmake) { throw 'cmake was not found; build first and pass -NoBuild' }
    & $cmake --build (Join-Path $repo 'build') --config Release | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'the build failed' }
    if (Test-Path -LiteralPath $stage) { [IO.Directory]::Delete($stage, $true) }
    & (Join-Path $repo 'swbf2\arena\build.ps1') -InstallTo $addon | Select-Object -Last 1
    foreach ($map in $Maps) { & (Join-Path $repo 'waw\mod\build.ps1') -Map $map -InstallTo (Join-Path $stage "mods\swbf2_$map") | Select-Object -Last 1 }
}

function Settings([string]$path) {
    $all = @{}; $section = ''
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $text = $line.Trim()
        if ($text -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
        if ($text -eq '' -or $text.StartsWith(';')) { continue }
        $at = $text.IndexOf('='); if ($at -lt 1) { continue }
        $all["$section.$($text.Substring(0, $at).Trim())"] = $text.Substring($at + 1).Trim()
    }
    $all
}
# What a release must not be installed with, and what it must.
$must = @{
    'waw\wawbf.ini.example'   = @{ 'bridge.without_launcher' = '0'; 'bridge.any_exe' = '0'; 'debug.god_at_start' = '0'; 'debug.console_line' = ''; 'waw.quit_at_menu' = '1'; 'overlay.draw' = '1'; 'window.dpi_aware' = '1' }
    'swbf2\wawbf.ini.example' = @{ 'bridge.without_launcher' = '0'; 'bridge.any_exe' = '0'; 'swbf2.hidden' = '1'; 'swbf2.keep_running' = '1'; 'swbf2.pointer_in_background' = '0'; 'swbf2.devices_in_background' = '0'; 'swbf2.follow' = '1'; 'overlay.publish' = '1'; 'debug.force_buttons' = '0'; 'debug.force_functions' = '0'; 'debug.frame_probe' = '0' }
    'tools\launcher\wawbf_launcher.ini.example' = @{ 'launcher.cheats' = '0'; 'launcher.waw_args' = ''; 'launcher.swbf2_args' = ''; 'launcher.fullscreen' = '1'; 'launcher.width' = '0'; 'launcher.height' = '0'; 'launcher.waw_video' = '1' }
}
foreach ($file in $must.Keys) {
    $have = Settings (Join-Path $repo $file)
    foreach ($key in $must[$file].Keys) {
        if ($have[$key] -ne $must[$file][$key]) { throw "$file has $key = '$($have[$key])'; a release is installed with '$($must[$file][$key])'" }
    }
}

if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
function Put([string]$from, [string]$to) {
    if (-not (Test-Path -LiteralPath $from)) { throw "missing: $from" }
    $dest = Join-Path $root $to
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
    Copy-Item -LiteralPath $from -Destination $dest -Force
}

Put (Join-Path $repo 'build\out\tools\wawbf_launcher.exe') 'Zombies with Battlefront II.exe'
Put (Join-Path $repo 'tools\launcher\wawbf_launcher.ini.example') 'wawbf_launcher.ini'
Put (Join-Path $repo 'tools\launcher\README.txt') 'README.txt'
[IO.File]::WriteAllText((Join-Path $root 'Uninstall.cmd'), "@echo off`r`nstart `"`" `"%~dp0Zombies with Battlefront II.exe`" /uninstall`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $root 'Settings.cmd'), "@echo off`r`nstart `"`" `"%~dp0Zombies with Battlefront II.exe`" /settings`r`n", [Text.Encoding]::ASCII)

Put (Join-Path $repo 'build\out\waw\d3d9.dll') 'files\waw\d3d9.dll'
Put (Join-Path $repo 'waw\wawbf.ini.example') 'files\waw\wawbf.ini'
Put (Join-Path $repo 'build\out\swbf2\d3d9.dll') 'files\swbf2\d3d9.dll'
Put (Join-Path $repo 'swbf2\wawbf.ini.example') 'files\swbf2\wawbf.ini'

# The arena.
if (-not (Test-Path -LiteralPath (Join-Path $addon 'addme.script'))) { throw "the arena is not built: no $addon\addme.script (run this without -NoBuild)" }
foreach ($file in Get-ChildItem -LiteralPath $addon -Recurse -File) { Put $file.FullName ('files\swbf2\addon\WAW' + $file.FullName.Substring($addon.Length)) }

# Each map's mod: mod.ff and the weapon files beside it.
foreach ($map in $Maps) {
    $mod = Join-Path $stage "mods\swbf2_$map"
    if (-not (Test-Path -LiteralPath (Join-Path $mod 'mod.ff'))) { throw "the mod for $map is not built: no $mod\mod.ff (run this without -NoBuild)" }
    foreach ($file in Get-ChildItem -LiteralPath $mod -Recurse -File) { Put $file.FullName ("files\mods\swbf2_$map" + $file.FullName.Substring($mod.Length)) }
}

$files = Get-ChildItem -LiteralPath $root -Recurse -File
'{0}: {1} files, {2:N1} MB' -f $root, $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB)
if (-not $NoZip) {
    $zip = Join-Path $Out "$name.zip"
    if (Test-Path -LiteralPath $zip) { [IO.File]::Delete($zip) }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($root, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
    '{0}: {1:N1} MB' -f $zip, ((Get-Item -LiteralPath $zip).Length / 1MB)
}
