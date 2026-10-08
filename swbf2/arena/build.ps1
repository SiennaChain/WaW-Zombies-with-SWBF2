# Builds the arena map with your own copy of the Battlefront II mod tools and
# installs it into the game as an addon.
#
# Nothing of Battlefront's is kept in this repository. The world itself (the
# terrain, sky and command posts) is the mod tools' blank template; this
# script lays out a project from it the way the tools' own "new world" step
# does, drops in the scripts from this folder (the rosters, what they share,
# and the one that registers the map), compiles ("munges") it, and copies the
# result to GameData\addon\WAW.
#
# The project lives in <mod tools>\data_WAW. -Fresh throws it away first.
# The game has to be restarted to see a new or changed addon.
#
# -AutoStart says which roster the game goes straight into once its main menu
# is reached, with no map to pick: gcw (Empire and Alliance, the default), cw
# (Republic and Separatists) or heroes (every hero and villain). With "none"
# the game stays at its menu and the arena is picked from Instant Action like
# any map. While it starts by itself there is no getting to the menu: quitting
# the mission starts it again. Rebuild with "none" for that.
param(
    [string]$ModTools = 'C:\BF2_ModTools',
    [string]$GameData = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData',
    [ValidateSet('gcw', 'cw', 'heroes', 'none')][string]$AutoStart = 'gcw',
    [switch]$Fresh,
    [switch]$NoInstall
)
$ErrorActionPreference = 'Stop'
$Id = 'WAW'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $ModTools "data_$Id"
$template = Join-Path $ModTools 'TEMPLATE'
$latin1 = [Text.Encoding]::GetEncoding(28591)
foreach ($need in (Join-Path $ModTools 'data\_BUILD\munge.bat'), $template, (Join-Path $ModTools 'ToolsFL\bin\LevelPack.exe')) {
    if (-not (Test-Path -LiteralPath $need)) { throw "not a Battlefront II mod tools install: $need is missing" }
}

function Write-Text([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
    [IO.File]::WriteAllBytes($path, $latin1.GetBytes($text))
}

if ($Fresh -and (Test-Path -LiteralPath $proj)) {
    if ((Split-Path -Leaf $proj) -ne "data_$Id") { throw "refusing to delete $proj" }
    Remove-Item -LiteralPath $proj -Recurse -Force -Confirm:$false
}

if (-not (Test-Path -LiteralPath $proj)) {
    "laying out the project in $proj"
    # The tools' own data folder is the base of every project: build scripts, shared scripts, config.
    robocopy (Join-Path $ModTools 'data') $proj /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying the mod tools' data folder failed (robocopy $LASTEXITCODE)" }
    # The stock missions' lists came along with it; their scripts did not, so they would only fail to pack.
    Get-ChildItem -LiteralPath (Join-Path $proj 'Common\mission') -Filter *.req | Remove-Item -Force -Confirm:$false

    # The template world, with its "@#$" placeholder filled in. Its files are kept flat in world1,
    # as the stock worlds are: the packer does not look in subfolders for .req and .mrq files.
    $binary = '.tga', '.msh', '.ter'
    foreach ($file in Get-ChildItem -LiteralPath $template -Recurse -File) {
        $rel = $file.FullName.Substring($template.Length + 1)
        if ($file.Extension -eq '.bak' -or $rel -like 'addme\*' -or $rel -like 'Common\*') { continue }   # ours replace these
        if ($rel -like 'Worlds\@#$\_BUILD\*') { $dest = Join-Path $proj "_BUILD\Worlds\$Id\$($file.Name)" }
        elseif ($rel -like 'Worlds\@#$\world1\*') { $dest = Join-Path $proj "Worlds\$Id\world1\$($file.Name.Replace('@#$', $Id))" }
        else { $dest = Join-Path $proj $rel.Replace('@#$', $Id) }
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
        if ($binary -contains $file.Extension.ToLower()) { Copy-Item -LiteralPath $file.FullName -Destination $dest -Force; continue }
        $text = $latin1.GetString([IO.File]::ReadAllBytes($file.FullName)).Replace('@#$', $Id)
        if ($rel -like 'Worlds\@#$\_BUILD\munge.bat') { $text = "@call ..\munge_world.bat $Id %1`r`n" }
        # The template's world list stops after "lvl" for the tool to finish: the layers to pack.
        if ($file.Name -eq '@#$.req') { $text = $text.TrimEnd() + "`r`n`t`t`"${Id}_conquest`"`r`n`t`t`"${Id}_ctf`"`r`n`t`t`"${Id}_1flag`"`r`n`t`t`"${Id}_eli`"`r`n`t}`r`n}`r`n" }
        Write-Text $dest $text
    }
}

# The tools merge the localization files with "more", which hands back nothing
# when there is no console to page on. The strings then come out empty, the
# core level fails to pack, and everything after it fails for want of it.
# "type" does the same job. Only this project's copy of the script is changed.
$merge = Join-Path $proj '_BUILD\Common\MergeLocalize.bat'
$mergeText = $latin1.GetString([IO.File]::ReadAllBytes($merge))
if ($mergeText -match '(?m)^\s*more %%i') { Write-Text $merge ($mergeText -replace '(?m)^(\s*)more %%i', '$1type %%i') }

# The tools' own string files are each one closing bracket short, and the
# string compiler rejects them outright ("No matching bracket"). With no
# strings the core level does not pack, and without the list of what is in
# the core level nothing else packs either: that is how a missing bracket in
# french.cfg leaves the map file empty. The bracket is added to this
# project's copies.
foreach ($cfg in Get-ChildItem -LiteralPath (Join-Path $proj 'Common\Localize') -Filter *.cfg) {
    $text = $latin1.GetString([IO.File]::ReadAllBytes($cfg.FullName))
    $short = ($text.Split('{').Count) - ($text.Split('}').Count)
    if ($short -gt 0) { Write-Text $cfg.FullName ($text.TrimEnd() + "`r`n" + ('}' * $short) + "`r`n") }
}

# Ours: the rosters (one mission each) with the script they share, the list of
# missions to pack, and the script that registers the map and can start it.
$missions = [ordered]@{ gcw = "${Id}g_con"; cw = "${Id}c_con"; heroes = "${Id}g_eli" }
$scripts = New-Item -ItemType Directory -Force -Path (Join-Path $proj "Common\scripts\$Id")
Copy-Item -LiteralPath (Join-Path $here 'WAW_arena.lua') -Destination $scripts -Force
foreach ($mission in $missions.Values) {
    Copy-Item -LiteralPath (Join-Path $here "$mission.lua") -Destination $scripts -Force
    Write-Text (Join-Path $proj "Common\mission\$mission.req") "ucft`r`n{`r`n`tREQN`r`n`t{`r`n`t`t`"config`"`r`n`t`t`"cor_movies`"`r`n`t}`r`n`r`n`tREQN`r`n`t{`r`n`t`t`"script`"`r`n`t`t`"WAW_arena`"`r`n`t`t`"$mission`"`r`n`t}`r`n}`r`n"
}
$missionReq = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $template 'Common\mission.req'))).TrimEnd()
Write-Text (Join-Path $proj 'Common\mission.req') ($missionReq + "`r`n" + (($missions.Values | ForEach-Object { "        `"$_`"`r`n" }) -join '') + "    }`r`n}`r`n")
$start = if ($AutoStart -eq 'none') { '' } else { $missions[$AutoStart] }
Write-Text (Join-Path $proj 'addme\addme.lua') ([IO.File]::ReadAllText((Join-Path $here 'addme.lua'), $latin1).Replace('@AUTO_START@', $start))
"rosters: $($missions.Values -join ', '); starts by itself: $(if ($start) { $start } else { 'no' })"

# A pack that fails still leaves an empty 8-byte level behind. The tools go
# by file dates, take it for up to date and never try again, so every later
# pack that needed its list of contents fails too. Clear those out first.
foreach ($dir in (Join-Path $proj '_LVL_PC'), (Join-Path $proj '_BUILD')) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Recurse -Filter *.lvl | Where-Object { $_.Length -le 8 } | ForEach-Object {
        [IO.File]::Delete($_.FullName); if (Test-Path -LiteralPath "$($_.FullName).req") { [IO.File]::Delete("$($_.FullName).req") }
    }
}

# Compile. /NOMESSAGES stops the tools opening Notepad on their log.
"munging (the first time takes a few minutes: it compiles the tools' whole common folder)"
$build = Join-Path $proj '_BUILD'
$log = Join-Path $build 'PC_MungeLog.txt'
$sw = [Diagnostics.Stopwatch]::StartNew()
# The tools' batch files are from 2005 and need two things of the shell they
# run in, both arranged here for this one command prompt and put back after:
#
# - They paste %PATH% inside bracketed "if ( ... )" blocks. A PATH with a
#   bracket in it, and "C:\Program Files (x86)\..." is in most, ends the
#   block early and the whole script dies with "\Common was unexpected at
#   this time". So they get a PATH of just Windows and their own programs.
#   (A mod tools folder with a bracket in its own path would hit the same.)
# - They call each other by bare name from their own folders, which a shell
#   set not to run programs from the current folder
#   (NoDefaultCurrentDirectoryInExePath) refuses to do.
$toolsBin = Join-Path $ModTools 'ToolsFL\bin'
$saved = @{ PATH = $env:PATH; NoDefaultCurrentDirectoryInExePath = $env:NoDefaultCurrentDirectoryInExePath; MUNGE_BIN_DIR = $env:MUNGE_BIN_DIR }
Push-Location $build
try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot;$toolsBin"
    $env:NoDefaultCurrentDirectoryInExePath = $null
    $env:MUNGE_BIN_DIR = $toolsBin
    cmd /c ".\munge.bat /WORLD $Id /COMMON /NOMESSAGES > munge_output.txt 2>&1"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { Set-Item -Path "env:$name" -Value $saved[$name] }
}
"munge finished in {0:N0} s" -f $sw.Elapsed.TotalSeconds
if (Test-Path -LiteralPath $log) {
    $problems = Get-Content -LiteralPath $log | Where-Object { $_ -match 'ERROR|WARNING' }
    "{0} lines in the munge log mention an error or a warning" -f @($problems).Count
    $problems | Where-Object { $_ -match $Id -or $_ -match 'mission' } | Select-Object -First 20 | ForEach-Object { "  $_" }
}

Push-Location (Join-Path $proj 'addme')
try {
    if (-not (Test-Path munged)) { [void](New-Item -ItemType Directory munged) }
    & (Join-Path $ModTools 'ToolsFL\bin\ScriptMunge.exe') -sourcedir . -platform pc -inputfile addme.lua -outputdir munged\ -continue | Out-Null
} finally { Pop-Location }

$outputs = [ordered]@{
    (Join-Path $proj 'addme\munged\addme.script') = 'addme.script'
    (Join-Path $proj '_LVL_PC\mission.lvl')       = 'data\_LVL_PC\mission.lvl'
    (Join-Path $proj "_LVL_PC\$Id\$Id.lvl")       = "data\_LVL_PC\$Id\$Id.lvl"
}
$missing = @($outputs.Keys | Where-Object { -not (Test-Path -LiteralPath $_) })
foreach ($o in $outputs.Keys) { if (Test-Path -LiteralPath $o) { '  built {0,12:N0} bytes  {1}' -f (Get-Item -LiteralPath $o).Length, $o } else { "  MISSING  $o" } }
if ($missing.Count) { throw "the munge did not produce everything; see $log and $build\munge_output.txt" }

if (-not $NoInstall) {
    $addon = Join-Path $GameData "addon\$Id"
    foreach ($o in $outputs.Keys) {
        $dest = Join-Path $addon $outputs[$o]
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
        Copy-Item -LiteralPath $o -Destination $dest -Force
    }
    "installed to $addon (restart Battlefront II to pick it up)"
}
