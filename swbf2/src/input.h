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
  int ability = -1;       // the character's ability: the game's "secondary fire"
  int meleeAbility = -1;  // the same for a character with a lightsaber (see SetMelee)
  int nextAbility = -1;   // selects the next ability
  int nextWeapon = -1;    // takes the next weapon in hand
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

// True while the player's character fights with a lightsaber. The game gives
// those their own buttons: its "secondary fire" raises the blade to block,
// and the Force is worked by what is "reload" for everyone else. So the
// ability button is sent to meleeAbility instead of ability, and reload is
// not sent at all.
void SetMelee(bool melee);

// Presses "next weapon" once.
void PressNextWeapon();

// Holds reload for a moment: WaW has begun reloading, whatever started it
// there (its button, or a magazine running out).
void PressReload();

// Holds any one function for this many of the game's updates: a press, for
// the ones the game treats as a switch (crouch).
void HoldFor(int function, int updates);

// Functions held for as long as they are in this mask (sprint, while the WaW
// player sprints).
void SetHeld(uint32_t mask);

// Pushes one of the game's four stick axes (the control state's floats: which
// is which is in docs/PHASE3.md) to a value for as long as it is not zero.
// The unit is moved by the bridge, not by the stick, but the game will not
// break into a sprint unless the stick says "forward".
void SetAxis(int axis, float value);

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
