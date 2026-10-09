# Phase 3: the character's own weapons

The player is a Battlefront II character, with that character's weapons and
abilities, and World at War makes them count: its shots are the ones that hit
zombies. This phase makes the two agree about what is in the player's hands,
what it does, and how the character stands and moves while doing it.

## What was asked for

By the user, 2026-10-08 and 2026-10-09, in the order it came:

- No weapon buys and no mystery box. A character keeps the weapons it has in
  SWBF2, and WaW is handed the closest match. **Walls sell ammunition.**
- The EE-3 fires in bursts, so its match must.
- The bowcaster charges while the trigger is held and fires only when it is
  let go; the longer the charge the more damage, up to the cap SWBF2's
  crosshair shows.
- Leia's pistol fires a beam, which has to match what WaW fires.
- A lightsaber is swung with **fire**, not melee. Melee is off for lightsaber
  heroes and stays on for characters with guns, whose knife is shown in first
  person and not in third.
- **A lightsaber kills in one hit, whatever the round**, hits whatever is in
  front of the player or to the side, and kills **only while it is being
  swung**.
- Abilities other than Force powers and throwing the lightsaber go. Charges
  and bombs all become grenades. Boba Fett's rockets stay.
- Every character can step through its abilities: the left shoulder button,
  and a key. (First left on the d-pad; moved at the user's word when that
  became the flamethrower's.) The Force is on right click or the left
  trigger.
- Boba Fett's flamethrower is part of his rifle, as it is in SWBF2, not a
  second weapon: left on the d-pad changes between the two.
- Force pull is Force push the other way: it kills, and throws towards the
  player. (First asked for as "brings zombies to the player", and built that
  way; changed at the user's word.)
- SWBF2's weapon sounds, not WaW's. Of SWBF2's HUD only the weapons and
  abilities, raised clear of WaW's round number. A lightsaber's kills take
  something off the zombie.
- Reloads take the same time in both games.
- A character with a lightsaber is always seen from behind; one with a gun
  stays in whichever view the player chose.
- Changing character does not show the old one dying or leave what it drops.
- WaW's pause menu is not behind the player's character.
- Grenades: SWBF2's character throws, WaW's grenade is the one that is seen,
  flies, bounces off WaW's world and bursts. No SWBF2 grenade is visible.
- F10, F11 and F9 are also up, down and right on the d-pad.
- Characters are drawn smaller, all by the same amount, about a zombie's
  height; Yoda as he was.
- Recoil is WaW's, not SWBF2's; none at all in third person; less on Han's
  pistol.
- The character crouches, sprints and jumps when the player does, and a jump
  lasts as long in WaW as it does in SWBF2. No prone.
- Guns have to hit what they are aimed at in third person.
- God mode while testing.

## The kits

A kit is a number that says what a character carries. The arena's mission
script knows the character (`swbf2/arena/WAW_arena.lua`, `KIT`), WaW's script
knows what to hand over for each kit (`waw/mod/scripts/maps/_wawbf.gsc`,
`add_kit` and `add_ability`), and the two bridges carry the number between
them. The three places have to agree.

| Kit | Who | In SWBF2 | In WaW | Abilities (place) |
|---|---|---|---|---|
| 1 | Han Solo | DL-44 | `swbf2_dl44` | grenade (2) |
| 2 | clone trooper, stormtrooper | blaster rifle, pistol | `swbf2_rifle`, `swbf2_pistol` | grenade (2) |
| 3 | battle droid | blaster rifle, rocket launcher | `swbf2_rifle`, `swbf2_launcher` | grenade (2) |
| 4 | Boba Fett | EE-3, flamethrower | `swbf2_ee3`, with `swbf2_flame` fitted to it | wrist rocket (2), grenade (3) |
| 5 | Chewbacca | bowcaster | `swbf2_bowcaster` | grenade (2) |
| 6 | Leia | sporting blaster | `swbf2_sporting` | grenade (1) |
| 7 | Luke, Obi-Wan, Mace Windu, Darth Maul | lightsaber | `swbf2_saber` | throw (1), push (2) |
| 8 | Aayla Secura | lightsaber | `swbf2_saber` | throw (1), pull (2) |
| 9 | Anakin, Darth Vader | lightsaber | `swbf2_saber` | throw (1), choke (2) |
| 10 | Yoda | lightsaber | `swbf2_saber` | pull (1), push (2) |
| 11 | Count Dooku | lightsaber | `swbf2_saber` | lightning (1), choke (2) |
| 12 | General Grievous | lightsabers | `swbf2_saber` | none |
| 13 | the Emperor | lightsaber | `swbf2_saber` | lightning (1), choke (2) |

The Emperor has a kit to himself, the same as Count Dooku's, so that the
WaW bridge can tell them apart: he glides, and is not to be heard walking
("Footsteps").

A "place" is where the ability sits among the SWBF2 unit's weapons, counting
the first weapon as 0. It is what SWBF2 reports as selected, so it is what
the WaW script is keyed by.

### What the arena changes about SWBF2's characters

All with `SetClassProperty` as the mission loads.

| What | How | Why |
|---|---|---|
| Fusion cutter, rallies, invulnerability taken away; detpacks and time bombs become thermal detonators | `CARRIES`: `WeaponNameN`, `""` to take one away | WaW has to be able to do whatever SWBF2 shows |
| 99 of everything that is counted | `COUNTED`: `WeaponAmmoN` | WaW does the counting |
| Weapons shoot straight | `STRAIGHT` on `KIT_WEAPONS`: the spread properties to 0 | recoil is WaW's (below) |
| The crosshair is not ten degrees above the aim in third person | `TiltValue` 0 | see "Third person" |
| The Emperor jumps as high as the other lightsaber characters | `JumpHeight` | WaW's jump is set by kit, and his is a lightsaber's |
| Chewbacca's rocket launcher taken away | `CARRIES` | below |

**Chewbacca has the bowcaster and nothing else to shoot** (the user's
decision, after three tries at giving him something). His own launcher fires
a rocket the player then steers, looking out from it: nothing in WaW flies
that way, and no character is left on the screen while it does. In its place
were tried the Alliance soldier's rocket launcher (`all_weap_inf_rocket_launcher`,
read in with `all_inf_rocketeer`), a copy of that with `AnimationBank =
"rifle"` packed into the arena's own world, and the Wookiee soldier's grenade
launcher (`all_weap_inf_mortar_launcher`, with `all_inf_wookiee`), which is
held like a rifle already and is the same model as his own. Each stopped the
game dead the moment he took it in hand seen from behind
(`BattlefrontII.exe+0x24196F`, reading through a null pointer, in what looks
like the unpacking of an animation); through his eyes, where his body is not
drawn, the last was fine. It is his body that cannot hold them.

Two things that did not work this way. `SkeletonRootScale` (how Yoda is made
small) was tried for the characters' size and did nothing. And `TiltValue`
is not only the camera's: at 45, tried to send SWBF2's crosshair off the top
of the screen, every unit fell through the floor from the moment it
appeared. 0 and 10 are safe. (The bridge now puts a unit found well below
the floor back on it, whatever the cause.)

### The WaW weapons

`waw/mod/build.ps1` makes each from a stock weapon by changing fields, with
SWBF2's own numbers (its class files in the mod tools: `ShotDelay`,
`SalvoCount` and `SalvoDelay`, `RoundsPerClip`, `ReloadTime`, the shot's
`MaxDamage`).

| Weapon | From | Fire | Between shots | Damage | Magazine | Reload | SWBF2's |
|---|---|---|---|---|---|---|---|
| `swbf2_dl44` | `sw_357` | 2-round burst | 0.1 s | 200 | endless | | two bolts a pull, 200 each, heat instead of ammunition |
| `swbf2_rifle` | `stg44` | automatic | 0.18 s | 70 | 50 | 1.5 s | 0.17 to 0.2 s, 60 to 75, 50, 1.5 s |
| `swbf2_pistol` | `walther` | single | 0.2 s | 45 | endless | | 0.2 s, 45, heat |
| `swbf2_ee3` | `stg44` | 3-round burst | 0.08 s | 150 | 36 | 1.5 s | three at 0.08 s, 0.75 s between bursts, 150, 36, 1.5 s |
| `swbf2_flame` | `m2_flamethrower_zombie` | as stock | | 30 | none: heat, 2 s of it | 1.5 s to cool | fitted to the EE-3 (below); 20 shots 0.1 s apart, 1.5 s |
| `swbf2_sporting` | `ray_gun` | single | 0.5 s | the Ray Gun's | endless | | a beam: 0.5 s, 300, heat |
| `swbf2_bowcaster` | `m1garand` | see "The bowcaster" | | | 35 | 1.75 s | 35, 1.75 s |
| `swbf2_launcher` | `panzerschrek` | as stock | | as stock | 1 | 4.0 s | 1, 4.0 s |
| `swbf2_saber` | `shotgun` | see "The lightsaber" | | none | endless | | |

The DL-44 has a third of the .357's kick (`kick = 0.35`, which scales every
view and gun kick field). Aimed, the .357 and the Walther also scatter their
shots a little (`adsSpread` 1.15 degrees) and the .357 fires a touch off the
line of sight (`adsAimPitch`), to suit sights that are not on the screen
here; both are set to nothing, as the STG-44 the rifle is made from has them.
Leia's sporting blaster is the game's Ray Gun underneath, at the user's word:
a shot that flies and bursts where it lands, and its damage, at SWBF2's half
second a shot. Nothing of the Ray Gun is seen or heard, though: its green
trail, its flash at the muzzle, and the green burst and the bang where it
lands are all taken out of the file. What is seen and heard is SWBF2's bolt.
(The burst could not simply be made the bolt's colour: the effect is drawn
from green pictures.)

**Twice the damage.** The table's numbers are SWBF2's. The build multiplies
them by `-GunDamage` (2) for every weapon that does its own hurting, the Ray
Gun excepted, and writes the number into the script for the shots that are
worked out there (the bowcaster's; Boba Fett's rocket is fired as
`swbf2_launcher` and so has it already).

**Each weapon is built twice**, the second time as `<name>_upgraded`: what
Pack-a-Punch hands back ("Pack-a-Punch" below). `-PackDamage` (2) times the
damage again, `-PackAmmo` (1.5) times the ammunition carried, "Mk II" after
the name. The magazine stays as it was, because SWBF2's does.

**Their sound is SWBF2's.** Everything WaW would play for a kit weapon
itself is taken out of its file by the build: firing, running dry,
reloading (and the sounds the reload's animation calls for, all but the
knife's), raising and putting away, a rocket's flight. What a shot hits is
still WaW's to sound. "Sound" below has SWBF2's side of it.

"Endless" weapons are topped up by the script and never reload
(`level.wawbf_endless`); in SWBF2 they heat up instead, which WaW does not
follow. The flamethrower is the game's own, which also works by heat where
SWBF2's has a magazine; that one is not matched.

**Boba Fett's flamethrower is fitted to his rifle.** In SWBF2 the two are
one gun (the same model, second in his list). Here the flamethrower was
first his second weapon, changed to like anyone's sidearm; the user asked
for it to be an attachment of the rifle instead. WaW has exactly that for a
rifle's grenade launcher (`m1garand_gl` and `m7_launcher`): each weapon's
file names the other as its `altWeapon`, and the fitted one's
`inventoryType` is `altmode`, which makes it no weapon of the player's in
its own right. `swbf2_ee3` and `swbf2_flame` are built the same way (and
their `_upgraded` forms name each other). So "change weapon" no longer
reaches the flamethrower; a button of its own does (left on the d-pad, 5 on
the keyboard: the game's own for an "alternate weapon", though it is not
the game that acts on it here; further down), in a third of a second each
way (`altRaiseTime`, `altDropTime`), and it weighs no more than the rifle
(`moveSpeedScale`). The script still tells the bridge "the second weapon is
in hand", so SWBF2 follows as before. And the flamethrower goes where the
rifle goes: into the Pack-a-Punch with it, out of it better with it
(`level.wawbf_part_of`, `fitted_to`); used while the flamethrower is out,
the machine takes the rifle it is part of. Being one of the mod's own guns
now, it hits twice as hard as the stock one did.

WaW shows what is fitted to the weapon in hand at the bottom of the screen,
in the middle: a picture, its ammunition, the button. For the flamethrower
that was a grey box (this map has no picture for it), "300" (it works by
heat) and "[DLEFT or 5]", and the user asked what it was, and then for it to
go. The game's setting for hiding it (`actionSlotsHide`) was tried and does
nothing on a PC: the PC's version of that part of the HUD (`ui/hud.menu`,
"DPad") does not look at it, and shows a slot for as long as the slot has
something to do. So the slot is given nothing to do (`SetActionSlot( 3, ""
)`), and the change is made the way "the next ability" is: the WaW bridge
looks at the button itself (`[waw] fitted_key`, `fitted_pad`: 5 and left on
the d-pad, which were the game's own for it) and says so in a bit of the
number the scripts read, and the script changes weapon (`change_fitted`). If
that is asked twice and nothing comes of it, the script hands the job back
to the game's own slot for the rest of the game, display and all.

**Its flame is SWBF2's.** WaW draws a flamethrower's flame from where its
own gun is, and its own gun is not the one on the screen: through the eyes
the flame began well in front of SWBF2's barrel, and from behind it hung
where the gun had last been drawn (the user: "in 3rd person the WaW
projectile stays in the last position the barrel was in 1st person"). The
game keeps what a flame looks and sounds like, and how its fire travels, in
a file of its own beside the weapon's (`weapons/sp/<name>`, loaded by name
when the weapon is: `CoDWaW.exe+0x23E60`). The build makes two for this
weapon out of the game's (`swbf2_flame_firstperson`, `_thirdperson`) with
everything that is drawn made nothing and the three sounds taken out; how
the fire travels and what it burns is as it was. What is seen and heard is
SWBF2's flame, from SWBF2's barrel, in both views.

That leaves SWBF2's flame having to be there whenever WaW's fire is. SWBF2's
flamethrower fires one burst for a pull of the trigger and wants a new pull
for the next; WaW's burns again by itself once it has cooled. So while the
trigger is held and WaW's is not firing (it has overheated), the script
tells the bridge the weapon has nothing to fire, exactly as for an empty
one, and SWBF2's trigger is let go; when WaW's fire comes back, SWBF2's
trigger is pulled afresh (`held_back`).

It burns and rests as SWBF2's does. There a pull of the trigger is twenty
shots a tenth of a second apart, which is the whole magazine, and the reload
takes 1.5 s: two seconds of flame, a second and a half without. WaW's works
by heat, counted to 100: `overheatRate` a second while it burns,
`cooldownRate` a second off while it does not, and once it has overheated
nothing until it is back down to `overheatEndVal`. The game's own are 30, 9
and 60 (3.3 s of flame, then 4.4 s before it fires again and 11 until it is
cold), and the user saw it: "it takes much longer to cooldown". Now 50, 66
and 1. (The units are read off the game's own figures and how its
flamethrower behaves, not out of its code.)

Changing character does not fill anything: what was left in a weapon when it
was put down is there when it is picked up again, and grenades and rockets
are counted for the player, not the character.

## How the two games talk

```
SWBF2 mission script ──(unit's full health)──► SWBF2 bridge ──(shared memory)──► WaW bridge ──(self.count)──► WaW script
                                               SWBF2 bridge ◄──(shared memory)── WaW bridge ◄──(self.dmg)──── WaW script
```

- **Script to bridge, in SWBF2.** The bridge cannot call the mission script.
  The script writes the kit into the unit's full health, which nothing else
  uses (the unit cannot be hurt): `1e37 * (1 + n / 65536)`, where `n` is the
  kit plus 32 for a hero or villain plus 64 for one with a lightsaber, plus
  128 times the number of who it is ("What Tab brings up").
  `[swbf2] unit_kit`.
- **Bridge to bridge.** Protocol version 11 (`protocol/wawbf_protocol.h`).
  From SWBF2: the kit, the ability selected, counts of the ability's and the
  weapon's uses, how far the weapon was charged, and whether each is in use.
  From WaW: the weapon in hand, its magazine and the magazine's size, and
  flags for "the ability can be used", "the weapon is empty", reloading,
  crouching and sprinting; and the buttons.
- **Bridge to script, in WaW.** A script can read and write a few numbers on
  any entity by name (the game's table of them is at `CoDWaW.exe+0x43A3D8`:
  a name, where the number sits in an entity, and its kind). Three of them
  mean nothing on a player, and sit in the first entity (`g_entities`,
  `CoDWaW.exe+0x136C6F0`, `0x378` bytes each, an entity's position at
  `+0x160`):
  - `count` (`+0x24C`), written by the bridge. From the low end: 5 bits of
    kit, 3 of the ability's place, 1 of "the ability is in use", 1 of "the
    weapon is in use", 7 of the count of the ability's uses, 7 of the
    weapon's, 4 of the charge. `[waw] kit_field`.
  - `dmg` (`+0x1D4`), written by the script. From the low end: 2 bits of the
    weapon in hand, 1 of "the ability can be used", 1 of "the weapon is
    empty", 8 of the rounds in the magazine, 8 of the magazine's size (0 for
    a weapon SWBF2 is not to follow), 11 of how far along the line through
    the middle of the screen the first thing is, in steps of 2 units (0 when
    the view is through the player's eyes, or for a character with nothing
    to aim). `[waw] scripts_say`.
  - `spawnflags` (`+0x1B0`), written by the bridge: the line through the
    middle of the screen, while the view is from behind ("Third person"
    below). `[waw] aim_field`.

  A number this size has to be taken apart in the script with whole numbers
  only (`x % 256`, then `(x - that) / 256`): divided as it stands it is first
  made a fraction, which keeps 24 bits of it.

The bridges log every change of kit and ability. The script must never make a
mistake the game counts as an error: a runtime error stops the one thread
that does all of this. (`SetDvar` on one of the game's own settings is such
an error, which is why the view kick is changed from the bridge.)

Both exes: `CoDWaW.exe` loads at `0x400000`; `BattlefrontII.exe` loads at
`0xB30000` on this machine, so an address seen in its memory is not its
offset. Every address in the code and the settings is an offset from where
the exe is loaded.

## Buttons

Everything is taken from WaW, where the player's hands are, and wherever
there is one from the game's own record of the action, so it works whatever
is bound to what.

| In WaW | In SWBF2 | |
|---|---|---|
| attack | function 0, fire | not while WaW says the weapon is empty |
| aim | function 5, zoom | first person only; with a lightsaber it is the ability instead |
| reload | function 7, reload | not with a lightsaber; also pressed whenever WaW's weapon starts reloading by itself |
| grenade (`+frag`) | function 1, secondary fire | "the ability"; only while WaW says there is one to use |
| | function 7 with a lightsaber | see below |
| jump (`+gostand`) | function 3, jump | a press; and WaW's jump is made as long as the character's (below) |
| crouched (a bit of the player's flags) | function 4, crouch | a switch in SWBF2: pressed while the two disagree |
| sprinting (the weapon's state) | function 2, sprint, held | and the stick, below |
| change weapon | function 13, next weapon | pressed by the SWBF2 bridge until its weapon is the one WaW's script says is in hand |
| left on the d-pad, or 5 | function 13, next weapon, as for "change weapon" | Boba Fett's flamethrower, fitted to his rifle ("The WaW weapons"); read by the WaW bridge itself: `[waw] fitted_pad`, `fitted_key` |
| the left shoulder button, or X | function 15, next ability | read by the WaW bridge itself: `[waw] next_ability_pad`, `next_ability_key`. The shoulder button is WaW's for a special grenade, of which this map has none |
| up, down on the d-pad; F10, F11 | the next hero, the next villain | read by the SWBF2 bridge: `next_hero_pad` and the rest |
| right on the d-pad; F9 | first or third person | `view_toggle_pad` |

The controller is read through XInput (`common/pad.cpp`) for the last three,
which are no action of either game.

**The stick.** The unit goes where the bridge puts it, but SWBF2 chooses how
the character moves its legs from its stick, and will not break into a sprint
without "forward". So the stick is pushed the way WaW's player is really
going: the control state's first float is "to the left" and its second
"forwards", each -1 to 1 (`[swbf2] strafe_axis`, `forward_axis`), full at
WaW's running speed. SWBF2's own count of how long a unit can sprint (its
energy, at `+0xA14` in the unit) is kept full: WaW decides that.

### SWBF2's functions

Found by `[debug] force_functions` and `tools/probe/bfweapons.ps1`, which
lists the words of the unit (or of one of its weapons) that a function
changes:

| Function | What | How it was told |
|---|---|---|
| 0 | fire | the weapon's state word goes 0, 1, 5, 0 |
| 1 | secondary fire; **block** for a lightsaber | a grenade leaves; a Jedi's energy drains at the 10 a second of its block |
| 2 | sprint | held with the stick forward, the character sprints |
| 3 | jump | the unit's height rises |
| 4 | crouch | the eye drops; `0x40` in the byte at `+0x742` |
| 5 | zoom | the field of view narrows |
| 7 | reload; **the Force** for a lightsaber | the selected ability's state word goes 0, 1, 0 |
| 8 | use | opens the class menu at a command post |
| 13 | next weapon | the unit's byte for the weapon in hand steps |
| 15 | next ability | the byte for the ability in hand steps |

The swap for lightsabers is the game's own, and its modding notes say so
("if you say Reload as a button in the combo file, that's the SecondaryFire /
Force Power button in-game"). It happens after the player's bindings are
read, which is where the bridge switches functions on, so the bridge has to
do the swap itself: `[swbf2] melee_ability_function = 7`.

`tools/probe/bfbindings.ps1` lists the player's bindings by function, which
is the quick way to name one: the player knows what their buttons do.

### The unit's weapons

In the unit (Steam build; a soldier is `0xFD0` bytes):

- `+0x720`: eight pointers to its weapons, in the order of its class file;
  0 where one was taken away.
- `+0x740`, `+0x741`: the place in hand for each of the two channels: the
  weapon, and the ability.

In a weapon (`0x1C0` bytes):

- `+0xB0`: what it is doing. 0 idle; 1 a shot or a swing under way; 3 held
  and charging (the bowcaster); 5 a lightsaber recovering after its swing; 2
  then 4 a grenade being thrown. The bridge counts a use of the ability each
  time the selected one's leaves 0, and a use of the weapon each time its
  becomes 1.
- `+0xB8`: while charging, how long a full charge takes (1.25 for the
  bowcaster).
- `+0x88`: pointer to its count of ammunition; in that, `+0x10` is the part
  of the magazine left, 0 to 1, and `+0x0C` the magazines to spare.
- `+0xD8`: for a thrower, what it will throw next; 0 from the throw until it
  has another ready.

## Magazines and reloads

WaW counts the ammunition. For a weapon with a magazine in both games
(`level.wawbf_magazine` in the script) the script tells the bridge the rounds
in WaW's magazine, and the SWBF2 bridge keeps SWBF2's magazine at the same
fraction, so the two run out together and SWBF2 never stops to reload while
WaW is still firing. When WaW's weapon starts to reload (its state says so:
`[waw] reload_states`), SWBF2's reload is pressed. The reloads take the same
time in both, so they end together.

## Recoil

Recoil is WaW's. A shot there kicks the view, and the kick is part of where
the shot goes. The WaW bridge tells SWBF2 the angles of WaW's camera, kick
and all, instead of the angles the player is aiming at, so SWBF2's weapon and
bolts go where WaW's shots go. SWBF2's own way of making a weapon harder to
hold on target is to scatter its shots, more the longer it fires; that is
switched off for every kit weapon (above).

From behind the character the shots themselves have no kick: there the bridge
points every shot at what the middle of the screen shows ("Third person"
below). The bridge also keeps the number behind `bg_viewKickScale` at 0 while
the view is third person (`[waw] view_kick`). That was meant to take the
kick away and does not: the game's code uses that number only for how far the
view is thrown when the player is hit (damage times it, between
`bg_viewKickMin` and `bg_viewKickMax`). Whether the camera still jumps with
each shot in third person has not been looked at since.

## The lightsaber

The swing is SWBF2's. The bridge counts each one and says while the blade is
moving; the WaW script (`saber_cut`, called from `follow_kit`) cuts at the
start of each swing and again every 0.15 s while it lasts. A cut kills every
zombie within `level.wawbf_saber_reach` (125 inches) whose direction is
within the arc `level.wawbf_saber_arc` (a little behind square to either
side) and that nothing solid stands in front of. It kills outright, whatever
the round: no damage number would, since zombies get tougher without end.

`swbf2_saber`, the weapon in the player's hands in WaW, is only a name on the
screen: its shot reaches nothing.

It was first built the other way round, the WaW weapon doing the cutting each
time it fired. But that weapon fires for as long as its trigger is held, and
SWBF2 swings once for each pull; a player holding the trigger killed whatever
they walked up to, with the blade still.

Melee and aiming are switched off for these kits; aim's button is the Force.

### The Force, and the thrown lightsaber

SWBF2 shows them; the WaW script does something to the zombies each time the
bridge says one was used (`use_ability`), or ten times a second while one is
in use (`hold_ability`). Reach, arc and how many at once are SWBF2's own. The
damage is not: there the Force only knocks soldiers down.

| | Reach | Arc | At once | Does |
|---|---|---|---|---|
| throw | 40 m, or the first wall | 1.1 m either side of its path | all | kills, as the blade gets there |
| push | 20 m | 120° | 4 | 1000; a zombie it kills is thrown back |
| pull | 40 m | 50° | 3 | 1000; a zombie it kills is thrown towards the player, harder the further off it was |
| choke | 20 m | 40° | 1 | 250 every tenth of a second while held |
| lightning | 15 m | 80° | 10 | 125 each every tenth of a second while held |

Pull first carried each zombie to just in front of the player, alive
(fastened to something that can be moved, and let go there). The user asked
for push the other way instead.

All of it is in `level.wawbf_*` at the top of the script.

## The bowcaster

In SWBF2 it charges for as long as the trigger is held (full at 1.25 s, shown
round the crosshair) and fires when the trigger is let go: a fan of seven
bolts, 0.7° from one to the next, 75 each; or, charged all the way, one bolt
of 300. No WaW weapon fires on letting go. So `swbf2_bowcaster` only stands
for it (the magazine, the reload, the name), and the shot is SWBF2's: the
bridge says when its bowcaster has fired and how far it was charged, and the
script (`bowcaster`) works the shot out. Each bolt is a line from the
player's eye, 8000 units long, that hurts the first zombie it meets. The
fan's bolts do 150 times one plus the charge (twice SWBF2's 75: the user
wanted "a ranged weapon like m1 garand but more damage", keeping the fan and
the heavy bolt); a full charge is the heavy bolt, 1000 through the first
five (SWBF2's does 300 and goes through nobody; "powerful" was asked for).
Nothing is drawn for them: the bolts on screen are SWBF2's.

**The magazine is SWBF2's.** A fan there takes a round for each of its seven
bolts and the heavy bolt takes one: measured in the running game by holding
its fire on (the magazine read 35, 28, 21). So five fans and a reload. The
script counts the same way (a fan with fewer than seven rounds left fires
what there is, the middle of the fan first), and the round WaW's stand-in
uses when its trigger is pulled is put back. The two magazines then agree
without the bridge having to hold SWBF2's up, and the reload comes at the
same moment in both.

**The stand-in is made from the M1 Garand.** It was first made from the
trench gun, and the user took it for one: "the constant reloading it needs to
do". The trench gun is loaded a shell at a time; the build made its loading
one movement, but that movement still put in one shell (`reloadAmmoAdd`), so
after the first thirty-five rounds every shot was followed by a reload of
1.75 s. It is also worked by hand after every shot (`boltAction`). The
Garand is neither: a shot a pull, and a reload that fills it.

## Grenades and rockets

WaW throws a grenade whenever its grenade button is pressed, and that button
is the ability button whatever the ability. So the player holds grenades only
while a grenade is the ability selected; the script puts them away and
remembers how many (`carry_grenades`).

WaW's grenade is the one that counts and the one that is seen. SWBF2's
character throws, and the grenade it throws is put far below the floor and
its fuse run out the moment it leaves the hand (`CarryGrenade` in the SWBF2
bridge).

Finding SWBF2's grenade: nothing points at it from the unit or the weapon,
so when an ability is used the bridge looks through the memory near the unit
for an object whose first word is the grenade class's and whose owner is the
unit (`tools/probe/bfflying.ps1` is how it was found). In it:

| Offset | What |
|---|---|
| `+0x00` | its class: the exe `+0x3AD0F4` |
| `+0x38` | 1 in flight, `0x101` once it has come to rest |
| `+0x3C` | its fuse, seconds, counted down only once at rest (0.6) |
| `+0x40` | seconds since it was thrown |
| `+0x48`, `+0xC8`, `+0xF0` | where it is, the same again, and where it was a frame ago |
| `+0x54` | the unit that threw it |
| `+0xFC` | its speed, three floats |
| `+0x12C` | gravity on it (-12.25) |

The search costs a frame of SWBF2's each time it goes wide, so an ability
that turns out to throw nothing (a rocket, the Force) is not looked for
again. That was first remembered by where the ability's weapon is in memory,
and it was wrong: a new character's weapons are put where the last one's
were, so a Jedi's Force push kept the grenade of whoever was played next
from ever being looked for, and the user saw it ("the three non heroes, when
they throw grenade it bf one is still visible"). It is remembered now by
whose ability it is and which of theirs, and only after two searches running
have found nothing. The bridge's log says each time a grenade is put away,
and how long after the throw began.

What was built first carried SWBF2's grenade along WaW's instead: the script
gave the bridge the entity number of WaW's grenade, the bridge read where
that was every frame (an entity's position is at `+0x160`) and put SWBF2's
there, with no speed and no weight, and set it off when WaW's went. The user
chose the simpler arrangement before that one was tried with a real throw,
and it was taken out again; the table above is what it needs.

Boba Fett's wrist rocket is a `panzerschrek` round fired from the player's
eye along their view 0.46 s after the button, which is how long SWBF2 takes.
The player has five; walls sell more. Its kills are credited to the player.

## The shops

`build.ps1` has the game's own `_zombiemode_weapons.gsc` call the mod's
`shops()` in place of setting up its own:

- every weapon outline on a wall sells a fill of everything the player
  carries (weapons, grenades, rockets) for 250, and charges nothing if
  nothing was short;
- the weapon cabinet and the mystery box are switched off.

## Standing, crouching, sprinting, jumping, the knife

The WaW bridge reads how the player stands from the game: crouched is bit 4
of the player's flags (`[waw] stance`), and the weapon's state says the rest
(`[waw] weapon_state`): a shot is 5 (a pump or bolt then 6), a reload 7, a
knife attack 13 to 15, a thrown grenade 16 to 21, a sprint 23 to 25. That is
the usual numbering for this family of engines with one more state somewhere
before 13. `tools/probe/posture.ps1` shows both games' idea of it side by
side.

Prone is switched off in the script (`AllowProne`).

**Jumps.** The two games' gravity is all but the same (19.3 metres a second a
second in SWBF2, measured from a jump; 20.3 in WaW), but a WaW player jumps
39 units, a metre, and SWBF2's characters jump 1.77 m (a trooper), 2.47 m (a
hero with a gun) and 3.41 m (anyone with a lightsaber), so the character was
still in the air long after the player had landed. The WaW bridge sets the
number behind WaW's `jump_height` by kit (`[waw] jump_heights`) to the height
that keeps the player off the ground exactly as long: 75, 107 and 150 units.
WaW's falling damage starts at 200 units in this mode, so a jump does not
hurt. It will hit a low ceiling, which SWBF2 knows nothing about.

A jump is passed to SWBF2 only when it is one: the button pressed while the
player stands upright on something (`[waw] ground`, the number of what they
stand on at `+0x88` of the player's record, 1023 in the air). Pressed again
in the air it does nothing in WaW, and SWBF2's heroes jumped a second time
off nothing; pressed while crouched it only stands the player up.

**A lightsaber's sprint.** A character with a lightsaber is not told to
sprint when WaW's player does (`[swbf2] saber_sprint = 0`). SWBF2's sprint
for those characters is a bounding run made for 22.5 metres a second (a Jedi's
`MaxSpeed` of 9 times the sprint's `ControlSpeed` of 2.5), and WaW's player
sprints at 7.2 whoever they are playing: its legs took about a second a step,
"running in slow motion". Their ordinary run, made for 9, takes a stride
every 0.8 s at WaW's sprint, so they run. Troopers (6, and 9 sprinting) and
heroes with guns (8 and 12) are near enough to WaW's speeds and sprint as
before.

What was tried first, and did nothing: telling the unit it was going faster
than it was. The game keeps a speed it is told (told 17.9, found at 18.8 a
frame later), but it does not pace the legs by it: at 1, 2.5, 4 and 5 times
WaW's speed the lightsaber sprint took the same second a step, in pictures
of the user's own sprints. The legs follow the ground really covered, and
that is WaW's to decide.

`[debug] treadmill = 4.8` gives the unit a speed while WaW's player stands
still, so that it moves its legs on the spot with nobody playing, and
`tools/probe/stride.ps1` times legs from pictures of the window. Neither has
given a clean reading yet: the user was playing each time they were tried.

A character with a gun keeps WaW's knife. While the weapon is in a knife
state and the view is first person, the WaW bridge shows WaW's own arms and
blade and SWBF2's picture stands aside (`overlay::SetStandAside`). In third
person nothing is shown.

## Third person

- **Who.** A character with a lightsaber is always seen from behind. Anyone
  else stays in the view the player chose.
- **Where the camera is.** Straight behind the head, the game's own place
  for it, the thing aimed at is behind the character's head. For a character
  with something to aim the bridge moves the camera to one side
  (`[waw] gun_view_angle`, -14 degrees, written to the number behind
  `cg_thirdPersonAngle`): it ends up some 28 units to the right of the
  player's eyes and 6 above, looking the way they look, so the character
  stands left of the middle of the picture. A lightsaber needs no aiming and
  keeps the game's own. Holding aim leaves the camera where it is and narrows
  the view (81 degrees across to 75 with the DL-44, to 58 with the rifle).
- **What the camera hangs on.** WaW works its third-person camera out from
  the head of the player's own soldier: it asks where the bone `j_head` is
  (`CoDWaW.exe+0x5ED20` is the routine, the call at `+0x5EDA5`), goes 8 units
  up and 120 back from there, and looks along the aim. The soldier is hidden
  but still animated: it breathes, shifts its weight, bobs as it runs and
  ducks as it reloads, and the whole picture went with its head, 9 units
  from side to side and 4 up and down with the player standing still
  (`tools/probe/camsway.ps1`). The WaW bridge sends that one call through a
  routine of its own (`callhook::InstallAfter`, `SteadyHead`), which answers
  "straight above where the soldier is drawn, at eye height": 60 units, 40
  crouched. Measured afterwards: 0.00 in every direction over five seconds.
  `[waw] head_call`, `head_routine`, `head_entity_origin`.
- **Size.** SWBF2's soldiers stand well over a zombie's height. They cannot
  be made smaller, but the camera can be put further from them: every part of
  the picture then shrinks towards the character's feet, which stay where
  WaW's player stands. `[swbf2] character_scale` (0.88), and
  `character_scale_kits` for a kit that is to differ (Yoda's, at 1).

### Shots from behind the character

For most of a day guns "did not work" in third person: they fired, and
zombies took no harm, except now and then, "depending where you stand".
Two wrong causes were fixed first (SWBF2's crosshair drawn ten degrees high;
then the camera not being on the line of the shot, for which a crosshair was
drawn where the shot would land). What settled it was watching the shots
themselves (`tools/probe/shotwatch.ps1`): 77 rounds, the line from the
player's eyes along their aim on a zombie for 19 of the 29 seconds, and no
zombie hurt by a bullet; while with WaW's own camera left in first person the
same shooting hurt zombies 23 times in 46 rounds.

The cause is in how WaW fires a player's shot. It does not use the way the
player looks:

- The server fires from the player's eyes along two angles kept in the
  client's record (`+0x2258` pitch, `+0x225C` yaw), unless the player is in
  a vehicle (flag `0x4000`). `CoDWaW.exe+0x151380` works out the muzzle;
  `+0x151590` fires; the bullet itself is `+0xE6810`.
- Those two angles arrive with the player's buttons (two 16-bit numbers at
  `+0x1C` and `+0x1E` of each command; `+0x23E4C0` fills them in from
  `CoDWaW.exe+0x2C7D67C` and `+0x2C7D680`).
- Which are copied each frame (`+0x38B10`) from the drawing side's own pair,
  `CoDWaW.exe+0x312B65C` and `+0x312B660`: the way the gun drawn in the
  player's hands points. The gun sways, and the shots go with it.
- And the routine that places that gun (`+0x69B50`) returns before setting
  them when the view is third person (`CoDWaW.exe+0x311DF48` not zero: no gun
  is drawn then).

So from behind, the angles stay as they were in the last frame seen through
the player's eyes, and every shot goes that way whichever way the player has
turned since. It hits when they happen to be facing the way they were.

The WaW bridge now sets the two angles itself, every frame the view is from
behind (`[waw] gun_angles`; `Aim` in `waw/src/main.cpp`). Since it can point
the shot anywhere, it points it at what the middle of the screen shows, which
is where a player aims and where SWBF2 draws its crosshair:

1. The bridge tells the scripts where the line through the middle of the
   screen runs, relative to the player's eyes and the way they look, which a
   script knows exactly: where the line crosses the plane through the eyes
   (to the right and up, half units, 8 bits each) and how its direction
   differs from theirs (to the right and up, eighths of a degree, 7 bits
   each), and a bit to say the number is there. In `spawnflags`.
2. The script follows that line to the first thing on it (`look_along`,
   twenty times a second) and says how far along it that is.
3. The bridge points the shot from the eyes at that spot, which is the
   middle of the screen, where SWBF2's crosshair is. (`[waw] aim_mark = 1`
   has the bridge draw a small cross of its own on the spot as well,
   `overlay::SetMark`, for checking that the two agree; it was the only
   crosshair from behind for a while.)

The script's own shots (Boba Fett's rockets, the bowcaster's bolts) go the
same way (`aim_ahead`). With nothing known of the middle of the screen (a
character with a lightsaber) the shot goes the way the player looks.

SWBF2's own crosshair needs the class's `TiltValue` at 0 to sit in the middle
(it is ten degrees above the aim as shipped).
## Changing character

The mission script can only take a unit away by killing it, and what dies
falls over and may drop a pick-up. Three things keep that off the screen:

- the script moves the unit 2 km below the floor before it kills it;
- from the moment the bridge asks for the change until the new unit is in
  the world, the picture it sends WaW is empty (`overlay::SetBlank`);
- for that same moment WaW is told what it was told before, so it does not
  drop out of third person or take the player's weapons away and hand them
  back.

## The pause menu

SWBF2's picture is drawn last, over everything of WaW's. While WaW is paused
(`[waw] paused`, the byte behind its `cl_paused`) the picture stands aside,
so the menu is not behind the character. The character is not drawn under
the menu either; that would need the picture drawn earlier in WaW's frame,
before its own HUD, which would also put WaW's HUD and hints in front of the
character where they belong.

## Sound

SWBF2 was never heard. It plays everything through DirectSound, which
silences a program that is not the one in front unless a sound was created
with "global focus", and the game never asks for that; under WaW it is never
in front. Its level in Windows' mixer read 0.000 with a blaster firing.

- **Heard in the background.** The SWBF2 bridge sends DirectSound's one
  routine that creates a sound through its own, which adds the request
  (`swbf2/src/sound.cpp`; `[swbf2] sound_in_background`). The game makes four
  sounds in all and mixes everything into one of them itself (48 kHz, two
  channels, a tenth of a second long, played round and round), so that is
  all it takes.
- **Loud enough.** The game's own levels were nearly off (1% of full scale
  firing). The arena's script sets them: effects and the master all the way
  up, music and both kinds of talk off (`ScriptCB_SetVolumes`). A
  stormtrooper's rifle then reads 0.19 to 0.23.
- **No music, chatter or wind.** The arena no longer opens the streams they
  play from.
- **WaW's own are taken out** of the kit weapons' files ("The WaW weapons").

**One era's recordings only.** Each era's pack for a planet
(`sound\tat.lvl;tat2gcw`) carries one bank of recordings and the definitions
that use them, and the game takes in the first bank it is given and no
other. Measured, each character firing in turn with the bridge holding the
trigger (`[debug] force_functions`), loudest level in Windows' mixer:

| Read, in this order | Clone | Droid | Stormtrooper | Han Solo |
|---|---|---|---|---|
| `tat2gcw`, `tat2cw` (as it was) | 0.003 | 0.004 | 0.19 | 0.05 |
| `tat2gcw`, `kas2cw` | 0.003 | 0.004 | 0.19 | |
| `kas2cw`, `tat2gcw` | 0.19 | | | 0.00 |
| `tat2cw`, `tat2gcw` | 0.19 | 0.16 | 0.004 | 0.00 |
| `tat2cw`, `kas2gcw` | 0.19 | 0.17 | 0.009 | |

So a roster that mixes eras reads the Empire's and Alliance's pack, which is
also the one with every hero's sounds (it is hero assault's). (Han Solo's
and Leia's pistols are the same sound in SWBF2: both classes ask for the
Alliance pistol's.)

**A bank of the arena's own** has the two Clone Wars troopers' weapons. A
small bank read ahead of the era's is taken in as well as it (it is a second
*big* one that is not), so `swbf2/arena/build.ps1` makes one with four firing
sounds in it, under the names those weapons ask for
(`rep_weap_inf_rifle_fire` and so on), and the mission reads it first
(`dc:sound\waw.lvl;wawcw`).

- The mod tools build a bank from a list of .wav files (`SoundFLMunge`, run
  by their `soundmungedir.bat`), and come with every list and definition but
  no recordings.
- The game has the recordings. Every era's bank draws on one file,
  `GameData\data\_lvl_pc\sound\common.bnk`: a table of pairs (a field's name
  as a hash, then its value) that gives each recording's name (hashed:
  FNV-1a over the lower-case letters), its rate and its length in bytes; and
  then, from the first multiple of 2048 after the table (40 + the header
  length the table itself states), the recordings one after another with
  nothing between, 16 bits a point, one channel. That the layout is right
  shows in the edges: read this way, the first and last points of 1,400
  recordings are 0.04 times as loud as points from their middles, and read
  from anywhere else they are as loud. The build copies the four out as .wav
  files for the tools to pack. Nothing of the game's goes into this
  repository.

Measured afterwards, as before: the clone's rifle 0.21 (it read 0.003, and
0.06 with a borrowed sound), the battle droid's 0.18, the stormtrooper's
0.20, Leia's pistol 0.11, Boba Fett's rifle 0.18.

`tools/probe/audiopeak.ps1` reads the mixer. A pistol's reading is unsteady
(held down, it does not always fire); a rifle's is not.

## What is left of SWBF2's HUD

Only the part that shows the weapons and abilities, raised clear of WaW's
round number. WaW has its own health, points, round and crosshair.

The HUD is laid out in a text file in the mod tools, a block for each part
with a place on the screen. The arena's build raises the weapons' block and
gives every other block a place far off the screen
(`swbf2/arena/build.ps1`, `-HudLift`), and packs the result as this add-on's
own `ingame.lvl`, which the mission reads before the game's. That alone does
not do it:

- read *instead of* the game's, ours crashes the game as it starts (it is
  built from the tools' sources, which are not this build's);
- read *as well*, the game has two HUDs, its own in full and ours.

So both are read, and the bridge confines everything drawn in the HUD's part
of the frame to the rectangle our weapons are in (`[overlay] hud_keep`, the
scissor test; `frameprobe::SetHudKeep`). The HUD's part is found by its lens:
the game draws it last, after its second depth-only clear, through a
projection of its own that never changes (x scale 1.7321 at 16:9). While the
game is zoomed in the weapons are not drawn: it draws a scope over the whole
screen then, and a corner of it showed in the rectangle.

**The crosshair is SWBF2's**, in every view, for a character with something
to aim. A second rectangle is kept, the middle of the picture
(`[overlay] hud_middle`; `frameprobe::SetHudMiddle`, each of the HUD's draw
calls being made once for each rectangle kept), and the bridge says in what
it tells WaW that its crosshair is there (`kBfCrosshair`); WaW's bridge then
switches WaW's own off (the byte behind `cg_drawCrosshair`,
`[waw] draw_crosshair`). The user asked for it back from behind and when
aiming, "central", and then for the game's overheating display, which is
part of it: the ring round SWBF2's crosshair shows the magazine, or for a
weapon that heats up instead, the heat. So it is on through the player's
eyes too, in place of WaW's. A character with a lightsaber has none.

The word that comes up when a weapon has overheated is a part of the HUD by
itself, low in the middle of the screen. In the arena's HUD it is put just
above the weapons, inside the first rectangle (`build.ps1`, `-OverheatAt`).

Not looked at yet: aiming through the eyes with a weapon that has a scope
(Leia's pistol, the bowcaster, the droid's launcher). What shows then is the
middle of SWBF2's scope, cut square.

## The line on the horizon

A thin olive line a quarter of the screen wide, on the horizon in one
direction: the arena's one square of terrain, 64 m of grass 230 m from where
the player stands, seen edge-on.

- A world cannot be built without a terrain. With its "active" square made
  empty the game loads and will not put the player into the world.
- Where the square is taken from in the grid makes no difference to where it
  is drawn: at the middle of the world. (It was "in a far corner".)
- The far-scene range does not hide it. It is drawn in the near scene, and
  again in the far one.

So the bridge does not let it be drawn: it is a strip of triangles with 81
corners and 149 triangles, three times in the world's part of each frame and
once in the far scene's, and a draw call of exactly that shape before the
HUD is skipped (`[overlay] hide_ground`; `frameprobe::SetHiddenShape`). Found
with the frame recorder, which now says what each draw call draws
(`[debug] frame_dump = name: 5, 6, 7`).

## A lightsaber's kills

Take something off: an arm, a leg, both legs, the middle or the head, by
chance (`saber_gib`). The game does this itself for zombies killed by enough
firepower, by rules a hurt from a script never meets, and chooses afresh as
the zombie dies; so the script calls the game's own routines
(`animscripts\death::do_gib`, `maps\_zombiemode_spawner::zombie_head_gib`)
on the zombie while it is still standing, and then kills it.

## Lightning, and the choke

Force lightning looks and sounds on a zombie as the Wunderwaffe's shot does
when it lands (`shock` in the script, after the game's own
`maps\_zombiemode_tesla.gsc`): sparks over the body and in the eyes, the
crack of it, a bolt that jumps from each zombie struck to the next with its
own sound, and half of those it kills lose their heads. A zombie the
lightning stays on shows it again every 0.9 s, not every tenth of a second.

Nacht der Untoten has no Wunderwaffe and none of this. The effects and
sounds are in Shi No Numa's files (`nazi_zombie_sumpf.ff` and its
`localized_` twin), and OpenAssetTools' Linker, shown those zones as well,
copies whatever the mod's list names out of them into `mod.ff`
(`$Borrowed` in `waw/mod/build.ps1`). Not brought over: the death the
Wunderwaffe gives a zombie, standing and shaking. Those animations have to
be in the game's list of animations for a soldier, and this map's list
(the one in `common.ff`) does not have them; Shi No Numa's is its own.

What the choke kills, it kills by the head, always.

## Pack-a-Punch, Quick Revive, and more to take

The user asked for Pack-a-Punch "where the box is" and Quick Revive "where
the cabinet is". The mystery box and the weapon cabinet are part of the map
as it was built (the map's list of entities, read out of the running game
with `tools/probe/wawents.ps1`, has the box's lid and the cabinet's doors
and no box or cabinet), so a script cannot take them away. The machines are
the game's own models from Der Riese, copied in like the rest.

- **Pack-a-Punch** (5000) stands over the mystery box, facing as the box
  does, at the user's word: it is used from the same place looking the same
  way, through the box's own "use" place. The box is 96 units long and the
  machine 86 wide, so the box's two ends show at its feet; its lid is hidden.
  It takes the weapon in the player's hands, if it is one of the character's
  own and not a lightsaber, and gives back its second form
  (`<name>_upgraded`): twice the damage, half as much ammunition again. The
  character has it for the rest of the game, whoever else is played in
  between. (The bowcaster's bolts, which the script works out, hit twice as
  hard.) The show is Der Riese's: the weapon goes in and comes out, the
  sparks, the two sounds, and the player cracks their knuckles.
  While it is in there it is out of the player's hands, as the user asked:
  with another weapon of the character's they are left holding that one and
  cannot put it away; with none they are unarmed (the script says "neither
  weapon", so SWBF2 does not fire and its picture stands aside). The weapon
  comes out after three seconds and waits fifteen to be taken, by the one
  who paid; taken, it goes straight into their hands. Left, it is lost,
  until the character is changed or a wall is paid to fill everything up,
  either of which hands it back as it was (`wawbf_away`, `recover`).
- **Quick Revive** (1500) stands against the pillar that faces the cabinet
  across the room, looking back at it: where the user pointed, the cabinet
  being 81 units tall and the machine's body 50, too small to stand over it.
  The script finds the pillar (`stand_revive`: lines followed straight out
  from the cabinet's front, a hand's width apart; the ones stopped soonest,
  together, by something facing back, have found its face) and moves the
  cabinet's "use" place to the machine. The player drinks from the bottle.
- **Its last stand.** Alone, Quick Revive is what gets the player back up,
  as in the later games: the blow that would have put them down leaves them
  in a last stand for ten seconds, and then they are up, whole. There nobody
  lies down (SWBF2's characters cannot), so it is on one knee: crouched and
  unable to move from the spot, still able to turn, shoot or swing a
  lightsaber, and nothing can hurt them. Meanwhile they are shown what
  someone reviving another player is shown, "Reviving" and the bar that
  fills (the game's own bar, `_hud_util`), at the top of the screen because
  SWBF2's character is drawn over where the game puts it; and nothing is
  played (the machine's jingle was, at first; the user asked for the bar and
  not the jingle). And the zombies walk away, as the user asked and the
  later games have it (`keep_away`): the game's zombies choose whom to make
  for by a routine that has no "down" of this kind in it but does have "is
  a zombie", which the player is called for as long as it lasts; and each
  zombie already inside the building is sent to one of the eight path nodes
  furthest from the player among those within 1100 units and on their
  floor, trying the next if there is no way to one. They come back within a
  second of the player getting up. It is used up by that and can be bought
  three times in a game. How: the game's scripts are told of every
  blow to a player before it lands (`level.overridePlayerDamage`), and this
  map's own routine there ends the game on the blow that puts down the last
  player standing. Ours is put in front of it, and for that blow never comes
  back, which is how the game's own stops one.
- **Four blows to go down.** The player has 200 to take where the game gives
  100; a zombie's blow takes 50 or 60. This is the WaW bridge's doing (`[waw]
  max_health`, `player_health`): it keeps the game's setting
  `g_player_maxhealth` at 200, which the game hands a player when it puts
  them into a map. The script did it first, by raising `self.maxhealth`, and
  that went wrong in a way the user described exactly: "after third hit the
  injured sound kept playing". The game gets a player back to health after a
  blow as a part of *its* most (`SetNormalHealth`, `CoDWaW.exe+0x11C6A0`,
  which reads the client record at `+0x217C`), and the scripts work out
  which part from *their* most (`self.maxhealth`, the entity's `+0x1CC`).
  With the scripts' at 200 and the game's still 100, a player on 150 was
  "healed" to 100, and one on 50 was taken down to 25, then 12, and held
  near death for good. A script cannot write the game's figure; the setting
  is where it comes from. (The game's scripts also write 100 into a player
  as they arrive, `_load.gsc`; ours puts the setting's figure back.)
- **The blow that puts them down** ended the game with "All stances
  disallowed for player" and the main menu. The game lays a downed player on
  the ground and its script then forbids standing and crouching; ours had
  forbidden lying down for everyone, SWBF2's characters having no way to.
  Lying down is allowed again from the blow that puts a player down
  (`player_damage`). And surviving a third blow brought up the game's "get
  to cover" hint for the first time in this map, whose routine asks the map
  something only a campaign map answers and stopped with an error; it is
  told not to ask (`level.enable_cover_warning`).

**The player's own hands.** Knuckles and bottle are WaW's to show, as its
knife is: SWBF2 has no picture of either. The game does them as weapons
that are only ever taken in hand (`zombie_knuckle_crack`,
`zombie_perk_bottle_revive`; copied into `mod.ff` and, like the mod's own
weapons, dumped as plain files beside it, or the game says "Could not load
weapon file"). While one is in hand the script tells the bridge "neither
weapon" (3 where it says 1 or 2), and the WaW bridge then shows WaW's hands
in place of SWBF2's picture, exactly as for the knife, and passes no fire,
aim, ability or reload on to SWBF2: nobody shoots in either game until the
hands are free.

**Something to walk into.** A model a script stands in the map is only a
picture. What the map's own furniture is walked into is worked out when the
map is built, and a script's model has none of it. Three tries:

1. A player found inside a machine was put back outside it, twenty times a
   second. The user: "you bounce on them and you can end up getting pushed
   out the map".
2. Every entity's record has a box round it (`r.mins`, `r.maxs`, at `+0x12C`
   and `+0x138` of its 0x378 bytes) and what the box stops (`r.contents`,
   `+0x144`), both nothing for a thing a script makes. The WaW bridge filled
   them in for entities the script marked. The game took the boxes up, and
   walked the player straight through them. (It looked as if it worked at
   the Pack-a-Punch. That was the mystery box underneath: the player stopped
   27 units from its middle, the box's half depth and their own.)
3. Why, from the game's code: the routine that stops a move at an entity
   (`CoDWaW.exe+0x1AAD70`) asks first whether the entity has a model. If it
   has, only the model's own collision counts, and these have none. If it
   has not, and is not a brush either, its box counts, unless it is one of
   the kind scripts move about (type 6: `script_model`, `script_origin`),
   which is skipped. A trigger of the kind that is a plain box of a given
   width and height (`trigger_radius`) is none of those, and a script can
   say what any entity's contents are (`SetContents`, which also has the
   game take the change up). So a block is that trigger, told it is solid
   (`1`) and so no longer a trigger: `stand_solid` in `_wawbf.gsc`, all of it
   script. Players, zombies and shots stop at it as at a wall.

A block is square and stands square to the map, so each machine has a row of
them along its width: three for the Pack-a-Punch (46 units square), two for
Quick Revive (38), all 86 high. Twelve seconds into a map the script sends
something the size of a player at each machine from 90 units in front of it
and says how far it got, in `wawbf_solid_pack` and `wawbf_solid_revive`
(typed into the console, each shows its number: how far it got times 1000,
plus how far it is to the machine's middle).

**And still something to use.** With the blocks in, neither machine could be
used. The game offers a player something to use only if a line from their
eyes to the middle of it is clear (`CoDWaW.exe+0x161CC7`, in the routine
that lists what is in reach), and both "use" places had their middles inside
a block. Each is now put 8 units in front of its machine's blocks
(`stand_solid` says how far forward they reach).

## Power-ups

In the world this map's power-ups already look and sound as the later maps'
do. What those have and this had not: a picture at the bottom of the screen
for as long as double points or insta-kill lasts, flashing as it runs out,
in place of a line of text counting down; and the voice that says which was
picked up. The pictures and the voice are copied out of Shi No Numa's files;
the build takes the text out of the game's own power-up script and has it
call the voice, and the script draws the pictures off the numbers that
script keeps. They sit at the top of the screen, in the middle, where the
later maps have them at the bottom: SWBF2's picture is drawn over everything
of WaW's, and at the bottom there is its character seen from behind, or its
weapon seen through the eyes ("Max Ammo!" comes up under them).

## What Tab brings up

Played alone, WaW has no scoreboard on Tab (or a controller's Back button):
it shows "Mission Objectives", and zombies has none. The player's tally was
first put there as objectives (`tally`): the round, their points, their
kills, how often they went down. It still shows on the pause menu.

The user then asked for the scoreboard "exactly how it is in multiplayer".
The game has it, for co-op, and chooses between the two in its code by
whether the game is an online one (its `onlinegame` setting): the routine
that brings the objectives up while the button is held
(`CoDWaW.exe+0x379D0`) and the one that draws the scoreboard
(`CoDWaW.exe+0x2680B0`) each begin with a short jump on it. The WaW bridge
changes the two jumps (`[waw] scoreboard_alone`, which gives each as a
place, the bytes expected and the bytes to put), so the button brings up the
co-op scoreboard alone as well. The setting itself is left as it is: some
forty other places in the code go by it. Which columns the scoreboard has
is chosen by the game for zombies whatever `onlinegame` says.

**The name on it is the character's.** Alone, the player is "Unknown
Soldier"; the user wanted whoever they are playing. A kit does not say who
(four characters share kit 7), so the arena's script sends a second number
with it, who the character is (`WHO` in `WAW_arena.lua`; the unit's full
health is now `1e37 * (1 + says / 65536)`, with the kit and its two flags in
the low seven bits of what it says and who above them), the SWBF2 bridge
passes it on (`BfPlayerState.who`, protocol 12), and the WaW bridge has the
name for each number (`[waw] character_names`). It changes the player's name
the way the player could: `name "Boba Fett"` given to the game's console
through the game's own routine for a typed line (`[waw] console`,
`CoDWaW.exe+0x194200`, which takes the text in `eax` and the player in
`ecx`). What the player was called before is read first and put back when
SWBF2 goes away. The game does not keep the name between runs.

## SWBF2 and the player's keyboard and controller

SWBF2 reads the devices itself, through DirectInput, and is kept running as
if it were in front; so whatever was pressed for WaW also did what it does
in SWBF2. Tab, or Back, brought up SWBF2's own list of players, over the
part of its HUD that is kept. While its window is not really the one in
front, SWBF2 is now given every device as untouched (`swbf2/src/devices.cpp`:
the two routines of DirectInput's that hand a device's state over are sent
through ours; `[swbf2] devices_in_background`). What it needs of the player
the bridge gives it, as before.

## The blow struck out of a sprint

A character with a lightsaber is not told to sprint ("A lightsaber's
sprint"), and SWBF2 gives the blow its characters strike out of a sprint
only to one that is sprinting as the button goes down. So when WaW's player
strikes while sprinting (or within a quarter of a second of it: WaW's own
sprint ends as the button is pressed), the SWBF2 bridge holds sprint, keeps
the blow back for 120 ms while the sprint takes, then strikes and holds the
button for 250 ms, and lets the sprint go (`[swbf2] sprint_attack`,
`sprint_attack_lead_ms`, `sprint_attack_hold_ms`). Built, and not yet seen
to work: the bridge's log says "sprint attack" each time it does this.

## Footsteps

WaW's player is heard walking whoever the character is, and the Emperor
glides. For his kit WaW's `cg_footsteps` is kept at 0 while the player is on
their feet (`[waw] footsteps_setting`, `quiet_kits`); crouched he creeps
like anyone and is heard.

**Settings found by name.** This one, the crosshair's (`cg_drawCrosshair`)
and the one that hides a lightsaber's ammunition (`ammoCounterHide`: the
weapon that stands for a lightsaber in WaW has to have some, and WaW counts
it on the screen) are looked up by name each time the game runs. The game
keeps its settings in one table, a record each, each where the last left
off; `tools/probe/wawdvar.ps1` finds a record from a part of the name. The
three were first written into the ini as plain addresses, and the next
"+set" added to the way the game is started moved every one of them a
record along, onto its neighbour (which the bridge then wrote to: three
harmless settings, as it turned out). Settings the bridge reaches through a
pointer the game keeps to the record do not have this trouble; for these no
such pointer is known, so the table is searched (`mem::FindRecordNamed`).

## Hints from behind

"Press F to ..." did not come up in third person. The game works out what
the player could use either way, but the routine that passes it to the
screen (`CoDWaW.exe+0x51130`) begins "is the view from behind? then go to
the end". The WaW bridge takes that jump out (two bytes at `+0x51137`,
`[waw] hint_jump`).

## Testing

Two things for testing, neither part of the mod as played.

Start WaW with `+set wawbf_points 50000` and the player begins with that
many points (the script, `test_start`).

With `[debug] god_at_start = 1` in the WaW bridge's settings the player
begins each map unable to be hurt, exactly as if `god` had been typed into
the console, so typing it there turns it off, and on again (the last stand
cannot be reached while it is on). This took three goes. The script first
kept the player invulnerable for as long as a setting was on, which nothing
typed could undo; then did it once at the start, and still nothing typed
could undo it. The reason is in the game's code: what a script can switch
(`EnableInvulnerability`) is a bit in the player's client record, and the
console's `god` flips another, the lowest of the switches on the player's
entity (`CoDWaW.exe+0xF4420`: `xor [entity+0x1B4], 1`). So the bridge sets
that one itself (`[waw] player_flags`), once for each time the player is
put into a map: the game sets those switches afresh then (to 0x800), and
the bridge leaves one of its own among them, one the game's code never
tests, to say it has been seen to.

## What has been checked, and what has not

Checked on 2026-10-09, by driving SWBF2 through the bridge's `[debug]`
settings, from pictures of the two windows, and from memory and the bridges'
logs while the user played:

- the kit, the ability selected and each use of it reach the WaW script, and
  the script's answers reach SWBF2;
- function 15 steps through abilities and function 7 uses a Jedi's; the
  user's own Force button and d-pad shortcuts arrive;
- pressing "next weapon" in SWBF2 alone is undone by the bridge;
- Boba Fett's rocket bursts in WaW, and (the user) its kills give points;
- the trimmed loadouts; wall ammunition (the user);
- push, choke, lightning and the thrown lightsaber kill (the user);
- a change of character leaves no body and no pick-up;
- the picture stands aside while WaW is paused;
- in third person, for a character with a gun, the camera is to one side,
  and the bridge's crosshair sits in the middle of SWBF2's own, clear of the
  character (a picture, Han Solo);
- from behind, the angles the game fires along now follow the middle of the
  screen as the player turns (read from the game while the user played), and
  the first shots watched afterwards killed the zombie in the middle of the
  screen both times one was there (15 pulls of the DL-44, 2 zombies); then
  40 rounds of the blaster rifle hurt zombies 11 times and killed 4, where
  77 rounds had hurt none before;
- WaW's jump is set by kit (the log: 150 units for Darth Vader);
- SWBF2's character crouches within a few hundredths of a second of WaW's
  player, jumps when they jump, and sprints (seen: Boba Fett's stride changes)
  with its stick following WaW's movement;
- SWBF2's grenade is found as it leaves the hand;
- SWBF2's magazine follows WaW's (a round fired there is put back at once
  while WaW's is full);
- the mod loads with no script errors;
- SWBF2 is heard with another window in front, and how loud each character's
  weapon is ("Sound");
- of SWBF2's HUD only the weapons are drawn, above WaW's round number, and
  the line on the horizon is gone (pictures of both windows, and a search of
  them for a run of green);
- SWBF2's crosshair is in the exact middle of WaW's picture from behind and
  through the eyes, with its ring, and WaW's own is off meanwhile (pictures;
  the WaW bridge's log);
- the clone's and the battle droid's weapons are as loud as anyone's with
  the bank of the arena's own, and the others are as they were ("Sound");
- the mod loads with no script errors with everything copied in from the
  other maps, and none came up in half an hour of the user's play;
- WaW's footsteps go off for the Emperor's kit and come back (the log), and
  the jump that kept hints off the screen from behind is found and taken out
  (the log).

- both machines stand where they were meant to (pictures taken as the user
  walked up to each), the Pack-a-Punch takes a weapon and hands back its
  second form (seen: the weapon lit up inside it, 5000 points gone), WaW's
  hands come up for the knuckles and the bottle (the bridge's log, twice,
  2.6 s each), a lightsaber's ammunition goes from the screen (the log), and
  the tally is on the Tab screen (a picture of the pause menu).

- neither machine can be walked into: read from the game while the user
  walked at each, the player came no closer to the Pack-a-Punch's middle
  than 40.0 units and to Quick Revive's than 39.9 (the block's face plus the
  player's own 15; before, 27.7, which is the mystery box, and 2.5). The
  blocks in the game's memory are type 0, contents 1, with the boxes asked
  for;
- `god_at_start`: the bridge's log says it was done, six seconds into the
  map; the player's switches read 0x40000801 and the client record's bit for
  the script's invulnerability is off;
- Boba Fett's flamethrower: with the user playing him, the weapon in hand
  went from the first to the second and back five times without the
  character changing, and SWBF2's bridge pressed "next weapon" each time
  (both logs). Which button they pressed cannot be told from here.

- more to take: the bridge's log says the setting was raised three seconds
  into loading, twenty-seven before the player was put in, and the player's
  health, the entity's most and the client record's most all read 200;
- going down no longer ends at the main menu: in the first game played with
  the fix the console's log has the player put down once and no "All stances
  disallowed", where the two games before it each ended with one;
- Quick Revive can be bought again with the blocks in (the console's log
  reached the end of a purchase), and its picture is on the screen after
  (a picture of the window);
- the scores button brings up the co-op scoreboard alone: a picture taken
  with it held shows the player's name, "Points 47670, Kills 3, Headshots
  0", and the game ran on;
- the name on it is the character's: the WaW bridge's log has the player
  called Clone Trooper, Han Solo, Chewbacca, Luke Skywalker and Obi-Wan
  Kenobi as the user went through them, and a picture with the scores button
  held reads "Obi-Wan Kenobi  50330  4  1".

Not yet checked (all built on 2026-10-09 and in the user's hands, none of it
seen by me):

- the last stand and its "Reviving" bar; that the fourth blow is the one
  that puts the player down, and that health comes back after the third;
  that SWBF2's list of players no longer comes up with Tab;
- that "change weapon" no longer reaches Boba Fett's flamethrower, that it
  goes into the Pack-a-Punch with the rifle and comes out better, that it
  now burns for two seconds and rests for one and a half, and what
  `wawbf_solid_pack` and `wawbf_solid_revive` say;
- the Pack-a-Punch's "use" place where it now is; the bowcaster made from
  the rifle: its reload, five fans to the magazine, a fan of what is left;
- the flamethrower with nothing of WaW's drawn: that the fire still burns
  what it reaches, that SWBF2's flame comes back by itself with the trigger
  held through a cooling off, and that the game answers "firing" for a
  flamethrower at all (`held_back` does nothing until it has);
- the change to and from the flamethrower made by the script, with the
  game's own slot idle and nothing at the bottom of the screen;
- the zombies walking off while the player is down; a trooper's grenade no
  longer seen in flight;
- lightning's sparks and sounds on a zombie, the choke's heads, the pictures
  and the voice for power-ups;
- the blow struck out of a sprint (the bridge's log will say each time it
  tries);
- that hints do come up from behind, and that the Emperor is quiet standing
  and heard crouched, by ear;
- aiming through the eyes with a weapon that has a scope;

- the bowcaster's charge reaching the script and its two shots;
- Force pull throwing what it kills towards the player; a lightsaber's kill
  taking a limb or the head off (the game's own routines, called by the
  script: no script error on loading, nobody has cut a zombie down yet);
- Leia's Ray Gun; SWBF2's sound against WaW's by ear (the levels are
  measured, below, not heard);
- the reload pressed in SWBF2 when WaW reloads, and the two ending together;
- that no SWBF2 grenade is ever seen (the first throw after SWBF2 starts was
  missed once before the search was changed);
- the lightsaber's cut landing only during a swing, against zombies;
- whether the camera still jumps with each shot in third person, and the
  DL-44's kick;
- the empty picture during a change of character;
- third-person shooting over a longer stretch, with every gun, and what the
  user makes of it; the rockets and the bowcaster's bolts from behind; how
  the camera to one side feels;
- whether the game minds `spawnflags` being written on a player (nothing
  seen so far);
- a jump in both games side by side, and that a second press in the air now
  does nothing in SWBF2;
- what the user makes of a lightsaber character running, not sprinting, when
  they sprint (seen in pictures of one sprint before the change was built
  in: a stride every 0.8 s).

Open:

- The user found the DL-44 and the sporting blaster "a bit weird" in third
  person, "not sure if holding aim offsets the reticule". Not reproduced:
  with aim held the camera stays behind and only the view narrows. What was
  changed is what sets those two apart from the rifle in the weapon files
  (the kick, and the scatter and offset when aimed, above).
- Each frame WaW first puts its camera at the player's eyes and then moves
  it behind them. A reader on another thread can catch it in between (about
  one look in a hundred from outside the game). Whether the bridge, which
  reads it as the frame is presented, ever does, has not been checked; it
  would show as the character jumping for one frame.

- Crouch was "a bit funky" on changing between first and third person; the
  bridge now waits 0.15 s before pressing crouch, on the guess that the
  unit's posture cannot be trusted for a frame or two as the view changes.
  The user then said it "seems to be good now".
- While the player turns fast, the line told to the script is a twentieth of
  a second old by the time the script uses it, so the spot aimed at trails
  the middle of the screen a little until they stop turning.
- `tools/probe/zombiehits.ps1` and `wawaim.ps1` assume a shot goes the way
  the player looks. `shotwatch.ps1` follows the angles the game really uses.

Known gaps:

- SWBF2's weapons that heat up can refuse to fire while WaW still does.
- SWBF2 shows its own count beside the ability (99), not WaW's.
- SWBF2's own HUD says the old character "died" at each change.
- A rocket in SWBF2 flies through its own empty arena, not WaW's rooms.
- Chewbacca's second weapon is SWBF2's guided rocket: fired, the game hands
  the player the rocket to steer, the character is not the thing followed
  for a second or two, and WaW is told there is no kit for that long.
- The clone trooper's and the battle droid's weapons fire with the other
  era's sounds ("Sound").
- The flamethrower's two halves work differently (heat against a magazine).
- About every 10 to 20 s SWBF2's field of view reads 36 degrees for a second
  (its own zoom?); not looked into.
