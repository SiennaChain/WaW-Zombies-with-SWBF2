// Keeps the game from acting on the player's keyboard, mouse and controller
// while another window is in front.
//
// The player's hands are on World at War. What this game needs of them, the
// bridge gives it, by setting the game's functions directly (input.h). But
// the game also still reads the devices themselves, through DirectInput, and
// it is kept running as if it were in front (focus.h), so it acts on them
// too: Tab, or a controller's Back button, held for World at War's tally,
// brought up this game's own list of players at the same moment, over the
// part of its HUD that is kept.
//
// So while this game's window is not really the one in front, every device
// reads as untouched: no key down, no mouse movement, no controller button
// pressed (a controller's sticks are left as they are; the bridge places the
// character and the camera itself). In front, with the player clicked into
// it, it reads them as it always did.
//
// DirectInput's two routines that hand a device's state to a program are sent
// through ours first, for every device there is or will be: all of them
// share one table of routines.
#pragma once

namespace wawbf::devices {

// Returns false if DirectInput is not there to change.
bool QuietInBackground();

}  // namespace wawbf::devices
