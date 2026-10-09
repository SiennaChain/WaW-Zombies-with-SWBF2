#include "pad.h"

#include <windows.h>

#include "log.h"

namespace wawbf::pad {

uint32_t Buttons() {
  struct State {
    DWORD packet;
    WORD buttons;
    BYTE triggers[2];
    SHORT sticks[4];
  };
  using GetState = DWORD(WINAPI*)(DWORD, State*);
  static GetState getState = nullptr;
  static bool looked = false;
  if (!looked) {
    looked = true;
    for (const wchar_t* name : {L"xinput1_3.dll", L"xinput1_4.dll", L"xinput9_1_0.dll"}) {
      const HMODULE library = LoadLibraryW(name);
      if (!library) continue;
      getState = reinterpret_cast<GetState>(GetProcAddress(library, "XInputGetState"));
      if (getState) {
        log::Info("controller: read through %ls", name);
        break;
      }
    }
    if (!getState) log::Info("controller: no XInput here; the controller's shortcuts are on the keyboard only");
  }
  if (!getState) return 0;
  // Asking after a controller that is not there is slow, so one that was
  // missing is only asked after again every couple of seconds.
  static DWORD askAgain[4] = {};
  const DWORD now = GetTickCount();
  uint32_t buttons = 0;
  for (DWORD pad = 0; pad < 4; ++pad) {
    if (askAgain[pad] && static_cast<int32_t>(now - askAgain[pad]) < 0) continue;
    State state{};
    if (getState(pad, &state) == ERROR_SUCCESS) {
      buttons |= state.buttons;
      askAgain[pad] = 0;
    } else {
      askAgain[pad] = (now + 2000) | 1;
    }
  }
  return buttons;
}

}  // namespace wawbf::pad
