# Phase 0: Link

Goal: prove the two games can be linked. When this phase is done, both
bridges load, find each other through shared memory, and walking around in
World at War moves your Battlefront II unit to match.

Everything here is on Windows, with the latest Steam versions of both games.

## 1. Build

Needs Visual Studio 2022 (Desktop C++ workload) and CMake 3.20+.

```bat
cmake -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release
```

Outputs in `build\out\`:

| File | Goes to |
|---|---|
| `waw\d3d9.dll` | `steamapps\common\Call of Duty World at War\` (next to `CoDWaW.exe`) |
| `swbf2\d3d9.dll` | `steamapps\common\Star Wars Battlefront II\GameData\` (next to `BattlefrontII.exe`) |
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

- [ ] WaW loads the bridge
- [ ] SWBF2 loads the bridge

## 3. Run both and check the link

Run both games windowed so you can see them side by side. For WaW, use the
video options or `/r_fullscreen 0` then `/vid_restart` in the console. For
SWBF2, use its video options or a windowed launch option. Start
`wawbf_monitor.exe`.

The monitor should show both PIDs as `alive`. Close one game; within two
seconds it should show `STALE`.

- [ ] Both sides `alive` in the monitor
- [ ] Closing a game shows `STALE`

**Does SWBF2 keep running without focus?** Start an instant action match,
then click into the WaW window. Watch the SWBF2 window: do bots and effects
keep moving? Our bridge thread runs either way, so the monitor can't tell
you this. If SWBF2 pauses, finding and patching that check moves to the top
of Phase 1, because everything later depends on it.

- [ ] SWBF2 keeps simulating while unfocused (or: notes on how it pauses)

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

### Battlefront II: `[swbf2] player_position`

Same method on `BattlefrontII.exe` in an instant action match. Height
should be the **middle** float (Y-up). Positions often sit in a 4×4
transform matrix, in which case the translation is the last row.

You'll need to *write* this one, so check it's the authoritative copy:
freeze it in Cheat Engine. If the unit stays pinned in place, that's the
right address. If the game keeps overwriting it, it's a copy.

Put each value in the relevant `wawbf.ini`, restart, and confirm the monitor
shows valid positions that change as you move.

- [ ] `player_origin` found (record the WaW address here)
- [ ] `view_angles` found
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
