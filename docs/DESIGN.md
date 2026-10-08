# Design

Play Call of Duty: World at War Nazi Zombies as a Star Wars Battlefront II
(2005) character: clone troopers, droids and heroes, with Battlefront weapons
in the mystery box and on the walls.

The approach follows [SkyCraft](https://github.com/chasmlol/SkyCraft) (Skyrim
× Minecraft). **Neither game is rewritten.** Both run at the same time, and
a small bridge DLL inside each one translates between them through shared
memory.

## The two games

| | Game A: World at War | Game B: Battlefront II (2005) |
|---|---|---|
| Version | Latest Steam (`CoDWaW.exe`, patch 1.7) | Latest Steam "Classic" (`GameData\BattlefrontII.exe`) |
| Window | Visible, has focus, draws the frame | Hidden, keeps simulating |
| Engine | IW engine (CoD4 lineage), 32-bit, D3D9 | Zero Engine, 32-bit, D3D9 |
| Scripting | GSC (zombie mode is all GSC) | Lua mission scripts, ODF data files |
| Prior reverse engineering | A lot: CoD4/T4 community (T4M, Plutonium) | Very little public; mostly ours to do |

## Who owns what

SkyCraft makes Minecraft (B) authoritative for player movement, which forces
it to rebuild Skyrim's terrain as Minecraft collision (its `CollisionField`,
the largest piece of that project). We do the opposite for movement so the
WaW map never has to exist inside SWBF2:

| Owned by World at War (A) | Owned by Battlefront II (B) |
|---|---|
| Map, collision, player movement | Player character model and animations |
| Zombies, AI, rounds, points | Weapons: fire timing, ammo, overheat, reload |
| Mystery box, wall buys, perks, Pack-a-Punch | Heroes: lightsabers, Force powers |
| Hit detection and damage to zombies | Weapon and hero sounds |
| Player health, downs, revives | First-person weapon view and HUD (drawn over WaW) |

Guiding rule for combat: **Battlefront decides *when* and *what* fires; World
at War decides *what it hits*.** A blaster shot in SWBF2 becomes a projectile
or trace in WaW carrying the SWBF2 weapon's damage and speed. A lightsaber
swing becomes a melee cone check in WaW. Zombies never need to exist inside
SWBF2, and SWBF2 never needs WaW's collision.

## Components

```
waw/       Game A bridge: d3d9.dll proxy for CoDWaW.exe (C++)
           later: mods/swbf2_zombies/ GSC + weapon files
swbf2/     Game B bridge: d3d9.dll proxy for BattlefrontII.exe (C++)
           later: a mission/side mod for the hidden arena
protocol/  wawbf_protocol.h: the shared-memory layout, used by both bridges
common/    Shared bridge code: proxy, shared memory, config, logging
tools/     wawbf_monitor: live view of the shared block
tests/     Platform-neutral protocol tests
```

### Getting code into each game

Both games import `d3d9.dll`, and Windows loads it from the game folder
before System32. Each bridge is a `d3d9.dll` that forwards every export to the
real one and starts a bridge thread. No injector or launcher is needed, and
the proxy is where the D3D9 device gets hooked for compositing later.

### Talking to GSC

GSC can't read shared memory. Until the WaW bridge can register its own
script functions (by hooking the script VM's builtin table), the two talk
through dvars: the bridge sets dvars that a GSC loop polls, and GSC calls
`setDvar` for things the bridge needs to know. It's slow, but fine for
"player bought weapon X" or "BF fired a shot".

### Talking to SWBF2

Lua mission scripts run inside the hidden SWBF2 session. We need them for
the setup: load an empty arena map, spawn the player as the chosen unit, and
turn AI and bots off. Per-frame work goes through the native bridge.

## Shared memory

`Local\WaWBF_v1`, 64 KiB, laid out in `protocol/wawbf_protocol.h`:

- **Header:** magic, protocol version, and a PID + heartbeat per side. A side
  whose heartbeat is more than 2 s old is treated as gone.
- **Latest-value slots** under a seqlock for per-frame state: `WawPlayerState`
  (A→B) and `BfPlayerState` (B→A).
- **Later:** one single-producer/single-consumer event ring per direction for
  discrete events, e.g. `WeaponGranted`, `FireWeapon`, `MeleeSwing`,
  `ForcePower`, `PlayerDowned` and `RoundChanged`.

Every struct uses fixed-width fields only, so 32-bit games and a 64-bit tool
agree on the layout. Bump `kVersion` on any change; mismatched bridges refuse
to connect.

## Coordinates

WaW is Z-up with 1 unit ≈ 1 inch. SWBF2 is Y-up and assumed to be in metres.
Only the SWBF2 bridge converts; the protocol always carries WaW space. An
anchor pair pins a spot in the WaW map to a spot in SWBF2's hidden arena.
Scale, handedness and yaw convention are config values until Phase 0
measures them (`docs/PHASE0.md`).

## Weapons: the character's own (proposed 2026-10-08)

A simpler plan than the one in the next section, proposed by the user after
playing with fire, aim and reload working, and the one to build towards
unless that changes:

- **No Battlefront weapons in the box or on the walls.** A character keeps
  the weapons it has in SWBF2. Han Solo has his pistol; a clone has a rifle
  and a pistol.
- **WaW is given the closest match.** Whatever the SWBF2 character is
  holding, the WaW player is handed the WaW weapon most like it, so that the
  shot WaW fires and the one SWBF2 shows agree in kind, rate and reload.
- **The walls sell ammunition**, not weapons.
- **The character is changed with a key**, cycling through the heroes with
  one and the villains with another, instead of through SWBF2's spawn
  screen. Built: `docs/PHASE2.md`.
- **Third person** for the characters it suits, lightsaber heroes above all.

What it saves: SWBF2 never has to be given a weapon it does not already have
on that character, and nothing has to be invented for each pairing of a WaW
weapon with a SWBF2 one. What it needs: the WaW script mod (to hand out the
matching weapon, to turn wall buys into ammunition, and to take the weapons
out of the box), and a way for the bridge to tell that script which
character is in play.

## Weapons in the box and on walls (the earlier plan)

The box and wall buys stay stock WaW GSC. Each Battlefront weapon gets a
**placeholder weapon** in WaW (e.g. `swbf2_dc15a`): a weapon file with the
SWBF2 weapon's name, an invisible view model and no real shots of its own.
It's registered like any custom zombies weapon (`include_weapon` in the map
script, `add_zombie_weapon` with cost and box odds), so the box cycle, wall
chalk and costs all work unchanged.

When the player holds a placeholder, the WaW bridge tells SWBF2 to equip the
real weapon. Fire input goes to SWBF2, SWBF2 reports each shot, and WaW turns
it into damage (`MagicBullet` / trace). Ammo and overheat show on SWBF2's HUD.

Heroes have no weapon pickups. Choosing a hero (a menu or a special box roll)
swaps the SWBF2 unit, and the WaW placeholder becomes a melee/Force kit.

### Building the WaW mod

Tried on 2026-10-07 with a throwaway mod on stock Nacht der Untoten; the
official mod tools were not needed.

- **Tooling:** [OpenAssetTools](https://github.com/Laupetin/OpenAssetTools)
  v0.33.0, unpacked to `tools/oat/` (not committed). `Unlinker` dumps the
  stock scripts and weapon files from the game's own `.ff` files, and `Linker`
  builds a `mod.ff` the game loads without complaint.
- **Scripts:** a `rawfile` in `mod.ff` replaces the stock script of the same
  name. An edited `maps/_zombiemode_weapons.gsc` (the box and wall-buy script)
  ran in place of the stock one.
- **Weapons:** the game reads a weapon's definition from a loose
  `weapons/sp/<name>` file in the mod folder, not from the weapon asset in
  `mod.ff`. Without that file it logs `Could not load weapon file` and hands
  out the default weapon. With a copy of the stock Ray Gun file under a new
  name, `GiveWeapon` gave a working Ray Gun. Whether the weapon asset in
  `mod.ff` is needed at all for a placeholder was not tested.
- **Where it goes:** `%LOCALAPPDATA%\Activision\CoDWaW\mods\<mod>\`, started
  through Steam with `+set fs_game mods/<mod> +devmap nazi_zombie_prototype`.
  Adding `+set logfile 2` writes `mods\<mod>\console.log` in the game folder.
- **Stock files stay out of the repo.** The build has to patch the dumped
  stock script rather than commit a modified copy of it.

## Rendering (Phase 2)

SWBF2 renders the player's first-person weapon/arms and HUD offscreen at
WaW's resolution, with its camera locked to WaW's. The frame is then drawn
over WaW's frame in the WaW proxy's `Present`.

Both games use plain D3D9, which can't share GPU surfaces between processes.
Shared handles need D3D9Ex, and D3D9Ex rejects `D3DPOOL_MANAGED` resources,
which old games often use. The first version reads the image back on the CPU
(`GetRenderTargetData`, one frame of latency); GPU sharing comes later if
it's needed.

## Phases

| Phase | Goal | Done when |
|---|---|---|
| 0 | **Link** | Both bridges load and connect; positions found; walking in WaW moves the SWBF2 unit with a small `delta`. See `PHASE0.md`. |
| 1 | **Puppet** | SWBF2 runs hidden and unpaused; its unit's position and facing follow WaW from a hook in its update loop (no jitter); SWBF2's camera matches WaW's. |
| 2 | **Overlay** | SWBF2's first-person weapon and HUD composite over WaW; input routing (movement → WaW, fire/abilities → SWBF2). |
| 3 | **Combat** | One blaster end to end: SWBF2 fires, WaW zombies take damage, ammo and heat work. |
| 4 | **Box & walls** | Placeholder weapons in the box and on walls; buying one equips it in SWBF2. |
| 5 | **Heroes** | Lightsaber melee, Force push/choke/lightning as WaW-side area effects. |
| 6 | **Polish** | Perks mapped to SWBF2 stats, Pack-a-Punch variants, downs and revives, sound balance. |

## Risks

- **SWBF2 internals are uncharted.** Every Phase 0–3 task on the B side is
  reverse engineering from scratch.
- **SWBF2 may pause when unfocused.** Phase 0 checks this; if it does, a patch
  to keep it running is a hard prerequisite.
- **Two games at once:** CPU/GPU cost, two audio streams (mute WaW's player
  weapon sounds, keep SWBF2's), and both wanting the mouse (WaW keeps focus;
  SWBF2 gets input forwarded).
- **Assets:** passthrough means we never redistribute Battlefront content, and
  players need to own both games. Keep it that way.
