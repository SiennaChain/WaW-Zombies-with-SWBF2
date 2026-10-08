# Phase 1: Puppet

Goal: the SWBF2 unit follows the WaW player's position and facing smoothly,
from inside SWBF2's own frame, while SWBF2 runs unfocused; then SWBF2's camera
matches WaW's. See `DESIGN.md` for where this sits.

Carried over from Phase 0 (`PHASE0.md`): the link, both games' addresses, and
the proof that a position written into SWBF2 is accepted.

## Status

- [x] SWBF2 keeps playing while unfocused (`keep_running`, from Phase 0)
- [x] The unit is moved once per frame, in step with the game
- [x] It stands on SWBF2's ground instead of "falling"
- [x] It faces where the WaW player faces
- [x] Nothing is written unless the target is confirmed to be a soldier
- [x] Left and right settled by eye: `z_sign = -1` (see Findings)
- [x] Movement looks smooth: "turns correctly and very smooth" (2026-10-08)
- [ ] The unit animates (it slides in its idle pose). `follow_velocity` is
      built and untested: see "The soldier object"
- [ ] The unit aims up and down with the WaW player. `follow_pitch` is built
      and untested
- [ ] First / third person switched by a key. `view_toggle` is built; the
      address is not found yet (`tools/probe/bftoggle.ps1`)
- [ ] SWBF2's camera matches WaW's
- [ ] SWBF2 hidden rather than merely behind another window
- [ ] An empty arena with an invulnerable unit (needs the SWBF2 mod tools)

## How it works

**Once per frame.** `common/proxy_d3d9.cpp` hooks the Direct3D device's
`Present`, which the game calls from its own rendering thread after it has
updated the world for that frame. `BridgeFrame()` runs there. Phase 0 wrote
from the bridge thread instead, with no relation to the game's update, which
is why the unit jittered. If no frames are being drawn the bridge thread takes
over, so the unit does not drift.

SWBF2 uses the device's `Present`. WaW does not: it presents through a swap
chain. Hooking `IDirect3DSwapChain9::Present` crashed WaW at the first call
(access violation at a garbage address, stack too damaged for the crash log
to run) and the cause was not found, so that hook was removed. `EndScene` is
hooked as the fallback and is what WaW uses. A game can call it more than once
a frame, so `BridgeFrame` must not assume exactly one call per frame.

**Two frame rates.** WaW draws about 90 frames a second and SWBF2 about 80,
and neither knows about the other. The first version passed "the newest
position" across, sampled on a third clock (the WaW bridge's 60 Hz timer).
Some SWBF2 frames then got no movement and the next got two frames' worth,
which looked jittery even though the average error was a fraction of an inch.
Now:

- WaW publishes from its own frame, only when the player has moved or turned
  (or every 50 ms as a heartbeat), with the time it was read
  (`WawPlayerState::timeUs`, protocol version 2). The clock is the system
  performance counter, which is the same in both processes.
- SWBF2 keeps the two newest samples and places the player on the line
  through them at `now - follow_delay_ms`. With the default 12 ms, about one
  WaW frame, that is mostly interpolation and runs slightly past the newest
  sample when none has arrived yet. A gap over 250 ms or a jump over 60 units
  resets it, so a pause or a respawn is not turned into a glide.

What that looks like in memory, from `tools/probe/bftrace.ps1` (12 s, 961
frames, walking in WaW): the position changes exactly twice per 12.5 ms
frame. Once is the bridge's write, a 6.0 cm step at the median while moving
(4.8 m/s at 80 frames a second, which is WaW's run speed), differing from the
step before by 5% at the median and 15% at the 90th percentile. The other is
the game's own, about 0.1 mm along the ground and nothing in height, every
frame, moving or not. So the game is not fighting the write in any way that
matters, and by the numbers the motion is even. Watched side by side it was
judged very smooth, with the unit turning the right way.

The WaW addresses themselves were never the problem: measured with
`tools/probe/wawrate.ps1`, `player_origin` changes 91 times a second while
walking, once per frame, not at a slower internal tick as first assumed.

**Height is SWBF2's.** `follow_height = 0` (the default) writes only x and z
and keeps whatever height the unit has, so SWBF2's gravity and ground decide
it. Phase 0 imposed Nacht's floor heights on a different map, which the game
read as falling: fall animation, damage, and once a launch.

**Facing.** A soldier's transform is a 4x4 whose last row is its position,
so the 16 floats from 0x30 before the position are right, up, forward,
position. `follow_facing = 1` rewrites the three direction rows every frame
from the WaW yaw. The game keeps them: in every frame checked, the forward row
read back was the one written the frame before.

**Only ever a soldier.** `player_position` follows whatever the camera shows.
While the player is dead that is not a unit, and writing a transform over it
crashed the game the first time facing was tried. `unit_type` and
`unit_position_offset` identify a soldier (its object starts with
`BattlefrontII.exe+0x39D114`, position 0x120 in); nothing is written unless
that matches. A death now stops following and a respawn resumes it.

**If it does crash.** `common/crashlog.cpp` writes the exception, where it
happened (module + offset), the address touched and the callers to the bridge
log. It only observes.

**Trying an address without rebuilding.** `[debug] poke` in SWBF2's
`wawbf.ini` writes one value into the game each time the line is changed. It
has to be done from inside the game: the antivirus blocks outside tools that
write to another process.

## Results (2026-10-08)

`tools/probe/followtest.ps1` waits for a live unit, sets the anchors from
where both players are standing, switches following on through `wawbf.ini`,
and measures both games read-only for 75 s.

| | min | median | max |
|---|---|---|---|
| Position gap, WaW units (1 = 1 inch) | 0.0 | 0.1 | 9.6 |
| Facing error, degrees | 0.0 | 0.0 | 0.0 |
| Unit height in SWBF2, metres | -63.6 | -62.8 | -62.7 |

The WaW player walked 6,710 units and turned 2,648 degrees. The unit died
once; following stopped and resumed 15 s later with no crash. Height varying
by under a metre is the unit standing on SWBF2's terrain.

## Findings

- **Handedness: `z_sign = -1`, the protocol default, is right.** Settled by
  eye: with `1` the unit walked forwards and backwards correctly but turned
  left when the player turned right. The results table above was measured
  with `1`; the numbers do not depend on it, because position and facing are
  mirrored together.

  The first write-up of this claimed the opposite, from the unit's transform
  having right = up x forward. That proves nothing: it holds for every rotation
  matrix in either handedness. Which way a coordinate system is handed cannot
  be read off the numbers; someone has to look.
- **No scalar yaw** was found in the object, in radians or degrees. The body's
  transform is the only place its heading lives, which is why writing it works.

## The soldier object

Worked out from one 25 s recording of the player running about in SWBF2
(`tools/probe/bfrecord.ps1 -SaveTo`, mined offline with
`tools/probe/bfrecan.ps1`). Offsets are from the start of the object; subtract
0x120 for the offset from `player_position`.

| Offset | What | How sure |
|---|---|---|
| 0x000 | class word, `BattlefrontII.exe+0x39D114` for a soldier | used every frame |
| 0x0F0 | transform: right, up, forward, position rows | written every frame |
| 0x2C0, 0x2C4 | movement asked for, forwards and to the left, each -1 to 1 | fits the recording; not written |
| 0x31C | eye: the position plus 1.80 m | exact in every sample |
| 0x328 | aim direction, unit length, pitch included | exact against 0x4E8 |
| 0x4DC | velocity, x y z, metres per second | correlation 0.998 / 0.995 / 0.998 with the measured velocity |
| 0x4E8 | aim pitch, radians, positive looking up | equals the pitch of 0x328 to 0.00 degrees |
| 0x548 | a second aim direction, about 0.7 degrees higher | probably where shots go |

- **Velocity was there all along.** The first search judged each candidate
  against the step between two neighbouring samples. The game moves the unit
  once per frame and the recorder samples at its own rate, so that step is
  anything from nothing to two frames' worth, and the real field failed the
  test. Measured over 60 ms either side instead, 0x4DC matches to a few
  centimetres a second.
- **Aim is yaw from the body plus one pitch angle.** In the recording the aim
  direction's heading equalled the body's exactly, and its pitch equalled
  0x4E8 exactly. So `follow_pitch` writes that one angle and leaves the game
  to work out the rest.
- **The third-person camera** sat 3.0 m behind the unit along its line of
  sight and 1.6 m above the unit's origin, looking 10 degrees further down
  than the aim. That is the game's own doing from the unit and its aim;
  nothing here writes the camera.
- **`BattlefrontII.exe+0x3DE378` is not a camera-to-world matrix**, as Phase 0
  took it to be. It is three rows of the view-projection matrix followed by
  the camera's position. Its third row is the view direction and its fourth
  the position, which is all that has been read from it, so nothing measured
  so far was wrong.
- **0x2C0 and 0x2C4 look like the stick.** While running their two values
  made a unit-length pair, 0x2C0 times 7 m/s came close to the forward speed,
  and both were zero standing. They are most likely what the game turns into speed and
  into the choice of animation. They are filled in from the controller before
  the unit is updated, so a write made after the frame is drawn, which is
  where this bridge writes, is expected to be overwritten before it is used.
  `[debug] hold1` will say whether that is so.
- **The player runs at 6.6 m/s in SWBF2** (5.0 to 9.5 across the recording)
  against 4.8 m/s in WaW, so a unit animated at WaW's speed will jog.

## Trying a field without rebuilding

Each build of the DLL costs a restart of SWBF2 and a match started by hand,
so the bridge now carries what is needed to try things live, all from
`wawbf.ini`, which is re-read within a second of being saved:

- `[debug] poke` writes one value once.
- `[debug] hold1` to `hold8` write a value every frame, after the following,
  and only while the camera is on a live unit. Once a second the log says
  whether the value was still there a frame later, and what the game put in
  its place if not. That separates fields the game takes from us (the
  transform, hopefully the pitch) from fields it recomputes (probably the
  stick values).
- `view_toggle` and `view_toggle_key` flip one value between two settings on
  a key press, whichever window has the keyboard.
- With `follow_velocity = 1` the log also says how much of the speed written
  one frame was still there the next.

## Not done yet, and why it matters

- **Animation.** The game is given no movement input, so the unit glides in
  its idle pose. `follow_velocity` gives it the WaW player's speed. Whether
  the game animates from speed alone, or needs the stick values as well, is
  the next thing to watch.
- **Camera.** Needed before any of SWBF2's picture can be laid over WaW's
  (Phase 2). In third person the game places it from the unit and its aim, so
  getting the aim right may be all it takes. First person needs the view
  setting found, and WaW's field of view matched.
- **Hidden.** SWBF2 has only been run as a visible window behind another.
- **Arena.** Tests run in a live instant action match, so the unit gets shot.
  The design wants an empty map and an invulnerable unit, which means building
  a mission with the SWBF2 mod tools.
