// Minimal thread-safe file logger. Each bridge writes next to its DLL
// (wawbf_waw.log / wawbf_swbf2.log) because neither game has a console we
// can rely on.
#pragma once

#include <string>

namespace wawbf::log {

void Init(const std::wstring& path);
void Info(const char* fmt, ...);
void Error(const char* fmt, ...);

}  // namespace wawbf::log
