// Pulls Battlefront II's trigger when the player pulls World at War's.
//
// The player's hands are on WaW: it has the keyboard and mouse, and SWBF2 is
// a window behind it (later, no window at all) that Windows gives no input
// to. But the weapon on screen is SWBF2's, so its trigger has to be pulled in
// SWBF2.
//
// Every frame the game reads its devices, looks up what the player has bound
// to each of its "game functions" (fire, jump, reload, ...) and leaves the
// answer in the player's control state: one bit for each function that is
// on. The soldier is driven from that and never looks at a device. This turns
// the function on there, just after the game has filled the state in from its
// own bindings.
//
// So it makes no difference what the player has bound fire to in SWBF2's
// options (a mouse button, a key, a controller's trigger) or whether SWBF2
// can see any of those while it sits behind WaW. Pressing the mouse button on
// the game's behalf was tried first; it did nothing for a player whose fire
// was on a controller.
//
// Looking and moving are not input here: Phase 1 writes those into the game
// directly.
#pragma once

#include <cstdint>

namespace wawbf::input {

// Which game function each WaW button turns on, by the game's own numbering;
// -1 to leave a button out.
struct Functions {
  int fire = 0;
  int altFire = -1;
  int reload = -1;
};

// Call every bridge tick with the current [swbf2] forward_fire setting. The
// game is patched the first time it is true; after that, false leaves the
// game's input exactly as the game made it.
void Tick(bool enabled);

void SetFunctions(const Functions& functions);

// The WawButtons held down now, or 0 if WaW has gone quiet.
void SetButtons(uint32_t buttons);

// [debug] force_buttons: WawButtons held down regardless of WaW, for trying
// this without anyone having to be in WaW.
void SetForced(uint32_t buttons);

// [debug] force_functions: game functions held on, one bit each, for finding
// out which number is which.
void SetForcedFunctions(uint32_t mask);

}  // namespace wawbf::input
