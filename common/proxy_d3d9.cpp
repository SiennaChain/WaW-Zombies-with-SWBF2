// Both games load d3d9.dll from their own folder before System32, so the
// bridge ships as a d3d9.dll that forwards to the real one. That gives us
// code inside each game with no injector, and a natural place to hook the
// D3D9 device later for compositing (Phase 2).
//
// Set [proxy] chain = <path> in wawbf.ini to load another d3d9.dll (ReShade,
// dgVoodoo, ...) instead of the system one.
#include <windows.h>

#include <string>

#include "bridge.h"
#include "config.h"

namespace {

HMODULE g_self = nullptr;

HMODULE RealD3D9() {
  static HMODULE real = [] {
    const wawbf::Config config(wawbf::ModuleDir(g_self) + L"wawbf.ini");
    const std::string chain = config.GetString("proxy", "chain");
    if (!chain.empty()) {
      if (HMODULE m = LoadLibraryA(chain.c_str())) return m;
    }
    wchar_t path[MAX_PATH];
    GetSystemDirectoryW(path, MAX_PATH);
    return LoadLibraryW((std::wstring(path) + L"\\d3d9.dll").c_str());
  }();
  return real;
}

template <class Fn>
Fn Real(const char* name) {
  HMODULE m = RealD3D9();
  return m ? reinterpret_cast<Fn>(reinterpret_cast<void*>(GetProcAddress(m, name))) : nullptr;
}

DWORD WINAPI BridgeThread(LPVOID) {
  // Pin ourselves so the bridge thread can never outlive its code.
  HMODULE pinned = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                     reinterpret_cast<LPCWSTR>(&BridgeThread), &pinned);
  wawbf::BridgeMain(g_self);
  return 0;
}

}  // namespace

namespace wawbf {

std::wstring ModuleDir(HMODULE module) {
  wchar_t path[MAX_PATH];
  const DWORD n = GetModuleFileNameW(module, path, MAX_PATH);
  std::wstring dir(path, n);
  const size_t slash = dir.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"" : dir.substr(0, slash + 1);
}

}  // namespace wawbf

// --- d3d9.dll exports (names fixed by d3d9.def) ------------------------------
// Pointer types are void* so we don't depend on d3d9.h; the ABI is identical.
extern "C" {

void* WINAPI Direct3DCreate9(UINT sdkVersion) {
  using Fn = void*(WINAPI*)(UINT);
  auto fn = Real<Fn>("Direct3DCreate9");
  return fn ? fn(sdkVersion) : nullptr;
}

HRESULT WINAPI Direct3DCreate9Ex(UINT sdkVersion, void** out) {
  using Fn = HRESULT(WINAPI*)(UINT, void**);
  auto fn = Real<Fn>("Direct3DCreate9Ex");
  return fn ? fn(sdkVersion, out) : E_NOTIMPL;
}

int WINAPI D3DPERF_BeginEvent(DWORD color, LPCWSTR name) {
  using Fn = int(WINAPI*)(DWORD, LPCWSTR);
  auto fn = Real<Fn>("D3DPERF_BeginEvent");
  return fn ? fn(color, name) : -1;
}

int WINAPI D3DPERF_EndEvent() {
  using Fn = int(WINAPI*)();
  auto fn = Real<Fn>("D3DPERF_EndEvent");
  return fn ? fn() : -1;
}

void WINAPI D3DPERF_SetMarker(DWORD color, LPCWSTR name) {
  using Fn = void(WINAPI*)(DWORD, LPCWSTR);
  if (auto fn = Real<Fn>("D3DPERF_SetMarker")) fn(color, name);
}

void WINAPI D3DPERF_SetRegion(DWORD color, LPCWSTR name) {
  using Fn = void(WINAPI*)(DWORD, LPCWSTR);
  if (auto fn = Real<Fn>("D3DPERF_SetRegion")) fn(color, name);
}

BOOL WINAPI D3DPERF_QueryRepeatFrame() {
  using Fn = BOOL(WINAPI*)();
  auto fn = Real<Fn>("D3DPERF_QueryRepeatFrame");
  return fn ? fn() : FALSE;
}

void WINAPI D3DPERF_SetOptions(DWORD options) {
  using Fn = void(WINAPI*)(DWORD);
  if (auto fn = Real<Fn>("D3DPERF_SetOptions")) fn(options);
}

DWORD WINAPI D3DPERF_GetStatus() {
  using Fn = DWORD(WINAPI*)();
  auto fn = Real<Fn>("D3DPERF_GetStatus");
  return fn ? fn() : 0;
}

}  // extern "C"

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_self = instance;
    DisableThreadLibraryCalls(instance);
    // Only start a thread here; everything else runs on it, outside the
    // loader lock.
    if (HANDLE thread = CreateThread(nullptr, 0, BridgeThread, nullptr, 0, nullptr)) {
      CloseHandle(thread);
    }
  }
  return TRUE;
}
