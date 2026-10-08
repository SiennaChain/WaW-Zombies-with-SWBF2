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
- [ ] The other buttons (secondary fire, reload, abilities): the way is there, the numbers are not
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
first person and the spawn screen. Third person has not been looked at: the
character is part of the world there and would be cut away.

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

## Fire

The WaW bridge says which buttons are held (`WawPlayerState::buttons`); the
SWBF2 bridge pulls the trigger (`swbf2/src/input.cpp`, switched on with
`[swbf2] forward_fire = 1`).

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

`[waw] held_fire`, `held_alt_fire` and `held_reload` take the held bytes. The
first word of a record is the number of the key holding it down: 19 is a
controller's right trigger, which is what showed up there for this player.

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

Function 0 is primary fire. Functions 0 to 7, 9 to 12 and 29 stay on while
their button is down; the rest below 30 are on only for the update in which
it went down. 30 and up are not bits but the axes: 35 to 38 are strafe right,
strafe left, forward and back.

`tools/probe/bfwatch.ps1` shows the control state changing as the player
presses things, and `tools/probe/bfcontrols.ps1` the raw controls.

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

Checked with `[debug] force_functions = 0x1`, which holds function 0 on with
nobody touching anything: with SWBF2 behind WaW, pictures of its window show
the muzzle flash, the recoil and the bolt landing.

`[debug] force_functions` is also how the other numbers are to be found: hold
one bit on and see what the soldier does. `alt_fire_function` and
`reload_function` wait for that.

### End to end

`tools/probe/firelink.ps1` watches WaW's attack record and SWBF2's fire bit
together. With the player on a controller: 6 pulls, each held down by WaW's
key 19 (the right trigger), SWBF2's fire on in all 6, about 15 ms after.

## One gun

WaW draws its own gun unless its `cg_drawGun` setting is 0. The bridge keeps
that at 0 while SWBF2's picture is being drawn over WaW's and puts it back to
1 if the picture stops, so the player is never left with no gun or two.
`[waw] draw_gun` is the byte: the setting is found through the pointer WaW
keeps to it (`CoDWaW.exe+0x3066528`), and its value is `0x10` into it.

Putting `+set cg_drawGun 0` on WaW's command line does not last, which is why
it is written rather than set once.

## Not done yet

- **What a shot does.** SWBF2's weapon fires, and WaW's own hidden gun fires
  with it. The bolt is part of SWBF2's world, which is cut away, so only the
  flash and the recoil reach WaW's picture; and it is still WaW's bullet that
  hurts the zombie. Deciding which game owns the damage is Phase 3.
- **The other buttons.** WaW's aim and reload are sent; SWBF2 does nothing
  with them until their function numbers are known.
- **Two HUDs.** Both games' are on screen. Which parts of each survive is a
  design choice: SWBF2's crosshair and ammo belong to its weapon; WaW's
  points and round count belong to its game; SWBF2's minimap and health show
  an empty arena and a unit that cannot be hurt.
- **Third person**, as above.
- **Different window sizes.** The picture is stretched to WaW's size if they
  differ, which has not been tried.
- **How late the weapon is.** Probably a frame or two; not measured, and not
  noticeable.
