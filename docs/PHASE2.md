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
- [ ] WaW's own gun hidden (by hand for now: `cg_drawGun 0` in its console)
- [ ] Fire and abilities sent to SWBF2
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

## Not done yet

- **Fire.** The player's clicks only reach WaW, so SWBF2's weapon never
  fires. Next.
- **Two guns.** WaW still draws its own. `cg_drawGun 0` hides it; it should
  be set by the mod, not typed.
- **Two HUDs.** Both games' are on screen. Which parts of each survive is a
  design choice: SWBF2's crosshair and ammo belong to its weapon; WaW's
  points and round count belong to its game; SWBF2's minimap and health show
  an empty arena and a unit that cannot be hurt.
- **Third person**, as above.
- **Different window sizes.** The picture is stretched to WaW's size if they
  differ, which has not been tried.
- **How late the weapon is.** Probably a frame or two; not measured, and not
  noticeable.
