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

}  // namespace

bool Install(uintptr_t site, const unsigned char expected[5], Handler handler) {
  auto* call = reinterpret_cast<BYTE*>(site);
  BYTE found[5] = {};
  if (!mem::Read(site, found, sizeof(found)) || std::memcmp(found, expected, sizeof(found)) != 0) return false;
  int32_t distance = 0;
  std::memcpy(&distance, call + 1, sizeof(distance));
  BYTE* thunk = MakeThunk(reinterpret_cast<void*>(handler), call + 5 + distance);
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

}  // namespace wawbf::callhook
