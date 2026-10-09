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
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "address_spec.h"
#include "bridge.h"
#include "callhook.h"
#include "clock.h"
#include "config.h"
#include "crashlog.h"
#include "log.h"
#include "memory.h"
#include "overlay.h"
#include "pad.h"
#include "shm.h"

namespace wawbf {
namespace {

// A change to the game's code: at a place, these bytes for those.
struct CodeChange {
  AddressSpec at;
  std::vector<unsigned char> before, after;
};

// Everything this bridge takes from wawbf.ini. Read again whenever the file
// is saved, so it can be changed while the game runs.
struct Settings {
  AddressSpec origin, angles, fov;
  bool haveOrigin = false;
  bool haveAngles = false;
  bool haveFov = false;
  bool forwardButtons = true;
  // Where the game records each of SWBF2's buttons as held; empty = not known.
  std::vector<AddressSpec> heldFire, heldAim, heldReload, heldAbility, heldJump;
  int nextAbilityKey = 0;       // a Windows virtual-key code; 0 = none
  uint32_t nextAbilityPad = 0;  // a controller's buttons, as XInput numbers them; 0 = none
  int fittedKey = 0;            // the same for "what is fitted to the weapon": Boba Fett's flamethrower
  uint32_t fittedPad = 0;
  std::vector<CodeChange> scoreboardAlone;  // what makes the scores button bring up the scoreboard in a game played alone
  std::vector<CodeChange> quietRename;      // and what keeps "... renamed to ..." off the screen when the bridge changes the player's name
  AddressSpec console;          // the game's routine that takes a line for its console
  bool haveConsole = false;
  AddressSpec playerName;       // the player's name as the game has it (text), for putting back
  bool havePlayerName = false;
  std::vector<std::pair<int, std::string>> characterNames;  // SWBF2's number for a character, and the name the player goes by as them
  AddressSpec maxHealth;        // the number behind g_player_maxhealth: what a player is given when put into a map
  bool haveMaxHealth = false;
  int playerHealth = 0;         // and what it is to be; 0 = the game's own
  AddressSpec playerFlags;      // the player entity's switches, one of which is what "god" in the console turns on and off
  bool havePlayerFlags = false;
  bool godAtStart = false;      // [debug] god_at_start: the player begins each map with that one on
  AddressSpec drawGun;  // the byte behind cg_drawGun
  bool haveDrawGun = false;
  AddressSpec viewOrigin, viewAxis;  // where the game is drawing from: 3 floats, and 9 (forward, left, up)
  bool haveView = false;
  AddressSpec thirdPerson;           // the number behind cg_thirdPerson
  bool haveThirdPerson = false;
  std::vector<AddressSpec> hideBody; // the flags in which bit kHidden keeps the player's own soldier from being drawn
  AddressSpec kitField;              // a number on the player's entity that the game's scripts can read
  bool haveKitField = false;
  AddressSpec scriptsSay;            // and one that they write, for this bridge to read
  bool haveScriptsSay = false;
  AddressSpec weaponState;           // what the player's weapon is doing, as the game numbers it
  bool haveWeaponState = false;
  std::vector<int> knifeStates;      // the numbers that are a knife attack
  std::vector<int> reloadStates;     // and those that are a reload
  std::vector<int> sprintStates;     // and those that are a sprint
  AddressSpec viewKick;              // the number behind bg_viewKickScale: how far being hit throws the view
  bool haveViewKick = false;
  AddressSpec gunAngles;             // two floats, pitch and yaw: the way the game fires the player's next shot
  bool haveGunAngles = false;
  AddressSpec aimField;              // a number on the player's entity the scripts read: the line through the middle of the screen
  bool haveAimField = false;
  bool aimMark = false;              // draw a crosshair of the bridge's own on the spot a shot from behind is pointed at
  AddressSpec viewAngle;             // the number behind cg_thirdPersonAngle: how far round the player the camera sits
  bool haveViewAngle = false;
  float gunViewAngle = 0;            // and what it is to be, in degrees, for a character with something to aim
  AddressSpec jumpHeight;            // the number behind jump_height: how high the player jumps, in units
  bool haveJumpHeight = false;
  std::vector<std::pair<int, float>> jumpHeights;  // and what it is to be for each kit
  AddressSpec hintJump;              // the jump that keeps "Press F to ..." off the screen in third person
  bool haveHintJump = false;
  // Three of the game's own settings that are found by name each time the
  // game runs (NamedSetting, below): no pointer to them is known, and where
  // a setting is kept moves with what the game was started with.
  AddressSpec settingsTable;         // where the game keeps its settings, roughly
  uint32_t settingsTableSize = 0;    // and how much of memory from there to look through
  std::string crosshairSetting;      // "cg_drawCrosshair"
  std::string ammoSetting;           // "ammoCounterHide": the weapon's name and ammunition are not shown
  std::string footstepsSetting;      // "cg_footsteps": whether the player's own footsteps are heard
  std::vector<int> quietKits;        // the kits that are not heard walking
  AddressSpec stance;                // the player's flags, in which one bit is "crouched"
  bool haveStance = false;
  uint32_t crouchBit = 0x4;
  AddressSpec headCall, headRoutine; // the call that asks where the player's head is, for the camera; and the routine it calls
  bool haveHeadCall = false;
  int headEntityOrigin = 0x24;       // in the entity handed to that call: where it is drawn (3 floats)
  AddressSpec ground;                // the number of the thing the player is standing on
  bool haveGround = false;
  int groundNone = 1023;             // and what it reads when they are standing on nothing
  bool logWeaponState = false;       // [debug] log_weapon_state: say each change, for finding those numbers
  AddressSpec paused;                // the byte behind cl_paused: not zero while the pause menu is up
  bool havePaused = false;

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

// Changes to the game's code, as a setting has them: "place: bytes there =
// bytes to put, place: ...". None at all if any one cannot be read.
std::vector<CodeChange> LoadChanges(const Config& config, const char* key) {
  std::vector<CodeChange> list;
  const std::string changes = config.GetString("waw", key);
  const auto bytes = [](const std::string& text, std::vector<unsigned char>& out) {
    for (const char* p = text.c_str(); *p;) {
      char* stop = nullptr;
      const unsigned long byte = std::strtoul(p, &stop, 16);
      if (stop == p) {
        ++p;
      } else {
        out.push_back(static_cast<unsigned char>(byte));
        p = stop;
      }
    }
  };
  for (size_t start = 0; start < changes.size();) {
    size_t end = changes.find(',', start);
    if (end == std::string::npos) end = changes.size();
    const std::string one = changes.substr(start, end - start);
    start = end + 1;
    if (one.find_first_not_of(" \t") == std::string::npos) continue;
    const size_t colon = one.find(':'), equals = one.find('=');
    CodeChange change;
    if (colon != std::string::npos && equals != std::string::npos && equals > colon && ParseAddressSpec(one.substr(0, colon), change.at)) {
      bytes(one.substr(colon + 1, equals - colon - 1), change.before);
      bytes(one.substr(equals + 1), change.after);
    }
    if (change.before.empty() || change.before.size() != change.after.size()) {
      log::Error("[waw] %s: can't parse \"%s\"", key, one.c_str());
      return {};
    }
    list.push_back(change);
  }
  return list;
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
  s.heldAbility = LoadPlaces(config, "held_ability");
  s.heldJump = LoadPlaces(config, "held_jump");
  s.nextAbilityKey = config.GetInt("waw", "next_ability_key", 0);
  s.nextAbilityPad = static_cast<uint32_t>(config.GetInt("waw", "next_ability_pad", 0));
  s.fittedKey = config.GetInt("waw", "fitted_key", 0);
  s.fittedPad = static_cast<uint32_t>(config.GetInt("waw", "fitted_pad", 0));
  s.scoreboardAlone = LoadChanges(config, "scoreboard_alone");
  s.quietRename = LoadChanges(config, "quiet_rename");
  s.haveConsole = config.GetAddress("waw", "console", s.console);
  s.havePlayerName = config.GetAddress("waw", "player_name", s.playerName);
  // "1 = Han Solo, 2 = Clone Trooper": a character's number, and their name
  const std::string names = config.GetString("waw", "character_names");
  for (size_t start = 0; start < names.size();) {
    size_t end = names.find(',', start);
    if (end == std::string::npos) end = names.size();
    const std::string one = names.substr(start, end - start);
    start = end + 1;
    const size_t equals = one.find('=');
    if (equals == std::string::npos) continue;
    const int who = std::atoi(one.substr(0, equals).c_str());
    const size_t from = one.find_first_not_of(" \t", equals + 1), to = one.find_last_not_of(" \t");
    if (who > 0 && from != std::string::npos && to >= from) s.characterNames.emplace_back(who, one.substr(from, to - from + 1));
  }
  s.haveMaxHealth = config.GetAddress("waw", "max_health", s.maxHealth);
  s.playerHealth = config.GetInt("waw", "player_health", 0);
  s.havePlayerFlags = config.GetAddress("waw", "player_flags", s.playerFlags);
  s.godAtStart = config.GetInt("debug", "god_at_start", 0) != 0;
  s.haveDrawGun = config.GetAddress("waw", "draw_gun", s.drawGun);
  s.haveView = config.GetAddress("waw", "view_origin", s.viewOrigin) &&
               config.GetAddress("waw", "view_axis", s.viewAxis);
  s.haveThirdPerson = config.GetAddress("waw", "third_person", s.thirdPerson);
  s.hideBody = LoadPlaces(config, "hide_body");
  s.haveKitField = config.GetAddress("waw", "kit_field", s.kitField);
  s.haveScriptsSay = config.GetAddress("waw", "scripts_say", s.scriptsSay);
  s.haveWeaponState = config.GetAddress("waw", "weapon_state", s.weaponState);
  s.havePaused = config.GetAddress("waw", "paused", s.paused);

  const auto states = [&config](const char* key, const char* otherwise) {
    std::vector<int> list;
    const std::string text = config.GetString("waw", key, otherwise);
    for (const char* p = text.c_str(); *p;) {
      char* end = nullptr;
      const long state = std::strtol(p, &end, 0);
      if (end == p) {
        ++p;
      } else {
        list.push_back(static_cast<int>(state));
        p = end;
      }
    }
    return list;
  };
  s.knifeStates = states("knife_states", "");
  s.reloadStates = states("reload_states", "7, 8, 9, 10, 11");
  s.sprintStates = states("sprint_states", "23, 24");
  s.haveStance = config.GetAddress("waw", "stance", s.stance);
  s.haveViewKick = config.GetAddress("waw", "view_kick", s.viewKick);
  s.haveGunAngles = config.GetAddress("waw", "gun_angles", s.gunAngles);
  s.haveAimField = config.GetAddress("waw", "aim_field", s.aimField);
  s.aimMark = config.GetInt("waw", "aim_mark", 0) != 0;
  s.haveViewAngle = config.GetAddress("waw", "third_person_angle", s.viewAngle);
  s.gunViewAngle = config.GetFloat("waw", "gun_view_angle", 0.0f);
  s.haveJumpHeight = config.GetAddress("waw", "jump_height", s.jumpHeight);
  // "1 = 107, 2 = 75": a kit, and the height for it
  const std::string heights = config.GetString("waw", "jump_heights");
  for (const char* p = heights.c_str(); *p;) {
    int kit = 0, used = 0;
    float height = 0;
    if (std::sscanf(p, " %d = %f%n", &kit, &height, &used) == 2 && height >= 10.0f && height <= 400.0f) {
      s.jumpHeights.emplace_back(kit, height);
      p += used;
    }
    while (*p && *p != ',') ++p;
    if (*p == ',') ++p;
  }
  s.haveHintJump = config.GetAddress("waw", "hint_jump", s.hintJump);
  if (config.GetAddress("waw", "settings_table", s.settingsTable)) {
    s.settingsTableSize = static_cast<uint32_t>(std::strtoul(config.GetString("waw", "settings_table_size", "0x180000").c_str(), nullptr, 0));
  }
  s.crosshairSetting = config.GetString("waw", "crosshair_setting");
  s.ammoSetting = config.GetString("waw", "ammo_setting");
  s.footstepsSetting = config.GetString("waw", "footsteps_setting");
  s.quietKits = states("quiet_kits", "");
  s.crouchBit = static_cast<uint32_t>(config.GetInt("waw", "crouch_bit", 0x4));
  s.haveHeadCall = config.GetAddress("waw", "head_call", s.headCall) && config.GetAddress("waw", "head_routine", s.headRoutine);
  s.headEntityOrigin = config.GetInt("waw", "head_entity_origin", s.headEntityOrigin);
  s.haveGround = config.GetAddress("waw", "ground", s.ground);
  s.groundNone = config.GetInt("waw", "ground_none", 1023);
  s.logWeaponState = config.GetInt("debug", "log_weapon_state", 0) != 0;
  const auto source = [](const std::vector<AddressSpec>& places, const char* fallback) {
    return places.empty() ? fallback : "the game's own record";
  };
  log::Info("buttons for SWBF2: fire from %s, aim from %s, reload from %s, ability from %s%s",
            source(s.heldFire, "the left mouse button"), source(s.heldAim, "the right mouse button"),
            source(s.heldReload, "the R key"), source(s.heldAbility, "the G key"),
            s.forwardButtons ? "" : " (forward_buttons = 0: none are sent)");
  log::Info("the next ability: key 0x%X, controller buttons 0x%X (0: none)", static_cast<unsigned>(s.nextAbilityKey),
            static_cast<unsigned>(s.nextAbilityPad));
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
bool g_fromBehind = false;       // guarded by g_mutex; this game is being drawn from behind the player
bool g_handsBusy = false;        // guarded by g_mutex; the scripts say the player's hands are doing something of WaW's own
float g_aimFar = 0;              // guarded by g_mutex; how far along the line through the middle of the screen the first thing is, in units (from the scripts); 0 = nothing to aim
std::atomic<uint32_t> g_frames{0};
std::atomic<bool> g_crouched{false};       // the player is crouched (for SteadyHead, which runs on the game's own thread)
std::atomic<int> g_headEntityOrigin{0x24};

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
                 {kWawButtonReload, s.heldReload, 'R'},
                 {kWawButtonAbility, s.heldAbility, 'G'},
                 {kWawButtonJump, s.heldJump, VK_SPACE}};
  uint32_t held = 0;
  for (const auto& button : buttons) {
    const bool down = button.places.empty() ? inFront && (GetAsyncKeyState(button.fallbackKey) & 0x8000) != 0
                                            : AnyHeld(button.places);
    if (down) held |= button.bit;
  }
  // "The next ability" is nothing WaW has an action for, so there is no
  // record of it to read: the key and the controller are looked at directly.
  if (inFront && ((s.nextAbilityKey && (GetAsyncKeyState(s.nextAbilityKey) & 0x8000) != 0) ||
                  (s.nextAbilityPad && (pad::Buttons() & s.nextAbilityPad) != 0))) {
    held |= kWawButtonNextAbility;
  }
  // A jump is passed on only when it is one: pressed while the player stands
  // upright on something. Pressed again in the air it does nothing here, and
  // SWBF2's heroes would jump a second time off nothing; pressed while
  // crouched it only stands the player up.
  static bool jumpWas = false, jumpCounts = true;
  const bool jump = (held & kWawButtonJump) != 0;
  if (jump && !jumpWas) {
    int32_t on = 0;
    uint32_t flags = 0;
    const uintptr_t groundAt = s.haveGround ? mem::Resolve(s.ground) : 0;
    const uintptr_t stanceAt = s.haveStance ? mem::Resolve(s.stance) : 0;
    const bool inAir = groundAt && mem::Read(groundAt, &on, sizeof(on)) && on == s.groundNone;
    const bool crouched = stanceAt && mem::Read(stanceAt, &flags, sizeof(flags)) && (flags & s.crouchBit) != 0;
    jumpCounts = !inAir && !crouched;
  }
  jumpWas = jump;
  if (jump && !jumpCounts) held &= ~static_cast<uint32_t>(kWawButtonJump);
  return held;
}

// One gun on screen, not two: while SWBF2's weapon is being drawn over the
// picture, WaW's own is switched off (its cg_drawGun setting), and it comes
// back if SWBF2's picture stops arriving. WaW's gun is otherwise untouched:
// it still fires, and whatever the player sets cg_drawGun to themselves is
// left alone while there is no overlay. Call with g_mutex held.
void HideGun(bool knifing) {
  static bool hiding = false;
  const bool hide = overlay::Drawing() && !knifing;
  if (!g_settings.haveDrawGun || (!hide && !hiding)) return;
  const uintptr_t address = mem::Resolve(g_settings.drawGun);
  if (!address) return;  // the game has not made the setting yet
  const uint8_t wanted = hide ? 0 : 1;
  uint8_t now = wanted;
  if (mem::Read(address, &now, sizeof(now)) && now != wanted) mem::Write(address, &wanted, sizeof(wanted));
  if (hide != hiding && !knifing) log::Info(hide ? "hiding WaW's own gun while SWBF2's is drawn" : "showing WaW's own gun again");
  hiding = hide;
}

// The knife. A character with a gun still has WaW's knife, and SWBF2 has no
// picture of one being used. So for as long as the player's weapon is in one
// of the game's knife states, WaW's own arms and blade are shown and SWBF2's
// picture stands aside. Only through the player's eyes: from behind there is
// nothing of WaW's to show (its soldier is hidden), and the character simply
// does not move for it. Call with g_mutex held.
bool Knifing() {
  static int32_t last = -1;
  static bool was = false;
  const Settings& s = g_settings;
  int32_t state = -1;
  const uintptr_t address = s.haveWeaponState ? mem::Resolve(s.weaponState) : 0;
  if (!address || !mem::Read(address, &state, sizeof(state))) return false;
  if (s.logWeaponState && state != last) log::Info("[debug] log_weapon_state: %ld -> %ld", static_cast<long>(last), static_cast<long>(state));
  last = state;
  BfPlayerState bf{};
  const bool behind = g_block && g_block->bf.read(bf) && (bf.flags & kBfThirdPerson) != 0;
  // The same for anything else WaW's own hands do, which the scripts say:
  // the bottle a perk is drunk from, the knuckles cracked at Pack-a-Punch.
  const bool knifing = !behind && (g_handsBusy || std::find(s.knifeStates.begin(), s.knifeStates.end(), static_cast<int>(state)) != s.knifeStates.end());
  if (knifing != was && overlay::Drawing()) log::Info(knifing ? "knife: showing WaW's own hands while they are used" : "knife: done");
  was = knifing;
  return knifing;
}

// Third person. When SWBF2 shows the player's character from behind, this
// game has to draw from behind the player too, or the character is drawn
// standing in front of a camera that is still in the player's eyes. Two
// things are switched together, and switched back together:
//
// - cg_thirdPerson, the game's own camera behind the player. Where exactly it
//   ends up (it comes in when a wall is behind the player) is published like
//   everything else, and SWBF2 draws from the same place.
// - The player's own soldier, which that camera would otherwise show, where
//   SWBF2's character is about to be drawn. The game's script function
//   hide() does it by setting one bit in the entity's flags and in the
//   player's, and nothing clears it but show(); the same bit is set here.
//
// Only while SWBF2's picture is really arriving: a player left looking at the
// back of nobody would be worse than either view. Call with g_mutex held.
const uint32_t kHidden = 0x20;

void ThirdPerson() {
  static bool on = false;
  BfPlayerState bf{};
  const bool want = g_block && overlay::Drawing() && g_block->bf.read(bf) && (bf.flags & kBfThirdPerson) != 0;
  if (!g_settings.haveThirdPerson || (!want && !on)) return;
  const uintptr_t setting = mem::Resolve(g_settings.thirdPerson);
  if (!setting) return;  // the game has not made the setting yet
  const int32_t wanted = want ? 1 : 0;
  int32_t now = wanted;
  if (mem::Read(setting, &now, sizeof(now)) && now != wanted) mem::Write(setting, &wanted, sizeof(wanted));
  for (const AddressSpec& place : g_settings.hideBody) {
    const uintptr_t address = mem::Resolve(place);
    uint32_t flags = 0;
    if (!address || !mem::Read(address, &flags, sizeof(flags))) continue;
    const uint32_t changed = want ? (flags | kHidden) : (flags & ~kHidden);
    if (changed != flags) mem::Write(address, &changed, sizeof(changed));
  }
  // Being hit throws the view about (the number behind bg_viewKickScale is how
  // far, for each point of damage; the game will not let a script change it).
  // From behind the character that is only a nuisance, so there it is kept at
  // nothing, and put back when the view returns to the player's eyes. (It was
  // first taken for the kick of the player's own shots, which it is not.)
  static float kickWas = 0;
  const uintptr_t kickAt = g_settings.haveViewKick ? mem::Resolve(g_settings.viewKick) : 0;
  float kick = 0;
  if (kickAt && mem::Read(kickAt, &kick, sizeof(kick))) {
    if (want && kick != 0.0f) {
      if (kick > 0.0f && kick < 10.0f) kickWas = kick;
      const float none = 0.0f;
      mem::Write(kickAt, &none, sizeof(none));
    } else if (!want && on && kick == 0.0f && kickWas > 0.0f) {
      mem::Write(kickAt, &kickWas, sizeof(kickWas));
    }
  }
  // Where the camera sits. The game puts it straight behind the player's
  // head, looking the way they look: the middle of the screen is the back of
  // the character's head. That does for a lightsaber. For a character with
  // something to aim, the camera is moved to one side (the number behind
  // cg_thirdPersonAngle), so the character stands left of the middle and the
  // crosshair is clear of it. (g_aimFar is not zero exactly when the scripts
  // say there is something to aim.)
  const uintptr_t angleAt = g_settings.haveViewAngle ? mem::Resolve(g_settings.viewAngle) : 0;
  float angle = 0;
  if (angleAt && mem::Read(angleAt, &angle, sizeof(angle))) {
    float round = want && g_aimFar > 0 ? g_settings.gunViewAngle : 0.0f;
    if (round < 0) round += 360.0f;
    if (std::fabs(angle - round) > 0.01f && (want || on)) mem::Write(angleAt, &round, sizeof(round));
  }
  if (want != on) log::Info(want ? "third person: drawing from behind the player, without WaW's own soldier" : "third person: off");
  on = want;
  g_fromBehind = want;
}

// Tells the game's scripts which kit SWBF2's character carries, so that they
// can hand the player the weapons that match (waw/mod/scripts has them).
//
// Scripts cannot read shared memory, and this bridge cannot call a script.
// What both can reach is the player's entity: the game lets a script read and
// write a handful of numbers on any entity by name, and one of them, "count",
// means nothing on a player. The bridge writes the kit there and the script
// reads self.count. Where each of those numbers sits in an entity is in the
// game's own table of them (docs/PHASE3.md).
//
// With SWBF2 gone it is 0, "not known", and the scripts leave the player with
// what they have.
//
// The same number carries the character's abilities, which are SWBF2's to
// work: which one is selected, whether it is in use this moment, and how many
// times one has been used, so that the scripts can do to the zombies what
// SWBF2 is showing. And it carries each use of the weapon in hand, which for
// a lightsaber is a swing: the blade cuts in WaW only while SWBF2's character
// is swinging it. From the low end: five bits of kit, three of which ability,
// one of "the ability is in use", one of "the weapon is in use", eight of the
// count of the ability's uses and seven of the weapon's (both go round at
// 128; the scripts only look for a change), and four of how far the weapon
// was charged when it was last fired (0 to 15). Call with g_mutex held.
void TellKit() {
  static int32_t toldKit = -1, toldAbility = -1;
  if (!g_settings.haveKitField || !g_block) return;
  BfPlayerState bf{};
  const bool have = overlay::Drawing() && g_block->bf.read(bf);
  const int32_t kit = have ? static_cast<int32_t>(bf.kit & 31) : 0;
  const int32_t ability = have ? static_cast<int32_t>(bf.ability & 7) : 0;
  // And one bit of the player's own: the button that changes between a
  // weapon and what is fitted to it (Boba Fett's rifle and its flamethrower)
  // is held. The game has an action of its own for this, but with that
  // action in use it shows the fitted weapon at the bottom of the screen, and
  // nothing the bridge can reach hides that on a PC; so the action is left
  // idle, and the key and the controller button are looked at directly, as
  // for "the next ability", while WaW is the window in front.
  DWORD foreground = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &foreground);
  const bool fitted = have && foreground == GetCurrentProcessId() &&
                      ((g_settings.fittedKey && (GetAsyncKeyState(g_settings.fittedKey) & 0x8000) != 0) ||
                       (g_settings.fittedPad && (pad::Buttons() & g_settings.fittedPad) != 0));
  const int32_t says = !have ? 0
                             : kit | (ability << 5) | ((bf.flags & kBfAbilityInUse) ? 1 << 8 : 0) |
                                   ((bf.flags & kBfWeaponInUse) ? 1 << 9 : 0) |
                                   static_cast<int32_t>((bf.abilityUses & 0x7F) << 10) |
                                   static_cast<int32_t>((bf.weaponUses & 0x7F) << 17) |
                                   (static_cast<int32_t>(std::min(1.0f, std::max(0.0f, bf.weaponCharge)) * 15.0f + 0.5f) << 24) |
                                   (fitted ? 1 << 28 : 0);
  const uintptr_t address = mem::Resolve(g_settings.kitField);
  int32_t now = says;
  if (!address || !mem::Read(address, &now, sizeof(now))) return;
  if (now != says) mem::Write(address, &says, sizeof(says));
  if (kit != toldKit) log::Info("kit: telling the scripts SWBF2's character carries kit %ld", static_cast<long>(kit));
  if (ability != toldAbility) log::Info("kit: telling the scripts the ability selected is weapon %ld", static_cast<long>(ability));
  toldKit = kit;
  toldAbility = ability;
}

// What the scripts say back, on another of the player's numbers ("dmg", which
// like "count" means nothing on a player): which of the character's weapons
// is in hand (two bits: 1, 2, or 0 for not known), whether the ability may be
// used (a bit), whether the weapon in hand has run dry (a bit), and the
// rounds in its magazine and how many it holds (eight bits each; a size of 0
// is a weapon SWBF2 is not to follow). SWBF2 keeps its own weapon in step
// with all of it. Above those, eleven bits of how far along the line through
// the middle of the screen the first thing is, in steps of 2 units (0: nothing
// to aim, or not from behind), which is for Aim.

void HearScripts(const Settings& s, WawPlayerState& next) {
  next.weapon = next.clip = next.clipSize = 0;
  g_aimFar = 0;
  g_handsBusy = false;
  int32_t says = 0;
  const uintptr_t address = s.haveScriptsSay ? mem::Resolve(s.scriptsSay) : 0;
  if (!address || !mem::Read(address, &says, sizeof(says)) || says < 0) return;
  g_aimFar = static_cast<float>((says >> 20) & 0x7FF) * 2.0f;
  next.weapon = static_cast<uint32_t>(says & 3);
  // 3 is neither weapon: the player's own hands are busy with something of
  // WaW's (drinking a perk, cracking their knuckles at the Pack-a-Punch).
  // SWBF2 is told "not known", is not to fire meanwhile, and its picture
  // stands aside for WaW's hands as it does for the knife (Knifing).
  g_handsBusy = next.weapon == 3;
  if (g_handsBusy) {
    next.weapon = 0;
    next.buttons &= ~static_cast<uint32_t>(kWawButtonFire | kWawButtonAim | kWawButtonAbility | kWawButtonReload | kWawButtonNextAbility);
  }
  if (says & 4) next.flags |= kWawAbilityReady;
  if (says & 8) next.flags |= kWawDry;
  next.clip = static_cast<uint32_t>((says >> 4) & 0xFF);
  next.clipSize = static_cast<uint32_t>((says >> 12) & 0xFF);
}

// What the player is doing, from the game itself: reloading or sprinting (its
// weapon is in a state that says so), and crouched (a bit in the player's
// flags). SWBF2's character does the same.
void ReadPosture(const Settings& s, WawPlayerState& next) {
  int32_t state = -1;
  const uintptr_t stateAt = s.haveWeaponState ? mem::Resolve(s.weaponState) : 0;
  if (stateAt && mem::Read(stateAt, &state, sizeof(state))) {
    const auto in = [state](const std::vector<int>& states) {
      return std::find(states.begin(), states.end(), static_cast<int>(state)) != states.end();
    };
    if (in(s.reloadStates)) next.flags |= kWawReloading;
    if (in(s.sprintStates)) next.flags |= kWawSprinting;
  }
  uint32_t flags = 0;
  const uintptr_t stanceAt = s.haveStance ? mem::Resolve(s.stance) : 0;
  if (stanceAt && mem::Read(stanceAt, &flags, sizeof(flags)) && (flags & s.crouchBit)) next.flags |= kWawCrouching;
  g_crouched.store((next.flags & kWawCrouching) != 0, std::memory_order_relaxed);
  static uint32_t said = ~0u;
  const uint32_t now = next.flags & (kWawCrouching | kWawSprinting);
  if (now != said) {
    said = now;
    log::Info("posture: %s%s (the player's flags read 0x%X)", (now & kWawCrouching) ? "crouched" : "standing",
              (now & kWawSprinting) ? ", sprinting" : "", static_cast<unsigned>(flags));
  }
}

// A camera that does not ride on a soldier nobody can see.
//
// In third person this game hangs its camera on the head of the player's
// soldier: it asks where the bone "j_head" is, and works out the camera from
// there. The soldier is hidden, SWBF2's character being drawn in its place,
// but it is still standing there breathing, shifting its weight, bobbing as
// it runs and ducking as it reloads, and the whole picture went with its head:
// some 9 units from side to side and 4 up and down with the player standing
// still.
//
// So the answer to that one question is changed: the call that asks is sent
// through here (callhook::InstallAfter), and the head is said to be straight
// above the place the soldier is drawn at, at the height of the player's eyes
// (60 units, 40 crouched, taken a tenth of a second or so to change between).
// The place is the game's own smooth one, frame by frame, not the twenty-a-
// second position the bridge reads elsewhere. Runs on the game's thread.
void __cdecl SteadyHead(void** arguments) {
  if (!reinterpret_cast<const uint32_t*>(arguments)[-1]) return;  // no such bone: the game gives up as well
  const auto* entity = static_cast<const unsigned char*>(arguments[0]);
  auto* head = static_cast<float*>(arguments[2]);
  if (!entity || !head) return;
  float feet[3];
  std::memcpy(feet, entity + g_headEntityOrigin.load(std::memory_order_relaxed), sizeof(feet));
  // Only if the head is roughly over that place. Anything else, and this is
  // not the call it was taken for.
  const float dx = head[0] - feet[0], dy = head[1] - feet[1], dz = head[2] - feet[2];
  if (!(dx * dx + dy * dy < 80.0f * 80.0f) || !(dz > -10.0f && dz < 110.0f)) return;
  static float height = 60.0f;
  static DWORD last = 0;
  const DWORD now = GetTickCount();
  const float want = g_crouched.load(std::memory_order_relaxed) ? 40.0f : 60.0f;
  const float part = last ? std::min(1.0f, static_cast<float>(now - last) / 100.0f) : 1.0f;
  height += (want - height) * part;
  last = now;
  head[0] = feet[0];
  head[1] = feet[1];
  head[2] = feet[2] + height;
}

// Sends that call through SteadyHead, once, if the settings say where it is
// and the call there is the one expected. (Asked again a few times if it is
// not: the game's code may not all be in place the moment this is loaded.)
void SteadyCamera(const Settings& s) {
  static int tries = 0;
  static bool done = false;
  if (done || tries >= 20 || !s.haveHeadCall) return;
  ++tries;
  const uintptr_t site = mem::Resolve(s.headCall), routine = mem::Resolve(s.headRoutine);
  unsigned char expected[5] = {0xE8};
  const int32_t distance = static_cast<int32_t>(routine - (site + 5));
  std::memcpy(expected + 1, &distance, sizeof(distance));
  g_headEntityOrigin.store(s.headEntityOrigin, std::memory_order_relaxed);
  if (site && routine && callhook::InstallAfter(site, expected, &SteadyHead)) {
    done = true;
    log::Info("camera: in third person it no longer rides on the hidden soldier's head");
  } else if (tries == 20) {
    log::Error("[waw] head_call: the call there is not the one to head_routine; the camera is left on the soldier's head");
  }
}

// "Press F to ..." from behind the character. The game works out what the
// player could use (a door, a wall that sells something) wherever its camera
// is, but the routine that passes that on to the screen gives up at once
// when the view is third person: two instructions, "is the view from behind?
// then go to the end" (CoDWaW.exe+0x51130; the hint is not shown and nothing
// says why). The second of them, a two-byte jump, is taken out, once, if the
// settings say where it is and it is the jump expected.
void ShowHints(const Settings& s) {
  static int tries = 0;
  static bool done = false;
  if (done || tries >= 20 || !s.haveHintJump) return;
  ++tries;
  const uintptr_t at = mem::Resolve(s.hintJump);
  unsigned char now[2] = {};
  if (at && mem::Read(at, now, sizeof(now)) && now[0] == 0x75 && now[1] == 0x40) {
    DWORD old = 0;
    if (VirtualProtect(reinterpret_cast<void*>(at), 2, PAGE_EXECUTE_READWRITE, &old)) {
      const unsigned char nothing[2] = {0x90, 0x90};
      std::memcpy(reinterpret_cast<void*>(at), nothing, sizeof(nothing));
      VirtualProtect(reinterpret_cast<void*>(at), 2, old, &old);
      FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(at), 2);
      done = true;
      log::Info("hints: what the player can use is said on the screen from behind the character as well");
    }
  } else if (at && now[0] == 0x90 && now[1] == 0x90) {
    done = true;  // already out
  } else if (tries == 20) {
    log::Error("[waw] hint_jump: what is there is not the jump expected; no hints from behind the character");
  }
}

// The scoreboard, played alone. What the "scores" button brings up is decided
// in the game's code by whether the game is an online one: if it is, the
// scoreboard the players of a co-op game see (names, points, kills, downs,
// revives, headshots); if not, "Mission Objectives", which zombies has none
// of. Two places decide it, each a short jump on the game's "onlinegame"
// setting: the routine that brings the objectives up while the button is held
// (CoDWaW.exe+0x379D0) and the one that draws the scoreboard
// (CoDWaW.exe+0x2680B0). Both jumps are changed, so that alone, too, the
// button brings up the scoreboard and not the objectives. The setting itself
// is left alone: far more than this hangs on it.
//
// The settings give each change as a place, the bytes expected there and the
// bytes to put ([waw] scoreboard_alone); nothing is changed unless every
// place holds what is expected (or has been changed already).
//
// And one more change of the same kind, for the name the bridge gives the
// player (NameCharacter, below). The game says "... renamed to ..." at the
// top of the screen whenever a player's name changes, which here is every
// change of character; the user asked for that to go. Where the game takes in
// a player's details and finds a new name, it says so unless the old name was
// empty (CoDWaW.exe+0x27373D); the jump that skips the saying is made to be
// taken always ([waw] quiet_rename). The name is still taken in.
struct ChangesMade {
  int tries = 0;
  bool done = false;
};

// True once every change in the list is in the game's code.
bool ChangeCode(const std::vector<CodeChange>& changes, const char* key, ChangesMade& made) {
  if (made.done) return true;
  if (made.tries >= 20 || changes.empty()) return false;
  ++made.tries;
  std::vector<uintptr_t> places;
  for (const CodeChange& change : changes) {
    const uintptr_t at = mem::Resolve(change.at);
    std::vector<unsigned char> now(change.before.size());
    if (!at || !mem::Read(at, now.data(), now.size()) || (now != change.before && now != change.after)) {
      if (made.tries == 20) log::Error("[waw] %s: what is at one of the places is not what was expected; the game's code is left as it is", key);
      return false;
    }
    places.push_back(now == change.after ? 0 : at);
  }
  for (size_t i = 0; i < places.size(); ++i) {
    const std::vector<unsigned char>& bytes = changes[i].after;
    DWORD old = 0;
    if (!places[i] || !VirtualProtect(reinterpret_cast<void*>(places[i]), bytes.size(), PAGE_EXECUTE_READWRITE, &old)) continue;
    std::memcpy(reinterpret_cast<void*>(places[i]), bytes.data(), bytes.size());
    VirtualProtect(reinterpret_cast<void*>(places[i]), bytes.size(), old, &old);
    FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(places[i]), bytes.size());
  }
  made.done = true;
  return true;
}

void ScoreboardAlone(const Settings& s) {
  static ChangesMade scoreboard, rename;
  const bool had = scoreboard.done, hadQuiet = rename.done;
  if (ChangeCode(s.scoreboardAlone, "scoreboard_alone", scoreboard) && !had) {
    log::Info("scores: played alone, the scores button brings up the scoreboard a co-op game has (%zu changes to the game's code)", s.scoreboardAlone.size());
  }
  if (ChangeCode(s.quietRename, "quiet_rename", rename) && !hadQuiet) {
    log::Info("name: the game no longer says so on the screen when the player's name changes");
  }
}

// A line for the game's console, as if it had been typed there: the game's
// own routine for adding one (CoDWaW.exe+0x194200). It takes the text in one
// register and which player's console in another, not in the usual way, so
// it is called by hand. It keeps to itself behind a lock of the game's, and
// can be called from any thread.
void Console(uintptr_t routine, const char* text) {
  __asm {
    mov eax, text
    xor ecx, ecx
    call routine
  }
}

// The player's name is the character's. The game shows the player's name on
// its scoreboard, and played alone that is "Unknown Soldier" or whatever the
// player goes by; the user wanted whoever they are playing at the moment.
// SWBF2's side says who that is, as a number (several characters share a
// kit), the settings have the name that goes with each number, and the name
// is changed the way the player could change it: "name ..." in the console.
// The game does the rest (it tells its own server half, which tells
// everything that shows names). What the player was called before is read
// from the game first and put back when SWBF2 goes away.
void NameCharacter(const Settings& s, const SharedBlock* block, bool swbf2Alive) {
  static uint32_t named = 0;
  static std::string before;
  const uintptr_t console = s.haveConsole ? mem::Resolve(s.console) : 0;
  if (!console || s.characterNames.empty() || !block) return;
  // Only with a player in a map. The place the name is read from is reached
  // through the player's own record, which is there from when they are put
  // into a map and not before; and the console is not to be given anything
  // while the game is still starting up (it was, once, sixteen thousandths of
  // a second after this was loaded, and the game went down with it).
  char was[33] = {};
  const uintptr_t at = s.havePlayerName ? mem::Resolve(s.playerName) : 0;
  if (!at || !mem::Read(at, was, sizeof(was) - 1) || !was[0]) return;
  BfPlayerState bf{};
  const uint32_t who = swbf2Alive && block->bf.read(bf) ? bf.who : 0;
  if (who == named) return;
  std::string name;
  if (who) {
    for (const auto& one : s.characterNames) {
      if (one.first == static_cast<int>(who)) name = one.second;
    }
    if (name.empty()) return;  // nobody the settings have a name for: the player keeps the one they have
    if (!named) before = was;
  } else {
    name = before;
  }
  // Nothing that would end the name early or begin another command.
  name.erase(std::remove_if(name.begin(), name.end(), [](unsigned char c) { return c < 32 || c == '"' || c == ';' || c == '\\'; }), name.end());
  if (!name.empty()) {
    const std::string line = "name \"" + name + "\"\n";
    Console(console, line.c_str());
    log::Info("name: the player is called %s%s", name.c_str(), who ? "" : " again");
  }
  named = who;
}

// More for the player to take: 200 where the game gives 100, so that a
// zombie's fourth blow is the one that puts them down, not its second.
//
// The game takes the figure from its setting g_player_maxhealth each time it
// puts a player into a map, and writes it in three places: the player's
// health, the most their entity can have, and the most their client record
// says they can have. The last is the one it gets a player back to after a
// blow (CoDWaW.exe+0x11C778, behind the scripts' SetNormalHealth), and no
// script can change it: the scripts' own "maxhealth" is the second. With only
// that one raised, as it first was, the game "healed" a player on 150 of 200
// down to 100, and one on 50 down to 25 and on down, and left them there.
//
// So the setting itself is kept at the figure wanted, from before the map is
// loaded: looked at every time round, since the game makes the setting when
// it starts loading a map and puts the player in some seconds later. It is
// reached through the game's own pointer to it, which does not move.
void MoreHealth(const Settings& s) {
  static int told = 0;
  if (!s.haveMaxHealth || s.playerHealth <= 0) return;
  const uintptr_t at = mem::Resolve(s.maxHealth);
  int32_t now = 0;
  if (!at || !mem::Read(at, &now, sizeof(now)) || now == s.playerHealth || now <= 0) return;
  const int32_t want = s.playerHealth;
  if (mem::Write(at, &want, sizeof(want)) && told != want) {
    told = want;
    log::Info("health: a player put into a map from now on has %ld (the game's own: %ld)", static_cast<long>(want), static_cast<long>(now));
  }
}

// For testing: the player begins each map unable to be hurt, exactly as if
// "god" had been typed into the console, so that typing it there turns it off,
// and on again. The console's "god" flips the lowest of the switches the game
// keeps on the player's entity (CoDWaW.exe+0xF4420: "xor [entity+0x1B4], 1"),
// and so does this, once for each time the player is put into a map.
//
// The game sets those switches afresh whenever it puts a player into a map
// (to 0x800), so a switch of this bridge's own among them, one the game's code
// never looks at, says "seen to already": it is gone again after the next
// map, or the same map started over, and at no other time. Nothing is done
// while the switches read 0: no player is there yet.
//
// (This was first the scripts' doing, with what they have for it,
// EnableInvulnerability. That is another switch, kept somewhere else, and
// nothing typed into the console could turn it off.)
const uint32_t kGodSwitch = 0x1, kSeenSwitch = 0x40000000;

void GodAtStart(const Settings& s) {
  if (!s.godAtStart || !s.havePlayerFlags) return;
  const uintptr_t at = mem::Resolve(s.playerFlags);
  uint32_t switches = 0;
  if (!at || !mem::Read(at, &switches, sizeof(switches)) || switches == 0 || (switches & kSeenSwitch)) return;
  switches |= kGodSwitch | kSeenSwitch;
  if (mem::Write(at, &switches, sizeof(switches))) {
    log::Info("[debug] god_at_start: the player begins unable to be hurt (\"god\" in the console turns it off)");
  }
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
  HearScripts(s, next);
  ReadPosture(s, next);
  // The camera: where the picture was last drawn from. The axis is three
  // directions of length one, forward, left and up; if the forward one is not
  // of length one the address is wrong.
  float axis[9];
  if (s.haveView && mem::ReadFloat3(mem::Resolve(s.viewOrigin), next.cameraOrigin) &&
      mem::Read(mem::Resolve(s.viewAxis), axis, sizeof(axis)) &&
      std::fabs(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2] - 1.0f) < 0.01f) {
    std::memcpy(next.cameraForward, axis, sizeof(next.cameraForward));
    std::memcpy(next.cameraUp, axis + 6, sizeof(next.cameraUp));
    next.flags |= kWawCameraValid;
    // Recoil is this game's to give. The angles above are where the player
    // is aiming before a shot has kicked the view; the camera is where the
    // view really points, kick and all, and it is where this game's shots
    // go. So through the player's eyes SWBF2 is told the camera's angles,
    // and its weapon and its bolts go with WaW's recoil. (From behind, the
    // camera is somewhere else and looks slightly elsewhere.)
    if (!g_fromBehind && (next.flags & kWawAnglesValid)) {
      next.viewAngles[0] = -std::asin(std::min(1.0f, std::max(-1.0f, axis[2]))) * 57.2957795f;
      next.viewAngles[1] = std::atan2(axis[1], axis[0]) * 57.2957795f;
    }
  }
  const bool same = next.flags == g_state.flags && next.buttons == g_state.buttons && next.weapon == g_state.weapon &&
                    next.clip == g_state.clip && next.clipSize == g_state.clipSize &&

                    std::memcmp(next.origin, g_state.origin, sizeof(next.origin)) == 0 &&
                    std::memcmp(next.viewAngles, g_state.viewAngles, sizeof(next.viewAngles)) == 0 &&
                    std::memcmp(next.tanHalfFov, g_state.tanHalfFov, sizeof(next.tanHalfFov)) == 0 &&
                    std::memcmp(next.cameraOrigin, g_state.cameraOrigin, sizeof(next.cameraOrigin)) == 0;
  if (same && g_state.frame != 0 && ElapsedUs(g_state.timeUs, next.timeUs) < 50000) return;
  ++next.frame;
  g_state = next;
  g_block->waw.write(g_state);
}

// Jumps. SWBF2's character jumps when WaW's player does, and the two fall at
// very nearly the same rate (SWBF2's gravity is 19.3 metres a second a second
// against WaW's 20.3), but they do not jump the same height: a WaW player
// rises 39 units, a metre, and is down again while a SWBF2 trooper, who
// jumps 1.8 m, is still in the air, and a Jedi, who jumps 3.4 m, has barely
// started. So WaW's jump is made the character's: the number behind
// jump_height is set, by kit, to the height that keeps WaW's player off the
// ground exactly as long as SWBF2's character. It is put back when SWBF2
// goes away. Call with g_mutex held.
void MatchJump() {
  static float original = 0, ours = 0;
  if (!g_settings.haveJumpHeight || !g_block) return;
  const uintptr_t at = mem::Resolve(g_settings.jumpHeight);
  float now = 0;
  if (!at || !mem::Read(at, &now, sizeof(now)) || now < 1.0f || now > 1000.0f) return;
  if (now != ours) original = now;  // the game's own, or the player's from the console
  BfPlayerState bf{};
  float want = original;
  if (overlay::Drawing() && g_block->bf.read(bf)) {
    for (const auto& kit : g_settings.jumpHeights) {
      if (kit.first == static_cast<int>(bf.kit & 31)) want = kit.second;
    }
  }
  if (want > 0 && want != now && mem::Write(at, &want, sizeof(want))) {
    ours = want == original ? 0 : want;
    static float said = 0;
    if (want != said) log::Info("jump: the player now jumps %.0f units high (the game's own is %.0f)", want, original);
    said = want;
  }
}

// Where one of the game's own settings keeps its value, found by the
// setting's name. The game keeps them all in one table, a record each, the
// record beginning with a pointer to the name and holding the value sixteen
// bytes in. Most of the settings this bridge touches are reached through a
// pointer the game itself keeps to the record, which never moves. For these
// no such pointer is known, and a record's place in the table depends on how
// many settings were made before it: start the game with one more "+set" and
// every later one is a record further on (found the hard way: the three were
// first written as plain addresses, and a new option for testing moved them
// all onto their neighbours). So the table is looked through for the name,
// once, and the answer checked each time it is used. 0 until it is found;
// looked for again every couple of seconds at most.
struct NamedSetting {
  std::string name;
  uintptr_t record = 0;
  uint32_t namePointer = 0;
  DWORD lookedAt = 0;
};

uintptr_t ValueOf(NamedSetting& setting, const std::string& name) {
  if (name.empty() || !g_settings.settingsTableSize) return 0;
  if (setting.name != name) setting = NamedSetting{name};
  uint32_t pointer = 0;
  if (setting.record && mem::Read(setting.record, &pointer, sizeof(pointer)) && pointer == setting.namePointer) {
    return setting.record + 0x10;
  }
  const DWORD now = GetTickCount();
  if (setting.lookedAt && now - setting.lookedAt < 2000) return 0;
  setting.lookedAt = now | 1;
  setting.record = mem::FindRecordNamed(mem::Resolve(g_settings.settingsTable), g_settings.settingsTableSize, name.c_str());
  if (!setting.record || !mem::Read(setting.record, &setting.namePointer, sizeof(setting.namePointer))) {
    setting.record = 0;
    return 0;
  }
  log::Info("settings: the game keeps %s at 0x%08lX", name.c_str(), static_cast<unsigned long>(setting.record));
  return setting.record + 0x10;
}

// One crosshair on screen, not two. SWBF2's picture has its own in it for a
// character with something to aim (with the ring round it that shows the
// weapon's magazine, or its heat), and says so; WaW's is switched off for as
// long as it does (cg_drawCrosshair) and comes back when it stops. Call with
// g_mutex held.
void HideCrosshair() {
  static bool hiding = false;
  static NamedSetting setting;
  if (g_settings.crosshairSetting.empty() || !g_block) return;
  BfPlayerState bf{};
  const bool hide = overlay::Drawing() && g_block->bf.read(bf) && (bf.flags & kBfCrosshair) != 0;
  if (!hide && !hiding) return;
  const uintptr_t at = ValueOf(setting, g_settings.crosshairSetting);
  if (!at) return;  // the game has not made the setting yet
  const uint8_t wanted = hide ? 0 : 1;
  uint8_t now = wanted;
  if (mem::Read(at, &now, sizeof(now)) && now != wanted) mem::Write(at, &wanted, sizeof(wanted));
  if (hide != hiding) log::Info(hide ? "crosshair: SWBF2's is in its picture; WaW's own is off" : "crosshair: WaW's own is back");
  hiding = hide;
}

// A lightsaber has no ammunition. The weapon that stands for one in WaW has
// (it has to fire to be a weapon at all), and WaW counts it down on the
// screen; so for a character with a lightsaber the game's own switch for
// that part of its HUD (ammoCounterHide: the weapon's name and its
// ammunition) is turned on, and off again for anyone else. Call with g_mutex
// held.
void HideAmmo() {
  static bool hiding = false;
  static NamedSetting setting;
  if (g_settings.ammoSetting.empty() || !g_block) return;
  BfPlayerState bf{};
  const bool hide = overlay::Drawing() && g_block->bf.read(bf) && (bf.flags & kBfMelee) != 0;
  if (!hide && !hiding) return;
  const uintptr_t at = ValueOf(setting, g_settings.ammoSetting);
  if (!at) return;  // the game has not made the setting yet
  const uint8_t wanted = hide ? 1 : 0;
  uint8_t now = wanted;
  if (mem::Read(at, &now, sizeof(now)) && now != wanted) mem::Write(at, &wanted, sizeof(wanted));
  if (hide != hiding) log::Info(hide ? "ammunition: a lightsaber has none; WaW's count of it is not shown" : "ammunition: WaW's count is shown again");
  hiding = hide;
}

// Footsteps. WaW's player is heard walking and running whoever the character
// is, and one of SWBF2's does neither: the Emperor glides. For the kits named
// in [waw] quiet_kits the game's own switch for the player's footstep sounds
// (cg_footsteps) is turned off, and turned back on for anybody else. Only
// while the player is on their feet: crouched, the Emperor creeps along like
// anyone, and is heard doing it. Call with g_mutex held.
void QuietSteps() {
  static bool quiet = false;
  static NamedSetting setting;
  if (g_settings.footstepsSetting.empty() || !g_block) return;
  BfPlayerState bf{};
  bool want = false;
  if (overlay::Drawing() && g_block->bf.read(bf) && !(g_state.flags & kWawCrouching)) {
    for (const int kit : g_settings.quietKits) want = want || kit == static_cast<int>(bf.kit & 31);
  }
  if (!want && !quiet) return;
  const uintptr_t at = ValueOf(setting, g_settings.footstepsSetting);
  if (!at) return;  // the game has not made the setting yet
  const uint8_t wanted = want ? 0 : 1;
  uint8_t now = wanted;
  if (mem::Read(at, &now, sizeof(now)) && now != wanted) mem::Write(at, &wanted, sizeof(wanted));
  if (want != quiet) log::Info(want ? "footsteps: this character is not heard walking; WaW's are off" : "footsteps: WaW's are back on");
  quiet = want;
}

// Aiming from behind the character.
//
// This game does not fire a player's shot the way they are looking. It fires
// it the way their gun points: two angles the drawing side of the game works
// out each frame from the gun it draws in the player's hands, sends along with
// the player's buttons, and the shot is fired from the player's eyes along
// them (the gun sways, and the shots go with it). In third person that gun is
// not drawn, the routine that draws it returns at once, and the two angles
// stay as they were in the last frame seen through the player's eyes. So from
// behind, every shot went the way the player happened to be facing when the
// view changed, whichever way they turned afterwards: 77 rounds with a zombie
// on the line of sight for two thirds of them hurt nothing
// (tools/probe/shotwatch.ps1; docs/PHASE3.md has the code).
//
// So from behind, this bridge sets those two angles itself, every frame. And
// since it can point the shot anywhere, it points it at what the middle of
// the screen shows, which is where a player aims and where SWBF2 draws its
// crosshair. The camera is not at the player's eyes, so that takes knowing how
// far off the thing in the middle of the screen is, and only a script can ask
// the game that. The bridge tells the scripts the line through the middle of
// the screen (in another number on the player's entity that means nothing on
// a player, "spawnflags"), a script follows it to the first thing it meets and
// says how far that was, and the shot is pointed from the eyes at that spot.
//
// The line is told relative to the player's eyes and the way they look, which
// the script knows exactly: where it crosses the plane through the eyes that
// faces the way they look (to the right and up, in half units), and how its
// direction differs from theirs (to the right and up, in eighths of a
// degree). The bridge then uses the line as told, not as measured, so that
// both ends mean the same one. From the low end: 8 bits right, 8 up, 7 and 7
// of direction, and a bit that says the number is there. 0: not from behind.
//
// The crosshair seen from behind is SWBF2's own, in the middle of its picture.
// With [waw] aim_mark the bridge also draws one of its own on the spot the
// shot is pointed at, which shows how well the two agree.
// Call with g_mutex held.
void Aim() {
  static bool told = false;
  const Settings& st = g_settings;
  const WawPlayerState& s = g_state;
  const uint32_t need = kWawOriginValid | kWawAnglesValid | kWawCameraValid | kWawFovValid;
  const uintptr_t fieldAt = st.haveAimField ? mem::Resolve(st.aimField) : 0;
  const auto tell = [fieldAt](int32_t line) {
    int32_t now = line;
    if (fieldAt && mem::Read(fieldAt, &now, sizeof(now)) && now != line) mem::Write(fieldAt, &line, sizeof(line));
  };
  if (!g_fromBehind || (s.flags & need) != need || !overlay::Drawing()) {
    if (told) tell(0);
    told = false;
    overlay::SetMark(false, 0, 0);
    return;
  }
  const float kDegrees = 3.14159265f / 180.0f;
  const float pitch = s.viewAngles[0] * kDegrees, yaw = s.viewAngles[1] * kDegrees;
  // the way the player looks, and what is to the right of that and above it
  const float ahead[3] = {std::cos(pitch) * std::cos(yaw), std::cos(pitch) * std::sin(yaw), -std::sin(pitch)};
  const float right[3] = {std::sin(yaw), -std::cos(yaw), 0.0f};
  const float above[3] = {std::sin(pitch) * std::cos(yaw), std::sin(pitch) * std::sin(yaw), std::cos(pitch)};
  const float eye[3] = {s.origin[0], s.origin[1], s.origin[2] + ((s.flags & kWawCrouching) ? 40.0f : 60.0f)};
  const auto dot = [](const float* a, const float* b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; };
  const float* f = s.cameraForward;
  float gun[2] = {s.viewAngles[0], s.viewAngles[1]};  // with nothing better known, the way the player looks
  bool marked = false;
  const float along = dot(f, ahead);
  if (along > 0.5f) {
    const float toEye[3] = {eye[0] - s.cameraOrigin[0], eye[1] - s.cameraOrigin[1], eye[2] - s.cameraOrigin[2]};
    const float reach = dot(toEye, ahead) / along;  // from the camera to the plane through the eyes
    const float across[3] = {s.cameraOrigin[0] + f[0] * reach - eye[0], s.cameraOrigin[1] + f[1] * reach - eye[1],
                             s.cameraOrigin[2] + f[2] * reach - eye[2]};
    const auto steps = [](float value, int most) {
      return std::max(-most, std::min(most, static_cast<int>(std::lround(value))));
    };
    const int side = steps(dot(across, right) * 2.0f, 127), rise = steps(dot(across, above) * 2.0f, 127);
    const int turn = steps(std::atan2(dot(f, right), along) / kDegrees * 8.0f, 63);
    const int lift = steps(std::atan2(dot(f, above), along) / kDegrees * 8.0f, 63);
    tell((1 << 30) | (side + 128) | ((rise + 128) << 8) | ((turn + 64) << 16) | ((lift + 64) << 23));
    told = true;
    if (g_aimFar > 0) {
      // The line as the script has it, and the spot on it that the script found.
      const float tanTurn = std::tan(turn / 8.0f * kDegrees), tanLift = std::tan(lift / 8.0f * kDegrees);
      float way[3], from[3], to[3];
      for (int i = 0; i < 3; ++i) {
        way[i] = ahead[i] + right[i] * tanTurn + above[i] * tanLift;
        from[i] = eye[i] + right[i] * (side * 0.5f) + above[i] * (rise * 0.5f);
      }
      const float length = std::sqrt(dot(way, way));
      for (int i = 0; i < 3; ++i) to[i] = from[i] + way[i] / length * g_aimFar - eye[i];  // from the eyes to the spot
      const float off = std::sqrt(dot(to, to));
      if (off > 4.0f) {
        gun[0] = -std::asin(std::max(-1.0f, std::min(1.0f, to[2] / off))) / kDegrees;
        gun[1] = std::atan2(to[1], to[0]) / kDegrees;
        // the spot, through the camera the picture was drawn with
        const float seen[3] = {eye[0] + to[0] - s.cameraOrigin[0], eye[1] + to[1] - s.cameraOrigin[1],
                               eye[2] + to[2] - s.cameraOrigin[2]};
        const float* u = s.cameraUp;
        const float l[3] = {u[1] * f[2] - u[2] * f[1], u[2] * f[0] - u[0] * f[2], u[0] * f[1] - u[1] * f[0]};  // left = up x forward
        const float depth = dot(seen, f);
        if (depth > 8.0f) {
          const float x = -dot(seen, l) / (depth * s.tanHalfFov[0]), y = dot(seen, u) / (depth * s.tanHalfFov[1]);
          marked = st.aimMark && std::fabs(x) < 1.0f && std::fabs(y) < 1.0f;
          if (marked) overlay::SetMark(true, x, y);
        }
      }
    }
  } else if (told) {
    tell(0);
    told = false;
  }
  if (!marked) overlay::SetMark(false, 0, 0);
  const uintptr_t gunAt = st.haveGunAngles ? mem::Resolve(st.gunAngles) : 0;
  if (gunAt) mem::Write(gunAt, gun, sizeof(gun));
  static bool said = false;
  if (!said && gunAt) log::Info("aim: from behind the character, shots are pointed at what the middle of the screen shows");
  said = said || gunAt != 0;
}
}  // namespace

// (This engine can present from a rendering thread separate from the one that
// runs the game. Reading two vectors from there is harmless; anything that
// changes game state would need more care.)
void BridgeFrame() {
  ++g_frames;
  std::lock_guard<std::mutex> lock(g_mutex);
  Publish();
  Aim();
  MatchJump();
  QuietSteps();
  HideCrosshair();
  HideAmmo();
  const bool knifing = Knifing();
  // The picture is drawn last, over everything of WaW's, the pause menu
  // included. So while the game is paused it stands aside as well, and the
  // menu is not behind the player's character.
  uint8_t paused = 0;
  const uintptr_t pausedAt = g_settings.havePaused ? mem::Resolve(g_settings.paused) : 0;
  if (pausedAt) mem::Read(pausedAt, &paused, sizeof(paused));
  static bool wasPaused = false;
  if ((paused != 0) != wasPaused) {
    wasPaused = paused != 0;
    log::Info(wasPaused ? "paused: SWBF2's picture stands aside for the menu" : "paused: no longer");
  }
  overlay::SetStandAside(knifing || paused != 0);
  HideGun(knifing);
  ThirdPerson();
  TellKit();
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
  SteadyCamera(settings);

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
    MoreHealth(settings);

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
    // (Not before the once-a-second work below has been round once: that is
    // what keeps the game from saying a name has changed.)
    if (lastReport) NameCharacter(settings, shm.block(), peerAlive);

    if (now - lastReport >= 1000) {
      lastReport = now;
      SteadyCamera(settings);
      ShowHints(settings);
      ScoreboardAlone(settings);
      GodAtStart(settings);
      if (config.Changed()) {
        log::Info("wawbf.ini changed, reloading");
        settings = LoadSettings(config);
        SteadyCamera(settings);
        ShowHints(settings);
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
