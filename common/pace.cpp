#include "pace.h"

#include <windows.h>

#include <algorithm>
#include <atomic>

#include "clock.h"
#include "log.h"
#include "overlay.h"
#include "perf.h"

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

namespace wawbf::pace {
namespace {

std::atomic<int> g_fps{0};
int64_t g_last = 0;  // rendering thread only: when the last frame was let go

// Sleep() only wakes on the system's timer tick, 15.6 ms unless something has
// asked for finer, which is a whole frame. A high-resolution waitable timer
// (Windows 10 1803 and later) wakes within about half a millisecond.
HANDLE Timer() {
  static const HANDLE timer = [] {
    HANDLE t = CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    log::Info(t ? "frame cap: waiting on a high-resolution timer" : "frame cap: no high-resolution timer; waiting with Sleep");
    return t;
  }();
  return timer;
}

void WaitUs(int64_t us) {
  if (us <= 0) return;
  if (const HANDLE timer = Timer()) {
    LARGE_INTEGER due;
    due.QuadPart = -us * 10;  // relative, in 100 ns
    if (SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE)) {
      WaitForSingleObject(timer, INFINITE);
      return;
    }
  }
  Sleep(static_cast<DWORD>(us / 1000));
}

}  // namespace

void Set(int fps) {
  if (g_fps.exchange(fps) == fps) return;
  if (fps == kMatch) {
    log::Info("frame cap: as fast as World at War draws, and a tenth (%d a second until it does)", kFallback);
  } else if (fps > 0) {
    log::Info("frame cap: %d frames a second", fps);
  } else {
    log::Info("frame cap: none");
  }
}

void RaiseGraphicsPriority() {
  static bool done = false;
  if (done) return;
  done = true;
  // Not in any header a game's build has: gdi32 exports it. 4 is
  // D3DKMT_SCHEDULINGPRIORITYCLASS_HIGH.
  using Fn = LONG(WINAPI*)(HANDLE, int);
  const HMODULE gdi = GetModuleHandleW(L"gdi32.dll");
  const auto set = gdi ? reinterpret_cast<Fn>(reinterpret_cast<void*>(GetProcAddress(gdi, "D3DKMTSetProcessSchedulingPriorityClass"))) : nullptr;
  const LONG status = set ? set(GetCurrentProcess(), 4) : -1;
  log::Info(status == 0 ? "graphics priority: high" : "graphics priority: Windows would not raise it (0x%08lX)", static_cast<unsigned long>(status));
}

void AfterPresent() {
  const int fps = g_fps.load(std::memory_order_relaxed);
  if (fps == 0) {
    g_last = 0;
    return;
  }
  int64_t interval;
  if (fps > 0) {
    interval = 1000000 / fps;
  } else {
    const uint32_t reader = overlay::ReaderFrameUs();
    interval = reader ? reader * 10 / 11 : 1000000 / kFallback;
  }
  interval = std::min<int64_t>(std::max<int64_t>(interval, 1000000 / 300), 1000000 / 20);

  const int64_t now = NowUs64();
  const int64_t next = g_last + interval;
  // Late already, or the first frame, or the clock has gone backwards: no wait,
  // and the count starts again from now rather than racing to catch up.
  if (!g_last || now >= next || next - now > interval) {
    g_last = now;
    return;
  }
  WaitUs(next - now);
  perf::Add(perf::kWait, NowUs64() - now);
  g_last = next;
}

}  // namespace wawbf::pace
