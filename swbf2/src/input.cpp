#include "input.h"

#include <windows.h>

#include <atomic>
#include <cstring>

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
std::atomic<int> g_fire{0}, g_aim{-1}, g_reload{-1};
std::atomic<int> g_zoomed{-1};
BYTE* g_player = nullptr;
bool g_installed = false, g_failed = false;

// For the log: how often the game updated the player's controller, and in how
// many of those a function was turned on.
std::atomic<uint32_t> g_updates{0}, g_turnedOn{0}, g_aimPresses{0};

uint32_t Bit(int function) { return function >= 0 && function < kFunctionCount ? 1u << function : 0; }

// The functions that are simply on while their button is.
uint32_t Wanted(uint32_t buttons) {
  uint32_t functions = g_forcedFunctions.load(std::memory_order_relaxed) & ((1u << kFunctionCount) - 1);
  if (buttons & kWawButtonFire) functions |= Bit(g_fire.load(std::memory_order_relaxed));
  if (buttons & kWawButtonReload) functions |= Bit(g_reload.load(std::memory_order_relaxed));
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
  if (enabled) on |= AimPress((buttons & kWawButtonAim) != 0);
  before = wanted;
  if (!on || !controller[kControllerInUse]) return;
  BYTE* state = *reinterpret_cast<BYTE**>(controller + kControllerState);
  if (!state) return;
  *reinterpret_cast<uint32_t*>(state + kStateFunctions) |= on;
  ++g_turnedOn;
}

// The game was built with its own ideas about which registers a call may
// change, so nothing can be assumed about what the caller still needs: this
// puts every register back, the floating point ones included, before going
// on to the function the game meant to call. The controller is in esi.
BYTE* MakeThunk(void* handler, const BYTE* original) {
  const BYTE code[] = {
      0x60,                                // pushad
      0x9C,                                // pushfd
      0x8B, 0xEC,                          // mov ebp, esp
      0x83, 0xE4, 0xF0,                    // and esp, -16
      0x81, 0xEC, 0x00, 0x02, 0x00, 0x00,  // sub esp, 512
      0x0F, 0xAE, 0x04, 0x24,              // fxsave [esp]
      0x56,                                // push esi
      0xB8, 0, 0, 0, 0,                    // mov eax, handler
      0xFF, 0xD0,                          // call eax
      0x83, 0xC4, 0x04,                    // add esp, 4
      0x0F, 0xAE, 0x0C, 0x24,              // fxrstor [esp]
      0x8B, 0xE5,                          // mov esp, ebp
      0x9D,                                // popfd
      0x61,                                // popad
      0xE9, 0, 0, 0, 0,                    // jmp original
  };
  const size_t kHandlerAt = 19, kJumpAt = sizeof(code) - 5;
  auto* thunk = static_cast<BYTE*>(VirtualAlloc(nullptr, sizeof(code), MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
  if (!thunk) return nullptr;
  std::memcpy(thunk, code, sizeof(code));
  std::memcpy(thunk + kHandlerAt, &handler, sizeof(handler));
  const int32_t jump = static_cast<int32_t>(original - (thunk + kJumpAt + 5));
  std::memcpy(thunk + kJumpAt + 1, &jump, sizeof(jump));
  DWORD old = 0;
  VirtualProtect(thunk, sizeof(code), PAGE_EXECUTE_READ, &old);
  FlushInstructionCache(GetCurrentProcess(), thunk, sizeof(code));
  return thunk;
}

bool Install() {
  auto* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
  BYTE* call = base + kUpdateCall;
  BYTE found[sizeof(kUpdateCallBytes)] = {};
  if (!mem::Read(reinterpret_cast<uintptr_t>(call), found, sizeof(found)) ||
      std::memcmp(found, kUpdateCallBytes, sizeof(found)) != 0) {
    log::Error("forward_fire: this is not the BattlefrontII.exe it was written for (%02X %02X %02X %02X %02X where the controller update should be); nothing is forwarded",
               found[0], found[1], found[2], found[3], found[4]);
    return false;
  }
  int32_t distance = 0;
  std::memcpy(&distance, call + 1, sizeof(distance));
  BYTE* thunk = MakeThunk(reinterpret_cast<void*>(&OnControllerUpdate), call + 5 + distance);
  if (!thunk) {
    log::Error("forward_fire: no memory for the hook; nothing is forwarded");
    return false;
  }
  g_player = base + kPlayerController;
  // The four bytes after the call's opcode sit on a four-byte boundary, so
  // the game's thread sees either the old call or the new one, never half.
  auto* slot = reinterpret_cast<volatile LONG*>(call + 1);
  DWORD old = 0;
  if (!VirtualProtect(call, sizeof(found), PAGE_EXECUTE_READWRITE, &old)) {
    log::Error("forward_fire: the game's code could not be changed (error %lu); nothing is forwarded", GetLastError());
    return false;
  }
  InterlockedExchange(slot, static_cast<LONG>(thunk - (call + 5)));
  VirtualProtect(call, sizeof(found), old, &old);
  FlushInstructionCache(GetCurrentProcess(), call, sizeof(found));
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
    said = true;
    log::Info("forward_fire: fire is game function %d, aim (zoom) %d, reload %d (-1: not forwarded)", functions.fire,
              functions.aim, functions.reload);
  }
}

void SetZoomed(int zoomed) { g_zoomed.store(zoomed, std::memory_order_relaxed); }

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
