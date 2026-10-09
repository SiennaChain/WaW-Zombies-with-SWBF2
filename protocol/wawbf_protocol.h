// WaW Zombies x SWBF2 shared-memory protocol.
//
// This header is the single source of truth for everything the two bridge
// DLLs exchange. It is plain C++17 with no OS headers so it can be unit
// tested on any platform (see tests/test_protocol.cpp).
//
// Layout rules, because the same block is mapped by two 32-bit games and
// possibly a 64-bit monitor tool:
//   * fixed-width integers, float and std::atomic<uint32_t> only;
//   * no pointers, size_t, bool, double or 64-bit fields (their size or
//     alignment differs between x86 and x64);
//   * bump kVersion whenever any struct below changes.
#pragma once

#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <type_traits>

namespace wawbf {

constexpr uint32_t kMagic = 0x46425757;  // "WWBF" in memory
constexpr uint32_t kMagicInitializing = 1;
constexpr uint32_t kVersion = 12;  // 2: WawPlayerState gained timeUs; 3: tanHalfFov; 4: buttons; 5: camera; 6: kit; 7: weapon in hand, abilities; 8: weapon uses; 9: magazine, charge; 10: the thrown grenade; 11: and not; 12: who the character is
constexpr const wchar_t* kMappingName = L"Local\\WaWBF_v1";
constexpr uint32_t kMappingSize = 0x10000;  // 64 KiB; later phases add rings
constexpr uint32_t kHeartbeatTimeoutMs = 2000;

static_assert(std::atomic<uint32_t>::is_always_lock_free,
              "cross-process atomics must be lock-free");

enum Side : uint32_t {
  kSideWaw = 0,  // game A: World at War, visible, owns the world
  kSideBf = 1,   // game B: Battlefront II, hidden, owns the player's kit
  kSideCount = 2,
};

// ---------------------------------------------------------------------------
// Seqlock: one writer, any number of readers, no blocking.
// seq is odd while the writer is mid-update; readers retry until they see
// the same even value before and after copying the payload.
// ---------------------------------------------------------------------------
template <class T>
struct Seqlocked {
  static_assert(std::is_trivially_copyable<T>::value, "payload must be POD");

  std::atomic<uint32_t> seq;
  T value;

  void write(const T& v) {
    const uint32_t s = seq.load(std::memory_order_relaxed);
    seq.store(s + 1, std::memory_order_relaxed);
    std::atomic_thread_fence(std::memory_order_release);
    std::memcpy(&value, &v, sizeof(T));
    seq.store(s + 2, std::memory_order_release);
  }

  // Returns false if nothing was ever written or the writer kept racing us.
  bool read(T& out, int maxTries = 64) const {
    for (int i = 0; i < maxTries; ++i) {
      const uint32_t before = seq.load(std::memory_order_acquire);
      if (before == 0) return false;
      if (before & 1) continue;
      std::memcpy(&out, &value, sizeof(T));
      std::atomic_thread_fence(std::memory_order_acquire);
      if (seq.load(std::memory_order_relaxed) == before) return true;
    }
    return false;
  }
};

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------
struct PeerInfo {
  std::atomic<uint32_t> pid;          // 0 = never attached
  std::atomic<uint32_t> heartbeatMs;  // writer's GetTickCount() at last beat
  std::atomic<uint32_t> beats;        // increments every beat
};

// Wrap-safe staleness check (GetTickCount wraps every ~49.7 days).
inline bool HeartbeatAlive(uint32_t lastBeatMs, uint32_t beats, uint32_t nowMs,
                           uint32_t timeoutMs = kHeartbeatTimeoutMs) {
  return beats != 0 && static_cast<uint32_t>(nowMs - lastBeatMs) <= timeoutMs;
}

struct alignas(64) Header {
  std::atomic<uint32_t> magic;  // 0 -> kMagicInitializing -> kMagic
  uint32_t version;
  uint32_t size;
  uint32_t reserved;
  PeerInfo peers[kSideCount];
};

// ---------------------------------------------------------------------------
// Per-frame state. All positions in the protocol are in WaW space (see
// "Coordinates" below); only the SWBF2 bridge converts to its own space.
// ---------------------------------------------------------------------------
enum WawFlags : uint32_t {
  kWawOriginValid = 1u << 0,
  kWawAnglesValid = 1u << 1,
  kWawFovValid = 1u << 2,
  kWawCameraValid = 1u << 3,
  // From WaW's scripts, which know what the player is carrying:
  kWawAbilityReady = 1u << 4,  // the character's ability may be used now (there is a grenade or a rocket left)
  kWawDry = 1u << 5,           // the weapon in hand has nothing left to fire
  kWawReloading = 1u << 6,     // the weapon in hand is being reloaded (from the game itself, not the scripts)

  kWawCrouching = 1u << 8,     // the player is crouched
  kWawSprinting = 1u << 9,     // the player is sprinting
};

// What the player is holding down in WaW that belongs to SWBF2's side of the
// game: the weapon is SWBF2's, so pulling its trigger is too.
enum WawButtons : uint32_t {
  kWawButtonFire = 1u << 0,     // WaW's attack
  kWawButtonAim = 1u << 1,      // WaW's aim down the sights
  kWawButtonReload = 1u << 2,
  kWawButtonAbility = 1u << 3,      // WaW's grenade button: the character's ability (a grenade, a rocket, the Force)
  kWawButtonNextAbility = 1u << 4,  // "the next ability": a button and a key the WaW bridge watches for itself
  kWawButtonJump = 1u << 5,         // WaW's jump (it also stands a crouched player up)
};

// Game A -> game B. WaW is authoritative for player movement.
struct WawPlayerState {
  uint32_t frame;        // increments on every publish
  uint32_t flags;        // WawFlags
  float origin[3];       // player feet, WaW units (~inches), Z-up
  float viewAngles[3];   // pitch, yaw, roll in degrees (CoD convention)
  // When origin and viewAngles were sampled, in microseconds on the system
  // performance counter (the same clock in every process), low 32 bits. It
  // wraps every ~71 minutes, so only ever compare two of these with
  // ElapsedUs. The two games draw frames at different rates, so the reader
  // needs this to place the WaW player at the instant it is drawing, not just
  // at "the last sample"; without it the follower visibly stutters.
  uint32_t timeUs;
  // WaW's field of view as the engine keeps it: the tangents of half the
  // horizontal and half the vertical angle. SWBF2's picture can only be laid
  // over WaW's if both are drawn with the same one.
  float tanHalfFov[2];
  uint32_t buttons;  // WawButtons held down now
  // Where WaW is drawing from: its camera's position, and the directions it
  // looks along and counts as up, in WaW space. In first person that is the
  // player's eyes. In third person it is behind them, wherever WaW has put
  // it after allowing for the walls, and SWBF2 has to draw from exactly
  // there for its character to stand where WaW's player is.
  float cameraOrigin[3];
  float cameraForward[3];
  float cameraUp[3];
  // Which of the character's weapons WaW's player has in hand: 1 the first,
  // 2 the second, 0 not known. SWBF2 changes its own to match.
  uint32_t weapon;
  // The rounds left in that weapon's magazine and how many it holds, from
  // WaW's scripts; clipSize 0 = not a weapon whose magazine SWBF2 should be
  // made to agree with. WaW does the counting, so SWBF2's magazine is kept at
  // WaW's, and it is reloaded when WaW's is.
  uint32_t clip;
  uint32_t clipSize;
};

// The full angle, in degrees, that a tangent of half of it stands for.
inline float FovDegrees(float tanHalf) { return 2.0f * 57.2957795f * std::atan(tanHalf); }

// Signed time from `from` to `to`, correct across the wrap.
inline int32_t ElapsedUs(uint32_t from, uint32_t to) { return static_cast<int32_t>(to - from); }

enum BfFlags : uint32_t {
  kBfPositionValid = 1u << 0,
  kBfFollowing = 1u << 1,  // bridge is driving the BF unit from WaW state
  // SWBF2 is showing the player's character from behind, so WaW should draw
  // from behind the player too, and leave its own soldier out.
  kBfThirdPerson = 1u << 2,
  kBfAbilityInUse = 1u << 3,  // the selected ability is being used this moment
  kBfWeaponInUse = 1u << 4,   // and so is the weapon in hand: a shot being fired, a lightsaber mid-swing
  // SWBF2's own crosshair is in the picture it sends (a character with
  // something to aim), so WaW's is not wanted as well.
  kBfCrosshair = 1u << 5,
  // The character fights with a lightsaber: WaW's count of the ammunition
  // for the weapon that stands for it there means nothing, and is not shown.
  kBfMelee = 1u << 6,
};

// Game B -> game A. Phase 0 only reports where the BF unit is, so the two
// positions can be compared to validate the coordinate mapping.
struct BfPlayerState {
  uint32_t frame;
  uint32_t flags;           // BfFlags
  float rawPosition[3];     // as read from SWBF2 memory, BF space
  float positionInWaw[3];   // rawPosition converted back to WaW space
  // Which kit the SWBF2 character carries (docs/PHASE3.md has the list), or
  // 0 if it is not known. WaW hands its player the weapons that match.
  uint32_t kit;
  // The character's abilities (SWBF2's "secondary" weapons: a grenade, a
  // rocket, a Force power). Which one is selected, as the place it has among
  // all the unit's weapons, and how many times one has been used: WaW's
  // scripts make the same thing happen to the zombies each time that goes up.
  uint32_t ability;
  uint32_t abilityUses;
  // The same count for the weapon in hand. For a lightsaber each one is a
  // swing, and a swing is the only time the blade cuts anything in WaW.
  uint32_t weaponUses;
  // How far the weapon had been charged when it was last fired, 0 to 1 (the
  // bowcaster: held, it charges, and fires when let go).
  float weaponCharge;
  // Who the character is, as a number (swbf2/arena/WAW_arena.lua has the
  // list), or 0 if it is not known: several characters share a kit. WaW shows
  // the name that goes with it where it shows the player's own.
  uint32_t who;
};

struct SharedBlock {
  Header header;
  alignas(64) Seqlocked<WawPlayerState> waw;
  alignas(64) Seqlocked<BfPlayerState> bf;
};

static_assert(std::is_standard_layout<SharedBlock>::value, "layout must be fixed");
static_assert(sizeof(PeerInfo) == 12, "PeerInfo layout changed: bump kVersion");
static_assert(sizeof(WawPlayerState) == 96, "WawPlayerState changed: bump kVersion");
static_assert(sizeof(BfPlayerState) == 56, "BfPlayerState changed: bump kVersion");
static_assert(offsetof(SharedBlock, waw) == 0x40, "layout changed: bump kVersion");
static_assert(offsetof(SharedBlock, bf) == 0xC0, "layout changed: bump kVersion");
static_assert(sizeof(SharedBlock) <= kMappingSize, "mapping too small");

// ---------------------------------------------------------------------------
// The picture (Phase 2)
//
// SWBF2's first-person weapon and HUD, cut out of its frame, go to WaW through
// a second mapping, because a picture is far bigger than everything else put
// together. It holds two pictures: SWBF2 fills the one that is not `front`,
// then makes it `front` and bumps `sequence`, so WaW never reads a picture
// that is half written (unless it takes longer over one than SWBF2 takes to
// draw two).
//
// Pixels are four bytes each, blue green red alpha, rows top to bottom with
// no padding, and the colour is already multiplied by the alpha: a pixel is
// laid over WaW's as  picture + waw * (1 - alpha).
// ---------------------------------------------------------------------------
constexpr const wchar_t* kFrameMappingName = L"Local\\WaWBF_frame_v1";
constexpr uint32_t kFrameMagic = 0x52465757;  // "WWFR" in memory
constexpr uint32_t kFrameMaxWidth = 1920;
constexpr uint32_t kFrameMaxHeight = 1200;
constexpr uint32_t kFrameMaxBytes = kFrameMaxWidth * kFrameMaxHeight * 4;

struct alignas(64) FrameHeader {
  std::atomic<uint32_t> magic;     // kFrameMagic once the writer has set it up
  std::atomic<uint32_t> sequence;  // goes up by one for every picture published
  std::atomic<uint32_t> front;     // 0 or 1: the picture that is complete
  uint32_t width[2];
  uint32_t height[2];
  uint32_t timeUs[2];              // when each was taken; compare with ElapsedUs
};

constexpr uint32_t kFrameMappingSize = 64 + 2 * kFrameMaxBytes;
static_assert(sizeof(FrameHeader) == 64, "FrameHeader changed: rename kFrameMappingName");

// ---------------------------------------------------------------------------
// Coordinates
//
// WaW (CoD) space: right-handed, X forward, Y left, Z up, 1 unit ~= 1 inch.
// SWBF2 space: Y up, metres. Its handedness is NOT verified yet; that is a
// Phase 0 task (docs/PHASE0.md). zSign captures it: with zSign = -1 the
// mapping is a proper rotation (right-handed BF), with +1 a mirror.
//
//   bf.x = (waw.x - anchorWaw.x) * scale + anchorBf.x
//   bf.y = (waw.z - anchorWaw.z) * scale + anchorBf.y
//   bf.z = (waw.y - anchorWaw.y) * scale * zSign + anchorBf.z
//
// The anchors pin a WaW map location (e.g. the zombies spawn room) to a
// spot in the hidden SWBF2 arena.
// ---------------------------------------------------------------------------
constexpr float kWawUnitsPerMetre = 39.3700787f;

struct Vec3 {
  float x, y, z;
};

struct CoordMapping {
  Vec3 anchorWaw{0, 0, 0};
  Vec3 anchorBf{0, 0, 0};
  float scale = 1.0f / kWawUnitsPerMetre;  // BF units per WaW unit
  float zSign = -1.0f;
  float yawSign = 1.0f;
  float yawOffsetDeg = 0.0f;
  float pitchSign = -1.0f;  // WaW pitch grows looking down, SWBF2's looking up
};

inline Vec3 WawToBf(const Vec3& w, const CoordMapping& m) {
  return {(w.x - m.anchorWaw.x) * m.scale + m.anchorBf.x,
          (w.z - m.anchorWaw.z) * m.scale + m.anchorBf.y,
          (w.y - m.anchorWaw.y) * m.scale * m.zSign + m.anchorBf.z};
}

inline Vec3 BfToWaw(const Vec3& b, const CoordMapping& m) {
  return {(b.x - m.anchorBf.x) / m.scale + m.anchorWaw.x,
          (b.z - m.anchorBf.z) / (m.scale * m.zSign) + m.anchorWaw.y,
          (b.y - m.anchorBf.y) / m.scale + m.anchorWaw.z};
}

inline float WawYawToBf(float yawDeg, const CoordMapping& m) {
  return yawDeg * m.yawSign + m.yawOffsetDeg;
}

// Degrees in, degrees out. WaW can hand over a pitch as 350 instead of -10.
inline float WawPitchToBf(float pitchDeg, const CoordMapping& m) {
  while (pitchDeg > 180.0f) pitchDeg -= 360.0f;
  while (pitchDeg < -180.0f) pitchDeg += 360.0f;
  return pitchDeg * m.pitchSign;
}

// A direction in WaW space as the same direction in SWBF2 space. Its length
// is kept, so a WaW distance times `scale` is a SWBF2 one.
inline Vec3 WawDirectionToBf(const Vec3& w, const CoordMapping& m) {
  return {w.x, w.z, w.y * m.zSign};
}

// A WaW velocity (units per second) as a SWBF2 one (metres per second).
inline Vec3 WawVelocityToBf(const Vec3& w, const CoordMapping& m) {
  return {w.x * m.scale, w.z * m.scale, w.y * m.scale * m.zSign};
}

}  // namespace wawbf
