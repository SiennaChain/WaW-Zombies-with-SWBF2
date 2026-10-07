# WaW-Zombies-with-SWBF2

Play World at War Nazi Zombies as Star Wars Battlefront II (2005) characters,
heroes included, with Battlefront weapons in the mystery box and on the walls.

It works like [SkyCraft](https://github.com/chasmlol/SkyCraft): neither game
is rewritten. World at War runs the map, zombies and rounds and draws the
screen, while Battlefront II runs hidden and provides your character,
weapons and Force powers. A bridge DLL in each game links them through
shared memory. You need both games; no Battlefront assets are redistributed.

**Status: Phase 0 (Link).** Nothing playable yet. Right now the work is
getting the two games talking. See [docs/PHASE0.md](docs/PHASE0.md).

## Targets

- Call of Duty: World at War, latest Steam version (`CoDWaW.exe`)
- Star Wars Battlefront II (2005), latest Steam version (`GameData\BattlefrontII.exe`)

## Layout

```
protocol/   Shared-memory layout used by both bridges (wawbf_protocol.h)
common/     Bridge code shared by both games: d3d9.dll proxy, shared memory, config, logging
waw/        Game A bridge for World at War
swbf2/      Game B bridge for Battlefront II
tools/      wawbf_monitor: live view of the link
tests/      Protocol tests (run on any OS)
docs/       DESIGN.md (architecture and phases), PHASE0.md (current checklist)
```

## Building

Windows, Visual Studio 2022 or later, CMake 3.20+. Both games are 32-bit, so
build 32-bit:

```bat
cmake -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release
```

Install steps are in [docs/PHASE0.md](docs/PHASE0.md#1-build).

## Disclaimer

Fan project, not affiliated with Activision, Treyarch, EA, Pandemic, Disney
or Lucasfilm. Use offline only. Don't load modified clients into online
matches.
