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
- [x] The unit animates: with `follow_velocity = 1` it runs instead of
      sliding in its idle pose (watched, 2026-10-08)
- [x] The unit aims up and down with the WaW player (`follow_pitch = 1`;
      watched, and exact by the numbers: see "Second test")
- [x] First / third person switched by a key: F9 works (see "The view
      setting")
- [x] SWBF2's camera matches WaW's: it looks where the WaW player looks, with
      the same field of view (the bridge logs 51.1 degrees for both in the
      arena; see "The camera")
- [x] SWBF2 hidden rather than merely behind another window: `hidden = 1`
      (see "Hidden")
- [x] An empty arena with an unkillable unit, which SWBF2 loads by itself
      (see "The arena")

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

## Second test (2026-10-08): speed and pitch

`followtest.ps1 -Velocity 1 -Pitch 1`, 75 s, the WaW player walking 7,882
units, turning 2,938 degrees and looking from 61 degrees up to 10 down.

| | min | median | max |
|---|---|---|---|
| Position gap, WaW units | 0.0 | 1.4 | 7.6 |
| Facing error, degrees | 0.0 | 0.0 | 0.0 |
| Pitch error, degrees | 0.0 | 0.0 | 7.3 |

- **Pitch is kept.** In every frame the angle read back was the one written
  the frame before, and the unit's aim ran from 10 degrees down to 60.5 up as
  the WaW player's did. `pitch_sign = -1` is right by the numbers. The 7.3 is
  the two games being read a moment apart during a fast look.
- **Speed is mostly kept.** Given about 4.8 m/s, the unit had about 3.9 m/s a
  frame later: the game takes the speed and bleeds some off, as it would for
  a unit nobody is steering. It also now moves the unit itself by that speed
  each frame, before the bridge puts it back on the line, so the trace of
  position changes shows two real steps a frame where it used to show one.
  Whether that reads as smooth, and whether the game animates from it, has to
  be judged by eye.
- No death, no crash, and none of the single-sample outliers the first test
  had. The three worst moments are now printed with their times, and all
  three were the player sprinting at 6.5 to 7.9 m/s.

## The view setting

`BattlefrontII.exe+0x1AF9106`, one byte: 0 = third person, 1 = first person.
Writing it switches the view at once: the camera went from 0.32 m from the
unit's eyes to 3.20 m and back. It is what `view_toggle` is set to.

How it was found, because the first step alone was not enough:

1. `tools/probe/bftoggle.ps1` snapshots memory while the player switches the
   view back and forth and keeps the bytes that held one value in every
   third-person snapshot and another in every first-person one. The player
   stood still while switching, so everything that depends on where the
   camera is repeated exactly too: 38,518 bytes survived, 1,016 of them at
   fixed addresses.
2. `tools/probe/bfsettle.ps1` watches those while the game is played in one
   view and drops any that stray. Forty seconds in third person and fifteen
   in first left 44 fixed addresses, five of them plain 0 / 1 values.
3. `tools/probe/bfviewtry.ps1` gives each of those its other value through
   `[debug] poke` and measures the camera. The second one tried was it.

`BattlefrontII.exe+0x1AC8106` sits in a block of the same shape 0x31000
bytes earlier and follows the setting, but writing it does nothing; it is
most likely the copy the options menu shows.

## The camera

Read from the view-projection matrix, which starts at
`BattlefrontII.exe+0x3DE368`: four rows of four floats (x, y, depth and w
rows; the length of the first three floats of the x and y rows is the
projection's scale on that axis), then the camera's position at `+0x3DE3A8`.

| | First person | Third person |
|---|---|---|
| Vertical field of view | 55.4 degrees | about 51.5 degrees |
| Horizontal, at 16:9 | 86.1 degrees | about 81 degrees |
| Camera, from the unit's origin | 0.30 m behind, 1.72 m up | 3.0 m behind along the view, 1.6 m up |
| Camera pitch | the aim pitch exactly | the aim pitch less 10 degrees |

So in first person the camera already looks exactly where the WaW player
looks: heading from the body, pitch from the aim, both written every frame.
That left the field of view.

The two games turn out to measure it the same way: the angle across a 4:3
picture, widened for a wider one. WaW's `cg_fov` is 65 by default. SWBF2's
soldiers carry `FirstPersonFOV = 70` and `ThirdPersonFOV = 65` in their class
files, which is exactly the 55.4 and 51.1 degrees measured above. So the
arena sets both to 65 for every class it offers (`SetClassProperty`), and the
two agree.

It is checked rather than assumed. WaW keeps the view it is drawing as the
tangents of half its horizontal and half its vertical angle, at
`CoDWaW.exe+0x3120348` (`tools/probe/wawfov.ps1` finds it: it reads 0.8494 and
0.4778, which is 80.7 by 51.1 degrees). The WaW bridge publishes them
(`view_fov`, protocol version 3), the SWBF2 bridge works out its own from its
view-projection matrix (`view_projection`), and logs both whenever either
changes. In the arena: "field of view: WaW 51.1, SWBF2 51.1 degrees top to
bottom: matched", in first and third person. A player who changes `cg_fov`
will see the mismatch in the log; nothing follows it automatically yet.

The eye heights differ (1.72 m here, 60 units = 1.52 m in WaW). For a
first-person weapon drawn over WaW's picture that does not matter, since the
weapon is placed relative to the camera.

## Hidden

With its window hidden the game goes on presenting frames (the bridge's frame
hook never reports a gap) and the match goes on playing: in a live match
`tools/probe/bfsim.ps1` counted 25 to 28 of 39 soldiers moving while hidden,
against 29 of 40 before. Showing the window again brings it back as it was.

`[swbf2] hidden = 1` does it from the bridge, and can be switched while the
game runs. The game shows its window again by itself when a mission loads,
so the bridge keeps it hidden rather than hiding it once. It is off by
default: during development both windows are watched side by side.

## The arena

Until now every test ran in a live Instant Action match, where the unit got
shot. The arena is a map with nothing in it for the hidden game to sit in:
flat ground, no soldiers but the player's, no objective, so it never ends,
and a unit given more health than anything can take off it.

`swbf2/arena/build.ps1` builds it with the player's own copy of the
Battlefront II mod tools and installs it as the addon `WAW`. Nothing of
Battlefront's is in this repository: the world is the tools' blank template,
and what is kept here is three small rosters, the script they share
(`WAW_arena.lua`) and the script that registers the map (`addme.lua`).

**Rosters.** The spawn screen has room for ten classes a team and there are
two teams, so one mission offers twenty characters at most. Heroes are added
as ordinary classes, the way the game's own hero assault mode does it.

| Mission | Team 1 | Team 2 |
|---|---|---|
| `WAWg_con` | Empire: six soldiers, Vader, the Emperor, Boba Fett | Alliance: six soldiers, Luke, Han, Leia, Chewbacca |
| `WAWc_con` | Republic: six soldiers, Obi-Wan, Yoda, Mace Windu, Anakin | Separatists: six soldiers, Maul, Dooku, Grievous, Jango Fett |
| `WAWg_eli` | all nine heroes | all eight villains |

**Starting by itself.** `build.ps1 -AutoStart gcw|cw|heroes` makes the game
log in the last-used profile and go straight into that roster, with no menu
to click through; the player lands on the spawn screen and picks a
character. `-AutoStart none` leaves the game at its menu, with the arena in
the Instant Action list like any map. While it starts by itself there is no
reaching the menu: quitting the mission starts it again.

Seen working once: the game was in the arena about 30 s after its window
appeared. Whether the profile step ran unaided that time, or the player
clicked first, was not confirmed.

How that works, and the mistake on the way: the script that registers a map
runs in the same Lua state as the menus, so it can wrap the two functions
every menu screen calls by name, its default "enter" and "update". On the
profile screen it sets the two fields the game itself uses to log in a
profile named on its command line; on the screen after that it launches the
mission the way Instant Action does. The first version waited for the main
menu screen (`ifs_main`) and never ran, because on PC there is no such
screen in the path: after the profile screen comes the single player tab
(`ifs_sp_campaign`). The shipped game keeps no script log, so the script
leaves a string in memory at each step and `tools/probe/bfluatrace.ps1`
looks for them.

**Three things that break the 2005 tools on a current machine**, all handled
in `build.ps1` and explained there:

- Their batch files paste `%PATH%` inside bracketed blocks, so a PATH with
  "Program Files (x86)" in it kills them with "\Common was unexpected at
  this time". They are run with a PATH of just Windows and themselves.
- Their string files are each one closing bracket short, the string compiler
  rejects them, the core level then fails to pack, and everything after it
  fails for want of its list of contents: the map comes out 8 bytes long.
- A pack that fails leaves an empty file that the tools then take for up to
  date, so one failure sticks until the empty files are cleared.

**Third test (2026-10-08), in the arena.** `followtest.ps1 -Velocity 1
-Pitch 1`, 75 s, the WaW player walking 10,449 units and turning 2,720
degrees.

| | min | median | max |
|---|---|---|---|
| Position gap, WaW units | 0.0 | 2.3 | 7.1 |
| Facing error, degrees | 0.0 | 0.0 | 0.0 |
| Pitch error, degrees | 0.0 | 0.0 | 3.3 |
| Unit height in SWBF2, metres | 0.0 | 0.0 | 0.0 |

The unit never changed (nothing to kill it), stood on flat ground the whole
time, and was judged by eye to look as good as before.

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

- **Animation is from speed alone.** Given the WaW player's speed the unit
  runs; the stick values at 0x2C0 were not needed. Not looked at yet: whether
  the animation matches the direction when strafing or backing up, and what
  it does at WaW's sprint and crouch speeds.
- **Following WaW's field of view.** It matches at WaW's default. If the
  player changes `cg_fov`, or WaW zooms, SWBF2 does not follow; the log only
  says so.
- **One roster at a time.** Changing which twenty characters are on offer is
  a rebuild of the addon and a restart of SWBF2. Choosing the character from
  the WaW side belongs with the weapons work in later phases.
- **The arena's look.** It still has the template's sky and ground. What the
  background should be depends on how SWBF2's picture is cut out in Phase 2.
- **Unkillable is by health, not by rule.** The unit is given an enormous
  amount of health when it spawns. Nothing in the arena has tested that
  against a fall or the edge of the map.
