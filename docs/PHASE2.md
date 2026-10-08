# Phase 2: Overlay

Goal: SWBF2's first-person weapon and HUD drawn over WaW's picture, and the
player's fire and abilities sent to SWBF2. See `DESIGN.md` for where this
sits; `PHASE1.md` for what it stands on (the unit follows the WaW player, the
two cameras agree, SWBF2 sits in an empty arena).

## Status

- [x] Found where in its frame SWBF2 draws the first-person weapon
- [x] The weapon and HUD cut out of the frame, with transparency
- [x] The picture carried to WaW and drawn over it, every frame
- [x] Judged by eye: looks good, no lag, no flicker, no drop in frame rate
- [x] WaW's own gun hidden while SWBF2's is drawn
- [x] Fire sent to SWBF2, whatever it is bound to in either game (checked with a controller)
- [x] Aim and reload sent the same way
- [x] A weapon that does not run out of ammunition in an arena with none to pick up
- [ ] The other buttons (secondary fire, weapon switching, abilities)
- [ ] One HUD, not two
- [ ] SWBF2 hidden while this runs (`hidden = 1` exists; not yet tried together)

## How SWBF2 draws a frame

Nothing documents it, so `common/frameprobe.cpp` writes it down. With
`[debug] frame_probe = 1` it hooks a dozen of the Direct3D device's calls, and
each time `[debug] frame_dump` is changed it records the next whole frame:
every clear, every change of render target, depth buffer, viewport and
projection, how many draw calls came between them, and the picture so far at
each depth-only clear and at the end.

A first-person frame in the arena, 231 draw calls:

| Draw calls | What | Sign |
|---|---|---|
| 0 to 3 | set-up | |
| 4 to 129 | the far scene, into a render target of its own | projection with the near plane at 2.0 |
| 130 to 188 | the near world, into the back buffer | depth-only clear, then near plane 0.5 |
| 189 to 196 | **the first-person weapon and arm** | depth-only clear, then near plane 0.3 |
| 197 to 230 | the HUD | a different projection altogether |

The picture saved at the second depth-only clear is the world with no weapon
in it; the picture at the end has the weapon and the HUD. On the spawn screen
the frame has the same shape, with the menu and its turning character where
the weapon and HUD would be.

## The cut

So the second depth-only clear of a frame is the seam: everything before it
is the world, everything after is what WaW should get. With
`[overlay] publish = 1` the bridge makes that clear wipe the picture as well,
to transparent black. What is left at the end of the frame is the weapon and
the HUD on nothing.

"On nothing" is exact, because the back buffer has an alpha channel
(`A8R8G8B8`) and the game writes to it honestly: solid models write full
alpha, the HUD's blended parts write part, and what nothing touched keeps the
zero it was cleared to. Measured on the spawn screen, the alpha channel is a
clean silhouette of the character and the buttons. No colour key is needed,
and the weapon's edges come with their own soft alpha.

Two things follow from where the alpha comes from:

- Blended pixels end up with their colour already multiplied by their alpha
  (they were blended onto black), so the picture is laid over WaW's as
  `picture + waw * (1 - alpha)`, not the usual blend.
- When SWBF2 dims its screen, as it does behind the spawn menu, that arrives
  as a faint alpha over the whole picture, and WaW's picture dims behind the
  menu just as SWBF2's world would have.

The cut is by position ("the second depth-only clear"), which is right for
first person and the spawn screen. In third person the character is part of
the world and is cut away with it: see "Third person", below.

## Getting the picture across

`common/overlay.cpp`. Both games use plain Direct3D 9, which cannot share a
surface between processes, so the picture goes through main memory:

- SWBF2, at the end of each frame: read the back buffer into a main-memory
  surface (`GetRenderTargetData`) and copy it into a second shared mapping,
  `Local\WaWBF_frame_v1`. The mapping holds two pictures; the one not being
  shown is filled and then made current, so WaW never reads half of one.
- WaW, at the end of each scene: if there is a new picture, copy it into a
  texture; draw the texture across the screen with every piece of device
  state saved first and put back after. If no new picture has come for half
  a second, draw nothing: better no weapon than a frozen one.

At 1280x720 that is 3.7 MB copied twice a frame. WaW stayed at 91 frames a
second and SWBF2 at 80, the same as before.

## Fire, aim and reload

The WaW bridge says which buttons are held (`WawPlayerState::buttons`: attack,
aim, reload); the SWBF2 bridge works the weapon (`swbf2/src/input.cpp`,
switched on with `[swbf2] forward_fire = 1`).

Neither end deals in keys or buttons. Each game already turns the player's
bindings into "this action is on", and that is where both ends work: WaW's
"attack" is read after WaW's bindings, and SWBF2's "fire" is switched on
after SWBF2's. A player can have fire on a mouse button in one game and a
controller's trigger in the other, or change either, and nothing here needs
to know.

### What did not work

Both ends were first written around a particular button, and both failed for
the first player to try them, who uses a controller:

- WaW's end read the left mouse button. The right trigger is not the left
  mouse button.
- SWBF2's end pressed the mouse button for the game, by hooking its
  DirectInput mouse and answering "left button down". The press arrived (the
  game's mouse object and its table of raw controls both showed it) and the
  gun did not fire: with fire on a controller's trigger, the mouse button was
  bound to nothing.

### WaW: which buttons are held

The game keeps a 20-byte record for each of its actions (`+attack`,
`+reload`, `+speed` ...). When a bound key or button goes down, the action's
"down" function puts that key's number in the record and sets a byte at
`+0x10`; "up" clears it. The byte is the game's own answer to "is attack
held".

The Steam exe is encrypted on disk, so this was read from the running game
(read-only): find the text `+attack`, find the code that registers it as a
command, read the few bytes of the function it registers. That function does
nothing but load the record's address and call "down".
`tools/probe/wawactions.ps1` does those steps for a list of actions:

| Action | Record | Held byte |
|---|---|---|
| `+attack` | `CoDWaW.exe+0x2C0FE4C` | `+0x2C0FE5C` |
| `+speed` (aim; `+speed_throw` sets it too) | `+0x2C0FDAC` | `+0x2C0FDBC` |
| `+reload` | `+0x2C0FEC4` | `+0x2C0FED4` |
| `+usereload` | `+0x2C0FED8` | `+0x2C0FEE8` |
| `+frag` | `+0x2C0FE74` | `+0x2C0FE84` |
| `+smoke` | `+0x2C0FE88` | `+0x2C0FE98` |
| `+melee` | `+0x2C0FE9C` | `+0x2C0FEAC` |
| `+activate` | `+0x2C0FEB0` | `+0x2C0FEC0` |
| `+sprint` | `+0x2C0FF50` | `+0x2C0FF60` |
| `+gostand` | `+0x2C0FDE8` | `+0x2C0FDF8` |

`[waw] held_fire`, `held_aim` and `held_reload` take the held bytes;
`held_reload` takes both kinds of reload, since which one a player has
depends on their layout. The first word of a record is the number of the key
holding it down: for this player 19, a controller's right trigger, for attack
and 3, its X button, for reload.

### SWBF2: how the game gets from a button to a shot

Read from a disassembly of the exe. Addresses are offsets from where
`BattlefrontII.exe` is loaded (Steam build).

1. Each player has a controller object; the first player's is at
   `+0x1ABE078`. Once a frame its update (`+0x14B80`) copies every device
   into one flat array of **raw controls**: 760 floats at controller `+0x14`,
   76 to a device.
2. The player's **bindings** are a table at controller `+0x20BC`: for each of
   43 **game functions**, two codes. A code up to `0xFF` is a keyboard key
   (DirectInput scan code); a higher one is a raw control, `(code >> 8) - 1`.
3. `+0x153C0` walks that table and, for every binding that is pressed, calls
   `+0x12B640` to switch the function on in the player's **control state**
   (pointer at controller `+0x25D0`). The state is four floats for the
   movement and look axes, and at `+0x10` one bit for each function that is
   on. It is emptied (`+0x12B8B0`) at the start of every update.
4. The soldier is driven from the control state. Nothing after this point
   knows what a mouse is.

Functions 0 to 7, 9 to 12 and 29 stay on while their button is down; the rest
below 30 are on only for the update in which it went down. 30 and up are not
bits but the axes: 35 to 38 are strafe right, strafe left, forward and back.

`tools/probe/bfwatch.ps1` shows the control state changing as the player
presses things, and `tools/probe/bfcontrols.ps1` the raw controls.

### SWBF2: which function is which

The game does not name them anywhere that could be read, so each was found by
holding it on with `[debug] force_functions` and seeing what the soldier did.

| Function | What | How it was told |
|---|---|---|
| 0 | primary fire | pictures of the window: flash, recoil, the bolt landing |
| 1 | secondary fire, probably | the grenade count went down by one; seen once |
| 5 | zoom | the field of view goes from 51 to 22 degrees (`tools/probe/bffunctions.ps1`) |
| 7 | reload | a part-used magazine came back full |
| 8 | use | at a command post it opens the class menu, over the player's game |
| 12 | not reload | nothing seen |

Three things made reload slow to find, and are worth knowing before looking
for another:

- **The magazine is the ring of marks round the crosshair**: one mark for each
  round left. The number beside the weapon is all the ammunition carried, and
  reloading does not change it.
- **The ring hides itself seven seconds after it last changed**, whatever it
  was showing. A ring that goes clean some seconds after a button was pressed
  is the ring hiding, not the weapon reloading; that was read as a reload
  twice. A reload shows within two seconds, as the ring going to full.
- **An empty magazine reloads by itself**, so a test that fires it dry proves
  nothing about the button pressed afterwards.

The player's own bindings are the quicker way in. The table at controller
`+0x20BC` says which function each of their buttons works, and they know what
their buttons do: reload was found the moment the player said theirs was down
on the d-pad, after a guess from the usual controller layout (12, the X
button) and a search by trial had both gone nowhere.

### SWBF2: what the bridge does

It turns the function on in the control state, in the same update, just after
the game has filled the state in and before anything reads it: the last call
the controller's update makes with that frame's input (`+0x1537B`) is sent
through a few bytes of our own first. Writing the bit from the bridge's frame
hook instead does nothing, because the next update empties the state before
the soldier looks at it.

So it does not depend on the player's bindings, and SWBF2 does not need to be
able to see a device at all, which it cannot from behind WaW. Whatever the
player really presses in SWBF2 still works; the bridge only adds.

The exe's bytes at the call are checked before it is changed. A different
build is left alone and the log says so.

Fire and reload are simply on for as long as WaW's are held
(`fire_function`, `reload_function`).

Aim cannot be done that way. WaW's aim is held; SWBF2's zoom is a press, once
to go in and once to come out. Holding the function on zooms in and leaves it
there. So the bridge presses zoom (`aim_function`), for two updates, whenever
the game is not zoomed the way WaW's aim is held, and it knows which way the
game is zoomed from the field of view it is drawing with, which nothing else
narrows (`zoomed_below_fov`, 40 degrees; unzoomed is 51 and zoomed 22). The
zoom takes a quarter of a second to move, so a second press waits 400 ms for
the first to show, and after two presses that changed nothing (a unit with
nothing to zoom) it is left alone until WaW's aim changes. Looking rather
than counting presses means a respawn, or a press that the game ignored,
cannot leave the two games permanently out of step.

In first person SWBF2 draws zoom as a scope across the whole screen, and that
is what arrives over WaW's picture.

### End to end

`tools/probe/firelink.ps1` watches one of WaW's action records and one of
SWBF2's function bits together. With the player on a controller:

- fire: 6 pulls, each held down by WaW's key 19 (the right trigger), SWBF2's
  fire on in all 6, about 15 ms after;
- reload: 4 presses, each by key 3 (the X button), SWBF2's reload on in all
  4, 15 to 32 ms after.

Aim was checked by the field of view: 21.6 degrees while WaW's aim was held,
51.1 again within a second of letting go, and by the player.

## Ammunition

The arena has nowhere to get any, and a soldier that follows a WaW player
through a few rounds of zombies shoots its four magazines and is left with a
rifle that does nothing; reload then looks broken too, since there is nothing
to reload from. `swbf2/arena/WAW_arena.lua` gives every class 99 magazines
for its first weapon (`WeaponAmmo1`). The magazine still empties and still
has to be reloaded.

This is a stand-in. Whose ammunition it is, WaW's or SWBF2's, belongs with
the question of whose damage it is.

## One gun

WaW draws its own gun unless its `cg_drawGun` setting is 0. The bridge keeps
that at 0 while SWBF2's picture is being drawn over WaW's and puts it back to
1 if the picture stops, so the player is never left with no gun or two.
`[waw] draw_gun` is the byte: the setting is found through the pointer WaW
keeps to it (`CoDWaW.exe+0x3066528`), and its value is `0x10` into it.

Putting `+set cg_drawGun 0` on WaW's command line does not last, which is why
it is written rather than set once.

## Changing character

The player is put in the world by the mission itself, and changes character
with a key: F10 for the next of team 1's characters (the heroes, in the
heroes roster), F11 for the next of team 2's. SWBF2's spawn screen is never
needed, which it could not be once the game is hidden.

The changing is done by the arena's mission script
(`swbf2/arena/WAW_arena.lua`), with functions the game's own campaign uses to
turn a soldier into a hero: `SelectCharacterTeam`, `SelectCharacterClass` and
`SpawnCharacter`, the last given the place the old unit stood
(`GetEntityMatrix`). The old unit is removed with `KillObject` first; a
character that is still in the world cannot be spawned again.

The bridge cannot call a script. What it can do is write to the unit, and
what the script can do is read the unit's health (`GetObjectHealth`). The
unit cannot be hurt, so its health carries nothing: the bridge asks by
setting it to 9e36 or 8e36 (`[swbf2] next_hero`, `next_villain`), and a timer
in the script looks ten times a second. Health is the two floats at `0x144`
and `0x148` in the soldier object, found by looking in it for the 1e37 the
script sets.

From the key going down to the new character being followed: 160 to 240 ms.
`ForceHumansOntoTeam1` in the script skips the "pick a team" screen, and with
no unit at the start of a mission the same timer spawns one, so SWBF2 goes
from its icon to a character in the world with nobody touching it.

## Third person

Looked at, not built. `[swbf2] view_toggle` (F9) already switches SWBF2's
view, and the character runs, turns and aims as the WaW player does. A frame
recorded there (209 draw calls):

| Draw calls | What |
|---|---|
| 0 to 3 | set-up |
| 4 to 115 | the far scene, into a render target of its own |
| 116 to 172 | the near world, **the character in it**; the far scene is in the picture by the end of these too |
| 173 to 174 | after a copy of the picture; not identified |
| 175 to 208 | the HUD, after the second depth-only clear |

There is no weapon pass, and the character is not set apart from the ground
it stands on, so there is no clear to cut at. Two ways to get it out:

- **Draw nothing else.** The arena is ours. With no terrain and no sky, and
  the player standing on the game's own invisible collision blocks
  (`com_inv_col_64`, listed in its `ingame.lvl`), the character is all there
  is, and the
  picture only needs clearing to transparent at the start. Anything the
  character does would then come across too: bolts, explosions, a thrown
  lightsaber, in first person as well, where the bolts are missing now.
- **Skip everything else**, by telling the character's draw calls from the
  ground's. Needs no new arena but has to recognise a character by how it is
  drawn.

The first is the one to try. Either way three things remain: WaW has to draw
from behind the player too (`cg_thirdPerson`), without its own soldier in the
picture; the two cameras have to sit in the same place, and WaW's moves in
when a wall is behind the player where SWBF2's has no wall to meet; and
SWBF2's picture always lands on top of WaW's, zombies in front of the player
included.

## Not done yet

- **What a shot does.** SWBF2's weapon fires, and WaW's own hidden gun fires
  with it. The bolt is part of SWBF2's world, which is cut away, so only the
  flash and the recoil reach WaW's picture; and it is still WaW's bullet that
  hurts the zombie. Deciding which game owns the damage is Phase 3.
- **The other buttons.** Grenades, weapon switching and whatever a hero's
  abilities are on. The WaW records for them are in the table above; the
  SWBF2 function numbers have to be found, and the protocol carries only
  three buttons so far.
- **Zoomed pictures do not line up.** WaW narrows its view when aiming by its
  own amount and SWBF2 by its own; nothing matches them. It does not show
  while SWBF2's world is cut away.
- **Two HUDs.** Both games' are on screen. Which parts of each survive is a
  design choice: SWBF2's crosshair and ammo belong to its weapon; WaW's
  points and round count belong to its game; SWBF2's minimap and health show
  an empty arena and a unit that cannot be hurt.
- **Third person**, as above: looked at, not built.
- **Different window sizes.** The picture is stretched to WaW's size if they
  differ, which has not been tried.
- **How late the weapon is.** Probably a frame or two; not measured, and not
  noticeable.
