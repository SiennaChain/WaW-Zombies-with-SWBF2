// Game B bridge, loaded into BattlefrontII.exe as d3d9.dll.
//
// Phase 0: report where the player's unit is, and with [swbf2] follow = 1,
// move it to wherever the WaW player is. Writing the position from this
// thread races the game's own update, so expect jitter; Phase 1 replaces it
// with a hook inside SWBF2's player update.
#include <windows.h>

#include <algorithm>

#include "bridge.h"
#include "config.h"
#include "log.h"
#include "memory.h"
#include "shm.h"

namespace wawbf {
namespace {

CoordMapping LoadMapping(const Config& config) {
  CoordMapping m;
  m.anchorWaw = config.GetVec3("mapping", "anchor_waw", m.anchorWaw);
  m.anchorBf = config.GetVec3("mapping", "anchor_bf", m.anchorBf);
  m.scale = config.GetFloat("mapping", "scale", m.scale);
  m.zSign = config.GetFloat("mapping", "z_sign", m.zSign) < 0 ? -1.0f : 1.0f;
  m.yawSign = config.GetFloat("mapping", "yaw_sign", m.yawSign) < 0 ? -1.0f : 1.0f;
  m.yawOffsetDeg = config.GetFloat("mapping", "yaw_offset", m.yawOffsetDeg);
  return m;
}

}  // namespace

void BridgeMain(HMODULE self) {
  const std::wstring dir = ModuleDir(self);
  log::Init(dir + L"wawbf_swbf2.log");
  log::Info("SWBF2 bridge loaded (pid %lu)", GetCurrentProcessId());

  const Config config(dir + L"wawbf.ini");
  AddressSpec positionSpec;
  const bool havePosition = config.GetAddress("swbf2", "player_position", positionSpec);
  if (!havePosition) {
    log::Info("[swbf2] player_position not set: heartbeat only (see docs/PHASE0.md)");
  }
  const bool follow = config.GetInt("swbf2", "follow", 0) != 0;
  const CoordMapping mapping = LoadMapping(config);
  log::Info("mapping: scale %.5f z_sign %.0f anchor_waw (%.1f %.1f %.1f) anchor_bf (%.2f %.2f %.2f)",
            mapping.scale, mapping.zSign, mapping.anchorWaw.x, mapping.anchorWaw.y,
            mapping.anchorWaw.z, mapping.anchorBf.x, mapping.anchorBf.y, mapping.anchorBf.z);
  const int tickMs = 1000 / std::max(1, config.GetInt("bridge", "tick_hz", 60));

  SharedMapping shm;
  if (!shm.Open(kSideBf)) return;

  BfPlayerState state{};
  bool peerWasAlive = false;
  DWORD lastReport = 0;
  for (;;) {
    shm.Beat();
    const bool peerAlive = shm.PeerAlive();
    if (peerAlive != peerWasAlive) {
      log::Info(peerAlive ? "WaW bridge connected" : "WaW bridge lost");
      peerWasAlive = peerAlive;
    }

    state.flags = 0;
    const uintptr_t positionAddr = havePosition ? mem::Resolve(positionSpec) : 0;

    WawPlayerState waw{};
    if (follow && positionAddr && peerAlive && shm.block()->waw.read(waw) &&
        (waw.flags & kWawOriginValid)) {
      const Vec3 target =
          WawToBf({waw.origin[0], waw.origin[1], waw.origin[2]}, mapping);
      const float v[3] = {target.x, target.y, target.z};
      if (mem::WriteFloat3(positionAddr, v)) state.flags |= kBfFollowing;
      // TODO(phase 1): facing. Needs SWBF2's rotation representation; then
      // use WawYawToBf(waw.viewAngles[1], mapping).
    }

    if (positionAddr && mem::ReadFloat3(positionAddr, state.rawPosition)) {
      state.flags |= kBfPositionValid;
      const Vec3 w = BfToWaw({state.rawPosition[0], state.rawPosition[1], state.rawPosition[2]},
                             mapping);
      state.positionInWaw[0] = w.x;
      state.positionInWaw[1] = w.y;
      state.positionInWaw[2] = w.z;
    }
    ++state.frame;
    shm.block()->bf.write(state);

    const DWORD now = GetTickCount();
    if (now - lastReport >= 1000 && (state.flags & kBfPositionValid)) {
      lastReport = now;
      log::Info("bf raw (%.2f %.2f %.2f)%s", state.rawPosition[0], state.rawPosition[1],
                state.rawPosition[2], (state.flags & kBfFollowing) ? " following" : "");
    }

    Sleep(tickMs);
  }
}

}  // namespace wawbf
