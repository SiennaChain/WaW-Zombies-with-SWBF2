#include "callhook.h"

#include <windows.h>

#include <cstring>

#include "memory.h"

namespace wawbf::callhook {
namespace {

// The game was built with its own ideas about which registers a call may
// change, so nothing can be assumed about what the caller still needs: this
// puts every register back, the floating point ones included, before going
// on to the function the game meant to call.
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

// The other order: the game's function first, then the handler. The game's
// way back is taken off the stack and kept, so that the function finds its
// arguments exactly where it expects them (and its registers untouched: this
// game passes some arguments in them); afterwards everything is saved, the
// handler is given where those arguments are, everything is put back, and
// the game's way back is taken.
BYTE* MakeThunkAfter(void* handler, const BYTE* original) {
  const BYTE code[] = {
      0x8F, 0x05, 0, 0, 0, 0,              // pop dword ptr [kept]       the game's way back
      0xE8, 0, 0, 0, 0,                    // call original
      0x50,                                // push eax                   what it returned
      0x60,                                // pushad
      0x9C,                                // pushfd
      0x8B, 0xEC,                          // mov ebp, esp
      0x83, 0xE4, 0xF0,                    // and esp, -16
      0x81, 0xEC, 0x00, 0x02, 0x00, 0x00,  // sub esp, 512
      0x0F, 0xAE, 0x04, 0x24,              // fxsave [esp]
      0x8D, 0x45, 0x28,                    // lea eax, [ebp+40]          the game's arguments
      0x50,                                // push eax
      0xB8, 0, 0, 0, 0,                    // mov eax, handler
      0xFF, 0xD0,                          // call eax
      0x83, 0xC4, 0x04,                    // add esp, 4
      0x0F, 0xAE, 0x0C, 0x24,              // fxrstor [esp]
      0x8B, 0xE5,                          // mov esp, ebp
      0x9D,                                // popfd
      0x61,                                // popad
      0x58,                                // pop eax
      0xFF, 0x35, 0, 0, 0, 0,              // push dword ptr [kept]
      0xC3,                                // ret
      0, 0, 0, 0,                          // kept
  };
  const size_t kPopAt = 2, kCallAt = 6, kHandlerAt = 34, kPushAt = sizeof(code) - 9, kKeptAt = sizeof(code) - 4;
  // Left writable as well as executable: the last four bytes are written on every call.
  auto* thunk = static_cast<BYTE*>(VirtualAlloc(nullptr, sizeof(code), MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
  if (!thunk) return nullptr;
  std::memcpy(thunk, code, sizeof(code));
  const BYTE* kept = thunk + kKeptAt;
  std::memcpy(thunk + kPopAt, &kept, sizeof(kept));
  std::memcpy(thunk + kPushAt, &kept, sizeof(kept));
  std::memcpy(thunk + kHandlerAt, &handler, sizeof(handler));
  const int32_t distance = static_cast<int32_t>(original - (thunk + kCallAt + 5));
  std::memcpy(thunk + kCallAt + 1, &distance, sizeof(distance));
  FlushInstructionCache(GetCurrentProcess(), thunk, sizeof(code));
  return thunk;
}

bool Redirect(uintptr_t site, const unsigned char expected[5], void* handler, bool after) {
  auto* call = reinterpret_cast<BYTE*>(site);
  BYTE found[5] = {};
  if (!mem::Read(site, found, sizeof(found)) || std::memcmp(found, expected, sizeof(found)) != 0) return false;
  int32_t distance = 0;
  std::memcpy(&distance, call + 1, sizeof(distance));
  BYTE* thunk = after ? MakeThunkAfter(handler, call + 5 + distance) : MakeThunk(handler, call + 5 + distance);
  if (!thunk) return false;
  DWORD old = 0;
  if (!VirtualProtect(call, sizeof(found), PAGE_EXECUTE_READWRITE, &old)) return false;
  const LONG redirected = static_cast<LONG>(thunk - (call + 5));
  if ((site + 1) % 4 == 0) {
    InterlockedExchange(reinterpret_cast<volatile LONG*>(call + 1), redirected);
  } else {
    std::memcpy(call + 1, &redirected, sizeof(redirected));
  }
  VirtualProtect(call, sizeof(found), old, &old);
  FlushInstructionCache(GetCurrentProcess(), call, sizeof(found));
  return true;
}

}  // namespace

bool Install(uintptr_t site, const unsigned char expected[5], Handler handler) {
  return Redirect(site, expected, reinterpret_cast<void*>(handler), false);
}

bool InstallAfter(uintptr_t site, const unsigned char expected[5], After handler) {
  return Redirect(site, expected, reinterpret_cast<void*>(handler), true);
}

}  // namespace wawbf::callhook
