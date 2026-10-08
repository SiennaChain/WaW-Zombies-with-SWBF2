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
#include <string>
#include <vector>

#include "address_spec.h"
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
  bool forwardButtons = true;
  // Where the game records each of SWBF2's buttons as held; empty = not known.
  std::vector<AddressSpec> heldFire, heldAim, heldReload;
  AddressSpec drawGun;  // the byte behind cg_drawGun
  bool haveDrawGun = false;
  int tickMs = 16;
};

// A list of addresses separated by commas. One that cannot be read as an
// address is logged and left out.
std::vector<AddressSpec> LoadPlaces(const Config& config, const char* key) {
  std::vector<AddressSpec> places;
  const std::string text = config.GetString("waw", key);
  for (size_t start = 0;;) {
    const size_t comma = text.find(',', start);
    const std::string part = text.substr(start, comma == std::string::npos ? comma : comma - start);
    AddressSpec place;
    if (ParseAddressSpec(part, place)) {
      places.push_back(place);
    } else if (part.find_first_not_of(" \t") != std::string::npos) {
      log::Error("[waw] %s: can't parse address \"%s\"", key, part.c_str());
    }
    if (comma == std::string::npos) break;
    start = comma + 1;
  }
  return places;
}

Settings LoadSettings(const Config& config) {
  Settings s;
  s.haveOrigin = config.GetAddress("waw", "player_origin", s.origin);
  s.haveAngles = config.GetAddress("waw", "view_angles", s.angles);
  s.haveFov = config.GetAddress("waw", "view_fov", s.fov);
  s.forwardButtons = config.GetInt("waw", "forward_buttons", 1) != 0;
  s.heldFire = LoadPlaces(config, "held_fire");
  s.heldAim = LoadPlaces(config, "held_aim");
  s.heldReload = LoadPlaces(config, "held_reload");
  s.haveDrawGun = config.GetAddress("waw", "draw_gun", s.drawGun);
  const auto source = [](const std::vector<AddressSpec>& places, const char* fallback) {
    return places.empty() ? fallback : "the game's own record";
  };
  log::Info("buttons for SWBF2: fire from %s, aim from %s, reload from %s%s",
            source(s.heldFire, "the left mouse button"), source(s.heldAim, "the right mouse button"),
            source(s.heldReload, "the R key"), s.forwardButtons ? "" : " (forward_buttons = 0: none are sent)");
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

// True if any of these places in the game holds a byte that is not zero.
bool AnyHeld(const std::vector<AddressSpec>& places) {
  for (const AddressSpec& place : places) {
    uint8_t held = 0;
    const uintptr_t address = mem::Resolve(place);
    if (address && mem::Read(address, &held, sizeof(held)) && held) return true;
  }
  return false;
}

// The buttons that belong to SWBF2's side of the game, as they are held now.
//
// Each is taken from the game's own record of it. The game keeps one for
// every action ("+attack" and the rest) and switches it on and off as the
// player's bindings say, so it reads "attack is held" whether attack is on a
// mouse button, a key or a controller's trigger. Reading the left mouse
// button instead, as this first did, left a player with a controller unable
// to fire.
//
// A button whose record is not in wawbf.ini falls back to a fixed one on the
// mouse or keyboard, read only while WaW is the window in front: a click in
// some other window is not a shot.
uint32_t HeldButtons(const Settings& s) {
  DWORD foreground = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &foreground);
  const bool inFront = foreground == GetCurrentProcessId();
  const struct {
    uint32_t bit;
    const std::vector<AddressSpec>& places;
    int fallbackKey;
  } buttons[] = {{kWawButtonFire, s.heldFire, VK_LBUTTON},
                 {kWawButtonAim, s.heldAim, VK_RBUTTON},
                 {kWawButtonReload, s.heldReload, 'R'}};
  uint32_t held = 0;
  for (const auto& button : buttons) {
    const bool down = button.places.empty() ? inFront && (GetAsyncKeyState(button.fallbackKey) & 0x8000) != 0
                                            : AnyHeld(button.places);
    if (down) held |= button.bit;
  }
  return held;
}

// One gun on screen, not two: while SWBF2's weapon is being drawn over the
// picture, WaW's own is switched off (its cg_drawGun setting), and it comes
// back if SWBF2's picture stops arriving. WaW's gun is otherwise untouched:
// it still fires, and whatever the player sets cg_drawGun to themselves is
// left alone while there is no overlay. Call with g_mutex held.
void HideGun() {
  static bool hiding = false;
  const bool hide = overlay::Drawing();
  if (!g_settings.haveDrawGun || (!hide && !hiding)) return;
  const uintptr_t address = mem::Resolve(g_settings.drawGun);
  if (!address) return;  // the game has not made the setting yet
  const uint8_t wanted = hide ? 0 : 1;
  uint8_t now = wanted;
  if (mem::Read(address, &now, sizeof(now)) && now != wanted) mem::Write(address, &wanted, sizeof(wanted));
  if (hide != hiding) log::Info(hide ? "hiding WaW's own gun while SWBF2's is drawn" : "showing WaW's own gun again");
  hiding = hide;
}

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
  next.buttons = s.forwardButtons ? HeldButtons(s) : 0;
  const bool same = next.flags == g_state.flags && next.buttons == g_state.buttons &&
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
  HideGun();
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
