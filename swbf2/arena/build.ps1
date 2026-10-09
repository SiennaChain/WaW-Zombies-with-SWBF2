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
#
# The arena draws nothing: no ground, no sky. Whatever Battlefront then puts
# in its picture is the player's (their character, weapon and shots, and what
# is left of the HUD) and the whole picture can be laid over World at War's.
# -Ground builds the template's grass and sky back in, for looking at the game
# on its own.
#
# Of the HUD only the weapons and abilities are left, raised by -HudLift (a
# part of the screen's height) to clear World at War's round number. -FullHud
# keeps the game's own HUD where it is.
param(
    [string]$ModTools = 'C:\BF2_ModTools',
    [string]$GameData = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData',
    [ValidateSet('gcw', 'cw', 'heroes', 'none')][string]$AutoStart = 'gcw',
    [switch]$Ground,
    [double]$HudLift = 0.17,
    # Where the word that says a weapon has overheated goes (across, down; parts of the screen):
    # above the weapons, inside what wawbf.ini's hud_keep leaves of the HUD.
    [double[]]$OverheatAt = @(0.165, 0.572),
    [switch]$FullHud,
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

# The string tables. Each is rebuilt from the tools' own copy every time, with
# two changes:
#
# - The tools' files are each one closing bracket short, and the string
#   compiler rejects them outright ("No matching bracket"). With no strings
#   the core level does not pack, and without the list of what is in the core
#   level nothing else packs either: that is how a missing bracket in
#   french.cfg leaves the map file empty. The bracket is added.
# - The arena's own text (strings.txt) is appended, as one more block per
#   key; the compiler merges blocks.
#
# A string is stored as four bytes (a small counter the tools keep; 1 here)
# and then UTF-16, written out in hex with the two digits of every byte
# swapped, 32 bytes to a line.
function ConvertTo-LocBlock([string]$key, [string]$text) {
    $bytes = [byte[]](1, 0, 0, 0) + [Text.Encoding]::Unicode.GetBytes($text)
    $hex = -join ($bytes | ForEach-Object { $h = $_.ToString('X2'); $h[1] + $h[0] })
    $parts = $key.Split('.'); $lines = New-Object Collections.Generic.List[string]
    $lines.Add('DataBase()'); $lines.Add('{')
    for ($i = 0; $i -lt $parts.Count - 1; $i++) { $pad = '  ' * ($i + 1); $lines.Add("${pad}VarScope(`"$($parts[$i])`")"); $lines.Add("${pad}{") }
    $pad = '  ' * $parts.Count
    $lines.Add("${pad}VarBinary(`"$($parts[-1])`")"); $lines.Add("${pad}{"); $lines.Add("${pad}  Size($($bytes.Count));")
    for ($o = 0; $o -lt $hex.Length; $o += 64) { $lines.Add("${pad}  Value(`"$($hex.Substring($o, [Math]::Min(64, $hex.Length - $o)))`");") }
    $lines.Add("${pad}}")
    for ($i = $parts.Count - 2; $i -ge 0; $i--) { $lines.Add(('  ' * ($i + 1)) + '}') }
    $lines.Add('}')
    ($lines -join "`r`n") + "`r`n"
}
$ours = ''
foreach ($line in Get-Content -LiteralPath (Join-Path $here 'strings.txt') -Encoding UTF8) {
    if ($line -match '^\s*([A-Za-z0-9_.]+)\s*=\s*(.*)$') { $ours += ConvertTo-LocBlock $Matches[1] ($Matches[2].Trim().Replace('\n', "`r`n")) }
}
foreach ($cfg in Get-ChildItem -LiteralPath (Join-Path $ModTools 'data\Common\Localize') -Filter *.cfg) {
    $text = $latin1.GetString([IO.File]::ReadAllBytes($cfg.FullName))
    $short = ($text.Split('{').Count) - ($text.Split('}').Count)
    if ($short -gt 0) { $text = $text.TrimEnd() + "`r`n" + ('}' * $short) + "`r`n" }
    if ($cfg.BaseName -ne 'Comments') { $text += $ours }
    Write-Text (Join-Path $proj "Common\Localize\$($cfg.Name)") $text
}

# The world. Rewritten from the template every time, so that -Ground and its
# absence both get what they ask for and a file is only touched (and so only
# recompiled) when it comes out different.
#
# Without -Ground, four things are done so that nothing but the player is
# drawn:
#
# - The terrain is kept, because every world the tools know has one, but its
#   "active" square (the part that is compiled, drawn and stood on) is cut
#   down to eight cells. It cannot be none: with no terrain switched on the
#   game loads and will not put the player into the world. And it is not out
#   of sight: the game draws whatever is active at the middle of the world,
#   wherever in the grid it was taken from, 230 m from where the player
#   stands, where 64 m of grass seen edge-on was an olive line a quarter of
#   the screen wide on the horizon. The bridge leaves that one strip of
#   triangles out of the picture ([overlay] hide_ground in wawbf.ini).
# - The player stands instead on the game's own invisible collision blocks
#   (com_inv_col_64: a 64 m cube, its corner at the object's position), laid
#   as a floor with their tops at height 0 around where the player appears.
# - The sky file loses its dome, and its fog is pushed out to where nothing
#   is.
# - The command posts, which glow, go to the same far corner. Nothing uses
#   them: the mission script puts the player in the world from a path.
$world = Join-Path $proj "Worlds\$Id\world1"
$templateWorld = Join-Path $template 'Worlds\@#$\world1'
function Read-Template([string]$name) { $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $templateWorld $name))).Replace('@#$', $Id) }
function Write-IfChanged([string]$path, [string]$text) {
    if ((Test-Path -LiteralPath $path) -and $latin1.GetString([IO.File]::ReadAllBytes($path)) -ceq $text) { return }
    Write-Text $path $text
}
$wld = Read-Template '@#$.wld'
$sky = Read-Template '@#$.sky'
$conquest = Read-Template 'modes\conquest\@#$_conquest.lyr'
$terHead = New-Object byte[] 16
$fs = [IO.File]::OpenRead((Join-Path $templateWorld '@#$.TER')); [void]$fs.Read($terHead, 0, 16); $fs.Close()
$active = [byte[]]$terHead[8..15]                       # four 16-bit cell numbers: left, top, right, bottom
if (-not $Ground) {
    $active = [byte[]](@(120, 120, 128, 128) | ForEach-Object { [BitConverter]::GetBytes([int16]$_) })
    $centre = -218, 133; $tiles = 5; $size = 64         # the floor: 5 x 5 blocks around where cp1's spawn path is
    $floor = ''; $n = 0
    for ($i = 0; $i -lt $tiles; $i++) {
        for ($j = 0; $j -lt $tiles; $j++) {
            $n++; $x = $centre[0] + ($i - $tiles / 2) * $size; $z = $centre[1] + ($j - $tiles / 2 + 1) * $size
            $floor += "`r`nObject(`"waw_floor_$n`", `"com_inv_col_64`", $(900000 + $n))`r`n{`r`n`tChildRotation(1.000, 0.000, 0.000, 0.000);`r`n`tChildPosition($('{0:F3}, {1:F3}, {2:F3}' -f $x, (-$size), $z));`r`n`tSeqNo($(900000 + $n));`r`n`tTeam(0);`r`n`tNetworkId(-1);`r`n}`r`n"
        }
    }
    $wld = $wld.TrimEnd() + "`r`n" + $floor
    $sky = [regex]::Replace($sky, '(?s)DomeInfo\(\)\s*\{.*\}\s*$', '')
    $sky = [regex]::Replace($sky, '(?m)^(\s*)FogRange\(-100\.0, 600\.0\);', '$1FogRange(4990.0, 5000.0);')
    # And nothing is drawn beyond a kilometre: the command posts are four away.

    $sky = [regex]::Replace($sky, 'FarSceneRange\(5000\.0, 5000\.0\);', 'FarSceneRange(1000.0, 1000.0);')
    $sky = [regex]::Replace($sky, 'FarSceneRange\(5000\.0\);', 'FarSceneRange(1000.0);')
    $cp = 0
    $conquest = [regex]::Replace($conquest, '(Object\("cp\d+", "com_bldg_controlzone", -?\d+\)\s*\{\s*ChildRotation\([^)]*\);\s*ChildPosition\()[^)]*\)', {
        param($m) $script:cp++; $m.Groups[1].Value + ('{0:F3}, 0.000, 4000.000)' -f (4000 + 16 * $script:cp)) })
    if ($cp -eq 0) { throw 'the template''s command posts were not where this script looks for them' }
}
Write-IfChanged (Join-Path $world "$Id.wld") $wld
Write-IfChanged (Join-Path $world "$Id.sky") $sky
Write-IfChanged (Join-Path $world "${Id}_conquest.lyr") $conquest
$ter = Join-Path $world "$Id.TER"
$fs = [IO.File]::Open($ter, 'Open', 'ReadWrite')
try {
    $now = New-Object byte[] 8; [void]$fs.Seek(8, 'Begin'); [void]$fs.Read($now, 0, 8)
    if (-not [Linq.Enumerable]::SequenceEqual($now, $active)) { [void]$fs.Seek(8, 'Begin'); $fs.Write($active, 0, 8) }
} finally { $fs.Close() }
"world: $(if ($Ground) { 'the template''s ground and sky' } else { 'nothing drawn; an invisible floor of ' + ($tiles * $tiles) + ' blocks' })"

# The HUD. The picture laid over World at War is the player's character,
# weapon and shots, and of this game's HUD only what says which weapon and
# which ability are in hand: World at War shows its own health, round, points
# and crosshair. The HUD is laid out in a text file, one block for each part
# of it, each with a place on the screen. The block for the weapons is kept
# and raised (-HudLift, as a part of the screen's height: World at War's round
# number is in the corner under it, and it has to clear the game's own block,
# which is still there below it); every other block is given a place far off
# the screen, where it is still there for the game to switch on and off but
# is never drawn. The file is the tools' own, changed here every time, and
# packed into this add-on's ingame.lvl, which the mission script reads before
# the game's. The game's own HUD is then still drawn as well; the bridge
# keeps all of it but the place of our weapons out of the picture
# ([overlay] hud_keep in wawbf.ini, which has to agree with -HudLift).
# -FullHud leaves the file as it was.
$hudFile = 'Common\hud\PC\1playerhud.hud'
$hud = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $ModTools "data\$hudFile")))
if (-not $FullHud) {
    $block = ''; $placed = $true; $hidden = 0; $raised = 0; $moved = 0
    $hudLines = $hud -split "`r?`n"
    for ($i = 0; $i -lt $hudLines.Count; $i++) {
        if ($hudLines[$i] -match '^(\w+)\("([^"]+)"\)') { $block = $Matches[2]; $placed = ($Matches[1] -eq 'FileInfo'); continue }
        if ($placed) { continue }
        # a child's own block begins: this one had no place of its own
        if ($hudLines[$i] -match '^\s+\w+\("[^"]*"\)\s*$' -and $i + 1 -lt $hudLines.Count -and $hudLines[$i + 1] -match '^\s+\{') { $placed = $true; continue }
        if ($hudLines[$i] -match '^(\s+)Position\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*"Viewport"\s*\)') {
            $placed = $true
            if ($block -eq 'player1weaponinformation') {
                $hudLines[$i] = '{0}Position({1}, {2:F6}, {3}, "Viewport")' -f $Matches[1], $Matches[2], ([double]$Matches[3] - $HudLift), $Matches[4]; $raised++
            } elseif ($block -eq 'player1weapon1overheat') {
                # The word that comes up when a weapon has overheated. The game has it low in the
                # middle of the screen; here it goes just above the weapons, inside the part of
                # the HUD that is kept.
                $hudLines[$i] = '{0}Position({1:F6}, {2:F6}, {3}, "Viewport")' -f $Matches[1], $OverheatAt[0], $OverheatAt[1], $Matches[4]; $moved++
            } else {
                $hudLines[$i] = '{0}Position(-10.000000, -10.000000, {1}, "Viewport")' -f $Matches[1], $Matches[4]; $hidden++
            }
        }
    }
    if ($raised -ne 1 -or $moved -ne 1 -or $hidden -lt 30) { throw "the HUD file is not laid out as this script expects (raised $raised, moved $moved, hidden $hidden)" }
    $hud = $hudLines -join "`r`n"
    "HUD: the weapons raised by $HudLift of the screen, the overheating warning put above them, $hidden other parts put off the screen"
} else { 'HUD: the game''s own' }
Write-IfChanged (Join-Path $proj $hudFile) $hud

# The Clone Wars troopers' weapons, in a roster that also has the Empire's and
# the Alliance's. The game takes in one era's bank of recordings for a mission
# and no second one (docs/PHASE3.md has the measurements), so with the other
# era's read, a clone's rifle and a battle droid's are silent. A small bank of
# our own, read first, is taken in as well: it holds just those weapons'
# firing sounds, under the names the weapons ask for.
#
# The tools have everything to build a bank but the recordings. The game has
# those: every era's bank draws on one file, common.bnk, which begins with a
# table (for each recording a name, as a hash, its rate and its length) and
# then holds them one after another, 16 bits a point, one channel. The ones
# wanted are copied out of it as .wav files for the tools to pack.
$ownSounds = [ordered]@{          # what a weapon asks for = the recording it plays
    rep_weap_inf_rifle_fire           = 'wpn_rep_blaster_fire'
    rep_weap_inf_pistol_fire          = 'wpn_rep_pistol_fire'
    cis_weap_inf_rifle_fire           = 'wpn_cis_blaster_fire'
    cis_weap_inf_rocket_launcher_fire = 'wpn_cis_rcktlauncher_fire'
}
$soundDir = Join-Path $proj "Sound\worlds\$Id"
$bankFile = Join-Path $GameData 'data\_lvl_pc\sound\common.bnk'
if (-not (Test-Path -LiteralPath $bankFile)) { throw "the game's recordings are not where this script looks for them: $bankFile" }
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO; using System.Text;
public static class WawBank {
    public static uint Hash(string s) { uint h = 0x811C9DC5; foreach (char c in s) h = (h ^ (uint)(c | 0x20)) * 0x01000193; return h; }
    // Writes each of `names` found in the bank as <folder>\<name>.wav; returns those it wrote.
    public static List<string> Copy(string bank, string[] names, string folder) {
        var wanted = new Dictionary<uint, string>(); foreach (string n in names) wanted[Hash(n)] = n;
        var wrote = new List<string>();
        using (var f = File.OpenRead(bank)) {
            var r = new BinaryReader(f); f.Position = 24;
            long header = -1, at = 0; uint name = 0; int rate = 0, bytes = 0; bool inSample = false;
            var found = new List<object[]>();
            while (f.Position + 8 <= f.Length && found.Count < wanted.Count) {
                uint key = r.ReadUInt32(), value = r.ReadUInt32();
                if (key == 0x0FB40705) header = value;                        // how long the table is
                else if (key == 0x37386AE0) { name = value; inSample = true; } // a recording: its name
                else if (inSample && key == 0x2FB31C01) rate = (int)value;     // points a second
                else if (inSample && key == 0x23A0D95C) bytes = (int)value;    // its length
                else if (inSample && key == 0x809608B6) {                      // the last thing said of each
                    if (wanted.ContainsKey(name)) found.Add(new object[] { wanted[name], rate, bytes, at });
                    at += bytes; inSample = false;
                }
                else if (key != 0x8D39BDE6 && key != 0xB99D8552 && key != 0x98B889CE && key != 0x23A0D95C && key != 0x694AAA0B &&
                         key != 0x8EBF7143 && key != 0x2E789FB4 && key != 0x1D48FEEF) break;   // not the table any more
            }
            long start = 40 + header;
            if (header <= 0 || start % 2048 != 0) throw new InvalidDataException("common.bnk is not laid out as expected");
            foreach (object[] one in found) {
                var data = new byte[(int)one[2]]; f.Position = start + (long)one[3];
                if (f.Read(data, 0, data.Length) != data.Length) throw new InvalidDataException("common.bnk ends early");
                using (var o = new BinaryWriter(File.Create(Path.Combine(folder, (string)one[0] + ".wav")))) {
                    o.Write(Encoding.ASCII.GetBytes("RIFF")); o.Write(36 + data.Length); o.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); o.Write(16);
                    o.Write((short)1); o.Write((short)1); o.Write((int)one[1]); o.Write((int)one[1] * 2); o.Write((short)2); o.Write((short)16);
                    o.Write(Encoding.ASCII.GetBytes("data")); o.Write(data.Length); o.Write(data);
                }
                wrote.Add((string)one[0]);
            }
        }
        return wrote;
    }
}
'@
$effects = Join-Path $soundDir 'effects'
if (-not (Test-Path -LiteralPath $effects)) { [void](New-Item -ItemType Directory -Path $effects -Force) }
$copied = [WawBank]::Copy($bankFile, [string[]]@($ownSounds.Values), $effects)
$lost = @($ownSounds.Values | Where-Object { $copied -notcontains $_ })
if ($lost.Count) { throw "not found in the game's recordings: $($lost -join ', ')" }
$bank = "$($Id.ToLower())cw"
Write-IfChanged (Join-Path $soundDir "$($Id.ToLower()).req") "ucft`r`n{`r`n    REQN`r`n    {`r`n        `"lvl`"`r`n        `"$bank`"`r`n    }`r`n}`r`n"
Write-IfChanged (Join-Path $soundDir "$bank.req") "ucft`r`n{`r`n    REQN`r`n    {`r`n        `"bnk`"`r`n        `"align=2048`"`r`n        `"$bank`"`r`n    }`r`n    REQN`r`n    {`r`n        `"config`"`r`n        `"$bank`"`r`n    }`r`n}`r`n"
Write-IfChanged (Join-Path $soundDir "$bank.sfx") ((($ownSounds.Values | ForEach-Object { "effects\$_.wav -resample xbox 22050 pc 44100`r`n" }) -join ''))
Write-IfChanged (Join-Path $soundDir "$bank.snd") ((($ownSounds.Keys | ForEach-Object { "SoundProperties()`r`n{`r`n    Name(`"$_`");`r`n    Group(`"weapons`");`r`n    Inherit(`"weapon_template`");`r`n    SampleList()`r`n    {`r`n        Sample(`"$($ownSounds[$_])`", 1.0);`r`n    }`r`n}`r`n`r`n" }) -join ''))
"sounds: $($copied.Count) recordings copied out of the game's for a bank of our own ($bank)"

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
    # The bank of our own: the tools' script for one folder of sound, which packs the recordings,
    # compiles the definitions and makes the level file. It is run from the project's own folder
    # and finds its programs from there.
    $lower = $Id.ToLower()
    $stale = Join-Path $proj "_LVL_PC\sound\$lower.lvl"
    if (Test-Path -LiteralPath $stale) { [IO.File]::Delete($stale) }
    Set-Location $proj
    foreach ($pair in @{ MUNGE_LANGVERSION = 'English'; MUNGESTREAMS = '0'; SOUNDLOG = '1'; SOUNDNODATECHECK = '1'; MUNGE_LOG = $log }.GetEnumerator()) { Set-Item -Path "env:$($pair.Key)" -Value $pair.Value }
    cmd /c "soundmungedir.bat _BUILD\sound\worlds\$lower\MUNGED\PC sound\worlds\$lower sound\worlds\$lower\PC PC _BUILD _LVL_PC\sound _BUILD\sound $lower > _BUILD\soundmunge_output.txt 2>&1"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { Set-Item -Path "env:$name" -Value $saved[$name] }
    foreach ($name in 'MUNGE_LANGVERSION', 'MUNGESTREAMS', 'SOUNDLOG', 'SOUNDNODATECHECK', 'MUNGE_LOG') { Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue }
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
    (Join-Path $proj '_LVL_PC\core.lvl')          = 'data\_LVL_PC\core.lvl'      # the text: see strings.txt
    (Join-Path $proj '_LVL_PC\ingame.lvl')        = 'data\_LVL_PC\ingame.lvl'    # the HUD, cut down
    (Join-Path $proj '_LVL_PC\mission.lvl')       = 'data\_LVL_PC\mission.lvl'
    (Join-Path $proj "_LVL_PC\$Id\$Id.lvl")       = "data\_LVL_PC\$Id\$Id.lvl"
    (Join-Path $proj "_LVL_PC\sound\$($Id.ToLower()).lvl") = "data\_LVL_PC\sound\$($Id.ToLower()).lvl"   # the Clone Wars troopers' weapons
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
