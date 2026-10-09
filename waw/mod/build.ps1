# Builds World at War's half of the mod and installs it: the scripts that hand
# the player the weapons their Battlefront II character carries, and those
# weapons.
#
# Nothing of World at War's is kept in this repository. The map's script and
# the weapons this mod's are made from are the game's own, dumped from its
# files with OpenAssetTools' Unlinker (-StockDump is where); this script
# changes them and builds the result:
#
#   maps/nazi_zombie_prototype.gsc   the map's script, with one line added that
#                                    starts ours
#   maps/_zombiemode_weapons.gsc     the game's weapons script, with its shops
#                                    handed to ours
#   maps/_wawbf.gsc                  ours (scripts/ in this folder)
#   weapons/sp/swbf2_*               each a stock weapon with the fields in
#                                    $Weapons below changed
#
# The scripts go into mod.ff (OpenAssetTools' Linker; a script in a mod's
# mod.ff replaces the game's of the same name). Each weapon goes in twice, and
# the game wants both: listed in mod.ff, or its name is "unknown item" to the
# scripts; and beside mod.ff as a plain file, which is where the game actually
# reads the weapon's definition from. To put a weapon in mod.ff the Linker has
# to find everything it is made of (models, effects, sounds), so it is shown
# the game's own zones (-Game) and the dump.
#
# Installed to %LOCALAPPDATA%\Activision\CoDWaW\mods\<Mod>. Start the game
# with  +set fs_game mods/<Mod>  to use it.
param(
    [string]$StockDump = 'C:\Claude\waw-stock-dump',
    [string]$Game = 'E:\SteamLibrary\steamapps\common\Call of Duty World at War',
    [string]$Oat = '',
    [string]$Mod = 'swbf2_zombies',
    [switch]$NoInstall
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $here)
if (-not $Oat) { $Oat = Join-Path $repo 'tools\oat' }
$linker = Join-Path $Oat 'Linker.exe'
$stockMap = Join-Path $StockDump 'nazi_zombie_prototype'
$zones = (Join-Path $Game 'zone\english\common.ff'), (Join-Path $Game 'zone\english\nazi_zombie_prototype.ff')
foreach ($need in @($linker, (Join-Path $stockMap 'maps\nazi_zombie_prototype.gsc'), (Join-Path $stockMap 'maps\_zombiemode_weapons.gsc'), (Join-Path $stockMap 'weapons\stg44')) + $zones) {
    if (-not (Test-Path -LiteralPath $need)) { throw "missing: $need" }
}
$latin1 = [Text.Encoding]::GetEncoding(28591)
function Write-Text([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
    [IO.File]::WriteAllBytes($path, $latin1.GetBytes($text))
}

# The weapons. Each is the stock weapon named in "from" with these fields
# changed. The numbers are Battlefront II's own for the weapon being matched
# (from its class files: ShotDelay, SalvoCount and SalvoDelay, RoundsPerClip,
# ReloadTime, and its shot's MaxDamage), so that the two games fire at the
# same rate, in the same bursts, from the same magazine. docs/PHASE3.md has
# the table they came from.
$Weapons = [ordered]@{
    # Han Solo's DL-44: two bolts for each pull of the trigger, half a second between pulls. It is
    # made from the game's .357 Magnum, which kicks like one; the DL-44 is given a third of that.
    # (Aimed, the Magnum also scatters its shots a little and fires a touch off the line of sight,
    # to suit sights that are not on the screen here: both are taken out, as the rifle has them.)
    swbf2_dl44 = @{ from = 'sw_357'; kick = 0.35; set = [ordered]@{
        displayName = 'DL-44'; fireType = '2-Round Burst'; fireTime = '0.1'; adsSpread = '0'; adsAimPitch = '0'
        damage = '200'; minDamage = '120'; clipSize = '24'; startAmmo = '480'; maxAmmo = '480' } }
    # The troopers' blaster rifles: automatic, five or six bolts a second, fifty to the magazine.
    swbf2_rifle = @{ from = 'stg44'; set = [ordered]@{
        displayName = 'Blaster Rifle'; fireType = 'Full Auto'; fireTime = '0.18'
        damage = '70'; minDamage = '50'; clipSize = '50'; startAmmo = '500'; maxAmmo = '500'
        reloadTime = '1.5'; reloadEmptyTime = '1.5'; reloadAddTime = '1.0' } }
    # Their pistols: one bolt a pull.
    swbf2_pistol = @{ from = 'walther'; set = [ordered]@{
        displayName = 'Blaster Pistol'; fireType = 'Single Shot'; fireTime = '0.2'; adsSpread = '0'
        damage = '45'; minDamage = '30'; clipSize = '30'; startAmmo = '600'; maxAmmo = '600' } }
    # Boba Fett's EE-3: three bolts in a quarter of a second, thirty-six to the magazine.
    swbf2_ee3 = @{ from = 'stg44'; set = [ordered]@{
        displayName = 'EE-3'; fireType = '3-Round Burst'; fireTime = '0.08'
        damage = '150'; minDamage = '100'; clipSize = '36'; startAmmo = '360'; maxAmmo = '360'
        reloadTime = '1.5'; reloadEmptyTime = '1.5'; reloadAddTime = '1.0' } }
    # The bowcaster. It charges while the trigger is held and fires when it is let go, and no
    # weapon here can do that; the scripts work its shots out from Battlefront II's own
    # (_wawbf.gsc). This stands for it: the magazine, the reload (1.75 s, as there) and the name
    # on the screen, with a shot of its own that reaches nothing and makes no sound, flash or mark.
    swbf2_bowcaster = @{ from = 'shotgun'; set = [ordered]@{
        displayName = 'Bowcaster'; fireType = 'Single Shot'; fireTime = '0.2'; rechamberTime = '0'
        shotCount = '1'; damage = '1'; minDamage = '1'; maxDamageRange = '1'; minDamageRange = '2'
        clipSize = '35'; startAmmo = '350'; maxAmmo = '350'
        segmentedReload = '0'; reloadTime = '1.75'; reloadEmptyTime = '1.75'; reloadAddTime = '1.2'
        reloadStartTime = '0'; reloadEndTime = '0'; reloadStartAddTime = '0'
        fireSound = ''; fireSoundPlayer = ''; lastShotSound = ''; lastShotSoundPlayer = ''
        viewFlashEffect = ''; worldFlashEffect = ''; viewShellEjectEffect = ''; worldShellEjectEffect = ''
        impactType = 'none'; penetrateType = 'none' } }
    # The rocket launcher (the battle droid's, Chewbacca's): the game's own Panzerschreck, taking
    # the four seconds to reload that Battlefront II's does.
    swbf2_launcher = @{ from = 'panzerschrek'; set = [ordered]@{
        displayName = 'Rocket Launcher'; reloadTime = '4.0'; reloadEmptyTime = '4.0'; reloadAddTime = '3.0'
        startAmmo = '8'; maxAmmo = '8' } }
    # Leia's sporting blaster. Underneath it is this game's Ray Gun (the user's choice): its bolt,
    # which flies and bursts where it lands, and its damage. One every half second and twelve to
    # the magazine, as Battlefront II's has; and Battlefront II's sound, like every kit weapon.
    swbf2_sporting = @{ from = 'ray_gun'; set = [ordered]@{
        displayName = 'Sporting Blaster'; fireType = 'Single Shot'; fireTime = '0.5'
        clipSize = '12'; startAmmo = '240'; maxAmmo = '240' } }
    # A lightsaber. Only a name on the screen: the swing is Battlefront II's, and the scripts cut
    # down what it reaches when the bridge says one has begun (_wawbf.gsc). Its own shot reaches
    # nothing and makes no sound, flash or mark. (It was first a short, wide blow that did the
    # cutting; but it fires for as long as its trigger is held, and Battlefront II swings once a
    # pull.)
    swbf2_saber = @{ from = 'shotgun'; set = [ordered]@{
        displayName = 'Lightsaber'; fireType = 'Single Shot'; fireTime = '0.45'; rechamberTime = '0'
        shotCount = '1'; damage = '1'; minDamage = '1'; maxDamageRange = '1'; minDamageRange = '2'
        clipSize = '100'; startAmmo = '800'; maxAmmo = '800'; segmentedReload = '0'; reloadTime = '0.1'; reloadAddTime = '0.05'; reloadStartTime = '0'
        fireSound = ''; fireSoundPlayer = ''; lastShotSound = ''; lastShotSoundPlayer = ''
        viewFlashEffect = ''; worldFlashEffect = ''; viewShellEjectEffect = ''; worldShellEjectEffect = ''
        impactType = 'none'; penetrateType = 'none' } }
}

$work = Join-Path $repo 'build\wawmod'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -Confirm:$false }

# The map's script, with ours started from it. Ours has to run before the
# game's own start-up does, because that is when weapons are precached.
$map = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap 'maps\nazi_zombie_prototype.gsc')))
$anchor = 'maps\_zombiemode::main();'
if (([regex]::Matches($map, [regex]::Escape($anchor))).Count -ne 1) { throw "the map's script does not call $anchor exactly once: not the script this was written for" }
$map = $map.Replace($anchor, "maps\_wawbf::init();`r`n`t$anchor")
Write-Text (Join-Path $work 'raw\maps\nazi_zombie_prototype.gsc') $map
Copy-Item -LiteralPath (Join-Path $here 'scripts\maps\_wawbf.gsc') -Destination (Join-Path $work 'raw\maps\_wawbf.gsc')

# The game's weapons script, with its shops (the weapons on the walls, the
# cabinet, the mystery box) set up by ours instead. Its list of weapons is
# left alone: other scripts ask it about them.
$shops = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap 'maps\_zombiemode_weapons.gsc')))
$stock = [regex]'(?m)^\tinit_weapon_upgrade\(\);\s*\r?\n\tinit_weapon_cabinet\(\);\s*\r?\n\ttreasure_chest_init\(\);'
if ($stock.Matches($shops).Count -ne 1) { throw "the game's weapons script does not set up its shops the way this was written for" }
$shops = $stock.Replace($shops, "`tmaps\_wawbf::shops();")
Write-Text (Join-Path $work 'raw\maps\_zombiemode_weapons.gsc') $shops

$scripts = 'maps/nazi_zombie_prototype.gsc', 'maps/_zombiemode_weapons.gsc', 'maps/_wawbf.gsc'
Write-Text (Join-Path $work 'zone_source\mod.zone') (">game,T4`r`n`r`n" + (($scripts | ForEach-Object { "rawfile,$_`r`n" }) -join '') + (($Weapons.Keys | ForEach-Object { "weapon,$_`r`n" }) -join ''))

# The weapons. A weapon file is one line: WEAPONFILE\name\value\name\value...
foreach ($name in $Weapons.Keys) {
    $spec = $Weapons[$name]
    $parts = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap "weapons\$($spec.from)"))) -split '\\'
    if ($parts[0] -ne 'WEAPONFILE') { throw "$($spec.from) is not a weapon file" }
    $at = @{}; for ($i = 1; $i + 1 -lt $parts.Count; $i += 2) { $at[$parts[$i]] = $i + 1 }
    foreach ($field in $spec.set.Keys) {
        if (-not $at.ContainsKey($field)) { throw "${name}: the stock weapon $($spec.from) has no field '$field'" }
        $parts[$at[$field]] = $spec.set[$field]
    }
    # The sound of a kit weapon is Battlefront II's, which is heard under this game now: its blasters
    # for these, not a Magnum or an STG-44. So everything this game would play for the weapon itself
    # is taken out: firing, running dry, reloading (the sounds the reload's own animation calls for
    # as well, all but the knife's, which is this game's to do), bringing it up and putting it away,
    # and a rocket's flight. What it hits is still heard here: this is the game it hits things in.
    foreach ($field in @($at.Keys | Where-Object { $_ -match '^(fire|lastShot|emptyFire|reload|reloadEmpty|reloadStart|reloadEnd|rechamber|raise|firstRaise|putaway)Sound(Player)?$' -or $_ -eq 'projectileSound' })) {
        $parts[$at[$field]] = ''
    }
    if ($at.ContainsKey('notetrackSoundMap')) {
        $parts[$at['notetrackSoundMap']] = (($parts[$at['notetrackSoundMap']] -split "`r?`n") | Where-Object { $_ -match '^knife_' }) -join "`n"
    }
    # "kick" scales the weapon's recoil: how far a shot throws the view and the gun, hip and aimed.
    if ($spec.kick) {
        foreach ($field in @($at.Keys | Where-Object { $_ -match '^(hip|ads)(View|Gun)Kick(Pitch|Yaw)(Min|Max)$' })) {
            $parts[$at[$field]] = ([double]$parts[$at[$field]] * $spec.kick).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    Write-Text (Join-Path $work "raw\weapons\$name") ($parts -join '\')   # for the Linker, whole
    # The game will not read a weapon file much over 10,000 bytes ("Is too long
    # of a weapon file to parse": one of 11,858 was refused, one of 9,416
    # read), and the dumped ones are nearer 12,000, a good part of it fields
    # that are empty or 0. A field left out is read as empty or 0, so those go.
    $kept = New-Object Collections.Generic.List[string]; $kept.Add($parts[0])
    for ($i = 1; $i + 1 -lt $parts.Count; $i += 2) { if ($parts[$i + 1] -ne '' -and $parts[$i + 1] -ne '0') { $kept.Add($parts[$i]); $kept.Add($parts[$i + 1]) } }
    $text = $kept -join '\'
    if ($text.Length -gt 9400) { throw "${name}: $($text.Length) bytes even without its empty fields; the game may not read it" }
    Write-Text (Join-Path $work "weapons\sp\$name") $text
}
"weapons: $($Weapons.Keys -join ', ')"

$out = & $linker -b $work --add-asset-search-path "$stockMap;$(Join-Path $StockDump 'common')" -l $zones[0] -l $zones[1] mod 2>&1 | ForEach-Object { "$_" }
$ff = Join-Path $work 'zone_out\mod\mod.ff'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ff)) { $out | Where-Object { $_ -match 'ERROR|WARN|Failed' } | Select-Object -Last 20; throw 'the Linker did not build mod.ff' }
'built {0:N0} bytes  {1}' -f (Get-Item -LiteralPath $ff).Length, $ff

if (-not $NoInstall) {
    $dest = Join-Path $env:LOCALAPPDATA "Activision\CoDWaW\mods\$Mod"
    $sp = Join-Path $dest 'weapons\sp'
    if (-not (Test-Path -LiteralPath $sp)) { [void](New-Item -ItemType Directory -Path $sp -Force) }
    Copy-Item -LiteralPath $ff -Destination (Join-Path $dest 'mod.ff') -Force
    foreach ($old in [IO.Directory]::GetFiles($sp, 'swbf2_*')) { [IO.File]::Delete($old) }
    foreach ($name in $Weapons.Keys) { Copy-Item -LiteralPath (Join-Path $work "weapons\sp\$name") -Destination (Join-Path $sp $name) -Force }
    "installed to $dest (start World at War with +set fs_game mods/$Mod)"
}
