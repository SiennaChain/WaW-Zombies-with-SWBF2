#include "perf.h"

#include <atomic>
#include <cstdio>
#include <string>

#include "clock.h"
#include "log.h"

namespace wawbf::perf {
namespace {

const char* const kNames[kSectionCount] = {"bridge", "readback", "copy", "present", "wait", "upload", "draw"};

// A frame further apart than this is a load or a pause, not a frame.
constexpr int64_t kLongestFrameUs = 1000000;

struct Tally {
  std::atomic<uint32_t> count{0};
  std::atomic<uint64_t> totalUs{0};
  std::atomic<uint32_t> worstUs{0};

  void Add(int64_t us) {
    const uint32_t v = us < 0 ? 0 : us > 0xFFFFFFFF ? 0xFFFFFFFFu : static_cast<uint32_t>(us);
    count.fetch_add(1, std::memory_order_relaxed);
    totalUs.fetch_add(v, std::memory_order_relaxed);
    uint32_t worst = worstUs.load(std::memory_order_relaxed);
    while (v > worst && !worstUs.compare_exchange_weak(worst, v, std::memory_order_relaxed)) {
    }
  }
};

Tally g_frames;  // the time between one frame and the next
Tally g_sections[kSectionCount];
std::atomic<uint32_t> g_frameCount{0};  // every frame, the long ones included
int64_t g_lastFrame = 0;                // rendering thread only
std::atomic<uint32_t> g_averageUs{0};   // smoothed frame time, for pace.h
std::atomic<int64_t> g_lastReport{0};

}  // namespace

void Frame() {
  const int64_t now = NowUs64();
  g_frameCount.fetch_add(1, std::memory_order_relaxed);
  if (g_lastFrame) {
    const int64_t gap = now - g_lastFrame;
    if (gap > 0 && gap < kLongestFrameUs) {
      g_frames.Add(gap);
      // A moving average over roughly the last 16 frames.
      const uint32_t was = g_averageUs.load(std::memory_order_relaxed);
      const uint32_t next = was ? static_cast<uint32_t>((static_cast<int64_t>(was) * 15 + gap) / 16)
                                : static_cast<uint32_t>(gap);
      g_averageUs.store(next, std::memory_order_relaxed);
    }
  }
  g_lastFrame = now;
}

void Add(Section section, int64_t us) {
  if (section >= 0 && section < kSectionCount) g_sections[section].Add(us);
}

uint32_t FrameUs() { return g_averageUs.load(std::memory_order_relaxed); }

void Report() {
  const int64_t now = NowUs64();
  const int64_t since = g_lastReport.exchange(now);
  const uint32_t frames = g_frameCount.exchange(0);
  const uint32_t timed = g_frames.count.exchange(0);
  const uint64_t frameTotal = g_frames.totalUs.exchange(0);
  const uint32_t frameWorst = g_frames.worstUs.exchange(0);
  std::string sections;
  for (int i = 0; i < kSectionCount; ++i) {
    const uint32_t count = g_sections[i].count.exchange(0);
    const uint64_t total = g_sections[i].totalUs.exchange(0);
    const uint32_t worst = g_sections[i].worstUs.exchange(0);
    if (!count) continue;
    char part[64];
    std::snprintf(part, sizeof(part), " | %s %.1f/%.1f", kNames[i], total / 1000.0 / count, worst / 1000.0);
    sections += part;
  }
  if (!since || now <= since) return;  // the first call only starts the count
  if (!frames) {
    log::Info("perf: no frames drawn");
    return;
  }
  const double seconds = (now - since) / 1e6;
  log::Info("perf: %.1f fps, frame %.1f avg %.1f worst%s (ms, over %.0f s)", frames / seconds,
            timed ? frameTotal / 1000.0 / timed : 0.0, frameWorst / 1000.0, sections.c_str(), seconds);
}

void ReportEvery(int seconds) {
  if (seconds <= 0) return;
  const int64_t last = g_lastReport.load();
  if (!last || NowUs64() - last >= static_cast<int64_t>(seconds) * 1000000) Report();
}

Scope::Scope(Section section) : section_(section), start_(NowUs64()) {}

Scope::~Scope() { Add(section_, NowUs64() - start_); }

}  // namespace wawbf::perf
