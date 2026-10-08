// Both games load d3d9.dll from their own folder before System32, so the
// bridge ships as a d3d9.dll that forwards to the real one. That gives us
// code inside each game with no injector, and a natural place to hook the
// D3D9 device later for compositing (Phase 2).
//
// Set [proxy] chain = <path> in wawbf.ini to load another d3d9.dll (ReShade,
// dgVoodoo, ...) instead of the system one.
#include <windows.h>

#include <string>

#include <atomic>

#include "bridge.h"
#include "config.h"
#include "frameprobe.h"
#include "log.h"
#include "memory.h"
#include "overlay.h"

namespace {

HMODULE g_self = nullptr;

// --- once-per-frame callback -------------------------------------------------
// The game hands each finished frame to Direct3D from its own rendering
// thread, after it has updated the world for that frame. Hooking that moment
// is a place to act in step with the game without knowing anything about its
// update loop.
//
// Games do it in different ways. Two calls are hooked and the better one seen
// is used: the device's Present (Battlefront II), and failing that EndScene,
// which a game may call more than once a frame, so BridgeFrame must not assume
// exactly one call per frame.
//
// World at War presents through a swap chain instead of the device. Hooking
// IDirect3DSwapChain9::Present crashed it at the first call, with the stack too
// damaged for the crash log to run, and the reason was not found. Do not put
// that hook back without finding out why. Vtable slots are from d3d9.h.
const int kCreateDevice = 16;  // IDirect3D9
const int kPresent = 17;       // IDirect3DDevice9
const int kEndScene = 42;      // IDirect3DDevice9

using CreateDeviceFn = HRESULT(WINAPI*)(void* self, UINT adapter, DWORD type, HWND focus,
                                        DWORD behavior, void* parameters, void** device);
using PresentFn = HRESULT(WINAPI*)(void* self, const RECT* source, const RECT* destination,
                                   HWND window, const void* dirtyRegion);
using EndSceneFn = HRESULT(WINAPI*)(void* self);

CreateDeviceFn g_realCreateDevice = nullptr;
PresentFn g_realPresent = nullptr;
EndSceneFn g_realEndScene = nullptr;
std::atomic<bool> g_frameProbe{false};  // [debug] frame_probe: see frameprobe.h

// Which hook is driving BridgeFrame: 0 none yet, 1 the device's Present,
// 2 EndScene. Present wins once it has been seen.
std::atomic<int> g_frameSource{0};

void Frame(int source) {
  int current = g_frameSource.load();
  while ((current == 0 || source < current) && !g_frameSource.compare_exchange_weak(current, source)) {
  }
  if (g_frameSource.load() != source) return;
  static std::atomic<int> announced{0};
  if (announced.exchange(source) != source) {
    wawbf::log::Info("frames are counted at %s", source == 1 ? "the device's Present" : "EndScene");
  }
  wawbf::BridgeFrame();
}

HRESULT WINAPI PresentHook(void* self, const RECT* source, const RECT* destination, HWND window,
                           const void* dirtyRegion) {
  wawbf::overlay::Publish(static_cast<IDirect3DDevice9*>(self));
  if (g_frameProbe) wawbf::frameprobe::OnPresent(static_cast<IDirect3DDevice9*>(self));
  Frame(1);
  return g_realPresent(self, source, destination, window, dirtyRegion);
}

HRESULT WINAPI EndSceneHook(void* self) {
  Frame(2);
  // While the scene is still open: the other game's picture goes on last.
  wawbf::overlay::Draw(static_cast<IDirect3DDevice9*>(self));
  return g_realEndScene(self);
}

HRESULT WINAPI CreateDeviceHook(void* self, UINT adapter, DWORD type, HWND focus, DWORD behavior,
                                void* parameters, void** device) {
  const HRESULT result = g_realCreateDevice(self, adapter, type, focus, behavior, parameters, device);
  if (SUCCEEDED(result) && device && *device) {
    if (void* previous = wawbf::mem::PatchVtable(*device, kPresent, &PresentHook)) {
      g_realPresent = reinterpret_cast<PresentFn>(previous);
    }
    if (void* previous = wawbf::mem::PatchVtable(*device, kEndScene, &EndSceneHook)) {
      g_realEndScene = reinterpret_cast<EndSceneFn>(previous);
    }
    wawbf::log::Info("Direct3D device created; frame hooks installed");
    // Off unless asked for: it hooks a dozen more of the device's calls.
    // Publishing a picture needs it too, for the cut (see overlay.h).
    const wawbf::Config config(wawbf::ModuleDir(g_self) + L"wawbf.ini");
    if (config.GetInt("debug", "frame_probe", 0) != 0 || config.GetInt("overlay", "publish", 0) != 0) {
      wawbf::frameprobe::Install(static_cast<IDirect3DDevice9*>(*device));
      g_frameProbe = true;
    }
  }
  return result;
}

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
  void* d3d = fn ? fn(sdkVersion) : nullptr;
  if (d3d) {
    if (void* previous = wawbf::mem::PatchVtable(d3d, kCreateDevice, &CreateDeviceHook)) {
      g_realCreateDevice = reinterpret_cast<CreateDeviceFn>(previous);
    }
  }
  return d3d;
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
