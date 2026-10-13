// Where a frame's time goes, written to the bridge's log.
//
// Both games and the picture passed between them share one PC. On a fast one
// nothing here is ever noticed; on a laptop with one integrated graphics chip
// for both games it can be what decides the frame rate. So each bridge counts
// its game's frames, and how long the mod's own parts of a frame take, and
// logs it every few seconds ([debug] perf_seconds) as one line:
//
//   perf: 58.1 fps, frame 17.2 avg 41.0 worst | readback 6.1/12.0 | copy 1.9/3.0 ...
//
// Times are milliseconds, average/worst over the lines' span. Sections that did
// not happen in that span are left out. What each is:
//
//   bridge    the bridge's own per-frame work (BridgeFrame), lock waits included
//   readback  SWBF2: getting its finished frame back from the graphics card
//   copy      SWBF2: copying that frame into the shared picture
//   present   SWBF2: the game's own Present: long when the graphics card is the limit
//   wait      SWBF2: time spent held back by the frame cap (pace.h)
//   upload    WaW: copying the newest picture into its texture
//   draw      WaW: drawing that texture over the frame, state saved and restored
#pragma once

#include <cstdint>

namespace wawbf::perf {

enum Section : int { kBridge, kReadback, kCopy, kPresent, kWait, kUpload, kDraw, kSectionCount };

// Once per frame, on the game's rendering thread.
void Frame();

// Adds one timing of a section.
void Add(Section section, int64_t us);

// This game's recent average time per frame, in microseconds; 0 until known.
uint32_t FrameUs();

// Logs one line covering everything since the last call, and starts again.
// From any thread.
void Report();

// Report(), at most once every `seconds`; call it often. 0 or less: never.
void ReportEvery(int seconds);

// Times the enclosing scope into a section.
class Scope {
 public:
  explicit Scope(Section section);
  ~Scope();
  Scope(const Scope&) = delete;
  Scope& operator=(const Scope&) = delete;

 private:
  Section section_;
  int64_t start_;
};

}  // namespace wawbf::perf
