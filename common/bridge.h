// Glue between the d3d9.dll proxy and each game's bridge.
#pragma once

#include <windows.h>

#include <string>

#include "session.h"

namespace wawbf {

// Implemented once per game: the exe this bridge was made for. In any other,
// or in that one started by anything but the launcher, the proxy passes
// Direct3D through and none of the rest of this is ever called (session.h).
const session::Game& BridgeGame();

// Implemented once per game. Called as the game loads the proxy, before the
// game has run a line of its own, with whether the bridge is going to run:
// for what has to be settled that early. It is inside DllMain, so nothing in
// it may go further than kernel32.
void BridgeLoaded(HMODULE self, bool live);

// Implemented once per game (waw/src/main.cpp, swbf2/src/main.cpp). Runs on
// its own thread, started when the game loads the proxy, and normally runs
// until the process exits.
void BridgeMain(HMODULE self);

// Implemented once per game. Called on the game's own rendering thread once
// per frame, just before the finished frame is shown, so anything it changes
// is in step with the game. It runs inside the game's frame: keep it short
// and never block.
void BridgeFrame();

// Directory the proxy DLL was loaded from, with a trailing backslash.
std::wstring ModuleDir(HMODULE module);

}  // namespace wawbf
