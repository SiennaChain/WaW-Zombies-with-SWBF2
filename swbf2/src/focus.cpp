#include "focus.h"

#include <windows.h>

#include <atomic>

#include "log.h"
#include "memory.h"

namespace wawbf::focus {
namespace {

HWND g_window = nullptr;       // set once the window is hooked
WNDPROC g_gameProc = nullptr;
bool g_installed = false;
std::atomic<bool> g_enabled{false};

BOOL CALLBACK FindGameWindow(HWND hwnd, LPARAM out) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid != GetCurrentProcessId() || !IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER)) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(out) = hwnd;
  return FALSE;
}

// Until the game's window is hooked there is nothing to pretend about, so
// the real answer is passed through.
HWND WINAPI ForegroundWindowHook() {
  return g_window && g_enabled ? g_window : GetForegroundWindow();
}
HWND WINAPI FocusHook() { return g_window && g_enabled ? g_window : GetFocus(); }

LRESULT CALLBACK FilterProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (g_enabled) {
    switch (message) {
      case WM_ACTIVATEAPP:
        if (!wparam) return 0;
        break;
      case WM_ACTIVATE:
        if (LOWORD(wparam) == WA_INACTIVE) return 0;
        break;
      case WM_KILLFOCUS:
        return 0;
      case WM_NCACTIVATE:
        if (!wparam) return TRUE;  // lets Windows carry on; the game just never hears of it
        break;
    }
  }
  return CallWindowProcA(g_gameProc, hwnd, message, wparam, lparam);
}

void Install() {
  g_installed = true;
  const bool foreground = mem::PatchImport("user32.dll", "GetForegroundWindow", &ForegroundWindowHook);
  const bool focus = mem::PatchImport("user32.dll", "GetFocus", &FocusHook);
  log::Info("keep_running: GetForegroundWindow %s, GetFocus %s", foreground ? "hooked" : "NOT FOUND",
            focus ? "hooked" : "NOT FOUND");
}

}  // namespace

void Tick(bool enabled) {
  if (enabled && !g_installed) Install();
  if (g_enabled.exchange(enabled) != enabled) {
    log::Info("keep_running: %s", enabled ? "on" : "off (hooks pass through)");
  }
  if (!g_installed || g_gameProc) return;

  // The window does not exist yet when the bridge starts; look twice a second.
  static DWORD lastSearch = 0;
  const DWORD now = GetTickCount();
  if (now - lastSearch < 500) return;
  lastSearch = now;
  HWND window = nullptr;
  EnumWindows(FindGameWindow, reinterpret_cast<LPARAM>(&window));
  if (!window) return;

  g_gameProc = reinterpret_cast<WNDPROC>(
      SetWindowLongPtrA(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&FilterProc)));
  if (!g_gameProc) {
    log::Error("keep_running: could not hook the game window (%lu)", GetLastError());
    return;
  }
  g_window = window;
  log::Info("keep_running: game window hooked");
}

}  // namespace wawbf::focus
