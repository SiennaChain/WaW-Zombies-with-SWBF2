# A release: what a player is given, and what keeps it out of their way

Everything up to here ran on one PC, set up by hand, with test settings on.
This is what was added so that somebody else can unpack a folder, run one
program and play, and so that the mod is nowhere to be seen when they do not.

## What a player gets

`tools/package.ps1` builds it, from the repo, into `dist/`:

```
Zombies with Battlefront II.exe   the launcher (tools/launcher)
wawbf_launcher.ini                its settings
README.txt  Settings.cmd  Uninstall.cmd
files\waw\      d3d9.dll, wawbf.ini                 -> World at War's folder
files\swbf2\    d3d9.dll, wawbf.ini, addon\WAW\...  -> Battlefront II's GameData
files\mods\     swbf2_<map>\mod.ff, weapons\...     -> World at War's mods
```

The script runs all three builds (cmake, `swbf2/arena/build.ps1`,
`waw/mod/build.ps1`) and has the last two put what they make straight into
the release (`-InstallTo`). Nothing is taken from what is installed in the
games on the PC it is built on, which may be a test set-up or nothing at all.
The two `wawbf.ini` are the repo's `wawbf.ini.example`, which are now kept as
what a release is installed with; the script refuses to go on if either, or
the launcher's, has a test setting in it (god mode, cheats, the bridges set
to run without the launcher, Battlefront II's window showing).

## The launcher

One program, `tools/launcher/main.cpp`. Run with one map installed, it starts
that map at once:

1. finds both games through Steam (its library list), and checks each exe is
   the build the mod was made for;
2. checks each game has a player profile (a first run of either asks for one,
   and Battlefront II would be asking with no window);
3. copies `files\` into the games, if it has one beside it and anything
   differs. A file of the same name that it did not put there (another mod's
   `d3d9.dll`) is set aside as `<name>.before-wawbf` first. What it installed
   is listed in `wawbf_installed.txt` in each place;
4. starts Battlefront II (`/win /nointro /resolution <w> <h>`), which never
   shows a window, and waits until its bridge reports a character in the
   arena. About nine seconds here;
5. starts World at War straight into the map with that map's mod, fullscreen
   at the screen's size unless told otherwise, with `+map` (no cheats);
6. waits for World at War to go, puts the player's name back if it has to
   (below), closes Battlefront II, and goes.

`/uninstall` takes out everything in those lists, puts back what was set
aside, and removes the folders that leaves empty. `/settings` opens only the
settings window.

With more than one map installed it is a list of them. A map counts as
installed if its mod is in World at War's `mods` or in `files\mods`.

## Doing nothing unless the launcher started the game

Both bridges are `d3d9.dll` in a game's folder, so the games load them every
time they start: for World at War's campaign, for its multiplayer (another
exe in the same folder), for Battlefront II played by itself. `common/session.h`:
a bridge does nothing at all, no thread, no hook, no change to the game,
unless

- the exe it is in has the name it was made for (`CoDWaW.exe`,
  `BattlefrontII.exe`), and the two numbers in the exe's header that tell one
  build from another (the link time and the image size) are the ones every
  address in `wawbf.ini` was found in; and
- the launcher is running: it holds a named object (`kSessionName`) from
  before it starts the first game until the last has gone.

This is settled in `DllMain`, before the game has run a line of its own. For
working on the mod, `[bridge] without_launcher = 1` and `any_exe = 1` waive
them.

Battlefront II's add-on is a third thing that is always there. Its
`addme.lua` used to go straight into the arena whenever the game started.
Now it does so only if it finds `addon\WAW\wawbf_start.txt`, which the
bridge makes as the game loads it when the launcher started the game, and
deletes when it did not (`ScriptCB_IsFileExist`, from where the game's levels
are: `..\..\addon\WAW\...`). Started from Steam, Battlefront II comes up at
its own menus, with the arena as one more map under Instant Action.

Checked: with the release installed, each game started from Steam by itself.
Neither bridge's log grew by a byte; Battlefront II stood at its profile
screen; World at War at its main menu.

## Battlefront II unseen

A player's PC has none of the window and mouse helpers this was developed
with, so what is needed of them is in the bridge (`swbf2/src/focus.cpp`):

- **No window.** `[swbf2] hidden = 1` used to hide the window after it had
  appeared, which with a 1920 x 1080 window is a flash of the whole screen,
  twice. Now the game's own calls to show it (`ShowWindow`, and
  `SetWindowPos` with the flag that shows) are answered without being carried
  out. A window that is never shown never comes to the front either, which
  matters once World at War has the whole screen: anything coming in front
  of that puts it away.
- **The pointer left alone.** The game puts the pointer back in the middle
  of its window every frame it believes it is in front, which with
  `keep_running` is every frame. `[swbf2] pointer_in_background = 0`: its
  `SetCursorPos` only goes through while its window really is in front.
- **World at War told the screen's real size.** `[window] dpi_aware = 1` in
  World at War's `wawbf.ini`: on a screen set to show things larger, Windows
  tells a game of that age a smaller size and stretches its picture.

(`mem::PatchImport` now finds an import by the name the exe asks for, not by
what is in the slot, and hands back whatever was there: something else in
the game may have put a routine of its own there first.)

Battlefront II's picture is the shape of World at War's and at most
`swbf2_height` lines (1080 as shipped); World at War stretches it to fit. At
3840 x 2160 over a 1920 x 1080 picture the game held 91 frames a second here.

## The video settings

World at War has two Graphics screens under one name. The one at its main
menu (in `ui.ff`) has every setting on it. The one reached from a map (in
`common.ff`, which replaces it while a map is loaded) shows the video mode,
refresh rate, aspect ratio, anti-aliasing, "sync every frame" and "dual video
cards" as words, not controls; the main menu's is not even in memory then.
Since the launcher skips the main menu, those would be out of reach
altogether. So the launcher has them: a Settings window (fullscreen,
resolution, refresh rate, anti-aliasing, sync every frame, and how many lines
Battlefront II's picture has), kept in `wawbf_launcher.ini` and given to
World at War on its command line. Pressed while a game is on its way, the
Settings button calls the start off first and closes Battlefront II again.

## Whose keys they are

Up and down on the d-pad are "the next character", read straight off the
controller by Battlefront II's bridge, whichever window is in front. They are
also how a controller moves through World at War's pause menu: a player going
down that menu went through two characters on the way. World at War's bridge
now says when the player's hands are on the game (`kWawHandsOn`: its window
is in front and it is not paused), and the keys and buttons either bridge
reads for itself count only then. (Protocol 13.)

## The player's name

The scoreboard shows the player by their character's name, which the bridge
sets with the game's own `name` command. The game writes any change of name
into the player's settings at once, so a game that ended while they were
Darth Vader left them Darth Vader in every game of World at War afterwards.
Now the bridge puts the name back before it tells the game to quit, and keeps
the name the player had in `wawbf_name.txt` for as long as they go by
another; if World at War has gone and that file is still there (the window
was closed, or it crashed), the launcher writes the name back into the
profile's `config.cfg`.

A change of character goes through "nobody" for a few tenths of a second,
and the name the game says the player has lags a frame or two behind what
was asked for. Reading "the player's own name" at each change, as this first
did, read the character just left: so the own name is learnt once in a game
and never again, a moment of nobody is waited out for two seconds before the
own name is put back, and no name is asked for until the player is in the
map and playing (asked the moment the player's record appeared, with the
game about to pause under its "click to start" screen, the name changed the
game's setting and never reached the scripts). If the game still has another
name three seconds after one was asked for, it is asked again.

## Nothing of Battlefront II's where it does not belong

Battlefront II is running, with a character standing in its arena, before
World at War is started. Its picture was therefore drawn from World at War's
first frame: over the film the game shows while the map loads (Nacht der
Untoten's opening scene), and over GAME OVER and the tour of the map that
follows a death. Now nothing of it is drawn (`Unseen` in the World at War
bridge; the picture stands aside, as it does for the pause menu):

- until the player is in the map with the game running, for a third of a
  second together. The film goes on over a paused game once the map has
  loaded ("click to start the mission"), so "in the map" alone is not enough;
- from the moment the game is over until the level starts again. The game's
  scripts know (`level.intermission`), and say so to the bridge in the number
  they already tell it the weapon in hand by: a value no weapon gives.

## Aiming from behind: where the marks and the bolts go

From behind the character the shot itself has gone to the middle of the
screen since Phase 3 (docs/PHASE3.md: the bridge points it there). Two things
a player sees did not, and a player judges by what they see: "the bullet
holes on the wall do not match up".

Measured (scratch `aimtest.ps1`: fire at a wall from behind, read the numbers
the two halves exchange, take pictures): the camera stands 29 units to the
character's right, looking the same way; the scripts found the first thing on
the line through the middle of the screen 90 units off; the shot was pointed
18 degrees right of the way the player looked, which is that spot from the
eyes. And the marks landed a hand's breadth left of the crosshair, where a
shot fired straight ahead from the eyes would have gone.

- **World at War's marks.** The half of the game that draws works the shot
  out again for itself to place the hole and the dust
  (`CoDWaW.exe+0x68D30`). Through the eyes it takes the direction from the
  same two gun angles the shot is fired along; from behind it takes it from
  the angles of the player's soldier. `[waw] marks_from_behind` changes the
  eighteen bytes that fetch the soldier's angles into five that fetch the gun
  angles. After it, four shots at a bare wall left one mark, on the dot.
- **Battlefront II's bolts** are left as they were, after being changed and
  changed back. Its character faces and aims the way the player looks, so a
  bolt flies parallel to the line through the middle of the screen, beside
  it. Having the character aim at the spot the shot is pointed at was tried,
  so that the bolt would cross the same spot, and was wrong: nothing in
  Battlefront II's world stops a bolt, it flies on through World at War's
  walls, and what the eye follows is the streak running away into the
  distance. Parallel to the camera, that streak runs to the middle of the
  screen. Aimed at a spot two metres off, it runs away to one side ("too far
  right", within a minute of being shipped to the user). Not measured before
  it was changed; that was the mistake.

- **Battlefront II's burst.** A bolt that hits something there goes off in
  orange sparks and smoke, and a bolt fired downwards from behind the
  character met that game's ground a few metres out: sparks a pace to the
  left of the crosshair and of World at War's own hit, with every shot ("the
  sparks are hitting to the left"). Seen for what it was only by recording
  Battlefront II's own picture frame after frame (scratch `bfframes.ps1`
  reads the picture mapping, 80 a second): level, the bolt runs away to the
  middle of the screen; twenty degrees down, it bursts four metres out. The
  ground is level ground the game has everywhere at height 0. The arena's
  invisible floor has nothing to do with it (a soldier lifted 36 m fell
  straight through the floor to 0), and nothing done to floor or terrain
  moved it. So the burst itself is emptied: the add-on's copy of
  `com_sfx_ord_exp`, which is read before the game's own and so is the one
  used, is given no particles (`swbf2/arena/build.ps1`).
- **World at War's own muzzle flash and spent cases**, which four of the
  stand-in weapons still had: they play at the unseen soldier's gun. Gone
  from all of them (`waw/mod/build.ps1`). Not what the user had seen, as it
  turned out, but not wanted either.

Two wrong turns on the way, both from reading one still picture instead of
measuring: the sparks were first taken for World at War's flash, and then for
a hit on the arena's floor.

## The view a game begins in

Third person (asked for). Battlefront II remembers the view it was last left
in, so `[swbf2] start_from_behind = 1` sets it once, when the first character
appears; after that it is the player's to change and stays as they leave it.

## Who the player starts as

A stormtrooper (asked for). A roster can name a class to start as (`start =`
in `swbf2/arena/WAWg_eli.lua`); the arena's script puts the player on that
character's team the first time, whichever team the game put them on.

## No main menu

`[waw] quit_at_menu = 1`: once the game has been in a map and is then out of
one for three seconds, it is told to quit. Each map has its own build of the
mod, and the game's own menu would offer the others with the wrong one.

## The arena's roster

`swbf2/arena/build.ps1` now builds for the roster with every hero and villain
unless told otherwise. It was the Galactic Civil War's by default and every
working build had been made with `-AutoStart heroes` by hand; the first
release built without that put the player in as a stormtrooper whose next
character was a rocketeer, who has no kit.

## Checked, and not

Checked on the PC it was made on, with the helpers taken out of both games:
install from a fresh folder; Battlefront II up with no window ever showing;
World at War fullscreen at 3840 x 2160 with the character drawn; `+map`; a
character changed once, twice in a fifth of a second, and not at all at the
pause menu; the name put back after the window was closed, and after Quit
from the pause menu (which also ends the game, as it should); uninstall,
with what had been set aside put back; both games from Steam untouched; the
Settings window by itself and pressed while a game was loading (the start
called off, Battlefront II gone, the game started again from Save and play),
and its refresh rate, anti-aliasing and sync turning up in World at War's
own settings; no character over the loading film or the "click to start"
screen (pictures taken every second of a start), and none from a death to
the level starting again (the bridge's log of a game the user lost); the
start as a stormtrooper, named so on the controls shown.

One mistake worth its own line, because it was in five places: a time kept
from being zero with `| 1` can be a thousandth of a second ahead of the
clock it came from, and the difference taken unsigned is then seven weeks,
not minus one. A lightsaber's blow out of a sprint was over before it began
whenever it was struck on an even thousandth of a second. Such differences
are taken signed now.

Not checked: any other PC, any other screen shape than 16:9 (`hud_lens` and
`hud_keep` are 16:9's), a PC whose Windows is set to another scale, an
antivirus other than this one's, Battlefront II from GOG (another exe: the
launcher will refuse it), a window in place of fullscreen from the Settings
window, and a resolution other than the screen's own.
