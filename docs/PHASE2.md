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
- [x] An arena that draws nothing but the player, and the whole frame laid over WaW: shots show, and so does the character in third person
- [x] WaW's camera behind the player too, its own soldier left out, and SWBF2 drawing from the same place: third person lines up
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
the world and is cut away with it, and so in either view is every shot the
weapon fires. That is why the cut is no longer what is used: see "Nothing to
cut", next. It remains as `[overlay] cut = 2`, for a world with a ground.

## Nothing to cut

The arena is ours, so instead of cutting the player's side out of the frame
the arena was changed to draw nothing else. `swbf2/arena/build.ps1`:

- **No ground.** Every world the tools know has a terrain, so it is kept,
  but its "active" square (four 16-bit cell numbers at byte 8 of the `.TER`:
  the part that is compiled, drawn and stood on) is moved to eight cells in
  a far corner.
- **An invisible floor.** The player stands on 25 of the game's own
  invisible collision blocks (`com_inv_col_64`, a 64 m cube with its corner
  at the object's position), tops at height 0, around where the player
  appears. The soldier stands and runs on them as on ground. They stop
  320 m across; past that there is nothing to stand on.
- **No sky.** The sky file loses its dome, and its fog is pushed out.
- **No command posts in sight.** They glow, so they are moved to the far
  corner. The mission script spawns the player from a path, not a post.

The frame went from 209 draw calls to about 90, and the game's own window
shows the character and the HUD on black.

Black is not see-through, though, and with `[overlay] cut = 0` the bridge
makes it so (`frameprobe::SetTransparentClears`). Two things in the frame
painted the whole picture solid:

- **The clears.** The game clears each picture to solid black. They are made
  clears to transparent black.
- **The far scene.** In the world's part of the frame the game lays its far
  scene, a full-size picture drawn earlier in the frame, in *behind*
  whatever is already there (a blend on the alpha already in the picture:
  source times one-minus-destination-alpha). The far scene is empty now, but
  it is laid down solid. It is recognised as a draw call, between the first
  and second depth-only clears, whose texture is a render target; such a
  call keeps its colour and is stopped from writing alpha. Found by saving
  the picture before each draw call of a frame and seeing which one took it
  from 2% solid to 100%.

What comes out is 90% see-through in either view, with the weapon or the
character, and the HUD, solid.

What this bought, seen in WaW's picture:

- **Shots.** The bolts leave the gun and fly off into WaW's world.
- **Third person.** The character, from behind, running in WaW's map.

SWBF2's picture is still laid on top of everything in WaW's: a bolt is not
stopped by a WaW wall, and a zombie between the camera and the character
appears behind the character.

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
   43 **game functions**, three codes of two bytes each. A code up to `0xFF`
   is a keyboard key (DirectInput scan code); a higher one is a raw control,
   `(code >> 8) - 1`. `tools/probe/bfbindings.ps1` lists it.
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
| 1 | secondary fire | the grenade count went down by one |
| 5 | zoom | the field of view goes from 51 to 22 degrees (`tools/probe/bffunctions.ps1`) |
| 7 | reload | a part-used magazine came back full |
| 8 | use | at a command post it opens the class menu, over the player's game |
| 12 | not reload | nothing seen |

`docs/PHASE3.md` has the ones found since (jump, crouch, the next weapon and
ability), and what 1 and 7 turn into for a character with a lightsaber.

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

`[swbf2] view_toggle` (F9) switches SWBF2's view, and the character runs,
turns and aims as the WaW player does. A frame recorded there while the arena
still had a ground (209 draw calls):

| Draw calls | What |
|---|---|
| 0 to 3 | set-up |
| 4 to 115 | the far scene, into a render target of its own |
| 116 to 172 | the near world, **the character in it**; the far scene is in the picture by the end of these too |
| 173 to 174 | after a copy of the picture; not identified |
| 175 to 208 | the HUD, after the second depth-only clear |

There is no weapon pass, and the character is not set apart from the ground
it stands on, so there is no clear to cut at. That is what "Nothing to cut",
above, was built for, and with it the character arrives in WaW's picture.

On its own that puts the character in the wrong place. WaW is still drawing
from the player's eyes, so the character stands a few metres in front of the
camera rather than where the player is. Three more things make it right, and
they happen together when SWBF2's view goes to third person (F9) and are
undone together when it leaves.

### WaW draws from behind the player

SWBF2's bridge says when its view is third person (`kBfThirdPerson`, read
from the same setting F9 flips: `[swbf2] third_person`). While it says so and
its picture is arriving, WaW's bridge sets WaW's own `cg_thirdPerson` to 1
(`[waw] third_person`). The setting was found the way `cg_drawGun` was: from
its name to the code that registers it to the pointer the game keeps to it.

| Setting | Pointer to it | Kind |
|---|---|---|
| `cg_thirdPerson` | `CoDWaW.exe+0x2F9CC14` | whole number |
| `cg_thirdPersonRange` | `+0x3288A30` | float, 120 |
| `cg_thirdPersonAngle` | `+0x328EBB0` | float, 0 |

The value is `0x10` into each. Only the first is written; how far back the
camera sits is left as the player has it.

### WaW leaves its own soldier out

That camera shows the player's own soldier, exactly where SWBF2's character
is about to be drawn. The game's scripts can hide an entity (`hide()`), and
what that does was read from the function the script method is listed with:

    eax = 0x176C6F0 + entity number * 0x378     ; the entity
    [eax + 8]    |= 0x20                        ; its flags
    eax = [eax + 0x180]                         ; its client record, if it has one
    [eax + 0xCC] |= 0x20                        ; the player's flags

`show()` clears the same bit. The player is entity 0 and its client record is
the one the player's position is already read from, so the bridge sets the
bit in those two places (`[waw] hide_body`) and clears it again afterwards.

### SWBF2 draws from where WaW's camera is

WaW's camera cannot be told where to go: it backs off behind the player
until a wall is in the way, and only WaW knows its walls. So WaW's is the
camera and SWBF2 is given it.

WaW's end is three floats and nine, just after the field of view that was
already being read: where the picture is drawn from (`CoDWaW.exe+0x3120354`)
and the directions it counts as forward, left and up (`+0x3120364`). They go
out with every sample (`cameraOrigin`, `cameraForward`, `cameraUp`).

SWBF2 keeps a camera as an object. Its renderer has one routine for readying
a camera to draw with (it starts at about `BattlefrontII.exe+0x2B76E0`), which
takes the camera from a pointer at `+0x3F58E0` and reads from it:

| At | What |
|---|---|
| `0x30` | which way is right, up and back: three rows of four floats |
| `0x60` | where it is |
| `0x70` | the same placement inverted, four rows: what drawing uses |
| `0xB0` | its lens |

The routine runs for each part of the frame. Just before it reads the camera
it makes a call, to set the world transform; that call
(`+0x2B77A0`) is sent through `OnCameraSetup` first (`swbf2/src/callhook.cpp`,
the same way the controller update is hooked), which writes both placements.
The game has put its own camera there by then and nothing has been drawn
with it yet.

What is written is WaW's camera *relative to WaW's player*, turned into
SWBF2's directions and metres and added to where the unit stands: the unit
is on SWBF2's floor at SWBF2's height, whatever staircase the WaW player is
on. Only the player's camera is touched (the HUD has one of its own, at the
origin), only in third person, and only once WaW's camera has actually moved
out of the player's head.

The first attempt keyed on the transform call itself, seen through the frame
probe's hook on the device. It never matched: the game sets every transform
from one wrapper, not from the routines that want them set, which
`[debug] transform_callers` shows.

### Aiming in third person

SWBF2's zoom is no use here. In third person it takes the character out of
the picture for a view down the sights (a screenshot taken while the player
happened to be aiming had nobody in it), and its zoomed lens is not WaW's
anyway. So in third person:

- **SWBF2 is kept zoomed out.** Aim is not passed on as a press of zoom
  (`input::SetAimAllowed`), whoever is holding it.
- **SWBF2 is given WaW's lens.** The camera object keeps the tangents of half
  its view, across and top to bottom, at `0x138` and `0x13C`, and at `0x140`
  a zoom they are divided by; the routine that readies the camera builds its
  projection from those. WaW's two tangents are written there (times the
  zoom, which is left alone) in the same hook that places the camera. When
  WaW narrows its view to aim, SWBF2's narrows with it and the character
  stays the size WaW's view of the room makes it.

Whether SWBF2 is zoomed is told from that zoom factor in third person, not
from the field of view, which is now WaW's.

### Checked

`tools/probe/camerafit.ps1` does this. Projecting the player's feet, and a
point 1.5 m above them, through each game's camera as read from memory,
eight times over three seconds while the player moved:

    WaW ( 0.002, -1.174) ( 0.002, -0.102)   SWBF2 ( 0.002, -1.175) ( 0.002, -0.101)
    WaW (-0.009, -1.158) (-0.009, -0.101)   SWBF2 (-0.009, -1.158) (-0.009, -0.100)

(across, up; as fractions of half the screen), with both cameras 3.34 m from
the feet. The two agree to a thousandth of the screen. With the player
aiming in WaW the lens read 0.770 x 0.433 in both and the feet still agreed;
while the player turns quickly SWBF2 is a frame behind, a few thousandths.

With WaW's distance of 120 the camera is at head height straight behind the
player, and looking level the feet are just off the bottom of the screen.
`cg_thirdPersonRange 180` or so in WaW's console shows the whole character;
SWBF2 follows whatever it is set to.

## Not done yet

- **What a shot does.** SWBF2's weapon fires, and WaW's own hidden gun fires
  with it. The bolt is seen, but it is WaW's bullet that hurts the zombie.
  Deciding which game owns the damage is Phase 3.
- **The other buttons.** Grenades, weapon switching and whatever a hero's
  abilities are on. The WaW records for them are in the table above; the
  SWBF2 function numbers have to be found, and the protocol carries only
  three buttons so far.
- **In first person, zoomed pictures do not line up.** WaW narrows its view
  when aiming by its own amount and SWBF2 by its own. Only SWBF2's scope is
  drawn there, so it does not show. (Third person is given WaW's lens.)
- **Two HUDs.** Both games' are on screen. Which parts of each survive is a
  design choice: SWBF2's crosshair and ammo belong to its weapon; WaW's
  points and round count belong to its game; SWBF2's minimap and health show
  an empty arena and a unit that cannot be hurt.
- **Third person is always on top.** The character is drawn over everything
  in WaW's picture, a zombie standing between it and the camera included.
- **Different window sizes.** The picture is stretched to WaW's size if they
  differ, which has not been tried.
- **How late the weapon is.** Probably a frame or two; not measured, and not
  noticeable.
