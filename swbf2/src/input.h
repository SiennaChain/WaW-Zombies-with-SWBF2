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
// Fire and reload are on for as long as WaW's are held. Aim is different in
// kind: WaW's is held, and SWBF2's zoom is pressed once to go in and once to
// come out. So for aim the function is pressed, briefly, whenever the game is
// not in the state WaW's button asks for; SetZoomed says which state it is in.
//
// Looking and moving are not input here: Phase 1 writes those into the game
// directly.
#pragma once

#include <cstdint>

namespace wawbf::input {

// Which game function each WaW button works, by the game's own numbering;
// -1 to leave a button out.
struct Functions {
  int fire = 0;
  int aim = -1;
  int reload = -1;
};

// Call every bridge tick with the current [swbf2] forward_fire setting. The
// game is patched the first time it is true; after that, false leaves the
// game's input exactly as the game made it.
void Tick(bool enabled);

void SetFunctions(const Functions& functions);

// The WawButtons held down now, or 0 if WaW has gone quiet.
void SetButtons(uint32_t buttons);

// False while aim must not zoom the game, whoever is holding it: the game is
// then kept zoomed out. (In third person its zoom hides the character.)
void SetAimAllowed(bool allowed);

// Whether the game is zoomed in now: 1, 0, or -1 for "cannot tell". Not
// knowing, aim is pressed once each time WaW's changes, which stays right
// only as long as nothing else zooms the game.
void SetZoomed(int zoomed);

// [debug] force_buttons: WawButtons held down regardless of WaW, for trying
// this without anyone having to be in WaW.
void SetForced(uint32_t buttons);

// [debug] force_functions: game functions held on, one bit each, for finding
// out which number is which.
void SetForcedFunctions(uint32_t mask);

}  // namespace wawbf::input
