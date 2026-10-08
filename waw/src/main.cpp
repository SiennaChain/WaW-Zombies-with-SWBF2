// Game A bridge, loaded into CoDWaW.exe as d3d9.dll.
//
// Publishes the player's origin and view angles so the SWBF2 bridge can
// mirror them. Addresses come from [waw] in wawbf.ini; until they are found
// the bridge only heartbeats.
//
// The state is published once per frame WaW draws (BridgeFrame), stamped with
// the time it was read. Phase 0 published from the bridge thread on its own
// 60 Hz timer; WaW draws about 90 frames a second and SWBF2 about 80, and
// three clocks that do not line up made the follower stutter.
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>

#include "bridge.h"
#include "clock.h"
#include "config.h"
#include "crashlog.h"
#include "log.h"
#include "memory.h"
#include "overlay.h"
#include "shm.h"

namespace wawbf {
namespace {

// Everything this bridge takes from wawbf.ini. Read again whenever the file
// is saved, so it can be changed while the game runs.
struct Settings {
  AddressSpec origin, angles, fov;
  bool haveOrigin = false;
  bool haveAngles = false;
  bool haveFov = false;
  int tickMs = 16;
};

Settings LoadSettings(const Config& config) {
  Settings s;
  s.haveOrigin = config.GetAddress("waw", "player_origin", s.origin);
  s.haveAngles = config.GetAddress("waw", "view_angles", s.angles);
  s.haveFov = config.GetAddress("waw", "view_fov", s.fov);
  if (!s.haveOrigin) {
    log::Info("[waw] player_origin not set: heartbeat only (see docs/PHASE0.md)");
  }
  s.tickMs = 1000 / std::max(1, config.GetInt("bridge", "tick_hz", 60));
  return s;
}

// Shared between the bridge thread, which loads the settings and owns the
// mapping, and the game's rendering thread, which publishes. The mutex also
// keeps the published slot to one writer at a time, which its seqlock needs.
std::mutex g_mutex;
Settings g_settings;             // guarded by g_mutex
SharedBlock* g_block = nullptr;  // guarded by g_mutex; set once the mapping is open
WawPlayerState g_state{};        // guarded by g_mutex; the last state published
std::atomic<uint32_t> g_frames{0};

// Reads the player and publishes it if it has changed. Call with g_mutex held.
//
// This can run more than once per frame the game draws. Publishing the same
// position twice with two timestamps would tell the other side the player
// stood still for part of a frame, which is exactly the stutter the
// timestamps are there to remove. So a sample goes out only when the player
// has moved or turned, and otherwise every 50 ms to say "still here".
void Publish() {
  if (!g_block) return;
  const Settings& s = g_settings;
  WawPlayerState next = g_state;
  next.flags = 0;
  next.timeUs = NowUs();
  if (s.haveOrigin && mem::ReadFloat3(mem::Resolve(s.origin), next.origin)) {
    next.flags |= kWawOriginValid;
  }
  if (s.haveAngles && mem::ReadFloat3(mem::Resolve(s.angles), next.viewAngles)) {
    next.flags |= kWawAnglesValid;
  }
  // Two tangents; anything outside a sane lens means the address is wrong.
  float fov[2];
  if (s.haveFov && mem::Read(mem::Resolve(s.fov), fov, sizeof(fov)) && fov[0] > 0.05f &&
      fov[0] < 5.0f && fov[1] > 0.05f && fov[1] < 5.0f) {
    next.tanHalfFov[0] = fov[0];
    next.tanHalfFov[1] = fov[1];
    next.flags |= kWawFovValid;
  }
  const bool same = next.flags == g_state.flags &&
                    std::memcmp(next.origin, g_state.origin, sizeof(next.origin)) == 0 &&
                    std::memcmp(next.viewAngles, g_state.viewAngles, sizeof(next.viewAngles)) == 0 &&
                    std::memcmp(next.tanHalfFov, g_state.tanHalfFov, sizeof(next.tanHalfFov)) == 0;
  if (same && g_state.frame != 0 && ElapsedUs(g_state.timeUs, next.timeUs) < 50000) return;
  ++next.frame;
  g_state = next;
  g_block->waw.write(g_state);
}

}  // namespace

// (This engine can present from a rendering thread separate from the one that
// runs the game. Reading two vectors from there is harmless; anything that
// changes game state would need more care.)
void BridgeFrame() {
  ++g_frames;
  std::lock_guard<std::mutex> lock(g_mutex);
  Publish();
}

void BridgeMain(HMODULE self) {
  const std::wstring dir = ModuleDir(self);
  log::Init(dir + L"wawbf_waw.log");
  log::Info("WaW bridge loaded (pid %lu)", GetCurrentProcessId());
  crashlog::Install();

  Config config(dir + L"wawbf.ini");
  Settings settings = LoadSettings(config);
  config.Changed();  // the load above is current; only later saves count
  overlay::SetDraw(config.GetInt("overlay", "draw", 0) != 0);

  SharedMapping shm;
  if (!shm.Open(kSideWaw)) return;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_settings = settings;
    g_block = shm.block();
  }

  bool peerWasAlive = false;
  bool wasRendering = false;
  uint32_t lastFrames = 0;
  DWORD lastFrameSeen = 0;
  DWORD lastReport = 0;
  for (;;) {
    shm.Beat();

    // While the game is drawing frames, BridgeFrame publishes. If it is not
    // (loading, minimised), publish from here so the other side still hears.
    const DWORD now = GetTickCount();
    const uint32_t frames = g_frames.load();
    if (frames != lastFrames) {
      lastFrames = frames;
      lastFrameSeen = now;
    }
    const bool rendering = lastFrameSeen != 0 && now - lastFrameSeen < 250;
    if (rendering != wasRendering) {
      log::Info(rendering ? "publishing once per frame, from the game's rendering thread"
                          : "no frames being drawn: publishing from the bridge thread");
      wasRendering = rendering;
    }
    WawPlayerState state;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      if (!rendering) Publish();
      state = g_state;
    }

    const bool peerAlive = shm.PeerAlive();
    if (peerAlive != peerWasAlive) {
      log::Info(peerAlive ? "SWBF2 bridge connected" : "SWBF2 bridge lost");
      peerWasAlive = peerAlive;
    }

    if (now - lastReport >= 1000) {
      lastReport = now;
      if (config.Changed()) {
        log::Info("wawbf.ini changed, reloading");
        settings = LoadSettings(config);
        overlay::SetDraw(config.GetInt("overlay", "draw", 0) != 0);
        std::lock_guard<std::mutex> lock(g_mutex);
        g_settings = settings;
      }

      // Once a second, log both sides' idea of the player position. When the
      // mapping is right, "delta" stays near zero while you move around.
      BfPlayerState bf{};
      const bool haveBf = peerAlive && shm.block()->bf.read(bf) && (bf.flags & kBfPositionValid);
      if ((state.flags & kWawOriginValid) && haveBf) {
        const float dx = bf.positionInWaw[0] - state.origin[0];
        const float dy = bf.positionInWaw[1] - state.origin[1];
        const float dz = bf.positionInWaw[2] - state.origin[2];
        log::Info("waw (%.1f %.1f %.1f) bf->waw (%.1f %.1f %.1f) delta %.1f units",
                  state.origin[0], state.origin[1], state.origin[2], bf.positionInWaw[0],
                  bf.positionInWaw[1], bf.positionInWaw[2],
                  std::sqrt(dx * dx + dy * dy + dz * dz));
      } else if (state.flags & kWawOriginValid) {
        log::Info("waw (%.1f %.1f %.1f) yaw %.1f", state.origin[0], state.origin[1],
                  state.origin[2], state.viewAngles[1]);
      }
    }

    Sleep(settings.tickMs);
  }
}

}  // namespace wawbf
