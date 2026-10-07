// wawbf_monitor: prints the shared block live, so the link can be checked
// without reading two log files. Run it while one or both games are up.
#include <windows.h>

#include <cmath>
#include <cstdio>

#include "wawbf_protocol.h"

using namespace wawbf;

namespace {

const char* PeerStatus(const PeerInfo& p) {
  if (p.pid.load() == 0) return "not attached";
  return HeartbeatAlive(p.heartbeatMs.load(), p.beats.load(), GetTickCount()) ? "alive"
                                                                             : "STALE";
}

}  // namespace

int main() {
  HANDLE handle = nullptr;
  std::printf("waiting for %ls ...\n", kMappingName);
  while (!(handle = OpenFileMappingW(FILE_MAP_READ, FALSE, kMappingName))) Sleep(500);

  const auto* block =
      static_cast<const SharedBlock*>(MapViewOfFile(handle, FILE_MAP_READ, 0, 0, kMappingSize));
  if (!block) {
    std::printf("MapViewOfFile failed: %lu\n", GetLastError());
    return 1;
  }
  if (block->header.magic.load() != kMagic || block->header.version != kVersion) {
    std::printf("unexpected header: magic 0x%08X version %u (monitor is v%u)\n",
                block->header.magic.load(), block->header.version, kVersion);
    return 1;
  }

  for (;;) {
    const PeerInfo& pw = block->header.peers[kSideWaw];
    const PeerInfo& pb = block->header.peers[kSideBf];
    std::printf("\nWaW   pid %-6u %s\nSWBF2 pid %-6u %s\n", pw.pid.load(), PeerStatus(pw),
                pb.pid.load(), PeerStatus(pb));

    WawPlayerState waw{};
    if (block->waw.read(waw)) {
      std::printf("waw   frame %-8u origin %s(%.1f, %.1f, %.1f) angles %s(%.1f, %.1f, %.1f)\n",
                  waw.frame, (waw.flags & kWawOriginValid) ? "" : "INVALID ", waw.origin[0],
                  waw.origin[1], waw.origin[2], (waw.flags & kWawAnglesValid) ? "" : "INVALID ",
                  waw.viewAngles[0], waw.viewAngles[1], waw.viewAngles[2]);
    }
    BfPlayerState bf{};
    if (block->bf.read(bf)) {
      std::printf("swbf2 frame %-8u raw %s(%.2f, %.2f, %.2f) in waw (%.1f, %.1f, %.1f)%s\n",
                  bf.frame, (bf.flags & kBfPositionValid) ? "" : "INVALID ", bf.rawPosition[0],
                  bf.rawPosition[1], bf.rawPosition[2], bf.positionInWaw[0], bf.positionInWaw[1],
                  bf.positionInWaw[2], (bf.flags & kBfFollowing) ? " [following]" : "");
      if ((waw.flags & kWawOriginValid) && (bf.flags & kBfPositionValid)) {
        const float dx = bf.positionInWaw[0] - waw.origin[0];
        const float dy = bf.positionInWaw[1] - waw.origin[1];
        const float dz = bf.positionInWaw[2] - waw.origin[2];
        std::printf("delta %.1f units\n", std::sqrt(dx * dx + dy * dy + dz * dz));
      }
    }
    Sleep(250);
  }
}
