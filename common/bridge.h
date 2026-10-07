// Glue between the d3d9.dll proxy and each game's bridge.
#pragma once

#include <windows.h>

#include <string>

namespace wawbf {

// Implemented once per game (waw/src/main.cpp, swbf2/src/main.cpp). Runs on
// its own thread, started when the game loads the proxy, and normally runs
// until the process exits.
void BridgeMain(HMODULE self);

// Directory the proxy DLL was loaded from, with a trailing backslash.
std::wstring ModuleDir(HMODULE module);

}  // namespace wawbf
