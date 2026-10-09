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
- Every character can step through its abilities: left on the d-pad, and a
  key. The Force is on right click or the left trigger.
- Force pull brings zombies to the player.
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
| 4 | Boba Fett | EE-3, flamethrower | `swbf2_ee3`, `m2_flamethrower_zombie` | wrist rocket (2), grenade (3) |
| 5 | Chewbacca | bowcaster, rocket launcher | `swbf2_bowcaster`, `swbf2_launcher` | grenade (2) |
| 6 | Leia | sporting blaster | `swbf2_sporting` | grenade (1) |
| 7 | Luke, Obi-Wan, Mace Windu, Darth Maul | lightsaber | `swbf2_saber` | throw (1), push (2) |
| 8 | Aayla Secura | lightsaber | `swbf2_saber` | throw (1), pull (2) |
| 9 | Anakin, Darth Vader | lightsaber | `swbf2_saber` | throw (1), choke (2) |
| 10 | Yoda | lightsaber | `swbf2_saber` | pull (1), push (2) |
| 11 | the Emperor, Count Dooku | lightsaber | `swbf2_saber` | lightning (1), choke (2) |
| 12 | General Grievous | lightsabers | `swbf2_saber` | none |

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
| The Emperor jumps as high as the other lightsaber characters | `JumpHeight` | he shares a kit with Count Dooku |

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
| `swbf2_sporting` | `sw_357` | single | 0.5 s | 300 | endless | | a beam: 0.5 s, 300, heat |
| `swbf2_bowcaster` | `shotgun` | see "The bowcaster" | | | 35 | 1.75 s | 35, 1.75 s |
| `swbf2_launcher` | `panzerschrek` | as stock | | as stock | 1 | 4.0 s | 1, 4.0 s |
| `swbf2_saber` | `shotgun` | see "The lightsaber" | | none | endless | | |

A bullet in WaW arrives at once, so Leia's beam needs nothing more than a
single shot with no spread to it. The DL-44 has a third of the .357's kick
(`kick = 0.35`, which scales every view and gun kick field), and so has
Leia's sporting blaster, which is made from the same gun. Aimed, the .357 and
the Walther also scatter their shots a little (`adsSpread` 1.15 degrees) and
the .357 fires a touch off the line of sight (`adsAimPitch`), to suit sights
that are not on the screen here; both are set to nothing, as the STG-44 the
rifle is made from has them.

"Endless" weapons are topped up by the script and never reload
(`level.wawbf_endless`); in SWBF2 they heat up instead, which WaW does not
follow. The flamethrower is the game's own, which also works by heat where
SWBF2's has a magazine; that one is not matched.

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
  uses (the unit cannot be hurt): `1e37 * (1 + n / 1024)`, where `n` is the
  kit plus 32 for a hero or villain plus 64 for one with a lightsaber.
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
| left on the d-pad, or X | function 15, next ability | read by the WaW bridge itself: `[waw] next_ability_pad`, `next_ability_key` |
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
| pull | 40 m | 50° | 3 | carries each to just in front of the player |
| choke | 20 m | 40° | 1 | 250 every tenth of a second while held |
| lightning | 15 m | 80° | 10 | 125 each every tenth of a second while held |

Pull fastens the zombie to something that can be moved, moves that, and lets
go (`pull`). Only zombies that are already inside (`ignoreall` is false once
one has come through its window): one brought in early would walk back out
to the window it was sent to.

All of it is in `level.wawbf_*` at the top of the script.

## The bowcaster

In SWBF2 it charges for as long as the trigger is held (full at 1.25 s, shown
round the crosshair) and fires when the trigger is let go: a fan of seven
bolts, 0.7° from one to the next, 75 each; or, charged all the way, one bolt
of 300. No WaW weapon fires on letting go. So `swbf2_bowcaster` only stands
for it (the magazine, the reload, the name), and the shot is SWBF2's: the
bridge says when its bowcaster has fired and how far it was charged, and the
script (`bowcaster`) works the shot out. Each bolt is a line from the
player's eye that hurts the first zombie it meets. The fan's bolts do 75
times one plus the charge, so up to twice as much; a full charge is the heavy
bolt, 1000 through the first five (SWBF2's does 300 and goes through nobody;
"powerful" was asked for). Nothing is drawn for them: the bolts on screen are
SWBF2's.

The rounds are counted by the script, one for each of SWBF2's shots; the
round WaW's stand-in uses when its trigger is pulled is put back.

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
3. The bridge points the shot from the eyes at that spot, and draws its own
   crosshair there (`overlay::SetMark`), which is the middle of the screen.

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

## Testing

Start WaW with `+set wawbf_god 1` and the player cannot be hurt.

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
- the trimmed loadouts; wall ammunition, the box and cabinet shut (the user);
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
- the mod loads with no script errors.

Not yet checked:

- the bowcaster's charge reaching the script and its two shots;
- Force pull carrying a zombie;
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
- WaW still plays its own gunfire for the weapons made from guns.
- The flamethrower's two halves work differently (heat against a magazine).
- About every 10 to 20 s SWBF2's field of view reads 36 degrees for a second
  (its own zoom?); not looked into.
