// Whether the mod is to do anything in this run of a game.
//
// The bridges are a d3d9.dll in each game's folder, so the games load them
// every time they start: for World at War's campaign, for its multiplayer (a
// different exe in the same folder), for Battlefront II played by itself.
// None of those is to notice. A bridge does nothing at all (no thread, no
// hook, nothing of the game's changed) unless both of these hold:
//
//   The exe it finds itself in is the one it was made for: by name, and by
//   the two numbers in an exe's header that tell one build of it from
//   another. Every address in wawbf.ini is a place in that build and in no
//   other; in another they are somebody else's memory.
//
//   The launcher started it. The launcher holds a named object (kSessionName)
//   from before it starts the first game until the last has gone.
//
// wawbf.ini can waive either, for working on the mod:
//   [bridge] without_launcher = 1    any_exe = 1
#pragma once

#include <windows.h>

#include <cstdint>
#include <string>

namespace wawbf::session {

struct ExeId {
  uint32_t stamp = 0;      // when it was linked, as the linker wrote it
  uint32_t imageSize = 0;  // how much memory it takes up loaded
};
inline bool operator==(const ExeId& a, const ExeId& b) { return a.stamp == b.stamp && a.imageSize == b.imageSize; }
inline bool operator!=(const ExeId& a, const ExeId& b) { return !(a == b); }

struct Game {
  const wchar_t* exe;
  ExeId id;
};
// The latest Steam builds of both, which are the ones every address was found in.
constexpr Game kWaw = {L"CoDWaW.exe", {0x4AEA1F46, 0x04B11000}};
constexpr Game kBf = {L"BattlefrontII.exe", {0x59EDE353, 0x01BE4000}};

// The numbers of an exe on disk. False if it cannot be read or is no exe.
bool OfFile(const std::wstring& path, ExeId* id);

// The launcher's side. Null if another launcher already holds it.
HANDLE Hold();

enum class Verdict { kRun, kNotThisExe, kNoLauncher, kOtherBuild };
// A bridge's side, asked once, as the game loads it. `ini` is the bridge's
// wawbf.ini. It is called from DllMain, so nothing in it goes further than
// kernel32.
Verdict Decide(const Game& game, const std::wstring& ini);

}  // namespace wawbf::session
