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
    # How hard the guns hit: this many times Battlefront II's own numbers, which are what the
    # table below has. (Not the Ray Gun under Leia's blaster, which is as the game has it.)
    [double]$GunDamage = 2.0,
    # Pack-a-Punch: what comes back hits this many times as hard again, and carries this many
    # times the ammunition. The magazine stays the size it was: Battlefront II's does.
    [double]$PackDamage = 2.0,
    [double]$PackAmmo = 1.5,
    [switch]$NoInstall
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $here)
if (-not $Oat) { $Oat = Join-Path $repo 'tools\oat' }
$linker = Join-Path $Oat 'Linker.exe'
$stockMap = Join-Path $StockDump 'nazi_zombie_prototype'
$zones = @((Join-Path $Game 'zone\english\common.ff'), (Join-Path $Game 'zone\english\nazi_zombie_prototype.ff'))
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
#
# "gun" marks the ones whose damage is then multiplied by -GunDamage: every
# weapon that does its own hurting but the Ray Gun. Each is built twice, the
# second time as <name>_upgraded, which is what Pack-a-Punch hands back for it:
# -PackDamage times the damage ("pack" marks a weapon that is not a "gun" but
# gets that too), -PackAmmo times the ammunition, and "Mk II" after its name.
# Not one marked "once": the lightsaber, which Pack-a-Punch does not take.
$Weapons = [ordered]@{
    # Han Solo's DL-44: two bolts for each pull of the trigger, half a second between pulls. It is
    # made from the game's .357 Magnum, which kicks like one; the DL-44 is given a third of that.
    # (Aimed, the Magnum also scatters its shots a little and fires a touch off the line of sight,
    # to suit sights that are not on the screen here: both are taken out, as the rifle has them.)
    swbf2_dl44 = @{ from = 'sw_357'; kick = 0.35; gun = $true; set = [ordered]@{
        displayName = 'DL-44'; fireType = '2-Round Burst'; fireTime = '0.1'; adsSpread = '0'; adsAimPitch = '0'
        damage = '200'; minDamage = '120'; clipSize = '24'; startAmmo = '480'; maxAmmo = '480' } }
    # The troopers' blaster rifles: automatic, five or six bolts a second, fifty to the magazine.
    swbf2_rifle = @{ from = 'stg44'; gun = $true; set = [ordered]@{
        displayName = 'Blaster Rifle'; fireType = 'Full Auto'; fireTime = '0.18'
        damage = '70'; minDamage = '50'; clipSize = '50'; startAmmo = '500'; maxAmmo = '500'
        reloadTime = '1.5'; reloadEmptyTime = '1.5'; reloadAddTime = '1.0' } }
    # Their pistols: one bolt a pull.
    swbf2_pistol = @{ from = 'walther'; gun = $true; set = [ordered]@{
        displayName = 'Blaster Pistol'; fireType = 'Single Shot'; fireTime = '0.2'; adsSpread = '0'
        damage = '45'; minDamage = '30'; clipSize = '30'; startAmmo = '600'; maxAmmo = '600' } }
    # Boba Fett's EE-3: three bolts in a quarter of a second, thirty-six to the magazine.
    swbf2_ee3 = @{ from = 'stg44'; gun = $true; set = [ordered]@{
        displayName = 'EE-3'; fireType = '3-Round Burst'; fireTime = '0.08'
        damage = '150'; minDamage = '100'; clipSize = '36'; startAmmo = '360'; maxAmmo = '360'
        reloadTime = '1.5'; reloadEmptyTime = '1.5'; reloadAddTime = '1.0'
        altWeapon = 'swbf2_flame' } }
    # And his flamethrower, which in Battlefront II is part of that rifle, and here is fitted to it
    # the way this game fits a grenade launcher to a rifle: each names the other as its "alternate",
    # and this one is no weapon of the player's in its own right (it is not one they change to with
    # the others, and it goes wherever the rifle goes). The game's own flamethrower, changed to and
    # from in a third of a second, and no heavier to carry than the rifle it is part of. (An
    # "_upgraded" weapon's alternate is the other's "_upgraded": further down.)
    # It burns for as long as Battlefront II's does and is out of use for as long: there a pull of
    # the trigger is twenty shots a tenth of a second apart, which is the whole magazine, and the
    # reload takes a second and a half. This game's works by heat, counted to 100: so much a second
    # while it burns, so much a second off while it does not, and once it has overheated nothing
    # until it is back down to a given figure. So 50 a second up (two seconds), and all the way
    # down in a second and a half. (The game's own are 30, 9 and 60: 3.3 s of fire, then 4.4 s
    # before it will fire again and 11 before it is cold.)
    # Its flame is Battlefront II's to show and to sound, like every kit weapon's shot: this game's
    # own is given nothing to draw ($Flames, further down).
    swbf2_flame = @{ from = 'm2_flamethrower_zombie'; gun = $true; set = [ordered]@{
        displayName = 'Flamethrower'; inventoryType = 'altmode'; altWeapon = 'swbf2_ee3'
        altRaiseTime = '0.3'; altDropTime = '0.3'
        overheatRate = '50'; cooldownRate = '66'; overheatEndVal = '1'
        flameTableFirstPerson = 'swbf2_flame_firstperson'; flameTableThirdPerson = 'swbf2_flame_thirdperson'
        moveSpeedScale = '1'; adsMoveSpeedScale = '1.3'; sprintDurationScale = '1' } }
    # The bowcaster. It charges while the trigger is held and fires when it is let go, and no
    # weapon here can do that; the scripts work its shots out from Battlefront II's own
    # (_wawbf.gsc). This stands for it: the magazine, the reload (1.75 s, as there) and the name
    # on the screen, with a shot of its own that reaches nothing and makes no sound, flash or mark.
    # Made from the M1 Garand, a rifle fired a shot a pull whose reload fills it. (It was first
    # made from the trench gun, which is worked by hand after every shot and loaded a shell at a
    # time: with the loading made one movement, that movement still put in one shell, so after
    # the first thirty-five rounds every shot was followed by a reload.)
    swbf2_bowcaster = @{ from = 'm1garand'; set = [ordered]@{
        displayName = 'Bowcaster'; fireType = 'Single Shot'; fireTime = '0.2'
        shotCount = '1'; damage = '1'; minDamage = '1'; maxDamageRange = '1'; minDamageRange = '2'
        clipSize = '35'; startAmmo = '350'; maxAmmo = '350'
        reloadTime = '1.75'; reloadEmptyTime = '1.75'; reloadAddTime = '1.2'; moveSpeedScale = '1'
        fireSound = ''; fireSoundPlayer = ''; lastShotSound = ''; lastShotSoundPlayer = ''
        viewFlashEffect = ''; worldFlashEffect = ''; viewShellEjectEffect = ''; worldShellEjectEffect = ''
        impactType = 'none'; penetrateType = 'none' } }
    # The rocket launcher (the battle droid's): the game's own Panzerschreck, taking
    # the four seconds to reload that Battlefront II's does.
    swbf2_launcher = @{ from = 'panzerschrek'; gun = $true; set = [ordered]@{
        displayName = 'Rocket Launcher'; reloadTime = '4.0'; reloadEmptyTime = '4.0'; reloadAddTime = '3.0'
        startAmmo = '8'; maxAmmo = '8' } }
    # Leia's sporting blaster. Underneath it is this game's Ray Gun (the user's choice): its bolt,
    # which flies and bursts where it lands, and its damage. One every half second and twelve to
    # the magazine, as Battlefront II's has; and Battlefront II's sound, like every kit weapon.
    # What is seen and heard is Battlefront II's bolt, so everything of the Ray Gun's own that
    # shows or sounds is taken out: its green bolt (a trail behind a shot with no shape of its
    # own), its green flash at the muzzle, and the green burst and the bang where it lands. What
    # the burst does to the zombies near it is still done.
    swbf2_sporting = @{ from = 'ray_gun'; pack = $true; set = [ordered]@{
        displayName = 'Sporting Blaster'; fireType = 'Single Shot'; fireTime = '0.5'
        clipSize = '12'; startAmmo = '240'; maxAmmo = '240'
        projTrailEffect = ''; viewFlashEffect = ''; worldFlashEffect = ''
        projExplosionEffect = ''; projExplosionSound = '' } }
    # A lightsaber. Only a name on the screen: the swing is Battlefront II's, and the scripts cut
    # down what it reaches when the bridge says one has begun (_wawbf.gsc). Its own shot reaches
    # nothing and makes no sound, flash or mark. (It was first a short, wide blow that did the
    # cutting; but it fires for as long as its trigger is held, and Battlefront II swings once a
    # pull.)
    swbf2_saber = @{ from = 'shotgun'; once = $true; set = [ordered]@{
        displayName = 'Lightsaber'; fireType = 'Single Shot'; fireTime = '0.45'; rechamberTime = '0'
        shotCount = '1'; damage = '1'; minDamage = '1'; maxDamageRange = '1'; minDamageRange = '2'
        clipSize = '100'; startAmmo = '800'; maxAmmo = '800'; segmentedReload = '0'; reloadTime = '0.1'; reloadAddTime = '0.05'; reloadStartTime = '0'
        fireSound = ''; fireSoundPlayer = ''; lastShotSound = ''; lastShotSoundPlayer = ''
        viewFlashEffect = ''; worldFlashEffect = ''; viewShellEjectEffect = ''; worldShellEjectEffect = ''
        impactType = 'none'; penetrateType = 'none' } }
}

# A flamethrower's flame. The game keeps what one looks and sounds like, and how
# its fire travels, in a file of its own beside the weapon's ("weapons/sp/<name>",
# read by name when the weapon is: CoDWaW.exe+0x23E60), one for the player's own
# view and one for everyone else's. The game draws the flame from where its own
# gun is, and its own gun is not what is on the screen: through the eyes the
# flame began well in front of Battlefront II's barrel, and from behind it was
# left hanging where the gun had last been drawn. Battlefront II draws a flame
# of its own from its own barrel in both views, so this game's is left with
# nothing to show or sound: each of these is the game's flame with everything
# that is drawn made nothing (the two ribbons, the fire, the drips, the smoke,
# the light it throws) and its three sounds taken out. How the fire travels and
# what it burns is untouched.
$Flames = [ordered]@{ swbf2_flame_firstperson = 'quinn_flame_firstperson'; swbf2_flame_thirdperson = 'quinn_flame_thirdperson' }
$Unseen = [ordered]@{
    flameVar_streamFuelSizeStart = '0.01'; flameVar_streamFuelSizeEnd = '0.01'; flameVar_streamFuelLength = '1'
    flameVar_streamFlameSizeStart = '0.01'; flameVar_streamFlameSizeEnd = '0.01'; flameVar_streamFlameLength = '1'
    flameVar_streamPrimaryLightRadius = '0'; flameVar_streamPrimaryLightRadiusFlutter = '0'
    flameVar_fireStartSizeScale = '0.001'; flameVar_fireEndSizeScale = '0.001'; flameVar_fireEndSizeAdd = '0'
    flameVar_dripsStartSizeScale = '0.001'; flameVar_dripsEndSizeScale = '0'; flameVar_dripsEndSizeAdd = '0'
    flameVar_smokeMaxAlpha = '0'; flameVar_smokeStartSizeAdd = '0'; flameVar_smokeEndSizeAdd = '0'
    flameOffLoopSound = ''; flameIgniteSound = ''; flameOnLoopSound = ''; flameCooldownSound = ''
}

# Things of the game's own that this map does not have, which the Linker
# copies into mod.ff out of the maps that do (it is shown their zones too).
#
# From Shi No Numa, what a zombie struck by the Wunderwaffe shows and sounds
# like, for Force lightning (_wawbf.gsc): the shock over its body and in its
# eyes, the bolt that jumps to the next one, and the sounds.
#
# From Der Riese, Pack-a-Punch's sparks and sounds, and Quick Revive's picture
# and sound.
$Borrowed = @(
    'fx,maps/zombie/fx_zombie_tesla_shock'
    'fx,maps/zombie/fx_zombie_tesla_shock_secondary'
    'fx,maps/zombie/fx_zombie_tesla_shock_eyes'
    'fx,maps/zombie/fx_zombie_tesla_bolt_secondary'
    'sound,imp_tesla'
    'sound,tesla_sizzle'            # which imp_tesla plays along with itself,
    'sound,wpn_tesla_proj_impact'   # and that one this
    'sound,tesla_bounce'
    'fx,maps/zombie/fx_zombie_packapunch'
    'sound,packa_weap_upgrade'
    'sound,packa_weap_ready'
    'sound,mx_packa_sting'
    'sound,mx_revive_sting'
    'material,specialty_quickrevive_zombies'
    'xmodel,zombie_vending_packapunch_on'   # the two machines themselves
    'xmodel,zombie_vending_revive_on'
    # And from either, what the later maps' power-ups have that this map's have not: the two
    # pictures, and the voice.
    'material,specialty_doublepoints_zombies'
    'material,specialty_instakill_zombies'
    'sound,dp_vox'
    'sound,insta_vox'
    'sound,ma_vox'
    'sound,nuke_vox'
)
# And what the player's hands do at each machine: cracking their knuckles,
# drinking from the bottle. The game does these as weapons that are only ever
# taken in hand, for what that looks like. Like this mod's own weapons they go
# in twice: copied into mod.ff like the rest above, and as a plain file beside
# it, which is what the game reads ("Could not load weapon file" otherwise);
# the plain files are dumped out of Der Riese's zone further down.
$Hands = 'zombie_knuckle_crack', 'zombie_perk_bottle_revive'
$Borrowed += $Hands | ForEach-Object { "weapon,$_" }
foreach ($from in 'nazi_zombie_sumpf', 'localized_nazi_zombie_sumpf', 'nazi_zombie_factory', 'localized_nazi_zombie_factory') {
    $zones += Join-Path $Game "zone\english\$from.ff"
}
foreach ($need in $zones) { if (-not (Test-Path -LiteralPath $need)) { throw "missing: $need" } }

# Each weapon twice: as it is handed out, and as Pack-a-Punch hands it back.
$invariant = [Globalization.CultureInfo]::InvariantCulture
$Builds = [ordered]@{}
foreach ($name in $Weapons.Keys) {
    $spec = $Weapons[$name]
    $hits = if ($spec.gun) { $GunDamage } else { 1.0 }
    $Builds[$name] = @{ spec = $spec; damage = $hits; ammo = 1.0; title = $spec.set.displayName }
    if ($spec.once) { continue }
    $Builds["${name}_upgraded"] = @{ spec = $spec; damage = $hits * $(if ($spec.gun -or $spec.pack) { $PackDamage } else { 1.0 }); ammo = $PackAmmo; title = "$($spec.set.displayName) Mk II"; again = $true }
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
# Ours, with the two numbers above written into it: the shots it works out
# itself have to hit as hard as the weapons' own.
$ours = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $here 'scripts\maps\_wawbf.gsc')))
foreach ($number in @{ wawbf_gun_damage = $GunDamage; wawbf_pack_damage = $PackDamage }.GetEnumerator()) {
    $line = [regex]"(?m)^(\s*level\.$($number.Key) = )[\d.]+;"
    if ($line.Matches($ours).Count -ne 1) { throw "_wawbf.gsc does not set level.$($number.Key) exactly once" }
    $ours = $line.Replace($ours, '${1}' + $number.Value.ToString('0.###', $invariant) + ';')
}
Write-Text (Join-Path $work 'raw\maps\_wawbf.gsc') $ours

# The game's weapons script, with its shops (the weapons on the walls, the
# cabinet, the mystery box) set up by ours instead. Its list of weapons is
# left alone: other scripts ask it about them.
$shops = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap 'maps\_zombiemode_weapons.gsc')))
$stock = [regex]'(?m)^\tinit_weapon_upgrade\(\);\s*\r?\n\tinit_weapon_cabinet\(\);\s*\r?\n\ttreasure_chest_init\(\);'
if ($stock.Matches($shops).Count -ne 1) { throw "the game's weapons script does not set up its shops the way this was written for" }
$shops = $stock.Replace($shops, "`tmaps\_wawbf::shops();")
Write-Text (Join-Path $work 'raw\maps\_zombiemode_weapons.gsc') $shops

# The game's power-up script, brought up to the later maps' in the two things
# it lacks (_wawbf.gsc has the rest): the line of text that counts double
# points and insta-kill down is never shown (ours draws a picture instead),
# and each power-up is announced by the voice.
function Edit-Function([string]$text, [string]$name, [scriptblock]$change) {
    $found = [regex]::Matches($text, "(?ms)^$([regex]::Escape($name))\s*\([^)\r\n]*\)\s*\r?\n\{.*?^\}")
    if ($found.Count -ne 1) { throw "the game's power-up script has $($found.Count) routines called $name, not one" }
    $new = & $change $found[0].Value
    if ($new -ceq $found[0].Value) { throw "the game's power-up script: nothing to change in $name; not the script this was written for" }
    return $text.Substring(0, $found[0].Index) + $new + $text.Substring($found[0].Index + $found[0].Length)
}
$powerups = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap 'maps\_zombiemode_powerups.gsc')))
foreach ($name in 'insta_kill_on_hud', 'point_doubler_on_hud') {
    $powerups = Edit-Function $powerups $name { param($body) $body.Replace('hudelem.alpha = 1;', 'hudelem.alpha = 0;') }
}
$says = [ordered]@{
    time_remaning_on_insta_kill_powerup     = 'level thread maps\_wawbf::announce( "insta_vox" );'
    time_remaining_on_point_doubler_powerup = 'level thread maps\_wawbf::announce( "dp_vox" );'
    full_ammo_move_hud                      = 'level thread maps\_wawbf::announce( "ma_vox" );'
    nuke_powerup                            = 'level thread maps\_wawbf::announce( "nuke_vox", 1.8 );'
}
foreach ($name in $says.Keys) {
    $line = $says[$name]
    $powerups = Edit-Function $powerups $name { param($body) ([regex]'\{').Replace($body, "{`r`n`t$line", 1) }
}
# "Max Ammo!" comes up in the middle of the lower half of the screen and drifts upwards as it
# fades. That is where a character seen from behind stands, and Battlefront II's picture is drawn
# over it; so it comes up near the top of the screen instead, under where ours puts the pictures.
$powerups = Edit-Function $powerups 'full_ammo_on_hud' { param($body) ([regex]'setPoint\( "TOP", undefined, 0, [^;]*\);').Replace($body, 'setPoint( "TOP", undefined, 0, 60 );', 1) }
$powerups = Edit-Function $powerups 'full_ammo_move_hud' { param($body) $body.Replace('self.y = 270;', 'self.y = 40;') }
Write-Text (Join-Path $work 'raw\maps\_zombiemode_powerups.gsc') $powerups

$scripts = 'maps/nazi_zombie_prototype.gsc', 'maps/_zombiemode_weapons.gsc', 'maps/_zombiemode_powerups.gsc', 'maps/_wawbf.gsc'
Write-Text (Join-Path $work 'zone_source\mod.zone') (">game,T4`r`n`r`n" + (($scripts | ForEach-Object { "rawfile,$_`r`n" }) -join '') + (($Builds.Keys | ForEach-Object { "weapon,$_`r`n" }) -join '') + (($Borrowed | ForEach-Object { "$_`r`n" }) -join ''))

# The weapons. A weapon file is one line: WEAPONFILE\name\value\name\value...
foreach ($name in $Builds.Keys) {
    $build = $Builds[$name]
    $spec = $build.spec
    $parts = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap "weapons\$($spec.from)"))) -split '\\'
    if ($parts[0] -ne 'WEAPONFILE') { throw "$($spec.from) is not a weapon file" }
    $at = @{}; for ($i = 1; $i + 1 -lt $parts.Count; $i += 2) { $at[$parts[$i]] = $i + 1 }
    foreach ($field in $spec.set.Keys) {
        if (-not $at.ContainsKey($field)) { throw "${name}: the stock weapon $($spec.from) has no field '$field'" }
        $parts[$at[$field]] = $spec.set[$field]
    }
    $parts[$at['displayName']] = $build.title
    if ($build.again -and $spec.set.Contains('altWeapon')) { $parts[$at['altWeapon']] = "$($spec.set.altWeapon)_upgraded" }
    # How hard it hits (a bullet's two numbers, near and far, and a rocket's or a burst's two,
    # at the middle and at the edge), and how much it carries.
    foreach ($field in 'damage', 'minDamage', 'explosionInnerDamage', 'explosionOuterDamage') {
        if ($build.damage -ne 1.0 -and $at.ContainsKey($field) -and [double]$parts[$at[$field]] -gt 0) {
            $parts[$at[$field]] = [Math]::Round([double]$parts[$at[$field]] * $build.damage).ToString($invariant)
        }
    }
    foreach ($field in 'startAmmo', 'maxAmmo') {
        if ($build.ammo -ne 1.0 -and $at.ContainsKey($field)) {
            $parts[$at[$field]] = [Math]::Round([double]$parts[$at[$field]] * $build.ammo).ToString($invariant)
        }
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
# The flames: whole, for the Linker (where its dump has the game's) and for the game.
foreach ($name in $Flames.Keys) {
    $parts = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $stockMap "weapons\$($Flames[$name])"))) -split '\\'
    if ($parts[0] -ne 'FLAMETABLEFILE') { throw "$($Flames[$name]) is not a flame file" }
    $at = @{}; for ($i = 1; $i + 1 -lt $parts.Count; $i += 2) { $at[$parts[$i]] = $i + 1 }
    foreach ($field in $Unseen.Keys) {
        if (-not $at.ContainsKey($field)) { throw "${name}: the game's flame $($Flames[$name]) has no '$field'" }
        $parts[$at[$field]] = $Unseen[$field]
    }
    $parts[$at['name']] = $name
    Write-Text (Join-Path $work "raw\weapons\$name") ($parts -join '\')
    Write-Text (Join-Path $work "weapons\sp\$name") ($parts -join '\')
}
# The hands' two, as plain files: dumped out of the zone that has them, and cut down like ours.
$dumped = Join-Path $work 'borrowed'
$null = & (Join-Path $Oat 'Unlinker.exe') --include-assets weapon -o $dumped (Join-Path $Game 'zone\english\nazi_zombie_factory.ff') 2>&1
foreach ($name in $Hands) {
    $file = Get-ChildItem -LiteralPath $dumped -Recurse -File -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $file) { throw "the Unlinker did not dump the weapon $name out of Der Riese's zone" }
    $parts = $latin1.GetString([IO.File]::ReadAllBytes($file.FullName)) -split '\\'
    if ($parts[0] -ne 'WEAPONFILE') { throw "$name was not dumped as a weapon file" }
    $kept = New-Object Collections.Generic.List[string]; $kept.Add($parts[0])
    for ($i = 1; $i + 1 -lt $parts.Count; $i += 2) { if ($parts[$i + 1] -ne '' -and $parts[$i + 1] -ne '0') { $kept.Add($parts[$i]); $kept.Add($parts[$i + 1]) } }
    $text = $kept -join '\'
    if ($text.Length -gt 9400) { throw "${name}: $($text.Length) bytes even without its empty fields; the game may not read it" }
    Write-Text (Join-Path $work "weapons\sp\$name") $text
}
"weapons: $($Weapons.Keys -join ', '), and each but the lightsaber again as _upgraded; guns hit $GunDamage times as hard, and $PackDamage times that after Pack-a-Punch"

$load = @(); foreach ($zone in $zones) { $load += '-l', $zone }
$out = & $linker -b $work --add-asset-search-path "$stockMap;$(Join-Path $StockDump 'common')" @load mod 2>&1 | ForEach-Object { "$_" }
$ff = Join-Path $work 'zone_out\mod\mod.ff'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ff)) { $out | Where-Object { $_ -match 'ERROR|WARN|Failed' } | Select-Object -Last 20; throw 'the Linker did not build mod.ff' }
'built {0:N0} bytes  {1}' -f (Get-Item -LiteralPath $ff).Length, $ff

if (-not $NoInstall) {
    $dest = Join-Path $env:LOCALAPPDATA "Activision\CoDWaW\mods\$Mod"
    $sp = Join-Path $dest 'weapons\sp'
    if (-not (Test-Path -LiteralPath $sp)) { [void](New-Item -ItemType Directory -Path $sp -Force) }
    Copy-Item -LiteralPath $ff -Destination (Join-Path $dest 'mod.ff') -Force
    foreach ($old in [IO.Directory]::GetFiles($sp, 'swbf2_*')) { [IO.File]::Delete($old) }
    foreach ($name in @($Builds.Keys) + $Hands + @($Flames.Keys)) { Copy-Item -LiteralPath (Join-Path $work "weapons\sp\$name") -Destination (Join-Path $sp $name) -Force }
    "installed to $dest (start World at War with +set fs_game mods/$Mod)"
}
