# Phase 0: Link

Goal: prove the two games can be linked. When this phase is done, both
bridges load, find each other through shared memory, and walking around in
World at War moves your Battlefront II unit to match.

Everything here is on Windows, with the latest Steam versions of both games.

Builds tested so far (addresses found in step 4 only hold for these; if a
hash changes, a Steam update replaced the exe):

| Exe | Linked | SHA-256 |
|---|---|---|
| `CoDWaW.exe` 1.7 | 2009-10-29 | `732900D158982C33E3121F0B86D22230BE79839BBCBFE3BDFC1238F408A7D64D` |
| `BattlefrontII.exe` | 2017-10-23 | `3BFDB0931885DE776126957AA4883B691FC391B58126FF639E36592309D75E90` |

## 1. Build

Needs Visual Studio 2022 or later (Desktop C++ workload, which includes
CMake). Run these from a *Developer Command Prompt for VS*:

```bat
cmake -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release
```

Outputs in `build\out\`:

| File | Goes to |
|---|---|
| `waw\d3d9.dll` | `steamapps\common\Call of Duty World at War\` (next to `CoDWaW.exe`) |
| `swbf2\d3d9.dll` | `steamapps\common\Star Wars Battlefront II Classic\GameData\` (wherever `BattlefrontII.exe` is) |
| `tools\wawbf_monitor.exe` | anywhere |

Copy `waw\wawbf.ini.example` and `swbf2\wawbf.ini.example` from the repo next
to each DLL and rename both to `wawbf.ini`.

(On Linux you can cross-compile with MinGW:
`cmake -B build-win -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-i686.cmake`.)

## 2. Confirm each bridge loads

Start each game on its own. A log file should appear next to the DLL:
`wawbf_waw.log` or `wawbf_swbf2.log`, starting with "bridge loaded".

If there's no log, the game didn't load our `d3d9.dll`. Check what it
imports from a VS Developer Command Prompt:

```bat
dumpbin /imports CoDWaW.exe | findstr /i ".dll"
```

If `d3d9.dll` isn't listed, the proxy needs to impersonate something else
the game does import (`dinput8.dll` is the usual choice). Note the result
here either way.

Result (2026-10-07): both exes import `d3d9.dll` and both load the bridge.
`BattlefrontII.exe` also imports `dinput8.dll`, which is a second way in if
we need one for input later.

Start both games from Steam. Running `CoDWaW.exe` directly makes it exit and
ask Steam to relaunch it, which did not always come back.

- [x] WaW loads the bridge
- [x] SWBF2 loads the bridge

## 3. Run both and check the link

Run both games windowed so you can see them side by side. For WaW, use the
video options or `/r_fullscreen 0` then `/vid_restart` in the console. For
SWBF2, use its video options or a windowed launch option. Start
`wawbf_monitor.exe`.

The monitor should show both PIDs as `alive`. Close one game; within two
seconds it should show `STALE`.

Result (2026-10-07), read from the two logs rather than the monitor: with
both games at their menus each bridge logged the other as connected, and WaW
logged `SWBF2 bridge lost` a few seconds after SWBF2 closed.

- [x] Both sides `alive` in the monitor
- [x] Closing a game shows `STALE`

**Does SWBF2 keep running without focus?** Start an instant action match,
then click into the WaW window. Watch the SWBF2 window: do bots and effects
keep moving? Our bridge thread runs either way, so the monitor can't tell
you this. If SWBF2 pauses, finding and patching that check moves to the top
of Phase 1, because everything later depends on it.

Result (2026-10-08): it depends on the display mode, not on a focus check we
need to patch. Measured as memory words changing per second
(`tools/probe/activity.ps1`), all in an instant action match:

| Mode | Focused | Not focused |
|---|---|---|
| Fullscreen (minimises when you switch away) | 526,000 | 4,000 |
| Windowed (`/win /resolution 1280 720`) | 593,000 to 669,000 | 347,000 to 465,000 |

So run SWBF2 windowed and it keeps simulating behind another window. Hooking
`GetForegroundWindow` / `GetFocus` and withholding the focus-loss window
messages made no measurable difference in windowed mode (421,000 to 547,000
unfocused), so that code was left out. Not checked: whether input and sound
still work while unfocused, and a hidden rather than merely covered window.

- [x] SWBF2 keeps simulating while unfocused (or: notes on how it pauses)

## 4. Find the player position in memory

Use [Cheat Engine](https://www.cheatengine.org/), attached to one game at a
time. Do this offline and single player only.

### World at War: `[waw] player_origin`, `view_angles`

1. Load a zombies map (Nacht der Untoten is simplest) and attach to `CoDWaW.exe`.
2. Search *Float*, *Unknown initial value*.
3. Height is the easiest axis (Z): go up the stairs and scan *Increased*,
   come down and scan *Decreased*, stand still and scan *Unchanged*. Repeat
   until there are a handful of results.
4. X and Y are usually the floats right before Z. Browse the memory region:
   three floats that change as you walk are the origin.
5. Expect several copies (server state, client prediction, render
   view). For reading, use the one that updates smoothly every frame.
6. Restart the game and check the address still works. If it moves, use
   Cheat Engine's pointer scan and write the result as a chain
   (`CoDWaW.exe+0x1234 > 0x10`).
7. View angles are found the same way: look up and down for pitch, turn for
   yaw (degrees).

Result (2026-10-07, exe build listed at the top):

```ini
player_origin = CoDWaW.exe+0x14ED088
view_angles = CoDWaW.exe+0x14ED18C
```

These were found with a script rather than by hand (`tools/probe/`).
`wawbf_probe.gsc`, called from a copy of `maps/_zombiemode_weapons.gsc` in a
throwaway mod, freezes the controls and teleports the player between known
spots; `wawscan.ps1` keeps the addresses that hold those numbers every time,
and `wawwatch.ps1` times which copy changes first.

About 50 copies tracked the player. This pair changed before all the others
on a teleport and sits in one structure (angles 0x104 after the origin), so it
is the game's own record of the player rather than a client-side copy. It
survives a restart: with these in `wawbf.ini` the bridge logged the scripted
positions and yaws exactly.

Not measured yet: how often it updates. It is probably the server's tick rate
rather than every rendered frame. If the follow test looks steppy,
`CoDWaW.exe+0x214776C` changed one frame later and is the first client-side
copy to try.

### Battlefront II: `[swbf2] player_position`

Same method on `BattlefrontII.exe` in an instant action match. Height
should be the **middle** float (Y-up). Positions often sit in a 4×4
transform matrix, in which case the translation is the last row.

You'll need to *write* this one, so check it's the authoritative copy:
freeze it in Cheat Engine. If the unit stays pinned in place, that's the
right address. If the game keeps overwriting it, it's a copy.

Put each value in the relevant `wawbf.ini`, restart, and confirm the monitor
shows valid positions that change as you move.

Result (2026-10-08, exe build listed at the top), found with `tools/probe/`
instead of Cheat Engine. Provisional: not yet confirmed after a respawn.

```ini
player_position = BattlefrontII.exe+0x1A296B0 > 0x0
```

- **How it was found.** `bfscan.ps1` has the player follow beeps (stand,
  walk, stand, ...) and keeps floats that hold still while standing and differ
  after every walk, then pairs them up as x and z 8 bytes apart. "Still" has
  to be a small tolerance: with bit-for-bit equality the unit was missed.
- **Which copy is real.** 19 addresses followed the unit. `bfnudge.ps1` raised
  each one's height by 3 m. Only one stayed raised, fell back to the ground
  over about 0.6 s, and took 15 of the others up with it: that is the position
  the game moves the unit from. The rest snapped back within 20 ms.
- **Getting to it.** That address is in the heap and moves with every spawn.
  `bfptr.ps1` found the unit object 0x120 bytes before it and two fixed
  pointers to that object, `+0x1B77078` and `+0x1B84190`. Layout is x, y, z
  with y up, as expected.
- **Which pointer.** Neither of those. Both pointed at the unit at the moment
  of the scan and at unrelated things later: with `+0x1B84190 > 0x120` in
  `wawbf.ini` the bridge logged one fixed spot for 95 s while the player ran
  around. One good-looking moment proves nothing; a chain has to hold across
  lives.
- **Ground truth without a pointer.** Soldiers are the heap objects whose
  first word is `BattlefrontII.exe+0x39D114` (31 to 41 of them in a match),
  with the position at +0x120. The player's is the one the camera
  (`+0x3DE3A8`) sits about 4 m behind. `bfunits.ps1` lists them.
- **Census.** `bfcensus.ps1` records, for each life, every exe slot that
  points into that soldier (directly, or through one heap object), and keeps
  only those seen in every life. Over six lives one direct slot survived:
  `+0x1A296B0`, which points straight at the position (soldier + 0x120). It
  agreed with the camera-followed soldier in 122 of 134 samples. Everything
  else matched one to three lives. `+0x1B99A78` also survived, as a pointer
  to soldier + 0x258.
- **What that pointer means.** It follows whichever soldier the camera
  follows. While the player is dead that is something else (a spectated unit
  or the death camera), so it is "the unit on screen", not strictly "the
  player's unit". For the hidden game, where the player's unit stays alive,
  the two are the same.
- **Still to do.** Confirm through the bridge: with this in `wawbf.ini` the
  log should trace the player's path, and `follow = 1` should move the unit.
- **Writes go through the bridge.** The outside lift test worked once, then
  the antivirus (ESET) began blocking any freshly compiled helper that writes
  to another process. Don't work around that: `follow = 1` writes from inside
  the game, which is what the design needs anyway. Read-only helpers are
  unaffected.
- **False lead worth knowing.** `BattlefrontII.exe+0x569D9C` (seven entries,
  0x44 apart) passed the first scan and looked like the player, but it is a
  list of recent sound positions: it matched because the player's own
  footsteps were the nearest sounds, and it jumps across the map when other
  sounds play.
- `BattlefrontII.exe+0x1B84300` matched the unit's x and z while it stood
  still, but later held a stale position, so don't rely on it.
  `BattlefrontII.exe+0x3DE378` is a 4x4 matrix that trails the unit by a few
  metres, most likely the camera.

- [x] `player_origin` found (record the WaW address here)
- [x] `view_angles` found
- [ ] `player_position` found and freezing it pins the unit

## 5. Follow test

1. In both games, stand still. Copy WaW's origin from the monitor into
   `anchor_waw` and SWBF2's raw position into `anchor_bf` (SWBF2's
   `wawbf.ini`, `[mapping]`).
2. Set `follow = 1` and restart SWBF2 (the ini is read at startup).
3. Walk around in WaW. The SWBF2 unit should move with you. Some jitter is
   expected, because Phase 0 writes the position from a background thread.

## 6. Measure the mapping

The default mapping assumes SWBF2 is Y-up, measured in metres and
right-handed. Check each assumption:

- **Up axis:** jump in SWBF2. Only the middle raw value should rise.
- **Handedness (`z_sign`):** in SWBF2, turn until walking forward increases
  only the first raw value (you're facing +X). In WaW, turn to yaw 0, which
  also faces +X. Now strafe *left* in WaW. The SWBF2 unit should slide to
  its left; if it slides right, set `z_sign = 1`.
- **Scale:** in SWBF2, stand on two landmarks and note their raw positions.
  Walk the same route in WaW from the anchor and compare. Adjust `scale` if
  the unit overshoots or falls short.
- **Yaw:** note the WaW yaw and SWBF2 facing for a few directions. You'll
  need these for `yaw_sign` and `yaw_offset` in Phase 1.

Record the measured values in `swbf2/wawbf.ini.example`. If handedness
turns out the other way, also update the default in
`protocol/wawbf_protocol.h` and its test.

## Done when

- [ ] Both bridges connect and report heartbeats
- [ ] Walking in WaW moves the SWBF2 unit in the same direction at the same scale
- [ ] Standing still, the monitor's `delta` stays within a few units
- [ ] Findings (imports, unfocused behaviour, addresses, mapping) recorded in this file
