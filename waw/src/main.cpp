// Game A bridge, loaded into CoDWaW.exe as d3d9.dll.
//
// Phase 0: publish the player's origin and view angles every tick so the
// SWBF2 bridge can mirror them. Addresses come from [waw] in wawbf.ini;
// until they are found the bridge only heartbeats.
#include <windows.h>

#include <algorithm>
#include <cmath>

#include "bridge.h"
#include "config.h"
#include "log.h"
#include "memory.h"
#include "shm.h"

namespace wawbf {
namespace {

// Everything this bridge takes from wawbf.ini. Read again whenever the file
// is saved, so it can be changed while the game runs.
struct Settings {
  AddressSpec origin, angles;
  bool haveOrigin = false;
  bool haveAngles = false;
  int tickMs = 16;
};

Settings LoadSettings(const Config& config) {
  Settings s;
  s.haveOrigin = config.GetAddress("waw", "player_origin", s.origin);
  s.haveAngles = config.GetAddress("waw", "view_angles", s.angles);
  if (!s.haveOrigin) {
    log::Info("[waw] player_origin not set: heartbeat only (see docs/PHASE0.md)");
  }
  s.tickMs = 1000 / std::max(1, config.GetInt("bridge", "tick_hz", 60));
  return s;
}

}  // namespace

void BridgeMain(HMODULE self) {
  const std::wstring dir = ModuleDir(self);
  log::Init(dir + L"wawbf_waw.log");
  log::Info("WaW bridge loaded (pid %lu)", GetCurrentProcessId());

  Config config(dir + L"wawbf.ini");
  Settings settings = LoadSettings(config);
  config.Changed();  // the load above is current; only later saves count

  SharedMapping shm;
  if (!shm.Open(kSideWaw)) return;

  WawPlayerState state{};
  bool peerWasAlive = false;
  DWORD lastReport = 0;
  for (;;) {
    shm.Beat();

    state.flags = 0;
    if (settings.haveOrigin && mem::ReadFloat3(mem::Resolve(settings.origin), state.origin)) {
      state.flags |= kWawOriginValid;
    }
    if (settings.haveAngles && mem::ReadFloat3(mem::Resolve(settings.angles), state.viewAngles)) {
      state.flags |= kWawAnglesValid;
    }
    ++state.frame;
    shm.block()->waw.write(state);

    const bool peerAlive = shm.PeerAlive();
    if (peerAlive != peerWasAlive) {
      log::Info(peerAlive ? "SWBF2 bridge connected" : "SWBF2 bridge lost");
      peerWasAlive = peerAlive;
    }

    const DWORD now = GetTickCount();
    if (now - lastReport >= 1000) {
      lastReport = now;
      if (config.Changed()) {
        log::Info("wawbf.ini changed, reloading");
        settings = LoadSettings(config);
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
