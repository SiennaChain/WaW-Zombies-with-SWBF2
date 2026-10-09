#include "focus.h"

#include <windows.h>

#include <atomic>

#include "log.h"
#include "memory.h"

namespace wawbf::focus {
namespace {

HWND g_window = nullptr;       // the game's main window, once found
WNDPROC g_gameProc = nullptr;  // its own window procedure, once ours is in front of it
bool g_installed = false;
std::atomic<bool> g_enabled{false};

// --- never shown, and never the pointer's -----------------------------------

using ShowWindowFn = BOOL(WINAPI*)(HWND, int);
using SetWindowPosFn = BOOL(WINAPI*)(HWND, HWND, int, int, int, int, UINT);
using SetCursorPosFn = BOOL(WINAPI*)(int, int);
ShowWindowFn g_showWindow = nullptr;
SetWindowPosFn g_setWindowPos = nullptr;
SetCursorPosFn g_setCursorPos = nullptr;
std::atomic<bool> g_wantHidden{false};
std::atomic<bool> g_pointerInBackground{true};
std::atomic<HWND> g_asked{nullptr};   // the window the game last asked to show and was not let
std::atomic<bool> g_keptBack{false};  // whether we are the reason the window is not showing

// A window of this game's own that stands by itself: its main window.
bool Main(HWND hwnd) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  return pid == GetCurrentProcessId() && !(GetWindowLongW(hwnd, GWL_STYLE) & WS_CHILD) && !GetWindow(hwnd, GW_OWNER);
}

// Really in front, whatever the game is being told (ForegroundWindowHook).
bool InFront() {
  DWORD pid = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &pid);
  return pid == GetCurrentProcessId();
}

void KeptBack(HWND hwnd) {
  g_asked.store(hwnd);
  if (!g_keptBack.exchange(true)) log::Info("hidden: the game went to show its window and was not let (it goes on drawing and playing)");
}

BOOL WINAPI ShowWindowHook(HWND hwnd, int how) {
  if (g_wantHidden.load(std::memory_order_relaxed) && how != SW_HIDE && Main(hwnd)) {
    KeptBack(hwnd);
    return IsWindowVisible(hwnd);  // what the real one answers: whether it was showing before
  }
  return g_showWindow(hwnd, how);
}

BOOL WINAPI SetWindowPosHook(HWND hwnd, HWND after, int x, int y, int cx, int cy, UINT flags) {
  if (g_wantHidden.load(std::memory_order_relaxed) && Main(hwnd)) {
    if (flags & SWP_SHOWWINDOW) KeptBack(hwnd);
    flags = (flags & ~static_cast<UINT>(SWP_SHOWWINDOW)) | SWP_NOACTIVATE;
  }
  return g_setWindowPos(hwnd, after, x, y, cx, cy, flags);
}

BOOL WINAPI SetCursorPosHook(int x, int y) {
  if (!g_pointerInBackground.load(std::memory_order_relaxed) && !InFront()) {
    static std::atomic<bool> said{false};
    if (!said.exchange(true)) log::Info("pointer: the game went to move it while its window was not the one in front, and was not let");
    return TRUE;
  }
  return g_setCursorPos(x, y);
}

BOOL CALLBACK FindGameWindow(HWND hwnd, LPARAM out) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid != GetCurrentProcessId() || !IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER)) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(out) = hwnd;
  return FALSE;
}

// Until the game's window is found there is nothing to pretend about, so
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

void Start(bool hidden, bool pointerInBackground) {
  g_wantHidden.store(hidden);
  g_pointerInBackground.store(pointerInBackground);
  g_showWindow = reinterpret_cast<ShowWindowFn>(mem::PatchImport("user32.dll", "ShowWindow", &ShowWindowHook));
  g_setWindowPos = reinterpret_cast<SetWindowPosFn>(mem::PatchImport("user32.dll", "SetWindowPos", &SetWindowPosHook));
  g_setCursorPos = reinterpret_cast<SetCursorPosFn>(mem::PatchImport("user32.dll", "SetCursorPos", &SetCursorPosHook));
  log::Info("window and pointer: ShowWindow %s, SetWindowPos %s, SetCursorPos %s", g_showWindow ? "hooked" : "NOT FOUND",
            g_setWindowPos ? "hooked" : "NOT FOUND", g_setCursorPos ? "hooked" : "NOT FOUND");
}

void Tick(bool keepRunning, bool hidden, bool pointerInBackground) {
  g_wantHidden.store(hidden, std::memory_order_relaxed);
  g_pointerInBackground.store(pointerInBackground, std::memory_order_relaxed);
  if (keepRunning && !g_installed) Install();
  if (g_enabled.exchange(keepRunning) != keepRunning) {
    log::Info("keep_running: %s", keepRunning ? "on" : "off (hooks pass through)");
  }

  if (g_window && !IsWindow(g_window)) {
    log::Info("the game window went away; looking for the new one");
    g_window = nullptr;
    g_gameProc = nullptr;
    g_keptBack.store(false);
  }
  if (!g_window) {
    // A window the game was not let show is its window all the same.
    const HWND asked = g_asked.load();
    if (asked && IsWindow(asked)) g_window = asked;
  }
  if (!g_window) {
    // The window does not exist yet when the bridge starts; look twice a second.
    static DWORD lastSearch = 0;
    const DWORD now = GetTickCount();
    if (now - lastSearch < 500) return;
    lastSearch = now;
    HWND window = nullptr;
    EnumWindows(FindGameWindow, reinterpret_cast<LPARAM>(&window));
    if (!window) return;
    g_window = window;
  }

  if (g_installed && !g_gameProc) {
    g_gameProc = reinterpret_cast<WNDPROC>(
        SetWindowLongPtrA(g_window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&FilterProc)));
    if (g_gameProc) {
      log::Info("keep_running: game window hooked");
    } else {
      log::Error("keep_running: could not hook the game window (%lu)", GetLastError());
    }
  }

  // The game shows its window again by itself when a mission loads, so being
  // hidden is something to keep true rather than something done once. Most of
  // the time it never gets as far as showing (ShowWindowHook); this is for
  // whatever other way it finds.
  if (hidden && IsWindowVisible(g_window)) {
    ShowWindowAsync(g_window, SW_HIDE);
    if (!g_keptBack.exchange(true)) log::Info("hidden: the game window is hidden (it goes on drawing and playing)");
  } else if (!hidden && g_keptBack.exchange(false)) {
    ShowWindowAsync(g_window, SW_SHOWNOACTIVATE);
    log::Info("hidden: off, the game window is showing again");
  }
}

}  // namespace wawbf::focus
