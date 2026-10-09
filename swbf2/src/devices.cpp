#include "devices.h"

#include <windows.h>

#include <unknwn.h>

#include <atomic>
#include <cstring>

#include "log.h"
#include "memory.h"

namespace wawbf::devices {
namespace {

// DirectInput's own names for itself and for the keyboard, spelt out so that
// nothing of its SDK has to be linked in.
const GUID kDirectInput8A = {0xBF798030, 0x483A, 0x4DA2, {0xAA, 0x99, 0x5D, 0x64, 0xED, 0x36, 0x97, 0x00}};
const GUID kDirectInput8W = {0xBF798031, 0x483A, 0x4DA2, {0xAA, 0x99, 0x5D, 0x64, 0xED, 0x36, 0x97, 0x00}};
const GUID kSysKeyboard = {0x6F1D2B61, 0xD5A0, 0x11CF, {0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00}};
const DWORD kVersion = 0x0800;

// The places in the two tables of routines: IDirectInput8's CreateDevice, and
// a device's GetDeviceState and GetDeviceData.
const int kCreateDevice = 3, kGetDeviceState = 9, kGetDeviceData = 10;

using GetState = HRESULT(__stdcall*)(void* self, DWORD size, void* data);
using GetData = HRESULT(__stdcall*)(void* self, DWORD each, void* data, DWORD* count, DWORD flags);

// One pair for the devices made for programs that use wide text and one for
// the others: DirectInput keeps a table for each.
GetState g_state[2] = {};
GetData g_data[2] = {};
std::atomic<unsigned> g_quieted{0};

// The game's own window is not the one in front. Asked a few times a frame,
// by the game's thread; Windows answers from a value it keeps.
bool Behind() {
  DWORD owner = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &owner);
  return owner != GetCurrentProcessId();
}

// What each kind of device hands over, by its size: a keyboard's 256 keys, a
// mouse's movement and buttons, a controller's sticks, hats and buttons.
void Untouched(DWORD size, void* data) {
  auto* bytes = static_cast<unsigned char*>(data);
  if (size == 256 || size == 16 || size == 20) {
    std::memset(bytes, 0, size);  // no key down; no movement, no button
  } else if (size == 80 || size == 272) {
    // Six axes and two sliders (left as they are), then four hats, then the
    // buttons: 32 of them, or 128. A hat nobody is pushing reads -1.
    std::memset(bytes + 32, 0xFF, 16);
    std::memset(bytes + 48, 0, size == 80 ? 32 : 128);
  }
}

template <int which>
HRESULT __stdcall StateHook(void* self, DWORD size, void* data) {
  const HRESULT result = g_state[which](self, size, data);
  if (SUCCEEDED(result) && data && Behind()) {
    Untouched(size, data);
    g_quieted.fetch_add(1, std::memory_order_relaxed);
  }
  return result;
}

// The other way a program can read a device: as a list of what has happened
// to it since it last asked. Behind, nothing has.
template <int which>
HRESULT __stdcall DataHook(void* self, DWORD each, void* data, DWORD* count, DWORD flags) {
  const HRESULT result = g_data[which](self, each, data, count, flags);
  if (SUCCEEDED(result) && count && Behind()) *count = 0;
  return result;
}

bool Swap(void** table, int place, void* ours, void** own) {
  DWORD old = 0;
  if (!VirtualProtect(&table[place], sizeof(void*), PAGE_READWRITE, &old)) return false;
  *own = table[place];
  InterlockedExchangePointer(&table[place], ours);
  VirtualProtect(&table[place], sizeof(void*), old, &old);
  return true;
}

// Makes a keyboard of one kind just to find the table every device of that
// kind shares, and changes the two routines in it.
bool Redirect(HMODULE dinput, const GUID& kind, int which, GetState state, GetData data) {
  using Create = HRESULT(WINAPI*)(HINSTANCE, DWORD, REFIID, void**, IUnknown*);
  const auto create = reinterpret_cast<Create>(GetProcAddress(dinput, "DirectInput8Create"));
  IUnknown* input = nullptr;
  if (!create || FAILED(create(GetModuleHandleW(nullptr), kVersion, kind, reinterpret_cast<void**>(&input), nullptr)) || !input) return false;
  using CreateDevice = HRESULT(__stdcall*)(void* self, REFGUID which, IUnknown** device, IUnknown* outer);
  IUnknown* keyboard = nullptr;
  const auto make = reinterpret_cast<CreateDevice>((*reinterpret_cast<void***>(input))[kCreateDevice]);
  bool done = false;
  if (SUCCEEDED(make(input, kSysKeyboard, &keyboard, nullptr)) && keyboard) {
    void** table = *reinterpret_cast<void***>(keyboard);
    if (table[kGetDeviceState] != reinterpret_cast<void*>(state)) {
      done = Swap(table, kGetDeviceState, reinterpret_cast<void*>(state), reinterpret_cast<void**>(&g_state[which])) &&
             Swap(table, kGetDeviceData, reinterpret_cast<void*>(data), reinterpret_cast<void**>(&g_data[which]));
    }
    keyboard->Release();
  }
  input->Release();
  return done;
}

}  // namespace

bool QuietInBackground() {
  // By name, so that it is whichever dinput8.dll the game itself is given.
  const HMODULE dinput = LoadLibraryW(L"dinput8.dll");
  if (!dinput) {
    log::Error("devices: no dinput8.dll (error %lu); the game goes on reading the keyboard and controller behind another window", GetLastError());
    return false;
  }
  const bool narrow = Redirect(dinput, kDirectInput8A, 0, &StateHook<0>, &DataHook<0>);
  const bool wide = Redirect(dinput, kDirectInput8W, 1, &StateHook<1>, &DataHook<1>);
  if (!narrow && !wide) {
    log::Error("devices: DirectInput could not be changed; the game goes on reading the keyboard and controller behind another window");
    return false;
  }
  log::Info("devices: while another window is in front, the game reads its keyboard, mouse and controller as untouched");
  return true;
}

}  // namespace wawbf::devices
