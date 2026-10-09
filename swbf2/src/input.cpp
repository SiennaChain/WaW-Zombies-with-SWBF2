#include "input.h"

#include <windows.h>

#include <atomic>
#include <cstring>

#include "callhook.h"
#include "log.h"
#include "memory.h"
#include "wawbf_protocol.h"

namespace wawbf::input {
namespace {

// Where things are in BattlefrontII.exe (the Steam build), as offsets from
// where it is loaded. docs/PHASE2.md says how they were found.
//
// The call that is redirected is the last thing the controller's update does
// with a frame's input. By then the control state has been emptied and filled
// in again from the player's bindings, and the soldier has not read it yet.
const uintptr_t kUpdateCall = 0x1537B;
const BYTE kUpdateCallBytes[] = {0xE8, 0x20, 0x66, 0x11, 0x00};  // call BattlefrontII.exe+0x12B9A0
const uintptr_t kPlayerController = 0x1ABE078;  // the first player's controller
const size_t kControllerInUse = 0x25CC;         // byte: its control state is emptied and refilled every update
const size_t kControllerState = 0x25D0;         // pointer to its control state
const size_t kStateFunctions = 0x10;            // in the state: a bit for each function that is on
const int kFunctionCount = 30;                  // the bits above these are not functions
// Functions the game holds on for as long as their button is down: 0-7, 9-12
// and 29. The others are on only for the update in which the button went
// down, which the game tells by comparing with the update before.
const uint32_t kHeldFunctions = 0x20001EFF;

// Pressing zoom. A press lasts this many controller updates; the zoom then
// takes about a quarter of a second to move, and is not pressed again before
// it has had that long. If two presses have not got the game where WaW's aim
// wants it (a unit with nothing to zoom, or none at all) it is left alone
// until WaW's aim changes again.
const int kAimPressUpdates = 2;
const DWORD kAimSettleMs = 400;
const int kAimTries = 2;

std::atomic<bool> g_enabled{false};
std::atomic<uint32_t> g_buttons{0};          // from WaW
std::atomic<uint32_t> g_forced{0};           // [debug] force_buttons
std::atomic<uint32_t> g_forcedFunctions{0};  // [debug] force_functions
std::atomic<int> g_fire{0}, g_aim{-1}, g_reload{-1}, g_ability{-1}, g_meleeAbility{-1}, g_nextAbility{-1}, g_nextWeapon{-1};
std::atomic<int> g_zoomed{-1};
std::atomic<bool> g_aimAllowed{true};
std::atomic<bool> g_melee{false};
std::atomic<uint32_t> g_nextWeaponPresses{0};  // asked for and not yet made
std::atomic<int> g_reloadUpdates{0};           // how many more updates reload is held for
std::atomic<int> g_holdUpdates[kFunctionCount];  // the same for any function (HoldFor)
std::atomic<uint32_t> g_held{0};               // SetHeld
std::atomic<float> g_axis[4];                  // SetAxis
BYTE* g_player = nullptr;
bool g_installed = false, g_failed = false;

// For the log: how often the game updated the player's controller, and in how
// many of those a function was turned on.
std::atomic<uint32_t> g_updates{0}, g_turnedOn{0}, g_aimPresses{0};

uint32_t Bit(int function) { return function >= 0 && function < kFunctionCount ? 1u << function : 0; }

// The functions that are simply on while their button is.
uint32_t Wanted(uint32_t buttons) {
  uint32_t functions = (g_forcedFunctions.load(std::memory_order_relaxed) | g_held.load(std::memory_order_relaxed)) &
                       ((1u << kFunctionCount) - 1);
  const bool melee = g_melee.load(std::memory_order_relaxed);
  if (buttons & kWawButtonFire) functions |= Bit(g_fire.load(std::memory_order_relaxed));
  if ((buttons & kWawButtonReload) && !melee) functions |= Bit(g_reload.load(std::memory_order_relaxed));
  if (buttons & kWawButtonAbility) functions |= Bit((melee ? g_meleeAbility : g_ability).load(std::memory_order_relaxed));
  if (buttons & kWawButtonNextAbility) functions |= Bit(g_nextAbility.load(std::memory_order_relaxed));
  return functions;
}

// Zoom's bit for this update, or 0: on while a press is being made, and a
// press is begun when the game is not zoomed the way WaW's aim is held.
uint32_t AimPress(bool held) {
  static bool was = false;
  static int tries = kAimTries, pressing = 0;
  static DWORD lastPress = 0;
  if (held != was) {
    was = held;
    tries = 0;
  }
  const uint32_t bit = Bit(g_aim.load(std::memory_order_relaxed));
  if (!bit) return 0;
  if (pressing > 0) {
    --pressing;
    return bit;
  }
  const int zoomed = g_zoomed.load(std::memory_order_relaxed);
  const bool wrong = zoomed < 0 ? tries == 0 : (zoomed != 0) != held;
  const DWORD now = GetTickCount();
  if (!wrong || tries >= kAimTries || now - lastPress < kAimSettleMs) return 0;
  tries = zoomed < 0 ? kAimTries : tries + 1;
  lastPress = now;
  pressing = kAimPressUpdates - 1;
  ++g_aimPresses;
  return bit;
}

// Runs on the game's own thread, in the middle of its input update, once for
// each controller. Whatever the player is really pressing in SWBF2 stays on:
// this only ever adds.
void __cdecl OnControllerUpdate(BYTE* controller) {
  if (controller != g_player) return;
  ++g_updates;
  static uint32_t before = 0;
  const bool enabled = g_enabled.load(std::memory_order_relaxed);
  const uint32_t buttons = g_buttons.load(std::memory_order_relaxed) | g_forced.load(std::memory_order_relaxed);
  const uint32_t wanted = enabled ? Wanted(buttons) : 0;
  uint32_t on = (wanted & kHeldFunctions) | (wanted & ~before & ~kHeldFunctions);
  if (enabled) on |= AimPress((buttons & kWawButtonAim) != 0 && g_aimAllowed.load(std::memory_order_relaxed));
  before = wanted;
  if (enabled) {
    for (int function = 0; function < kFunctionCount; ++function) {
      if (g_holdUpdates[function].load(std::memory_order_relaxed) > 0) {
        --g_holdUpdates[function];
        on |= Bit(function);
      }
    }
  }
  if (enabled && g_reloadUpdates.load(std::memory_order_relaxed) > 0) {
    --g_reloadUpdates;
    if (!g_melee.load(std::memory_order_relaxed)) on |= Bit(g_reload.load(std::memory_order_relaxed));
  }
  // A press of "next weapon": on for this update and off for the next, which
  // is how the game sees a button go down.
  static bool pressed = false;
  if (pressed) {
    pressed = false;
  } else if (enabled && g_nextWeaponPresses.load(std::memory_order_relaxed) > 0) {
    --g_nextWeaponPresses;
    on |= Bit(g_nextWeapon.load(std::memory_order_relaxed));
    pressed = true;
  }
  if (!controller[kControllerInUse]) return;
  BYTE* state = *reinterpret_cast<BYTE**>(controller + kControllerState);
  if (!state) return;
  if (enabled) {
    for (int axis = 0; axis < 4; ++axis) {
      const float value = g_axis[axis].load(std::memory_order_relaxed);
      if (value != 0.0f) reinterpret_cast<float*>(state)[axis] = value;
    }
  }
  if (!on) return;
  *reinterpret_cast<uint32_t*>(state + kStateFunctions) |= on;
  ++g_turnedOn;
}

bool Install() {
  auto* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
  g_player = base + kPlayerController;
  // The four bytes after this call's opcode sit on a four-byte boundary, so
  // it can be redirected from any thread: the game's sees either the old call
  // or the new one, never half. The controller is in esi there.
  if (!callhook::Install(reinterpret_cast<uintptr_t>(base + kUpdateCall), kUpdateCallBytes,
                         reinterpret_cast<callhook::Handler>(&OnControllerUpdate))) {
    log::Error("forward_fire: the controller update could not be hooked (not the BattlefrontII.exe this was written for?); nothing is forwarded");
    return false;
  }
  log::Info("forward_fire: hooked the controller update at BattlefrontII.exe+0x%X", static_cast<unsigned>(kUpdateCall));
  return true;
}
}  // namespace

void Tick(bool enabled) {
  if (g_enabled.exchange(enabled) != enabled) {
    log::Info("forward_fire: %s", enabled ? "on" : "off (the game's input is left as the game made it)");
  }
  if (enabled && !g_installed && !g_failed) {
    g_installed = Install();
    g_failed = !g_installed;
  }
  static DWORD lastReport = 0;
  const DWORD now = GetTickCount();
  if (g_installed && now - lastReport >= 5000) {
    lastReport = now;
    const uint32_t updates = g_updates.exchange(0), turnedOn = g_turnedOn.exchange(0);
    const uint32_t aimPresses = g_aimPresses.exchange(0);
    // Said when the picture changes, not every five seconds.
    static uint32_t lastShape = ~0u;
    const uint32_t shape = (updates ? 1u : 0) | (turnedOn ? 2u : 0) | (aimPresses ? 4u : 0);
    if (shape != lastShape) {
      lastShape = shape;
      log::Info("forward_fire, last 5 s: the game updated the player's controller %u times, a function was turned on in %u of them, and zoom was pressed %u times",
                updates, turnedOn, aimPresses);
    }
  }
}

void SetFunctions(const Functions& functions) {
  const int fire = g_fire.exchange(functions.fire), aim = g_aim.exchange(functions.aim),
            reload = g_reload.exchange(functions.reload);
  static bool said = false;
  if (!said || fire != functions.fire || aim != functions.aim || reload != functions.reload) {
    log::Info("forward_fire: fire is game function %d, aim (zoom) %d, reload %d (-1: not forwarded)", functions.fire,
              functions.aim, functions.reload);
  }
  const int ability = g_ability.exchange(functions.ability), meleeAbility = g_meleeAbility.exchange(functions.meleeAbility),
            nextAbility = g_nextAbility.exchange(functions.nextAbility), nextWeapon = g_nextWeapon.exchange(functions.nextWeapon);
  if (!said || ability != functions.ability || meleeAbility != functions.meleeAbility ||
      nextAbility != functions.nextAbility || nextWeapon != functions.nextWeapon) {
    log::Info("forward_fire: the ability is game function %d (%d with a lightsaber), the next ability %d, the next weapon %d",
              functions.ability, functions.meleeAbility, functions.nextAbility, functions.nextWeapon);
  }
  said = true;
}

void SetZoomed(int zoomed) { g_zoomed.store(zoomed, std::memory_order_relaxed); }

void SetAimAllowed(bool allowed) { g_aimAllowed.store(allowed, std::memory_order_relaxed); }

void SetMelee(bool melee) {
  if (g_melee.exchange(melee) != melee) {
    log::Info(melee ? "forward_fire: a lightsaber: the ability button works the Force, and reload is not sent"
                    : "forward_fire: no lightsaber: the ability button is secondary fire");
  }
}

void PressNextWeapon() { ++g_nextWeaponPresses; }

void PressReload() { g_reloadUpdates.store(12, std::memory_order_relaxed); }

void HoldFor(int function, int updates) {
  if (function >= 0 && function < kFunctionCount) g_holdUpdates[function].store(updates, std::memory_order_relaxed);
}

void SetHeld(uint32_t mask) { g_held.store(mask, std::memory_order_relaxed); }

void SetAxis(int axis, float value) {
  if (axis >= 0 && axis < 4) g_axis[axis].store(value, std::memory_order_relaxed);
}

void SetButtons(uint32_t buttons) {
  const uint32_t before = g_buttons.exchange(buttons);
  // Say when the trigger is first pulled: it is the proof the path from WaW works.
  static std::atomic<bool> said{false};
  if ((buttons & kWawButtonFire) && !(before & kWawButtonFire) && !said.exchange(true)) {
    log::Info("forward_fire: the first trigger pull arrived from WaW");
  }
}

void SetForced(uint32_t buttons) {
  if (g_forced.exchange(buttons) != buttons) log::Info("forward_fire: [debug] force_buttons = %u", buttons);
}

void SetForcedFunctions(uint32_t mask) {
  if (g_forcedFunctions.exchange(mask) != mask) log::Info("forward_fire: [debug] force_functions = 0x%X", mask);
}

}  // namespace wawbf::input
