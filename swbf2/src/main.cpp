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
#include "callhook.h"
#include "input.h"
#include "log.h"
#include "memory.h"
#include "overlay.h"
#include "pad.h"
#include "shm.h"
#include "devices.h"
#include "sound.h"

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
  bool soundInBackground = true;  // [swbf2] sound_in_background: the game is heard while another window is in front
  bool devicesInBackground = false;  // [swbf2] devices_in_background: and whether it goes on reading the keyboard and controller then
  bool pointerInBackground = false;  // [swbf2] pointer_in_background: and whether it goes on putting the pointer in the middle of its window then
  bool startFromBehind = false;      // [swbf2] start_from_behind: the view is put in third person once, when the first character appears
  bool forwardFire = false;      // pull this game's trigger when the WaW player pulls theirs
  ValueSpec asks[kAsks];         // what to write to ask the mission script for each of kAskNames
  int askKeys[kAsks] = {};       // and the key that asks (a Windows virtual-key code)
  int askPads[kAsks] = {};       // and the controller button (XInput's numbers); 0 = none
  int viewTogglePad = 0;         // the same for viewToggle

  int debugAxis = -1;            // [debug] force_axis
  float debugAxisValue = 0;
  int jumpFunction = -1;         // the game's function that jumps
  int crouchFunction = -1;       // the game's function that crouches and stands the unit again (a switch)
  int sprintFunction = -1;       // and the one held to sprint
  int forwardAxis = -1;          // which of the game's stick axes is "forward" (pushed to +1); -1 = the stick is left alone
  int strafeAxis = -1;           // and which is "to the left"
  float stickFullAt = 4.8f;      // the speed, metres a second, at which the stick is pushed all the way (WaW's run)
  bool saberSprint = false;      // whether a character with a lightsaber is told to sprint when WaW's player does
  bool sprintAttack = true;      // and, when it is not, whether it is for the blow struck out of a sprint
  int sprintAttackLeadMs = 120;  // how long the sprint is held before that blow is struck
  int sprintAttackHoldMs = 250;  // and how long the blow's button is then held
  float treadmill = 0;           // [debug] treadmill: a speed the unit is given while WaW's player stands still
  ValueSpec crouched;            // the unit is crouched while this address has these bits set (u8)
  AddressSpec energy;            // the unit's energy, which sprinting and jumping spend
  bool haveEnergy = false;
  float energyFull = 100.0f;
  float characterScale = 1.0f;   // third person: how big the character is drawn; 1 = as this game makes it
  std::vector<std::pair<int, float>> characterScaleKits;  // and for particular kits
  input::Functions functions;    // which of the game's functions each WaW button turns on
  float zoomedBelow = 40.0f;     // the game counts as zoomed in when its vertical field of view is under this; 0 = not looked at
  AddressSpec kit;               // the unit's full health, which the arena's script writes the kit into
  bool haveKit = false;
  AddressSpec weapons;           // the unit's weapons: eight pointers, then the place in hand for each of the two channels
  bool haveWeapons = false;
  int weaponState = 0xB0;        // in a weapon: a number that is 0 while the weapon is idle
  ValueSpec thirdPerson;         // the view is third person while this address holds this value
  bool followCamera = false;     // in third person, draw from where WaW's camera is

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
  s.viewTogglePad = config.GetInt("swbf2", "view_toggle_pad", 0);

  if (std::sscanf(config.GetString("debug", "force_axis").c_str(), " %d %f", &s.debugAxis, &s.debugAxisValue) != 2) s.debugAxis = -1;
  s.jumpFunction = config.GetInt("swbf2", "jump_function", s.jumpFunction);
  s.crouchFunction = config.GetInt("swbf2", "crouch_function", s.crouchFunction);
  s.sprintFunction = config.GetInt("swbf2", "sprint_function", s.sprintFunction);
  s.forwardAxis = config.GetInt("swbf2", "forward_axis", s.forwardAxis);
  s.strafeAxis = config.GetInt("swbf2", "strafe_axis", s.strafeAxis);
  s.stickFullAt = std::max(0.5f, config.GetFloat("swbf2", "stick_full_at", s.stickFullAt));
  s.saberSprint = config.GetInt("swbf2", "saber_sprint", 0) != 0;
  s.sprintAttack = config.GetInt("swbf2", "sprint_attack", 1) != 0;
  s.sprintAttackLeadMs = std::max(0, std::min(1000, config.GetInt("swbf2", "sprint_attack_lead_ms", s.sprintAttackLeadMs)));
  s.sprintAttackHoldMs = std::max(50, std::min(1000, config.GetInt("swbf2", "sprint_attack_hold_ms", s.sprintAttackHoldMs)));
  s.treadmill = std::min(30.0f, std::max(0.0f, config.GetFloat("debug", "treadmill", 0.0f)));
  ParseValueSpec("[swbf2] unit_crouched", config.GetString("swbf2", "unit_crouched"), s.crouched);
  s.haveEnergy = config.GetAddress("swbf2", "unit_energy", s.energy);
  s.energyFull = config.GetFloat("swbf2", "unit_energy_full", s.energyFull);
  s.characterScale = std::min(4.0f, std::max(0.25f, config.GetFloat("swbf2", "character_scale", 1.0f)));
  // "10 = 1.2, 12 = 0.9": a kit, and the scale for it
  const std::string byKit = config.GetString("swbf2", "character_scale_kits");
  for (const char* p = byKit.c_str(); *p;) {
    int kit = 0, used = 0;
    float scale = 0;
    if (std::sscanf(p, " %d = %f%n", &kit, &scale, &used) == 2 && scale >= 0.25f && scale <= 4.0f) {
      s.characterScaleKits.emplace_back(kit, scale);
      p += used;
    }
    while (*p && *p != ',') ++p;
    if (*p == ',') ++p;
  }
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
    s.askPads[i] = config.GetInt("swbf2", (std::string(kAskNames[i]) + "_pad").c_str(), 0);
    ParseValueSpec(kAskNames[i], config.GetString("swbf2", kAskNames[i]), s.asks[i]);
  }
  s.keepRunning = config.GetInt("swbf2", "keep_running", 0) != 0;
  s.hidden = config.GetInt("swbf2", "hidden", 0) != 0;
  s.soundInBackground = config.GetInt("swbf2", "sound_in_background", 1) != 0;
  s.devicesInBackground = config.GetInt("swbf2", "devices_in_background", 0) != 0;
  s.pointerInBackground = config.GetInt("swbf2", "pointer_in_background", 0) != 0;
  s.startFromBehind = config.GetInt("swbf2", "start_from_behind", 0) != 0;
  s.forwardFire = config.GetInt("swbf2", "forward_fire", 0) != 0;
  s.functions.fire = config.GetInt("swbf2", "fire_function", s.functions.fire);
  s.functions.aim = config.GetInt("swbf2", "aim_function", s.functions.aim);
  s.zoomedBelow = config.GetFloat("swbf2", "zoomed_below_fov", s.zoomedBelow);
  s.functions.reload = config.GetInt("swbf2", "reload_function", s.functions.reload);
  s.functions.ability = config.GetInt("swbf2", "ability_function", s.functions.ability);
  s.functions.meleeAbility = config.GetInt("swbf2", "melee_ability_function", s.functions.meleeAbility);
  s.functions.nextAbility = config.GetInt("swbf2", "next_ability_function", s.functions.nextAbility);
  s.functions.nextWeapon = config.GetInt("swbf2", "next_weapon_function", s.functions.nextWeapon);
  input::SetFunctions(s.functions);
  s.haveViewProjection = config.GetAddress("swbf2", "view_projection", s.viewProjection);
  s.haveKit = config.GetAddress("swbf2", "unit_kit", s.kit);
  s.haveWeapons = config.GetAddress("swbf2", "unit_weapons", s.weapons);
  s.weaponState = config.GetInt("swbf2", "weapon_state_offset", s.weaponState);
  ParseValueSpec("[swbf2] third_person", config.GetString("swbf2", "third_person"), s.thirdPerson);
  s.followCamera = config.GetInt("swbf2", "follow_camera", 0) != 0;

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
//
// Not while an ability is being used, though. This game adds the thrower's
// speed to whatever is thrown or launched, and WaW does not: a grenade thrown
// on the run left the hand going sideways here and straight ahead there. So
// for as long as the ability is in use, and a moment after, the unit is given
// no speed at all. (The bridge thread says when: g_noSpeedUntil.)
std::atomic<DWORD> g_noSpeedUntil{0};


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
  const bool still = static_cast<int32_t>(GetTickCount() - g_noSpeedUntil.load(std::memory_order_relaxed)) < 0;
  if (s.followVelocity && !still) want = WawVelocityToBf({pose.velocity[0], pose.velocity[1], pose.velocity[2]}, s.mapping);
  const float facing = WawYawToBf(pose.yaw, s.mapping) * 3.14159265f / 180.0f;
  const float fx = std::cos(facing), fz = s.mapping.zSign * std::sin(facing);
  // [debug] treadmill = <metres a second>: with WaW's player standing still,
  // the unit is told it is going forwards at that speed, and runs on the
  // spot. For looking at its legs with nobody playing.
  if (s.treadmill > 0 && s.followVelocity && !still && want.x * want.x + want.z * want.z < 0.01f) {
    want.x = fx * s.treadmill;
    want.z = fz * s.treadmill;
  }
  velocity[0] = want.x;
  velocity[2] = want.z;
  if (s.followHeight) velocity[1] = want.y;
  g_haveLastSpeed = mem::WriteFloat3(velocityAddr, velocity);
  g_lastSpeed = std::sqrt(want.x * want.x + want.z * want.z);

  // And the stick. The unit goes where it is put, whatever the stick says,
  // but the game chooses how the character moves its legs from the stick:
  // forwards, backwards or sideways, and it will not break into a sprint
  // without "forward". So the stick is pushed the way WaW's player is really
  // going, as far as their speed against a run.
  if (s.forwardAxis >= 0 || s.strafeAxis >= 0) {
    const auto push = [&s](float speed) {
      const float part = std::min(1.0f, std::max(-1.0f, speed / s.stickFullAt));
      return std::fabs(part) < 0.1f ? 0.0f : part;
    };
    input::SetAxis(s.forwardAxis, still ? 0.0f : push(want.x * fx + want.z * fz));
    input::SetAxis(s.strafeAxis, still ? 0.0f : push(want.z * fx - want.x * fz));
  }
}

void NoteWawCamera(const Settings& s, const WawPlayerState& waw);  // with the camera, below

// Puts the unit where the WaW player is. Call with g_mutex held.
bool Follow(const Settings& s, SharedBlock* block) {
  if (!s.follow || !s.havePosition || !block || !WawAlive(block)) return false;
  const uintptr_t positionAddr = mem::Resolve(s.position);
  if (!IsUnit(s, positionAddr)) return false;
  WawPlayerState waw{};
  if (!block->waw.read(waw) || !(waw.flags & kWawOriginValid)) return false;

  WawPose pose;
  WawNow(s, waw, pose);
  NoteWawCamera(s, waw);
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

// ---------------------------------------------------------------------------
// The camera, in third person.
//
// In third person both games draw the player from behind, and the two
// pictures only fit if both draw from the same place. WaW's camera cannot be
// told where to go: it backs off behind the player until a wall is in the
// way, and only WaW knows where its walls are. So WaW's is the camera, and
// this game is given it.
//
// The game keeps a camera as an object: four rows of four floats at 0x30 that
// say where it is and how it is turned (which way is right, up and back, then
// the position), and at 0x70 the same thing inverted, which is what drawing
// uses. Its renderer has one routine that readies a camera for drawing, run
// for each part of the frame, and just before that routine reads the camera
// it makes a call (to set the world transform). That call is sent through
// OnCameraSetup first (callhook.h), which is the moment the camera can be
// replaced: after the game has put its own there, before anything is drawn
// with it.
//
// What is taken from WaW is where its camera is relative to its player, not
// where it is: the unit here stands on this game's floor at this game's
// height, and the camera has to be behind that.
// ---------------------------------------------------------------------------
// Where things are in BattlefrontII.exe (the Steam build), as offsets from
// where it is loaded. docs/PHASE2.md says how they were found.
const uintptr_t kCameraSetupCall = 0x2B77A0;                                   // the call in the routine that readies a camera
const unsigned char kCameraSetupCallBytes[] = {0xE8, 0x1B, 0xC7, 0xFF, 0xFF};  // call BattlefrontII.exe+0x2B3EC0
const uintptr_t kCameraInUse = 0x3F58E0;   // pointer to the camera that routine is readying
const size_t kCameraPlacement = 0x30;      // right, up, back, position: 16 floats
const size_t kCameraPosition = 0x60;
const size_t kCameraLens = 0x138;          // two floats: the tangents of half the view across and top to bottom
const size_t kCameraZoom = 0x140;          // what the game divides those by: 1, or more while it is zoomed in
const float kPlayersOwnCamera = 30.0f;     // metres: a camera further than this from the unit is not the player's (the HUD's sits at the origin)
const float kBehindThePlayer = 0.6f;       // metres from WaW's player to its camera before WaW counts as drawing from behind

struct WawCamera {
  bool valid = false;
  Vec3 offset{};   // from the unit's feet to the camera, in this game's space and units
  Vec3 forward{};  // unit length
  Vec3 up{};
  float tanHalfFov[2] = {0, 0};  // WaW's lens, or zeros if it is not known
};
WawCamera g_wawCamera;                     // guarded by g_mutex
bool g_thirdPerson = false;                // guarded by g_mutex: the game's view is third person

std::atomic<uint32_t> g_camerasReplaced{0};
// How big the character is drawn in third person, 1 being as this game makes
// it. This game's soldiers stand a good deal taller than WaW's zombies. The
// character cannot be made smaller, but the camera can be put further from
// it: every part of the picture then shrinks towards the character's feet,
// which stay exactly where WaW's player stands.
std::atomic<float> g_characterScale{1.0f};
float g_gameZoom = 0;                      // guarded by g_mutex: the player's camera's own zoom, as last readied; 0 = not seen
std::atomic<bool> g_logTransformCallers{false};  // [debug] transform_callers

Vec3 Cross(const Vec3& a, const Vec3& b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
float Dot(const Vec3& a, const Vec3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
bool Normalise(Vec3& v) {
  const float length = std::sqrt(Dot(v, v));
  if (length < 1e-4f) return false;
  v = {v.x / length, v.y / length, v.z / length};
  return true;
}

// Which kit the character in play carries, or 0 if that cannot be told.
//
// The arena's mission script knows which class it put the player in the
// world as, and this bridge cannot ask it. So the script writes the answer
// where the bridge can read it: the unit's full health, which it sets to
// 1e37 * (1 + what it says / 65536). (The unit cannot be hurt; its health
// means nothing else.) swbf2/arena/WAW_arena.lua has the other end.
//
// Three things about the character come with the kit, as numbers added to it.
const uint32_t kKitNumber = 31;  // the kit itself is what is left under these
const uint32_t kKitHero = 32;    // a hero or a villain: always shown from behind
const uint32_t kKitMelee = 64;   // fights with a lightsaber
const uint32_t kKitWho = 128;    // and above those, who it is: a number from that script's list (several share a kit)
std::atomic<bool> g_melee{false};
std::atomic<int> g_dashFire{0};  // a blow struck out of a sprint: -1 kept back for now, 1 being struck, 0 as WaW has the button
std::atomic<bool> g_crosshairKept{false};  // the middle of the HUD, where the crosshair is, is part of the picture sent to WaW

uint32_t Kit(const Settings& s) {
  if (!s.haveKit || !s.havePosition || !IsUnit(s, mem::Resolve(s.position))) return 0;
  float full = 0;
  const uintptr_t address = mem::Resolve(s.kit);
  if (!address || !mem::Read(address, &full, sizeof(full))) return 0;
  const float over = full / 1e37f - 1.0f;
  if (!(over > -0.00001f && over < 0.25f)) return 0;  // not a health this arena set
  return static_cast<uint32_t>(over * 65536.0f + 0.5f);
}

// Whether the game's view is third person.
bool ThirdPerson(const Settings& s) {
  double now = 0;
  const uintptr_t address = s.thirdPerson.type ? mem::Resolve(s.thirdPerson.address) : 0;
  return address && ReadValue(s.thirdPerson, address, now) && SameValue(s.thirdPerson, now, s.thirdPerson.value);
}

// Takes WaW's camera from the sample the unit was just placed from. Call
// with g_mutex held.
void NoteWawCamera(const Settings& s, const WawPlayerState& waw) {
  WawCamera camera;
  if ((waw.flags & kWawCameraValid) && (waw.flags & kWawOriginValid)) {
    const Vec3 away{waw.cameraOrigin[0] - waw.origin[0], waw.cameraOrigin[1] - waw.origin[1],
                    waw.cameraOrigin[2] - waw.origin[2]};
    const Vec3 offset = WawDirectionToBf(away, s.mapping);
    camera.offset = {offset.x * s.mapping.scale, offset.y * s.mapping.scale, offset.z * s.mapping.scale};
    camera.forward = WawDirectionToBf({waw.cameraForward[0], waw.cameraForward[1], waw.cameraForward[2]}, s.mapping);
    camera.up = WawDirectionToBf({waw.cameraUp[0], waw.cameraUp[1], waw.cameraUp[2]}, s.mapping);
    // WaW's eyes are 60 of its units up. A camera still about there is WaW
    // drawing from the eyes: nothing to draw a character from.
    if (waw.flags & kWawFovValid) {
      camera.tanHalfFov[0] = waw.tanHalfFov[0];
      camera.tanHalfFov[1] = waw.tanHalfFov[1];
    }
    const Vec3 fromEyes{away.x, away.y, away.z - 60.0f};
    camera.valid = Normalise(camera.forward) && Normalise(camera.up) &&
                   std::sqrt(Dot(fromEyes, fromEyes)) * s.mapping.scale > kBehindThePlayer;
  }
  g_wawCamera = camera;
}

// [debug] transform_callers: says where in the game each kind of transform is
// set from, the first time each place is seen (the frame probe passes every
// SetTransform on). It is how the camera routine was found not to set its
// transforms itself: they all come from one place, a wrapper.
void OnTransform(unsigned state, void* caller) {
  if (g_logTransformCallers.load(std::memory_order_relaxed)) {
    static uintptr_t seen[24];
    static unsigned seenState[24];
    static int count = 0;
    // Only the game's own calls: Direct3D sets every transform itself when a
    // device is made. The exe is well under 32 MB.
    const uintptr_t from = reinterpret_cast<uintptr_t>(caller);
    const uintptr_t offset = from - reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    bool known = offset >= 0x2000000;
    for (int i = 0; i < count; ++i) known = known || (seen[i] == from && seenState[i] == state);
    if (!known && count < 24) {
      seen[count] = from;
      seenState[count++] = state;
      log::Info("[debug] transform_callers: transform %u set from BattlefrontII.exe+0x%X", state,
                static_cast<unsigned>(offset));
    }
  }
}

// Runs on the game's own thread, in the routine that readies a camera, once
// for each part of the frame: see above.
void __cdecl OnCameraSetup(void*) {
  std::lock_guard<std::mutex> lock(g_mutex);
  const Settings& s = g_settings;
  if (!s.followCamera || !g_thirdPerson || !g_wawCamera.valid || !g_following) return;
  const uintptr_t base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  uint32_t camera = 0;
  const uintptr_t positionAddr = mem::Resolve(s.position);
  float unit[3], was[3];
  if (!mem::Read(base + kCameraInUse, &camera, sizeof(camera)) || !camera || !IsUnit(s, positionAddr) ||
      !mem::ReadFloat3(positionAddr, unit) || !mem::ReadFloat3(camera + kCameraPosition, was)) {
    return;
  }
  const Vec3 apart{was[0] - unit[0], was[1] - unit[1], was[2] - unit[2]};
  if (Dot(apart, apart) > kPlayersOwnCamera * kPlayersOwnCamera) return;

  const Vec3 forward = g_wawCamera.forward;
  Vec3 right = Cross(forward, g_wawCamera.up);
  if (!Normalise(right)) return;
  const Vec3 up = Cross(right, forward);
  const Vec3 back{-forward.x, -forward.y, -forward.z};
  const float further = 1.0f / g_characterScale.load(std::memory_order_relaxed);
  const Vec3 at{unit[0] + g_wawCamera.offset.x * further, unit[1] + g_wawCamera.offset.y * further,
                unit[2] + g_wawCamera.offset.z * further};
  const float placement[32] = {
      right.x, right.y, right.z, 0, up.x,    up.y,    up.z,    0,
      back.x,  back.y,  back.z,  0, at.x,    at.y,    at.z,    1,
      // and inverted: the same turn the other way, then the position brought back
      right.x, up.x,    back.x,  0, right.y, up.y,    back.y,  0,
      right.z, up.z,    back.z,  0, -Dot(at, right), -Dot(at, up), -Dot(at, back), 1,
  };
  if (mem::Write(camera + kCameraPlacement, placement, sizeof(placement))) ++g_camerasReplaced;

  // And WaW's lens, so that the character stays the size WaW's view of the
  // room makes it when WaW narrows its view to aim. The game's own zoom is
  // left where it is and allowed for (TellZoom looks at it): what is drawn
  // with is the lens divided by the zoom.
  float zoom = 1.0f;
  if (mem::Read(camera + kCameraZoom, &zoom, sizeof(zoom)) && zoom > 0.1f && zoom < 100.0f) {
    g_gameZoom = zoom;
    if (g_wawCamera.tanHalfFov[0] > 0.05f && g_wawCamera.tanHalfFov[1] > 0.05f) {
      const float lens[2] = {g_wawCamera.tanHalfFov[0] * zoom, g_wawCamera.tanHalfFov[1] * zoom};
      mem::Write(camera + kCameraLens, lens, sizeof(lens));
    }
  }
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
DWORD g_changingSince = 0;  // the bridge thread's: when a change of character was asked for; 0 = none is under way

void Ask(const Settings& s, int which) {
  const ValueSpec& ask = s.asks[which];
  if (!s.havePosition || !IsUnit(s, mem::Resolve(s.position))) {
    log::Info("%s: there is no unit to ask through", kAskNames[which]);
    return;
  }
  const uintptr_t address = mem::Resolve(ask.address);
  if (address && WriteValue(ask, address, ask.value)) {
    log::Info("%s: asked", kAskNames[which]);
    g_changingSince = GetTickCount() | 1;
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
    // WaW counts the ammunition: a weapon that is empty there does not fire
    // here either.
    if (waw.flags & kWawDry) buttons &= ~kWawButtonFire;
    // With a lightsaber there is nothing to aim, and the button that aims for
    // everyone else (right click, the left trigger) works the Force, as it
    // does in this game played by itself.
    if (g_melee.load(std::memory_order_relaxed)) {
      if (buttons & kWawButtonAim) buttons |= kWawButtonAbility;
      buttons &= ~static_cast<uint32_t>(kWawButtonAim);
    }
    // A blow struck out of a sprint: kept back while the character is put
    // into its sprint, then struck (the bridge's main loop says which).
    const int dash = g_dashFire.load(std::memory_order_relaxed);
    if (dash < 0) buttons &= ~static_cast<uint32_t>(kWawButtonFire);
    if (dash > 0) buttons |= kWawButtonFire;
    // And WaW's scripts say when there is an ability to use: a grenade or a
    // rocket left.
    if (!(waw.flags & kWawAbilityReady)) buttons &= ~kWawButtonAbility;
  }
  input::SetButtons(buttons);
}

// Puts the game's view behind the character if it is not there.
void ShowFromBehind(const Settings& s, const char* why = "a lightsaber is shown from behind") {
  const uintptr_t address = s.thirdPerson.type ? mem::Resolve(s.thirdPerson.address) : 0;
  double now = 0;
  if (!address || !ReadValue(s.thirdPerson, address, now) || SameValue(s.thirdPerson, now, s.thirdPerson.value)) return;
  if (WriteValue(s.thirdPerson, address, s.thirdPerson.value)) log::Info("view: %s; changed to third person", why);
}

// What the unit has in hand: the place, among its weapons, of the weapon and
// of the ability, and whether the ability is in use this moment.
struct InHand {
  bool known = false;
  uint32_t weapon = 0;
  uint32_t ability = 0;   // 0: none (place 0 is always a weapon)
  uintptr_t weaponAt = 0, abilityAt = 0;
  bool weaponInUse = false, abilityInUse = false;
  bool weaponCharging = false;  // held, building up to its shot (the bowcaster)
  float chargeFull = 0;         // seconds it takes to charge all the way
  uintptr_t clipAt = 0;         // where the weapon's magazine is kept: a float, the part of it that is left
};

// In a weapon (the Steam build; found with tools/probe/bfweapons.ps1):
const size_t kWeaponCounter = 0x88;     // pointer to its count of ammunition
const size_t kCounterClip = 0x10;       // in that: the part of the magazine left, 0 to 1
const size_t kWeaponTimer = 0xB8;       // while charging: how long a full charge takes, seconds
const uint32_t kWeaponFiring = 1;       // its state while a shot or a swing is under way
const uint32_t kWeaponCharging = 3;     // and while it is held, charging

InHand ReadInHand(const Settings& s) {
  InHand hand;
  if (!s.haveWeapons || !s.havePosition || !IsUnit(s, mem::Resolve(s.position))) return hand;
  const uintptr_t table = mem::Resolve(s.weapons);
  uint32_t weapons[8];
  uint8_t places[2];
  if (!table || !mem::Read(table, weapons, sizeof(weapons)) || !mem::Read(table + sizeof(weapons), places, sizeof(places))) return hand;
  hand.known = true;
  hand.weapon = places[0];
  uint32_t state = 0;
  if (places[0] < 8 && weapons[places[0]]) {
    hand.weaponAt = weapons[places[0]];
    // 1 is the shot or the swing itself; a lightsaber then spends longer in
    // 5, recovering, and that is not a time for it to cut anything.
    const bool read = mem::Read(hand.weaponAt + s.weaponState, &state, sizeof(state));
    hand.weaponInUse = read && state == kWeaponFiring;
    hand.weaponCharging = read && state == kWeaponCharging;
    if (hand.weaponCharging) mem::Read(hand.weaponAt + kWeaponTimer, &hand.chargeFull, sizeof(hand.chargeFull));
    uint32_t counter = 0;
    if (mem::Read(hand.weaponAt + kWeaponCounter, &counter, sizeof(counter)) && counter > 0x10000) hand.clipAt = counter + kCounterClip;
  }
  if (places[1] < 8 && places[1] != places[0] && weapons[places[1]]) {
    hand.ability = places[1];
    hand.abilityAt = weapons[places[1]];
    state = 0;
    hand.abilityInUse = mem::Read(hand.abilityAt + s.weaponState, &state, sizeof(state)) && state != 0;
  }
  return hand;
}

// Keeps this game's weapon the one WaW's player has in hand: WaW's own
// "change weapon" is what the player presses, and its scripts say which
// weapon that left them holding. "Next weapon" is pressed here until the two
// agree, a few times at most (a character with one weapon has nothing to
// change to).
void MatchWeapon(const SharedBlock* block, const InHand& hand) {
  static uint32_t lastWanted = 0;
  static int tries = 0;
  static DWORD lastPress = 0;
  WawPlayerState waw{};
  if (!hand.known || !block->waw.read(waw) || !waw.weapon) return;
  const uint32_t wanted = waw.weapon - 1;
  if (wanted != lastWanted) {
    lastWanted = wanted;
    tries = 0;
  }
  const DWORD now = GetTickCount();
  if (hand.weapon == wanted || tries >= 4 || now - lastPress < 700) return;
  lastPress = now;
  ++tries;
  input::PressNextWeapon();
  log::Info("weapon: WaW's player has weapon %u in hand and this game's unit weapon %u: pressing next weapon", wanted + 1, hand.weapon + 1);
}

// Tells the input hooks whether the game is zoomed in, which they need for
// working its zoom from WaW's aim. Read off the field of view the game is
// drawing with: zooming is the one thing that narrows it. An answer has to
// stand for a few frames before it is passed on, so that one odd frame does
// not press a button.
void TellZoom(const Settings& s) {
  static int last = -1, same = 0, told = -1;
  const float fov = s.zoomedBelow > 0 ? OwnFovDegrees(s) : 0;
  int zoomed = fov > 0 ? (fov < s.zoomedBelow ? 1 : 0) : -1;
  // While the camera is being given WaW's lens the field of view says
  // nothing about this game's zoom; the camera's own zoom factor does.
  if (g_gameZoom > 0) zoomed = g_gameZoom > 1.2f ? 1 : 0;
  // What is left of the HUD. The weapons, except zoomed in, when the game
  // draws something else where they were. And the middle of the picture, for
  // a character with something to aim: this game's crosshair, with the ring
  // round it that shows a weapon heating up. (WaW's own crosshair is switched
  // off meanwhile, by its bridge.) A character with a lightsaber has neither.
  frameprobe::SetHudShown(zoomed != 1, !g_melee.load(std::memory_order_relaxed));
  same = zoomed == last ? same + 1 : 0;
  last = zoomed;
  if (same < 3 || zoomed == told) return;
  told = zoomed;
  input::SetZoomed(zoomed);
}

// The camera routine's call is redirected from here, the game's own thread:
// the four bytes changed do not sit on a four-byte boundary, so it must not
// be done while that thread could be making the call. Call with g_mutex held.
void HookCamera(const Settings& s) {
  static bool tried = false;
  if (tried || !s.followCamera) return;
  tried = true;
  const uintptr_t base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  if (callhook::Install(base + kCameraSetupCall, kCameraSetupCallBytes, &OnCameraSetup)) {
    log::Info("camera: hooked the routine that readies it at BattlefrontII.exe+0x%X", static_cast<unsigned>(kCameraSetupCall));
  } else {
    log::Error("camera: the routine that readies it could not be hooked (not the BattlefrontII.exe this was written for?); third person keeps this game's own camera");
  }
}

// ---------------------------------------------------------------------------
// The thrown grenade
//
// Two games throw a grenade when the player throws one. WaW's is the real
// one: it bounces off WaW's walls and floors, and its burst is what hurts.
// This game's would fly through its own empty arena and come down somewhere
// else. What is wanted of this game is the character throwing, not the
// grenade (the user, 2026-10-09: "just have the BF animation, but throw the
// grenade in WaW, no BF grenade is visible"). So the moment this game's
// grenade leaves the hand it is put far below the floor and its fuse run
// out, where nothing sees or hears it.
//
// (What was built first carried this game's grenade along WaW's instead,
// putting it every frame where WaW's was and setting it off when WaW's went.
// It worked as far as it was tried, which was not with a real throw; the
// layout below is what it needs, if it is ever wanted back.)
//
// The grenade in flight is its own object (Steam build; found with
// tools/probe/bfflying.ps1, docs/PHASE3.md has the layout). Nothing points
// at it from the unit or the weapon, so it is looked for once, at the moment
// the weapon lets go of it: the object whose first word is the grenade
// class's and whose owner is the player's unit. The game keeps such things
// in pools near each other, so the search is of the memory around the unit.
// ---------------------------------------------------------------------------
const uintptr_t kThrownClass = 0x3AD0F4;  // what a thrown grenade's first word points at, from where the exe is loaded (as unit_type is)
const size_t kThrownFlags = 0x38;         // 1 in flight, 0x101 once it has come to rest
const size_t kThrownFuse = 0x3C;          // seconds left, counted down only once it is at rest (0.6 to begin with)
const size_t kThrownAge = 0x40;           // seconds since it was thrown
const size_t kThrownPosition = 0x48;      // three floats; kThrownCopy and kThrownWas are the same a frame apart
const size_t kThrownOwner = 0x54;         // the unit that threw it
const size_t kThrownCopy = 0xC8;
const size_t kThrownWas = 0xF0;
const size_t kThrownSpeed = 0xFC;         // three floats, metres per second
const size_t kThrownGravity = 0x12C;      // metres per second per second, negative; 0 at rest
const size_t kThrownSize = 0x140;
const uint32_t kThrownAtRest = 0x101;

// What a search came across, for the log when it finds nothing.
struct ThrownSeen {
  int count = 0;          // objects of the grenade's class
  uintptr_t owner = 0;    // the last one's owner
  float age = 0;          // and age
};

uintptr_t ScanForThrown(uintptr_t from, uintptr_t to, uintptr_t wanted, uintptr_t owner, ThrownSeen* seen) {
  __try {
    for (uintptr_t at = (from + 3) & ~static_cast<uintptr_t>(3); at + kThrownSize <= to; at += 4) {
      if (*reinterpret_cast<const uint32_t*>(at) != wanted) continue;
      ++seen->count;
      seen->owner = *reinterpret_cast<const uint32_t*>(at + kThrownOwner);
      seen->age = *reinterpret_cast<const float*>(at + kThrownAge);
      if (seen->owner == owner && seen->age >= 0.0f && seen->age < 1.0f) return at;
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
  }
  return 0;
}

// Looks through the memory within `reach` of `middle`. Around the unit, 32 MB
// either way takes some 20 ms; around where the last one was, a megabyte
// takes under one.
uintptr_t FindThrown(uintptr_t unit, uintptr_t middle, uintptr_t reach, ThrownSeen* seen) {
  const uintptr_t wanted = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + kThrownClass;
  uintptr_t at = middle > reach + 0x10000 ? middle - reach : 0x10000;
  const uintptr_t end = middle + reach;
  while (at < end) {
    MEMORY_BASIC_INFORMATION info{};
    if (!VirtualQuery(reinterpret_cast<void*>(at), &info, sizeof(info))) break;
    const uintptr_t from = reinterpret_cast<uintptr_t>(info.BaseAddress), size = info.RegionSize;
    if (info.State == MEM_COMMIT && (info.Protect & (PAGE_READWRITE | PAGE_EXECUTE_READWRITE)) && !(info.Protect & PAGE_GUARD)) {
      const uintptr_t found = ScanForThrown(std::max(from, at), std::min(from + size, end), wanted, unit, seen);
      if (found) return found;
    }
    if (from + size <= at) break;
    at = from + size;
  }
  return 0;
}

DWORD g_seekThrownFrom = 0;            // an ability was used then, and what it threw is being looked for; 0 = no (the game thread's, like the rest)
int g_seekThrownLooks = 0;             // how many wide searches that has had
bool g_abilityWasInUse = false;
uintptr_t g_thrownLastAt = 0;          // where the last one was found: the next is usually the same place or beside it
// An ability that was used and threw nothing (a rocket, the Force), as whose
// it is and which of theirs: not looked for again. (It was first kept as
// where the ability's weapon is in memory. A new character's weapons are put
// where the last one's were, so a Jedi's Force push, which throws nothing,
// kept the grenade of whoever was played next from being looked for: the
// user saw the troopers' grenades in flight and nobody else's.)
uint32_t g_nothingThrownBy = 0;
uint32_t g_seekThrownBy = 0;           // whose ability is being looked for now, kept the same way
uint32_t g_foundNothingBy = 0;         // and whose the last search to find nothing was: it takes two running to give one up

// Call with g_mutex held, once a frame, from the game's own thread.
void PutGrenadeAway(const Settings& s) {
  const uintptr_t positionAddr = s.havePosition ? mem::Resolve(s.position) : 0;
  if (!positionAddr || !IsUnit(s, positionAddr)) {
    g_seekThrownFrom = 0;
    g_abilityWasInUse = false;
    return;
  }
  const uintptr_t unit = positionAddr - static_cast<uintptr_t>(s.unitPositionOffset);
  const DWORD now = GetTickCount();

  // An ability has just been used. If it is a grenade, it leaves the hand
  // about half a second later, and is then looked for: every frame around
  // where the last one was, which costs nothing, and a few times, spaced out,
  // through everything near the unit, which costs a frame of this game's each
  // time. An ability that turns out to throw nothing is not looked for again.
  const InHand hand = ReadInHand(s);
  const uint32_t ability = (Kit(s) << 4) | (hand.ability & 15) | 0x80000000u;  // whose, and which of theirs
  if (hand.abilityInUse && !g_abilityWasInUse && ability != g_nothingThrownBy) {
    g_seekThrownFrom = now | 1;
    g_seekThrownLooks = 0;
    g_seekThrownBy = ability;
  }
  g_abilityWasInUse = hand.abilityInUse;
  if (!g_seekThrownFrom) return;

  const int32_t waited = static_cast<int32_t>(now - g_seekThrownFrom);
  ThrownSeen seen;
  uintptr_t found = g_thrownLastAt ? FindThrown(unit, g_thrownLastAt, 1u << 20, &seen) : 0;
  if (!found && waited >= 400 + 120 * g_seekThrownLooks) {
    ++g_seekThrownLooks;
    found = FindThrown(unit, unit, 32u << 20, &seen);
  }
  if (found) {
    g_thrownLastAt = found;
    g_seekThrownFrom = 0;
    // Far below the floor, still, weightless, at rest and its fuse all but
    // run out: it bursts there on the game's next turn.
    float at[3] = {0, 0, 0};
    mem::ReadFloat3(positionAddr, at);
    at[1] -= 1000.0f;
    const float none[3] = {0, 0, 0};
    const float weightless = 0.0f, fuse = 0.01f;
    mem::Write(found + kThrownPosition, at, sizeof(at));
    mem::Write(found + kThrownCopy, at, sizeof(at));
    mem::Write(found + kThrownWas, at, sizeof(at));
    mem::Write(found + kThrownSpeed, none, sizeof(none));
    mem::Write(found + kThrownGravity, &weightless, sizeof(weightless));
    mem::Write(found + kThrownFlags, &kThrownAtRest, sizeof(kThrownAtRest));
    mem::Write(found + kThrownFuse, &fuse, sizeof(fuse));
    g_foundNothingBy = 0;
    log::Info("grenade: this game's has left the hand (0x%p, %ld ms after the throw began) and is put out of sight", reinterpret_cast<void*>(found),
              static_cast<long>(waited));
  } else if (g_seekThrownLooks >= 6) {
    g_seekThrownFrom = 0;
    if (g_foundNothingBy == g_seekThrownBy) g_nothingThrownBy = g_seekThrownBy;
    g_foundNothingBy = g_seekThrownBy;
    log::Info("grenade: nothing of the kind was thrown by that ability (%d of the kind were there; the last one's owner 0x%p, this unit 0x%p, its age %.2f s)",
              seen.count, reinterpret_cast<void*>(seen.owner), reinterpret_cast<void*>(unit), seen.age);
  }
}
void BridgeFrame() {
  ++g_frames;
  std::lock_guard<std::mutex> lock(g_mutex);
  HookCamera(g_settings);
  g_following = Follow(g_settings, g_block);
  PutGrenadeAway(g_settings);
  // The unit stands on the arena's floor and is only ever moved across it.
  // If it is found well below (it has happened: a class setting that upset
  // how units stand, and every one of them dropped through), it is put back,
  // rather than left to fall for good with the player's character gone from
  // the picture.
  if (g_following && g_settings.havePosition && !g_settings.followHeight) {
    const uintptr_t positionAt = mem::Resolve(g_settings.position);
    float at[3];
    if (positionAt && IsUnit(g_settings, positionAt) && mem::ReadFloat3(positionAt, at) && at[1] < g_settings.mapping.anchorBf.y - 4.0f) {
      static DWORD lastSaid = 0;
      const DWORD now = GetTickCount();
      if (now - lastSaid > 5000) {
        lastSaid = now;
        log::Info("the unit was %.1f m below the floor; put back on it", g_settings.mapping.anchorBf.y - at[1]);
      }
      at[1] = g_settings.mapping.anchorBf.y + 0.3f;
      mem::WriteFloat3(positionAt, at);
      const uintptr_t velocityAt = g_settings.haveVelocity ? mem::Resolve(g_settings.velocity) : 0;
      float speed[3];
      if (velocityAt && mem::ReadFloat3(velocityAt, speed)) {
        speed[1] = 0;
        mem::WriteFloat3(velocityAt, speed);
      }
    }
  }
  // WaW decides how long the player can sprint. This game's own count of
  // that (its energy, which sprinting spends) is kept full, so the character
  // never drops out of a sprint WaW's player is still in.
  if (g_following && g_settings.haveEnergy) {
    const uintptr_t energyAt = mem::Resolve(g_settings.energy);
    float energy = 0;
    if (energyAt && mem::Read(energyAt, &energy, sizeof(energy)) && energy >= 0.0f && energy < g_settings.energyFull) {
      mem::Write(energyAt, &g_settings.energyFull, sizeof(g_settings.energyFull));
    }
  }
  Hold(g_settings);
  ForwardButtons(g_block);
  TellZoom(g_settings);
  g_gameZoom = 0;  // the frame is over; the next one's camera says again
}

const session::Game& BridgeGame() { return session::kBf; }

// The arena's add-on is in the game's folder whatever the game is started
// for, and the game runs its script (swbf2/arena/addme.lua) every time. That
// script goes straight into the arena only if it finds this file, which is
// there for exactly as long as a game the launcher started is running: made
// here, before the game has read anything, and taken away by the next start
// that is not the launcher's. Started by itself, the game comes up at its
// own menus as it always did, with the arena as one more map in its list.
void BridgeLoaded(HMODULE self, bool live) {
  const std::wstring flag = ModuleDir(self) + L"addon\\WAW\\wawbf_start.txt";
  if (!live) {
    DeleteFileW(flag.c_str());
    return;
  }
  const HANDLE file = CreateFileW(flag.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
}

void BridgeMain(HMODULE self) {
  const std::wstring dir = ModuleDir(self);
  log::Init(dir + L"wawbf_swbf2.log");
  log::Info("SWBF2 bridge loaded (pid %lu)", GetCurrentProcessId());
  crashlog::Install();

  Config config(dir + L"wawbf.ini");
  Settings settings = LoadSettings(config);
  // Before the game starts its own sound up: only sounds made after this play in the background.
  if (settings.soundInBackground) sound::KeepPlaying();
  // And the player's keyboard and controller, which are World at War's while
  // that is the window in front, are not this game's to act on as well.
  if (!settings.devicesInBackground) devices::QuietInBackground();
  // Nor is the pointer, nor the screen: before the game makes its window.
  focus::Start(settings.hidden, settings.pointerInBackground);
  config.Changed();  // the load above is current; only later saves count
  // The picture for WaW (Phase 2), and the probe's own experiments. Publishing
  // needs the frame cut at the depth clear that comes before the first-person
  // weapon: the second depth-only clear of the frame.
  const auto probe = [&] {
    const bool publish = config.GetInt("overlay", "publish", 0) != 0;
    // cut = 0 is for an arena that draws nothing but the player, which is
    // what swbf2/arena builds: the whole frame is the picture, and only its
    // black background has to go. A number is for a world with a ground and
    // a sky in it: the picture is cut at that depth-only clear instead.
    const int cut = config.GetInt("overlay", "cut", 0);
    frameprobe::Request(dir, config.GetString("debug", "frame_dump"));
    frameprobe::SetCut(publish ? cut : config.GetInt("debug", "frame_cut", 0),
                       publish ? 0 : std::strtoul(config.GetString("debug", "frame_cut_colour", "0").c_str(), nullptr, 0));
    frameprobe::SetTransparentClears((publish && cut == 0) || config.GetInt("debug", "transparent_clears", 0) != 0);
    // Two things of the game's own that the whole-frame picture leaves out
    // (frameprobe.h): the one square of ground the arena has to have, and
    // all of the HUD but the part that shows the weapons.
    unsigned corners = 0, triangles = 0;
    if (std::sscanf(config.GetString("overlay", "hide_ground").c_str(), " %u , %u", &corners, &triangles) != 2) corners = triangles = 0;
    frameprobe::SetHiddenShape(corners, triangles);
    float keep[4] = {0, 0, 1, 1};
    const bool some = std::sscanf(config.GetString("overlay", "hud_keep").c_str(), " %f , %f , %f , %f", &keep[0], &keep[1], &keep[2], &keep[3]) == 4 &&
                      keep[2] > keep[0] && keep[3] > keep[1];
    frameprobe::SetHudKeep(some, keep[0], keep[1], keep[2], keep[3], config.GetFloat("overlay", "hud_lens", 1.7320508f));
    float middle[4] = {0, 0, 0, 0};
    const bool crosshair = std::sscanf(config.GetString("overlay", "hud_middle").c_str(), " %f , %f , %f , %f", &middle[0], &middle[1], &middle[2], &middle[3]) == 4 &&
                           middle[2] > middle[0] && middle[3] > middle[1];
    frameprobe::SetHudMiddle(some && crosshair, middle[0], middle[1], middle[2], middle[3]);
    g_crosshairKept.store(publish && some && crosshair, std::memory_order_relaxed);
    overlay::SetPublish(publish);
    input::SetForced(static_cast<uint32_t>(config.GetInt("debug", "force_buttons", 0)));
    input::SetForcedFunctions(std::strtoul(config.GetString("debug", "force_functions", "0").c_str(), nullptr, 0));
    g_logTransformCallers = config.GetInt("debug", "transform_callers", 0) != 0;
  };
  probe();

  SharedMapping shm;
  if (!shm.Open(kSideBf)) return;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_settings = settings;
    g_block = shm.block();
  }
  frameprobe::SetTransformObserver(&OnTransform);

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
    focus::Tick(settings.keepRunning, settings.hidden, settings.pointerInBackground);

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

    // The keys and buttons are read whichever window has the keyboard: the
    // player is in WaW. But only while WaW says they are playing it: not at
    // its pause menu, which a controller moves through with the same d-pad,
    // nor with some other window in front. (With no WaW there at all, this
    // game being looked at by itself, they always count.)
    WawPlayerState hands{};
    const bool handsOn = !peerAlive || (shm.block()->waw.read(hands) && (hands.flags & kWawHandsOn) != 0);
    bool anyPad = settings.viewTogglePad != 0;
    for (int i = 0; i < kAsks; ++i) anyPad = anyPad || settings.askPads[i] != 0;
    const uint32_t padButtons = anyPad ? pad::Buttons() : 0;
    const bool toggleKeyDown = handsOn && settings.viewToggle.type &&
                               ((settings.viewToggleKey && (GetAsyncKeyState(settings.viewToggleKey) & 0x8000) != 0) ||
                                (padButtons & static_cast<uint32_t>(settings.viewTogglePad)) != 0);
    if (toggleKeyDown && !toggleKeyWasDown) ApplyToggle(settings.viewToggle);
    toggleKeyWasDown = toggleKeyDown;
    for (int i = 0; i < kAsks; ++i) {
      const bool down = handsOn && settings.asks[i].type &&
                        ((settings.askKeys[i] && (GetAsyncKeyState(settings.askKeys[i]) & 0x8000) != 0) ||
                         (padButtons & static_cast<uint32_t>(settings.askPads[i])) != 0);
      if (down && !askKeyWasDown[i]) Ask(settings, i);
      askKeyWasDown[i] = down;
    }

    // WaW is told when this game is showing the player from behind, so that
    // it can do the same; and only while there is a unit to show.
    const bool thirdPerson = following && ThirdPerson(settings);
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_thirdPerson = thirdPerson;
    }

    // In third person this game is never zoomed: its zoom takes the character
    // out of the picture for a view down the sights. WaW's aim narrows WaW's
    // view, and the camera is given that instead (OnCameraSetup).
    input::SetAimAllowed(!thirdPerson);

    state.flags = following ? kBfFollowing : 0;
    if (thirdPerson) state.flags |= kBfThirdPerson;
    const uint32_t says = Kit(settings);

    // A change of character is not something to watch. The mission script
    // takes the old unit away and puts the new one where it stood, which
    // takes a few tenths of a second; from the asking until the new unit is
    // there, the picture sent to WaW is empty, and WaW is told nothing has
    // changed (it would otherwise drop out of third person and back, and take
    // the player's weapons away and hand them back).
    static bool changeSawNoUnit = false;
    if (g_changingSince) {
      if (!says) changeSawNoUnit = true;
      // (The asking can be a moment later than `now`, which was read at the
      // top of this turn of the loop: hence the signed difference.)
      if ((changeSawNoUnit && says) || static_cast<int32_t>(now - g_changingSince) > 2000) {
        g_changingSince = 0;
        changeSawNoUnit = false;
      }
    }
    const bool between = g_changingSince != 0 && !says;  // the old unit has gone and the new one is not there yet
    overlay::SetBlank(g_changingSince != 0);

    const bool melee = (says & kKitMelee) != 0;
    state.kit = says & kKitNumber;
    state.who = says / kKitWho;
    static uint32_t lastSays = ~0u;
    if (says != lastSays) {
      log::Info("kit: the character in play carries kit %u%s%s (character %u)", state.kit, (says & kKitHero) ? ", is a hero" : "",
                melee ? ", and fights with a lightsaber" : "", state.who);
      lastSays = says;
    }
    // A character with a lightsaber is always shown from behind. Anyone with
    // a weapon to aim is left in whichever view the player has chosen.
    if (melee && !thirdPerson && following) ShowFromBehind(settings);
    // [swbf2] start_from_behind: a game begins from behind the character,
    // whichever view this game was last left in (it remembers). Once, the
    // first time there is a character to show: after that the view is the
    // player's to change, and stays as they leave it.
    static bool begun = false;
    if (settings.startFromBehind && !begun && state.kit) {
      begun = true;
      if (!thirdPerson) ShowFromBehind(settings, "a game begins from behind the character");
    }
    float scale = settings.characterScale;
    for (const auto& kit : settings.characterScaleKits) {
      if (kit.first == static_cast<int>(state.kit)) scale = kit.second;
    }
    g_characterScale.store(scale, std::memory_order_relaxed);
    if (!between) {
      g_melee = melee;
      input::SetMelee(melee);
    }
    // This game's crosshair is in the picture for anyone with something to
    // aim; WaW leaves its own out then.
    if (following && state.kit && !melee && g_crosshairKept.load(std::memory_order_relaxed)) state.flags |= kBfCrosshair;
    if (following && state.kit && melee) state.flags |= kBfMelee;

    // The ability: which is selected, and each use of it.
    const InHand hand = ReadInHand(settings);
    static uintptr_t lastAbilityAt = 0;
    static bool abilityWasInUse = false;
    if (hand.abilityAt != lastAbilityAt) {
      lastAbilityAt = hand.abilityAt;
      abilityWasInUse = hand.abilityInUse;
      if (hand.ability) log::Info("ability: weapon %u of the unit's is selected", hand.ability + 1);
    } else if (hand.abilityInUse && !abilityWasInUse) {
      ++state.abilityUses;
      log::Info("ability: weapon %u used (%u so far)", hand.ability + 1, state.abilityUses);
    }
    abilityWasInUse = hand.abilityInUse;
    state.ability = hand.ability;
    if (hand.abilityInUse) {
      state.flags |= kBfAbilityInUse;
      g_noSpeedUntil.store(now + 300, std::memory_order_relaxed);
    }
    // And each use of the weapon in hand: for a lightsaber, each swing.
    // A weapon that charges says how long a full charge takes while it is
    // charging; how far it got is the time it was held against that.
    static uintptr_t lastWeaponAt = 0;
    static bool weaponWasInUse = false;
    static DWORD chargingSince = 0;
    static float chargeFull = 0;
    if (hand.weaponAt != lastWeaponAt) {
      lastWeaponAt = hand.weaponAt;
      chargingSince = 0;
    } else if (hand.weaponInUse && !weaponWasInUse) {
      ++state.weaponUses;
      // (A time kept from being zero by "| 1" can be a thousandth of a second
      // ahead of `now`: every difference from one is taken signed, here and
      // below. Taken unsigned, that thousandth is seven weeks.)
      state.weaponCharge = chargingSince && chargeFull > 0.05f
                               ? std::min(1.0f, static_cast<float>(std::max<int32_t>(0, static_cast<int32_t>(now - chargingSince))) / (chargeFull * 1000.0f))
                               : 0.0f;
    }
    if (hand.weaponCharging) {
      if (!chargingSince) chargingSince = now | 1;
      chargeFull = hand.chargeFull;
    } else {
      chargingSince = 0;
    }
    weaponWasInUse = hand.weaponInUse;
    if (hand.weaponInUse) state.flags |= kBfWeaponInUse;


    // WaW counts the ammunition, so this game's magazine is kept at WaW's:
    // then the two run out together, and this game never stops to reload
    // while WaW is still firing. And when WaW starts to reload, for whatever
    // reason, so does this game. (Not written while this game's is empty: it
    // is reloading, or about to.)
    WawPlayerState waw{};
    static bool wawWasReloading = false;
    // The character crouches when WaW's player does, and sprints while they
    // do. Crouch is a switch in this game: it is pressed whenever the unit is
    // not the way WaW's player is, no more often than twice a second, and
    // only once the two have disagreed for a moment: while the view changes,
    // or the unit is still arriving, what the unit says about itself cannot
    // be trusted for a frame or two, and a press made on the strength of it
    // stands a crouched character up. Sprint is simply held.
    if (peerAlive && following && shm.block()->waw.read(waw)) {
      static DWORD lastCrouchPress = 0, apartSince = 0;
      double posture = 0;
      const uintptr_t postureAt = settings.crouched.type ? mem::Resolve(settings.crouched.address) : 0;
      if (settings.crouchFunction >= 0 && postureAt && ReadValue(settings.crouched, postureAt, posture)) {
        const bool crouched = (static_cast<uint32_t>(posture) & static_cast<uint32_t>(settings.crouched.value)) != 0;
        if (crouched == ((waw.flags & kWawCrouching) != 0)) {
          apartSince = 0;
        } else if (!apartSince) {
          apartSince = now | 1;
        } else if (static_cast<int32_t>(now - apartSince) >= 150 && now - lastCrouchPress > 500) {
          lastCrouchPress = now;
          apartSince = 0;
          input::HoldFor(settings.crouchFunction, 3);
        }
      }
      // Not a character with a lightsaber, though. Its sprint in this game is
      // a bounding run made for 22 metres a second, and the game paces a
      // character's legs by the ground it really covers: at the 7 that WaW's
      // player sprints at, a step took a second, whatever speed the unit was
      // told it had (1, 2.5, 4 and 5 times WaW's were tried). Left to its
      // ordinary run, made for 9, the same character takes a stride every
      // 0.8 s at WaW's sprint. So that is what it does. ([swbf2] saber_sprint
      // = 1 brings the game's own sprint back.)
      //
      // But the blow such a character strikes out of a sprint is one of its
      // own, and the game only gives it to a character that is sprinting when
      // the button goes down. So when WaW's player strikes while sprinting,
      // the character is put into its sprint for just that: sprint is held,
      // the blow is kept back for a moment while the sprint takes
      // (sprint_attack_lead_ms), then struck (and held for
      // sprint_attack_hold_ms, so that a tap is not lost), and the sprint let
      // go again. WaW's player has stopped sprinting by the time the button
      // reaches here, hence "a moment ago".
      static DWORD wawSprintedAt = 0, dashAt = 0;
      static bool fireWasHeld = false;
      if (waw.flags & kWawSprinting) wawSprintedAt = now | 1;
      const bool fireHeld = (waw.buttons & kWawButtonFire) != 0;
      if (melee && !settings.saberSprint && settings.sprintAttack && settings.sprintFunction >= 0 && fireHeld && !fireWasHeld && !dashAt &&
          wawSprintedAt && static_cast<int32_t>(now - wawSprintedAt) < 250) {
        dashAt = now | 1;
        log::Info("sprint attack: WaW's player struck out of a sprint; sprinting here for the blow");
      }
      fireWasHeld = fireHeld;
      bool dashing = false;
      if (dashAt && melee) {
        // (Signed, as above: unsigned, a blow struck on an even thousandth of
        // a second was over before it began, which was every other one.)
        const DWORD since = static_cast<DWORD>(std::max<int32_t>(0, static_cast<int32_t>(now - dashAt)));
        dashing = since < static_cast<DWORD>(settings.sprintAttackLeadMs + settings.sprintAttackHoldMs);
        g_dashFire.store(!dashing ? 0 : since < static_cast<DWORD>(settings.sprintAttackLeadMs) ? -1 : 1, std::memory_order_relaxed);
        if (!dashing) dashAt = 0;
      } else {
        dashAt = 0;
        g_dashFire.store(0, std::memory_order_relaxed);
      }
      const bool sprinting = settings.sprintFunction >= 0 && (dashing || ((waw.flags & kWawSprinting) && (!melee || settings.saberSprint)));
      input::SetHeld(sprinting ? 1u << settings.sprintFunction : 0);
      // And jumps when they jump. How high is this game's own business: the
      // camera goes up with the unit, so all that shows is the jump itself,
      // against a room WaW is moving past as its own player rises.
      static bool jumpWasHeld = false;
      const bool jumpHeld = (waw.buttons & kWawButtonJump) != 0;
      if (jumpHeld && !jumpWasHeld && settings.jumpFunction >= 0) input::HoldFor(settings.jumpFunction, 3);
      jumpWasHeld = jumpHeld;
    } else {
      input::SetHeld(0);
      g_dashFire.store(0, std::memory_order_relaxed);
    }
    // [debug] force_axis = <axis> <value>: pushes a stick axis, to find which is which.
    if (settings.debugAxis >= 0) input::SetAxis(settings.debugAxis, settings.debugAxisValue);
    if (peerAlive && hand.known && shm.block()->waw.read(waw) && waw.weapon == hand.weapon + 1) {
      const bool reloading = (waw.flags & kWawReloading) != 0;
      if (reloading && !wawWasReloading) input::PressReload();
      wawWasReloading = reloading;
      float have = 0;
      if (hand.clipAt && waw.clipSize > 0 && !reloading && !(waw.flags & kWawDry) &&
          mem::Read(hand.clipAt, &have, sizeof(have)) && have > 0.0f && have <= 1.0f) {
        const float want = std::min(1.0f, static_cast<float>(waw.clip) / static_cast<float>(waw.clipSize));
        if (std::fabs(have - want) > 0.5f / static_cast<float>(waw.clipSize)) mem::Write(hand.clipAt, &want, sizeof(want));
      }
    } else {
      wawWasReloading = false;
    }
    if (peerAlive) MatchWeapon(shm.block(), hand);
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
    static BfPlayerState shown{};  // as last published with a unit in play
    BfPlayerState out = state;
    if (between) {
      out.flags = shown.flags;
      out.kit = shown.kit;
      out.who = shown.who;
      out.ability = shown.ability;
      std::memcpy(out.rawPosition, shown.rawPosition, sizeof(out.rawPosition));
      std::memcpy(out.positionInWaw, shown.positionInWaw, sizeof(out.positionInWaw));
    } else {
      shown = state;
    }
    shm.block()->bf.write(out);

    if (now - lastReport >= 1000) {
      lastReport = now;
      sound::Report();
      if (config.GetInt("debug", "log_sound", 0) != 0) sound::Describe();
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
      // Say when the camera starts and stops being WaW's.
      static bool cameraWasReplaced = false;
      const bool cameraReplaced = g_camerasReplaced.exchange(0) != 0;
      if (cameraReplaced != cameraWasReplaced) {
        log::Info(cameraReplaced ? "camera: third person, drawing from where WaW's camera is"
                                 : "camera: this game's own again");
        cameraWasReplaced = cameraReplaced;
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
