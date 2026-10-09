# WaW-Zombies-with-SWBF2

Play World at War Nazi Zombies as Star Wars Battlefront II (2005) characters,
heroes and villains included, with their own weapons, lightsabers and Force
powers.

It works like [SkyCraft](https://github.com/chasmlol/SkyCraft): neither game
is rewritten. World at War runs the map, zombies and rounds and fills the
screen, while Battlefront II runs unseen and provides your character,
weapons and Force powers, drawn over World at War's picture. A bridge DLL in
each game links them through shared memory. You need both games.

**Status: an alpha that can be handed to somebody else.** One map (Nacht der
Untoten), one player, eighteen characters. A launcher installs it, starts
both games and takes it out again; started any other way, both games are as
they were. What a release is and what was checked: [docs/RELEASE.md](docs/RELEASE.md).
What the mod does in play: [docs/PHASE3.md](docs/PHASE3.md). What a player
is told: [tools/launcher/README.txt](tools/launcher/README.txt).

## Targets

- Call of Duty: World at War, latest Steam version (`CoDWaW.exe`)
- Star Wars Battlefront II (2005), latest Steam version (`GameData\BattlefrontII.exe`)

Any other build of either exe is refused: every address the bridges use is a
place in those two.

## Layout

```
protocol/   Shared-memory layout used by both bridges (wawbf_protocol.h)
common/     Bridge code shared by both games: d3d9.dll proxy, shared memory, config, logging,
            and what keeps a bridge idle unless the launcher started its game (session.h)
waw/        Game A bridge for World at War, and its script mod (waw/mod)
swbf2/      Game B bridge for Battlefront II, and its arena add-on (swbf2/arena)
tools/      launcher: what a player runs. package.ps1: builds a release into dist/.
            monitor: live view of the link. probe: what the addresses were found with.
tests/      Protocol tests (run on any OS)
docs/       DESIGN.md (architecture and phases), PHASE0-3.md (how each part was done),
            RELEASE.md (the launcher, the release, and what was checked)
```

## Building

Windows, Visual Studio 2022 or later, CMake 3.20+. Both games are 32-bit, so
build 32-bit:

```bat
cmake -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release
```

That builds the two bridges and the launcher. A whole release (those, the
arena add-on and the World at War mod, gathered into a folder a player can
run from) is `tools\package.ps1`, which also needs the Battlefront II mod
tools and a dump of World at War's own scripts: see the top of
`swbf2/arena/build.ps1` and `waw/mod/build.ps1`.

While working on the mod the games are usually started by hand, not by the
launcher, and the bridges then do nothing: set `[bridge] without_launcher = 1`
in each game's `wawbf.ini` (docs/RELEASE.md).

## Disclaimer

Fan project, not affiliated with Activision, Treyarch, EA, Pandemic, Disney
or Lucasfilm. Use offline only. Don't load modified clients into online
matches.
