// Game B bridge, loaded into BattlefrontII.exe as d3d9.dll.
//
// With [swbf2] follow = 1 the player's unit is put wherever the WaW player
// is. Phase 0 did that from the bridge thread, which raced the game's own
// update and made the unit jitter. It is now done once per frame from the
// game's rendering thread (BridgeFrame), in step with the game.
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#include "bridge.h"
#include "clock.h"
#include "config.h"
#include "crashlog.h"
#include "focus.h"
#include "frameprobe.h"
#include "input.h"
#include "log.h"
#include "memory.h"
#include "overlay.h"
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
  m.pitchSign = config.GetFloat("mapping", "pitch_sign", m.pitchSign) < 0 ? -1.0f : 1.0f;
  return m;
}

// One value to put at one address, as written in wawbf.ini:
//   <address> = <u8|u32|f32> <value> [<second value>]
// The second value is only used by a toggle.
// Things the player can ask the arena's mission script for with a key. The
// bridge cannot call the script; it writes a value where the script looks
// (the unit's health, which nothing else uses: see swbf2/arena/WAW_arena.lua).
const int kAsks = 2;
const char* const kAskNames[kAsks] = {"next_hero", "next_villain"};

struct ValueSpec {
  std::string text;  // as written; empty = not set
  AddressSpec address;
  char type = 0;  // 'b' = u8, 'u' = u32, 'f' = f32; 0 = not set
  double value = 0;
  double other = 0;
  bool haveOther = false;
};

bool ParseValueSpec(const char* key, const std::string& text, ValueSpec& out) {
  out = ValueSpec{};
  if (text.empty()) return false;
  const size_t equals = text.rfind('=');
  char type[8] = "";
  int got = 0;
  if (equals != std::string::npos &&
      ParseAddressSpec(detail::Trim(text.substr(0, equals)), out.address)) {
    got = std::sscanf(text.c_str() + equals + 1, " %7s %lf %lf", type, &out.value, &out.other);
  }
  if (!std::strcmp(type, "u8")) out.type = 'b';
  else if (!std::strcmp(type, "u32")) out.type = 'u';
  else if (!std::strcmp(type, "f32")) out.type = 'f';
  if (got < 2 || !out.type) {
    log::Error("%s: expected \"<address> = <u8|u32|f32> <value>\", got \"%s\"", key, text.c_str());
    out = ValueSpec{};
    return false;
  }
  out.haveOther = got == 3;
  out.text = text;
  return true;
}

const char* TypeName(const ValueSpec& v) { return v.type == 'b' ? "u8" : v.type == 'u' ? "u32" : "f32"; }

bool ReadValue(const ValueSpec& v, uintptr_t address, double& out) {
  if (v.type == 'b') {
    uint8_t x = 0;
    if (!mem::Read(address, &x, sizeof(x))) return false;
    out = x;
  } else if (v.type == 'u') {
    uint32_t x = 0;
    if (!mem::Read(address, &x, sizeof(x))) return false;
    out = x;
  } else {
    float x = 0;
    if (!mem::Read(address, &x, sizeof(x))) return false;
    out = x;
  }
  return true;
}

bool WriteValue(const ValueSpec& v, uintptr_t address, double value) {
  if (v.type == 'b') {
    const uint8_t x = static_cast<uint8_t>(value);
    return mem::Write(address, &x, sizeof(x));
  }
  if (v.type == 'u') {
    const uint32_t x = static_cast<uint32_t>(value);
    return mem::Write(address, &x, sizeof(x));
  }
  const float x = static_cast<float>(value);
  return mem::Write(address, &x, sizeof(x));
}

bool SameValue(const ValueSpec& v, double a, double b) {
  return v.type == 'f' ? std::fabs(a - b) <= 1e-5 * std::max(1.0, std::fabs(b)) : a == b;
}

const int kMaxHolds = 8;

// Everything this bridge takes from wawbf.ini. Read again whenever the file
// is saved, so anchors and follow can be changed while the game runs.
struct Settings {
  AddressSpec position, velocity, unitType, aimPitch;
  bool havePosition = false;
  bool haveVelocity = false;
  bool haveUnitType = false;
  bool haveAimPitch = false;
  int unitPositionOffset = 0;  // where the position sits inside the unit object
  bool follow = false;
  bool followHeight = false;
  bool followFacing = false;
  bool followVelocity = false;
  bool followPitch = false;
  int followDelayUs = 12000;     // how far behind "now" the WaW player is placed; see WawNow
  std::vector<int> facingExtra;  // offsets from the position of other "forward" copies to write
  ValueSpec viewToggle;          // flipped between its two values by viewToggleKey
  int viewToggleKey = 0;         // virtual-key code; 0 = none
  ValueSpec poke;                // [debug] poke, applied once each time it changes
  ValueSpec holds[kMaxHolds];    // [debug] hold1..hold8, written every frame
  AddressSpec viewProjection;    // the game's view-projection matrix, to read its field of view from
  bool haveViewProjection = false;
  bool keepRunning = false;
  bool hidden = false;
  bool forwardFire = false;      // pull this game's trigger when the WaW player pulls theirs
  ValueSpec asks[kAsks];         // what to write to ask the mission script for each of kAskNames
  int askKeys[kAsks] = {};       // and the key that asks (a Windows virtual-key code)
  input::Functions functions;    // which of the game's functions each WaW button turns on
  float zoomedBelow = 40.0f;     // the game counts as zoomed in when its vertical field of view is under this; 0 = not looked at
  CoordMapping mapping;
  int tickMs = 16;
};

// "0x208, 0x428" -> {0x208, 0x428}
std::vector<int> ParseOffsets(const std::string& text) {
  std::vector<int> offsets;
  const char* p = text.c_str();
  while (*p) {
    char* end = nullptr;
    const long value = std::strtol(p, &end, 0);
    if (end == p) {
      ++p;
      continue;
    }
    offsets.push_back(static_cast<int>(value));
    p = end;
  }
  return offsets;
}

Settings LoadSettings(const Config& config) {
  Settings s;
  s.havePosition = config.GetAddress("swbf2", "player_position", s.position);
  s.haveVelocity = config.GetAddress("swbf2", "player_velocity", s.velocity);
  s.haveUnitType = config.GetAddress("swbf2", "unit_type", s.unitType);
  s.haveAimPitch = config.GetAddress("swbf2", "aim_pitch", s.aimPitch);
  s.unitPositionOffset = config.GetInt("swbf2", "unit_position_offset", 0);
  if (!s.havePosition) {
    log::Info("[swbf2] player_position not set: heartbeat only (see docs/PHASE0.md)");
  }
  if (!s.haveUnitType) {
    log::Info("[swbf2] unit_type not set: nothing will be written (see wawbf.ini.example)");
  }
  s.follow = config.GetInt("swbf2", "follow", 0) != 0;
  s.followHeight = config.GetInt("swbf2", "follow_height", 0) != 0;
  s.followFacing = config.GetInt("swbf2", "follow_facing", 0) != 0;
  s.followVelocity = config.GetInt("swbf2", "follow_velocity", 0) != 0;
  s.followPitch = config.GetInt("swbf2", "follow_pitch", 0) != 0;
  s.followDelayUs = static_cast<int>(config.GetFloat("swbf2", "follow_delay_ms", 12.0f) * 1000.0f);
  s.facingExtra = ParseOffsets(config.GetString("swbf2", "facing_extra"));
  s.viewToggleKey = config.GetInt("swbf2", "view_toggle_key", 0);
  if (ParseValueSpec("[swbf2] view_toggle", config.GetString("swbf2", "view_toggle"), s.viewToggle) &&
      !s.viewToggle.haveOther) {
    log::Error("[swbf2] view_toggle needs two values to flip between, got \"%s\"", s.viewToggle.text.c_str());
    s.viewToggle = ValueSpec{};
  }
  ParseValueSpec("[debug] poke", config.GetString("debug", "poke"), s.poke);
  int holds = 0;
  for (int i = 0; i < kMaxHolds; ++i) {
    char key[16];
    std::snprintf(key, sizeof(key), "hold%d", i + 1);
    if (ParseValueSpec(key, config.GetString("debug", key), s.holds[i])) ++holds;
  }
  for (int i = 0; i < kAsks; ++i) {
    const std::string key = std::string(kAskNames[i]) + "_key";
    s.askKeys[i] = config.GetInt("swbf2", key.c_str(), 0);
    ParseValueSpec(kAskNames[i], config.GetString("swbf2", kAskNames[i]), s.asks[i]);
  }
  s.keepRunning = config.GetInt("swbf2", "keep_running", 0) != 0;
  s.hidden = config.GetInt("swbf2", "hidden", 0) != 0;
  s.forwardFire = config.GetInt("swbf2", "forward_fire", 0) != 0;
  s.functions.fire = config.GetInt("swbf2", "fire_function", s.functions.fire);
  s.functions.aim = config.GetInt("swbf2", "aim_function", s.functions.aim);
  s.zoomedBelow = config.GetFloat("swbf2", "zoomed_below_fov", s.zoomedBelow);
  s.functions.reload = config.GetInt("swbf2", "reload_function", s.functions.reload);
  input::SetFunctions(s.functions);
  s.haveViewProjection = config.GetAddress("swbf2", "view_projection", s.viewProjection);
  s.mapping = LoadMapping(config);
  log::Info("follow %d (height %s, velocity %s, facing %s +%d extra, pitch %s), %d held value(s), mapping: scale %.5f z_sign %.0f yaw_sign %.0f yaw_offset %.0f pitch_sign %.0f anchor_waw (%.1f %.1f %.1f) anchor_bf (%.2f %.2f %.2f)",
            s.follow ? 1 : 0, s.followHeight ? "from WaW" : "left to SWBF2",
            !s.haveVelocity ? "untouched" : s.followVelocity ? "from WaW" : "cleared",
            s.followFacing ? "from WaW" : "untouched", static_cast<int>(s.facingExtra.size()),
            s.followPitch && s.haveAimPitch ? "from WaW" : "untouched", holds,
            s.mapping.scale, s.mapping.zSign, s.mapping.yawSign, s.mapping.yawOffsetDeg,
            s.mapping.pitchSign,
            s.mapping.anchorWaw.x, s.mapping.anchorWaw.y, s.mapping.anchorWaw.z,
            s.mapping.anchorBf.x, s.mapping.anchorBf.y, s.mapping.anchorBf.z);
  s.tickMs = 1000 / std::max(1, config.GetInt("bridge", "tick_hz", 60));
  return s;
}

// Shared between the bridge thread, which loads the settings and owns the
// mapping, and the game's rendering thread, which moves the unit.
std::mutex g_mutex;
Settings g_settings;               // guarded by g_mutex
SharedBlock* g_block = nullptr;    // guarded by g_mutex; set once the mapping is open
std::atomic<uint32_t> g_frames{0};
std::atomic<bool> g_following{false};

// Whether SWBF2 keeps what it is given: each frame, before writing, what is
// there is compared with what was written the frame before.
struct Kept {
  std::atomic<uint32_t> kept{0}, replaced{0};
};
Kept g_facing, g_pitch;
float g_lastForward[2] = {0, 0};  // x, z; guarded by g_mutex
bool g_haveLastForward = false;
float g_lastPitch = 0;            // guarded by g_mutex
bool g_haveLastPitch = false;

// The same for speed, which the game is expected to change: how much of the
// speed written one frame is still there the next. Guarded by g_mutex.
double g_speedGiven = 0, g_speedFound = 0;  // sums over g_speedFrames frames
uint32_t g_speedFrames = 0;
float g_lastSpeed = 0;
bool g_haveLastSpeed = false;

// The unit's transform is a 4x4 whose last row is the position, so the three
// rows before the position are its right, up and forward directions.
const int kRightRow = -0x30;
const int kForwardRow = -0x10;

void Face(const Settings& s, uintptr_t positionAddr, float wawYawDeg) {
  const float yaw = WawYawToBf(wawYawDeg, s.mapping) * 3.14159265f / 180.0f;
  // WaW yaw 0 looks along +X and turns towards +Y; +Y maps to SWBF2's z
  // through z_sign, like positions do.
  const float fx = std::cos(yaw);
  const float fz = s.mapping.zSign * std::sin(yaw);

  float current[3];
  if (g_haveLastForward && mem::ReadFloat3(positionAddr + kForwardRow, current)) {
    const bool kept = std::fabs(current[0] - g_lastForward[0]) < 0.001f &&
                      std::fabs(current[2] - g_lastForward[1]) < 0.001f;
    ++(kept ? g_facing.kept : g_facing.replaced);
  }

  // Upright unit: right = up x forward.
  const float rows[12] = {fz, 0, -fx, 0, 0, 1, 0, 0, fx, 0, fz, 0};
  if (!mem::Write(positionAddr + kRightRow, rows, sizeof(rows))) return;
  for (const int offset : s.facingExtra) {
    float forward[3];
    if (!mem::ReadFloat3(positionAddr + offset, forward)) continue;
    forward[0] = fx;
    forward[2] = fz;
    mem::WriteFloat3(positionAddr + offset, forward);
  }
  g_lastForward[0] = fx;
  g_lastForward[1] = fz;
  g_haveLastForward = true;
}

// How far up or down the unit aims. SWBF2 keeps it as one angle in radians,
// positive looking up, and works the aim direction and the camera out from it.
void Aim(const Settings& s, float wawPitchDeg) {
  const float kLimit = 1.48f;  // 85 degrees, WaW's own limit
  const float pitch = std::min(kLimit, std::max(-kLimit, WawPitchToBf(wawPitchDeg, s.mapping) * 3.14159265f / 180.0f));
  const uintptr_t address = mem::Resolve(s.aimPitch);
  float current = 0;
  if (!address || !mem::Read(address, &current, sizeof(current))) {
    g_haveLastPitch = false;
    return;
  }
  if (g_haveLastPitch) ++(std::fabs(current - g_lastPitch) < 0.0005f ? g_pitch.kept : g_pitch.replaced);
  g_haveLastPitch = mem::Write(address, &pitch, sizeof(pitch));
  g_lastPitch = pitch;
}

bool WawAlive(const SharedBlock* block) {
  const PeerInfo& waw = block->header.peers[kSideWaw];
  return waw.pid.load() != 0 &&
         HeartbeatAlive(waw.heartbeatMs.load(std::memory_order_relaxed),
                        waw.beats.load(std::memory_order_acquire), GetTickCount());
}

// True if `positionAddr` is the position of a live unit of the expected kind.
//
// player_position follows whatever the camera is showing. While the player
// is dead or choosing a spawn point that is not a unit at all, and writing a
// transform over it corrupts whatever is there: that crashed the game the
// first time facing was written. So nothing is written unless the object the
// position sits in starts with the unit class's identifying word.
bool IsUnit(const Settings& s, uintptr_t positionAddr) {
  if (!s.haveUnitType || !positionAddr) return false;
  const uintptr_t expected = mem::Resolve(s.unitType);
  uint32_t actual = 0;
  return expected != 0 && mem::Read(positionAddr - s.unitPositionOffset, &actual, sizeof(actual)) &&
         actual == static_cast<uint32_t>(expected);
}

// The WaW player at the instant this game is drawing.
struct WawPose {
  float origin[3];
  float velocity[3];  // WaW units per second
  float yaw, pitch;   // degrees
};

// The two newest distinct WaW samples; guarded by g_mutex.
WawPlayerState g_newer{}, g_older{};
bool g_haveNewer = false;
bool g_haveOlder = false;
float g_velocity[3] = {0, 0, 0};  // WaW units per second, smoothed

float AngleBetween(float older, float newer, float t) {
  float turn = newer - older;
  while (turn > 180.0f) turn -= 360.0f;
  while (turn < -180.0f) turn += 360.0f;
  return older + turn * t;
}

// Where the WaW player is at the instant this game is drawing.
//
// WaW publishes once per frame it draws; this game draws at a different rate.
// Using "the newest sample" as it stands means some frames get no movement
// and the next gets two frames' worth, which shows as stutter. So the player
// is placed on the line through the two newest samples, at time now - delay:
// with a delay of about one WaW frame that is mostly interpolation, running a
// little past the newest sample when none has arrived yet.
void WawNow(const Settings& s, const WawPlayerState& latest, WawPose& pose) {
  if (!g_haveNewer || latest.frame != g_newer.frame) {
    const int32_t gap = g_haveNewer ? ElapsedUs(g_newer.timeUs, latest.timeUs) : 0;
    // A long gap (pause, loading) or a jump (respawn, teleport) is no basis for a line.
    const float dx = latest.origin[0] - g_newer.origin[0], dy = latest.origin[1] - g_newer.origin[1];
    g_haveOlder = g_haveNewer && gap > 0 && gap < 250000 && dx * dx + dy * dy < 60.0f * 60.0f;
    // One frame's step over one frame's time is a noisy speed, so it is
    // smoothed over about 40 ms. A standing player is published every 50 ms,
    // which brings it to zero in one go.
    const float blend = g_haveOlder ? std::min(1.0f, gap / 40000.0f) : 1.0f;
    for (int k = 0; k < 3; ++k) {
      const float measured = g_haveOlder ? (latest.origin[k] - g_newer.origin[k]) / (gap * 1e-6f) : 0.0f;
      g_velocity[k] += (measured - g_velocity[k]) * blend;
    }
    g_older = g_newer;
    g_newer = latest;
    g_haveNewer = true;
  }
  const uint32_t now = NowUs();
  // WaW has gone quiet (paused, loading): it is not moving as far as anyone can tell.
  const bool stale = ElapsedUs(g_newer.timeUs, now) > 150000;
  for (int k = 0; k < 3; ++k) {
    pose.origin[k] = g_newer.origin[k];
    pose.velocity[k] = stale ? 0.0f : g_velocity[k];
  }
  pose.pitch = g_newer.viewAngles[0];
  pose.yaw = g_newer.viewAngles[1];
  if (!g_haveOlder) return;

  const int32_t span = ElapsedUs(g_older.timeUs, g_newer.timeUs);
  const int32_t at = ElapsedUs(g_older.timeUs, now - static_cast<uint32_t>(s.followDelayUs));
  // Up to two sample intervals past the newest, then hold: a stalled WaW must not send the unit off.
  const float t = std::min(3.0f, std::max(0.0f, static_cast<float>(at) / static_cast<float>(span)));
  for (int k = 0; k < 3; ++k) pose.origin[k] = g_older.origin[k] + (g_newer.origin[k] - g_older.origin[k]) * t;
  pose.pitch = AngleBetween(g_older.viewAngles[0], g_newer.viewAngles[0], t);
  pose.yaw = AngleBetween(g_older.viewAngles[1], g_newer.viewAngles[1], t);
}

// The game's physics does not know the unit was moved. Whatever speed it had
// is still there, and builds up, unless it is replaced along the axes we own:
// with nothing, or (follow_velocity) with the WaW player's own speed, so the
// game has something to pick the unit's animation from.
void SetVelocity(const Settings& s, const WawPose& pose) {
  const uintptr_t velocityAddr = mem::Resolve(s.velocity);
  float velocity[3];
  if (!velocityAddr || !mem::ReadFloat3(velocityAddr, velocity)) {
    g_haveLastSpeed = false;
    return;
  }
  if (g_haveLastSpeed && g_lastSpeed > 1.0f) {
    g_speedGiven += g_lastSpeed;
    g_speedFound += std::sqrt(velocity[0] * velocity[0] + velocity[2] * velocity[2]);
    ++g_speedFrames;
  }
  Vec3 want{0, 0, 0};
  if (s.followVelocity) want = WawVelocityToBf({pose.velocity[0], pose.velocity[1], pose.velocity[2]}, s.mapping);
  velocity[0] = want.x;
  velocity[2] = want.z;
  if (s.followHeight) velocity[1] = want.y;
  g_haveLastSpeed = mem::WriteFloat3(velocityAddr, velocity);
  g_lastSpeed = std::sqrt(want.x * want.x + want.z * want.z);
}

// Puts the unit where the WaW player is. Call with g_mutex held.
bool Follow(const Settings& s, SharedBlock* block) {
  if (!s.follow || !s.havePosition || !block || !WawAlive(block)) return false;
  const uintptr_t positionAddr = mem::Resolve(s.position);
  if (!IsUnit(s, positionAddr)) return false;
  WawPlayerState waw{};
  if (!block->waw.read(waw) || !(waw.flags & kWawOriginValid)) return false;

  WawPose pose;
  WawNow(s, waw, pose);
  const Vec3 target = WawToBf({pose.origin[0], pose.origin[1], pose.origin[2]}, s.mapping);
  float position[3] = {target.x, target.y, target.z};
  if (!s.followHeight) {
    // Height is left alone, so the unit stands on SWBF2's ground under
    // SWBF2's gravity. Imposing WaW's floor heights on a different map is what
    // had it "falling" and taking damage in the Phase 0 test.
    float current[3];
    if (!mem::ReadFloat3(positionAddr, current)) return false;
    position[1] = current[1];
  }
  if (!mem::WriteFloat3(positionAddr, position)) return false;

  if (s.haveVelocity) {
    SetVelocity(s, pose);
  } else {
    g_haveLastSpeed = false;
  }
  if (s.followFacing && (waw.flags & kWawAnglesValid)) {
    Face(s, positionAddr, pose.yaw);
  } else {
    g_haveLastForward = false;
  }
  if (s.followPitch && s.haveAimPitch && (waw.flags & kWawAnglesValid)) {
    Aim(s, pose.pitch);
  } else {
    g_haveLastPitch = false;
  }
  return true;
}

// [debug] hold1 .. hold8 = <address> = <u8|u32|f32> <value>
//
// Written every frame, after Follow, for as long as the line is there. It is
// how to find out what a field does, and whether the game leaves it alone,
// without building a new DLL: the log says once a second how often the value
// was still there a frame later and what the game had put in its place.
//
// Only while the camera is on a live unit, whatever the address: these are
// almost always fields of the unit, and writing them into whatever else
// player_position points at while the player is dead is how to crash the game.
struct HoldState {
  bool written = false;
  uint32_t kept = 0, replaced = 0;
  double found = 0;
};
HoldState g_holds[kMaxHolds];  // guarded by g_mutex

void Hold(const Settings& s) {
  bool any = false;
  for (const ValueSpec& hold : s.holds) any = any || hold.type;
  if (!any) return;
  const bool unit = s.havePosition && IsUnit(s, mem::Resolve(s.position));
  for (int i = 0; i < kMaxHolds; ++i) {
    const ValueSpec& hold = s.holds[i];
    HoldState& state = g_holds[i];
    if (!hold.type) continue;
    const uintptr_t address = unit ? mem::Resolve(hold.address) : 0;
    double found = 0;
    if (!address || !ReadValue(hold, address, found)) {
      state.written = false;
      continue;
    }
    if (state.written) {
      if (SameValue(hold, found, hold.value)) {
        ++state.kept;
      } else {
        ++state.replaced;
        state.found = found;
      }
    }
    state.written = WriteValue(hold, address, hold.value);
  }
}

// [debug] poke = <address> = <u8|u32|f32> <value>
//
// Writes one value into the game, once, each time the line is changed. It is
// how a newly found address gets tried without building a new DLL, and it has
// to be done from in here: an outside tool that writes to another process is
// blocked by the antivirus.
void ApplyPoke(const ValueSpec& poke) {
  const uintptr_t address = mem::Resolve(poke.address);
  double before = 0;
  if (ReadValue(poke, address, before) && WriteValue(poke, address, poke.value)) {
    log::Info("[debug] poke: 0x%p %s %g -> %g", reinterpret_cast<void*>(address), TypeName(poke), before, poke.value);
  } else {
    log::Error("[debug] poke: could not write %s at 0x%p", TypeName(poke), reinterpret_cast<void*>(address));
  }
}

// [swbf2] view_toggle: flips a setting between its two values. Meant for the
// first / third person view, which the game only offers in its pause menu.
void ApplyToggle(const ValueSpec& toggle) {
  const uintptr_t address = mem::Resolve(toggle.address);
  double before = 0;
  if (!ReadValue(toggle, address, before)) {
    log::Error("view_toggle: could not read %s at 0x%p", TypeName(toggle), reinterpret_cast<void*>(address));
    return;
  }
  const double after = SameValue(toggle, before, toggle.value) ? toggle.other : toggle.value;
  if (WriteValue(toggle, address, after)) {
    log::Info("view_toggle: 0x%p %s %g -> %g", reinterpret_cast<void*>(address), TypeName(toggle), before, after);
  } else {
    log::Error("view_toggle: could not write %s at 0x%p", TypeName(toggle), reinterpret_cast<void*>(address));
  }
}

// [swbf2] next_hero and the like: leaves the mission script its message. Like
// everything else written through the unit's pointer, only when what the
// pointer leads to is a soldier.
void Ask(const Settings& s, int which) {
  const ValueSpec& ask = s.asks[which];
  if (!s.havePosition || !IsUnit(s, mem::Resolve(s.position))) {
    log::Info("%s: there is no unit to ask through", kAskNames[which]);
    return;
  }
  const uintptr_t address = mem::Resolve(ask.address);
  if (address && WriteValue(ask, address, ask.value)) {
    log::Info("%s: asked", kAskNames[which]);
  } else {
    log::Error("%s: could not write %s at 0x%p", kAskNames[which], TypeName(ask), reinterpret_cast<void*>(address));
  }
}

// This game's vertical field of view in degrees, or 0 if it cannot be read.
//
// The view-projection matrix is four rows of four floats. The first three
// floats of its second row are the camera's up direction scaled by the
// projection, so their length is 1 / tan(half the vertical field of view).
float OwnFovDegrees(const Settings& s) {
  if (!s.haveViewProjection) return 0;
  float rows[8];
  if (!mem::Read(mem::Resolve(s.viewProjection), rows, sizeof(rows))) return 0;
  const float scale = std::sqrt(rows[4] * rows[4] + rows[5] * rows[5] + rows[6] * rows[6]);
  return scale > 0.01f && scale < 100.0f ? FovDegrees(1.0f / scale) : 0;
}

// Says, whenever either changes, what the two games' vertical fields of view
// are. They have to agree before one picture can be laid over the other.
void ReportFov(const Settings& s, const SharedBlock* block) {
  static float lastOwn = 0, lastWaw = 0;
  WawPlayerState waw{};
  const bool haveWaw = block->waw.read(waw) && (waw.flags & kWawFovValid);
  const float wawFov = haveWaw ? FovDegrees(waw.tanHalfFov[1]) : 0;
  const float own = OwnFovDegrees(s);
  if (own == 0 || wawFov == 0) return;
  if (std::fabs(own - lastOwn) < 0.2f && std::fabs(wawFov - lastWaw) < 0.2f) return;
  lastOwn = own;
  lastWaw = wawFov;
  const float apart = std::fabs(own - wawFov);
  if (apart < 0.3f) {
    log::Info("field of view: WaW %.1f, SWBF2 %.1f degrees top to bottom: matched", wawFov, own);
  } else {
    log::Info("field of view: WaW %.1f, SWBF2 %.1f degrees top to bottom: %.1f apart", wawFov, own, apart);
  }
}

void ReportKept(const char* what, Kept& counts) {
  const uint32_t kept = counts.kept.exchange(0), replaced = counts.replaced.exchange(0);
  if (kept + replaced) {
    log::Info("%s: the game kept what was written in %u of %u frames", what, kept, kept + replaced);
  }
}

}  // namespace

// Hands the buttons the WaW player is holding to the input hooks. A WaW that
// has gone quiet is holding nothing: a trigger must not stick down because
// the other game froze.
void ForwardButtons(SharedBlock* block) {
  WawPlayerState waw{};
  uint32_t buttons = 0;
  if (block && WawAlive(block) && block->waw.read(waw) && ElapsedUs(waw.timeUs, NowUs()) < 300000) {
    buttons = waw.buttons;
  }
  input::SetButtons(buttons);
}

// Tells the input hooks whether the game is zoomed in, which they need for
// working its zoom from WaW's aim. Read off the field of view the game is
// drawing with: zooming is the one thing that narrows it. An answer has to
// stand for a few frames before it is passed on, so that one odd frame does
// not press a button.
void TellZoom(const Settings& s) {
  static int last = -1, same = 0, told = -1;
  const float fov = s.zoomedBelow > 0 ? OwnFovDegrees(s) : 0;
  const int zoomed = fov > 0 ? (fov < s.zoomedBelow ? 1 : 0) : -1;
  same = zoomed == last ? same + 1 : 0;
  last = zoomed;
  if (same < 3 || zoomed == told) return;
  told = zoomed;
  input::SetZoomed(zoomed);
}

void BridgeFrame() {
  ++g_frames;
  std::lock_guard<std::mutex> lock(g_mutex);
  g_following = Follow(g_settings, g_block);
  Hold(g_settings);
  ForwardButtons(g_block);
  TellZoom(g_settings);
}

void BridgeMain(HMODULE self) {
  const std::wstring dir = ModuleDir(self);
  log::Init(dir + L"wawbf_swbf2.log");
  log::Info("SWBF2 bridge loaded (pid %lu)", GetCurrentProcessId());
  crashlog::Install();

  Config config(dir + L"wawbf.ini");
  Settings settings = LoadSettings(config);
  config.Changed();  // the load above is current; only later saves count
  // The picture for WaW (Phase 2), and the probe's own experiments. Publishing
  // needs the frame cut at the depth clear that comes before the first-person
  // weapon: the second depth-only clear of the frame.
  const auto probe = [&] {
    const bool publish = config.GetInt("overlay", "publish", 0) != 0;
    frameprobe::Request(dir, config.GetString("debug", "frame_dump"));
    frameprobe::SetCut(publish ? config.GetInt("overlay", "cut", 2) : config.GetInt("debug", "frame_cut", 0),
                       publish ? 0 : std::strtoul(config.GetString("debug", "frame_cut_colour", "0").c_str(), nullptr, 0));
    overlay::SetPublish(publish);
    input::SetForced(static_cast<uint32_t>(config.GetInt("debug", "force_buttons", 0)));
    input::SetForcedFunctions(std::strtoul(config.GetString("debug", "force_functions", "0").c_str(), nullptr, 0));
  };
  probe();

  SharedMapping shm;
  if (!shm.Open(kSideBf)) return;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_settings = settings;
    g_block = shm.block();
  }

  BfPlayerState state{};
  bool peerWasAlive = false;
  bool wasRendering = false;
  bool toggleKeyWasDown = false;
  bool askKeyWasDown[kAsks] = {};
  uint32_t lastFrames = 0;
  DWORD lastFrameSeen = 0;
  DWORD lastReport = 0;
  for (;;) {
    shm.Beat();
    focus::Tick(settings.keepRunning, settings.hidden);

    const bool peerAlive = shm.PeerAlive();
    if (peerAlive != peerWasAlive) {
      log::Info(peerAlive ? "WaW bridge connected" : "WaW bridge lost");
      peerWasAlive = peerAlive;
    }

    // While the game is drawing frames, BridgeFrame does the following. If it
    // is not (minimised, loading), fall back to doing it from here so the unit
    // does not drift away; that is the old jittery path, but better than none.
    const DWORD now = GetTickCount();
    const uint32_t frames = g_frames.load();
    if (frames != lastFrames) {
      lastFrames = frames;
      lastFrameSeen = now;
    }
    const bool rendering = lastFrameSeen != 0 && now - lastFrameSeen < 250;
    if (rendering != wasRendering) {
      log::Info(rendering ? "moving the unit once per frame, from the game's own thread"
                          : "no frames being drawn: moving the unit from the bridge thread");
      wasRendering = rendering;
    }
    if (!rendering) {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_following = Follow(g_settings, g_block);
      ForwardButtons(g_block);
    }
    input::Tick(settings.forwardFire);

    // Say when following starts and stops (a death stops it; a respawn resumes it).
    static bool wasFollowing = false;
    const bool following = g_following;
    if (following != wasFollowing) {
      log::Info(following ? "following: a unit is being moved" : "following: stopped (no live unit, or switched off)");
      wasFollowing = following;
    }

    // The key works whichever window has the keyboard: the player is in WaW.
    const bool toggleKeyDown = settings.viewToggleKey && settings.viewToggle.type &&
                               (GetAsyncKeyState(settings.viewToggleKey) & 0x8000) != 0;
    if (toggleKeyDown && !toggleKeyWasDown) ApplyToggle(settings.viewToggle);
    toggleKeyWasDown = toggleKeyDown;
    for (int i = 0; i < kAsks; ++i) {
      const bool down = settings.askKeys[i] && settings.asks[i].type &&
                        (GetAsyncKeyState(settings.askKeys[i]) & 0x8000) != 0;
      if (down && !askKeyWasDown[i]) Ask(settings, i);
      askKeyWasDown[i] = down;
    }

    state.flags = following ? kBfFollowing : 0;
    const uintptr_t positionAddr = settings.havePosition ? mem::Resolve(settings.position) : 0;
    if (positionAddr && mem::ReadFloat3(positionAddr, state.rawPosition)) {
      state.flags |= kBfPositionValid;
      const Vec3 w = BfToWaw({state.rawPosition[0], state.rawPosition[1], state.rawPosition[2]},
                             settings.mapping);
      state.positionInWaw[0] = w.x;
      state.positionInWaw[1] = w.y;
      state.positionInWaw[2] = w.z;
    }
    ++state.frame;
    shm.block()->bf.write(state);

    if (now - lastReport >= 1000) {
      lastReport = now;
      if (config.Changed()) {
        log::Info("wawbf.ini changed, reloading");
        const std::string previousPoke = settings.poke.text;
        settings = LoadSettings(config);
        if (settings.poke.type && settings.poke.text != previousPoke) ApplyPoke(settings.poke);
        probe();
        std::lock_guard<std::mutex> lock(g_mutex);
        g_settings = settings;
        for (HoldState& hold : g_holds) hold = HoldState{};
      }
      if (state.flags & kBfPositionValid) {
        log::Info("bf raw (%.2f %.2f %.2f)%s", state.rawPosition[0], state.rawPosition[1],
                  state.rawPosition[2], (state.flags & kBfFollowing) ? " following" : "");
      }
      ReportKept("facing", g_facing);
      ReportKept("pitch", g_pitch);
      ReportFov(settings, shm.block());
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_speedFrames) {
        log::Info("speed: given %.1f m/s, the unit had %.1f m/s a frame later (average of %u frames)",
                  g_speedGiven / g_speedFrames, g_speedFound / g_speedFrames, g_speedFrames);
      }
      g_speedGiven = g_speedFound = 0;
      g_speedFrames = 0;
      for (int i = 0; i < kMaxHolds; ++i) {
        HoldState& hold = g_holds[i];
        if (hold.replaced) {
          log::Info("hold%d: still there a frame later in %u of %u frames; the game last put %g in its place",
                    i + 1, hold.kept, hold.kept + hold.replaced, hold.found);
        } else if (hold.kept) {
          log::Info("hold%d: still there a frame later in all %u frames", i + 1, hold.kept);
        }
        hold.kept = hold.replaced = 0;
      }
    }

    Sleep(settings.tickMs);
  }
}

}  // namespace wawbf
