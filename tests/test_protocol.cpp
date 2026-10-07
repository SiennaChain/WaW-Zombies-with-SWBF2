// Platform-neutral tests for the protocol: coordinate mapping, seqlock,
// heartbeat and the wawbf.ini address syntax. Runs on Linux or Windows.
#include <cmath>
#include <cstdio>
#include <memory>
#include <thread>

#include "address_spec.h"
#include "wawbf_protocol.h"

using namespace wawbf;

namespace {

int g_failures = 0;

#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);       \
      ++g_failures;                                                     \
    }                                                                   \
  } while (0)

bool Near(float a, float b, float eps = 1e-3f) { return std::fabs(a - b) <= eps; }
bool Near(const Vec3& a, const Vec3& b, float eps = 1e-3f) {
  return Near(a.x, b.x, eps) && Near(a.y, b.y, eps) && Near(a.z, b.z, eps);
}

void TestScale() {
  const CoordMapping m;
  // One metre of WaW travel along each axis is one BF unit.
  CHECK(Near(WawToBf({kWawUnitsPerMetre, 0, 0}, m), {1, 0, 0}));
  CHECK(Near(WawToBf({0, 0, kWawUnitsPerMetre}, m), {0, 1, 0}));  // Z-up -> Y-up
  CHECK(Near(WawToBf({0, kWawUnitsPerMetre, 0}, m), {0, 0, -1}));  // zSign = -1
}

void TestAnchors() {
  CoordMapping m;
  m.anchorWaw = {1000, -250, 64};
  m.anchorBf = {12.5f, 3, -40};
  CHECK(Near(WawToBf(m.anchorWaw, m), m.anchorBf));
  CHECK(Near(BfToWaw(m.anchorBf, m), m.anchorWaw, 1e-2f));
}

void TestRoundTrip() {
  for (const float zSign : {-1.0f, 1.0f}) {
    CoordMapping m;
    m.zSign = zSign;
    m.anchorWaw = {-512, 300, 16};
    m.anchorBf = {7, 0.5f, -3};
    const Vec3 points[] = {{0, 0, 0}, {1234.5f, -987.25f, 128}, {-4096, 4096, -64}};
    for (const Vec3& p : points) {
      CHECK(Near(BfToWaw(WawToBf(p, m), m), p, 1e-2f));
    }
  }
}

void TestHandedness() {
  // zSign = -1 must be a proper rotation: X x Y = Z in WaW space maps to
  // bfX x bfY = bfZ on the mapped basis vectors (cross product preserved).
  const CoordMapping m;
  const Vec3 x = WawToBf({kWawUnitsPerMetre, 0, 0}, m);
  const Vec3 y = WawToBf({0, kWawUnitsPerMetre, 0}, m);
  const Vec3 z = WawToBf({0, 0, kWawUnitsPerMetre}, m);
  const Vec3 cross = {x.y * y.z - x.z * y.y, x.z * y.x - x.x * y.z, x.x * y.y - x.y * y.x};
  CHECK(Near(cross, z));
}

void TestHeartbeat() {
  CHECK(!HeartbeatAlive(0, 0, 100));             // never beat
  CHECK(HeartbeatAlive(1000, 5, 2500));          // 1.5 s old
  CHECK(!HeartbeatAlive(1000, 5, 3500));         // 2.5 s old
  CHECK(HeartbeatAlive(0xFFFFFF00u, 5, 0x100));  // across GetTickCount wrap
}

void TestSeqlock() {
  auto lock = std::make_unique<Seqlocked<WawPlayerState>>();
  lock->seq.store(0);
  WawPlayerState out{};
  CHECK(!lock->read(out));  // nothing written yet

  // A writer publishes states whose fields all equal the frame number; any
  // torn read would show mismatched fields.
  constexpr uint32_t kFrames = 200000;
  std::thread writer([&] {
    for (uint32_t i = 1; i <= kFrames; ++i) {
      WawPlayerState s{};
      s.frame = i;
      s.origin[0] = s.origin[1] = s.origin[2] = static_cast<float>(i);
      s.viewAngles[0] = s.viewAngles[1] = s.viewAngles[2] = static_cast<float>(i);
      lock->write(s);
    }
  });
  uint32_t lastFrame = 0, torn = 0, backwards = 0;
  while (lastFrame < kFrames) {
    if (!lock->read(out)) continue;
    const float f = static_cast<float>(out.frame);
    if (out.origin[0] != f || out.origin[2] != f || out.viewAngles[2] != f) ++torn;
    if (out.frame < lastFrame) ++backwards;
    lastFrame = out.frame;
  }
  writer.join();
  CHECK(torn == 0);
  CHECK(backwards == 0);
}

void TestAddressSpec() {
  AddressSpec a;
  CHECK(ParseAddressSpec("CoDWaW.exe+0x1A2B3C", a));
  CHECK(a.module == "CoDWaW.exe" && a.offset == 0x1A2B3C && a.chain.empty());

  CHECK(ParseAddressSpec("0x00C0FFEE", a));
  CHECK(a.module.empty() && a.offset == 0xC0FFEE);

  CHECK(ParseAddressSpec(" BattlefrontII.exe + 0x1234 > 0x10 > 44 ", a));
  CHECK(a.module == "BattlefrontII.exe" && a.offset == 0x1234);
  CHECK(a.chain.size() == 2 && a.chain[0] == 0x10 && a.chain[1] == 44);

  CHECK(!ParseAddressSpec("", a));
  CHECK(!ParseAddressSpec("CoDWaW.exe+", a));
  CHECK(!ParseAddressSpec("+0x10", a));
  CHECK(!ParseAddressSpec("0x10 > zz", a));
  CHECK(!ParseAddressSpec("0x1FFFFFFFF", a));  // wider than 32 bits
}

}  // namespace

int main() {
  TestScale();
  TestAnchors();
  TestRoundTrip();
  TestHandedness();
  TestHeartbeat();
  TestSeqlock();
  TestAddressSpec();
  if (g_failures) {
    std::printf("%d check(s) failed\n", g_failures);
    return 1;
  }
  std::printf("all protocol tests passed\n");
  return 0;
}
