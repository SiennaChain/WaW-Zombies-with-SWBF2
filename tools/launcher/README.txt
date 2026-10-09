ZOMBIES WITH BATTLEFRONT II                                          (alpha)
==========================================================================

Call of Duty: World at War's Nazi Zombies, played as the soldiers, heroes and
villains of Star Wars Battlefront II (2005), with their weapons, lightsabers
and Force powers. World at War runs the map and the zombies and fills the
screen; Battlefront II runs unseen beside it and is your character.

This is an early version: one map (Nacht der Untoten), one player.


WHAT YOU NEED
-------------
Both games, from Steam, installed and up to date:

    Call of Duty: World at War
    Star Wars Battlefront II (Classic, 2005)

Each has to have been started once by itself and given a player profile.
Windows 10 or 11.


TO PLAY
-------
1. Unpack this whole folder somewhere of your own (not inside either game).
2. Run "Zombies with Battlefront II.exe".

The first time, it puts the mod's files into both games. Every time, it
starts Battlefront II with no window (that is as it should be), waits for it
to load, and then starts World at War straight into the map. Allow half a
minute.

To stop, quit World at War: Esc, then Quit. Battlefront II closes by itself.
World at War's own main menu is skipped on purpose; to play again, run the
launcher again.

Started from Steam in the ordinary way, both games are exactly as they were.
The mod does nothing unless the launcher started them.


CONTROLS
--------
Everything is World at War's own, as you have it set there: move, look, fire,
aim, reload, grenade, melee, sprint, jump, crouch, use. On top of that:

                                         keyboard     controller
    Next character, heroes' side         F10          d-pad up
    Next character, villains' side       F11          d-pad down
    First / third person                 F9           d-pad right
    Next ability                         X            LB
    Boba Fett's flamethrower on / off    5            d-pad left

You start as a stormtrooper, seen from behind. The heroes are one press of
"next character, heroes' side" away, the villains one press of the other.

Your grenade button is your character's ability: a thermal detonator, a
rocket, Force push, Force lightning. With a lightsaber, aim uses the Force
as well.
A character's own controls are shown at the top left the first time you
become them.

In the map: the outlines on the walls sell ammunition for whatever you are
carrying, a Pack-a-Punch machine stands where the mystery box was, and a
Quick Revive machine stands opposite the weapon cabinet.


SETTINGS
--------
It starts fullscreen, at the size of your screen.

World at War only lets you change its video mode, refresh rate, anti-aliasing
and "sync every frame" at its main menu, and this skips the main menu: in the
game's own Options they are greyed out. So they are in the launcher instead.
Run "Settings.cmd", or press Settings in the launcher while it is loading
(that stops the start; Save and play starts it again):

    Fullscreen, or a window
    Resolution
    Refresh rate
    Anti-aliasing
    Sync every frame
    Your character's picture   lower it if the game runs slowly

Everything else is where it always was, in World at War's own Options while
you play (Esc): brightness, shadows, textures, sound, controls.

The same settings, and a few rarer ones, are in wawbf_launcher.ini beside the
launcher, which says what each line does.

The picture is made for widescreen (16:9).


TO REMOVE IT
------------
Run "Uninstall.cmd" in this folder, then delete the folder. It takes the
mod's files out of both games and puts back anything of the same name that
was there before (another mod's d3d9.dll, for instance; while this mod is
installed, that one is not in use).


IF SOMETHING GOES WRONG
-----------------------
The launcher says what stopped it. Beyond that:

  * Leave the mouse and keyboard alone for the few seconds it takes to start.
    World at War started behind another window (because you clicked on one,
    or were typing in one) does not get the screen and stops answering; end
    it from the Task Manager and start again.
  * An antivirus may object to d3d9.dll in the games' folders. It is how the
    mod gets inside each game; it is not signed by anybody. Allow it or do
    not play: there is no other way in.
  * "Not the version the mod was made for": the mod works with the current
    Steam builds only. Let Steam update or verify the game.
  * Three logs say what happened: wawbf_launcher.log here, wawbf_waw.log in
    World at War's folder and wawbf_swbf2.log in Battlefront II's GameData
    folder. Send those with any report.


Not affiliated with Activision, Treyarch, EA, Pandemic, Disney or Lucasfilm.
You need to own both games. Offline, single player only: do not take a
changed game into anybody else's match.
