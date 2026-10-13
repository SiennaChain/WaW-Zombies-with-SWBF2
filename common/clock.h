// The one clock both bridges agree on.
#pragma once

#include <windows.h>

#include <cstdint>

namespace wawbf {

// Microseconds on the system performance counter, low 32 bits. The counter is
// system-wide, so a value taken in one game means the same instant in the
// other. Compare two with ElapsedUs (wawbf_protocol.h); it wraps.
inline uint32_t NowUs() {
  static const LONGLONG frequency = [] {
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    return f.QuadPart;
  }();
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  // Split to avoid overflowing 64 bits on a long-running machine.
  const LONGLONG seconds = now.QuadPart / frequency;
  const LONGLONG remainder = now.QuadPart % frequency;
  return static_cast<uint32_t>(seconds * 1000000 + remainder * 1000000 / frequency);
}

// Microseconds on the same counter, all 64 bits: for timing inside one process,
// where a wrap would matter.
inline int64_t NowUs64() {
  static const LONGLONG frequency = [] {
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    return f.QuadPart;
  }();
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return static_cast<int64_t>(now.QuadPart / frequency * 1000000 + now.QuadPart % frequency * 1000000 / frequency);
}

}  // namespace wawbf
