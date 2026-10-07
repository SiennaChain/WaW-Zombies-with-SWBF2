// Parses memory locations written the way Cheat Engine shows them, so
// addresses found while reverse engineering can go straight into wawbf.ini:
//
//   player_origin = CoDWaW.exe+0x1A2B3C          ; module-relative
//   player_origin = 0x00C0FFEE                   ; absolute
//   player_origin = BattlefrontII.exe+0x1234 > 0x10 > 0x2C   ; pointer chain
//
// A chain is resolved like Cheat Engine does: start at the base, then for
// each offset read a pointer there and add the offset.
//
// Parsing is platform-neutral (and unit tested); resolving against a live
// process lives in memory.cpp.
#pragma once

#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

namespace wawbf {

struct AddressSpec {
  std::string module;  // empty = absolute address
  uint32_t offset = 0;
  std::vector<uint32_t> chain;
};

namespace detail {

inline std::string Trim(const std::string& s) {
  const char* ws = " \t\r\n";
  const size_t b = s.find_first_not_of(ws);
  if (b == std::string::npos) return {};
  const size_t e = s.find_last_not_of(ws);
  return s.substr(b, e - b + 1);
}

inline bool ParseNumber(const std::string& raw, uint32_t& out) {
  const std::string s = Trim(raw);
  if (s.empty()) return false;
  char* end = nullptr;
  const unsigned long long v = std::strtoull(s.c_str(), &end, 0);
  if (*end != '\0' || v > 0xFFFFFFFFull) return false;
  out = static_cast<uint32_t>(v);
  return true;
}

}  // namespace detail

// Returns false for an empty or malformed spec.
inline bool ParseAddressSpec(const std::string& text, AddressSpec& out) {
  out = AddressSpec{};

  std::vector<std::string> parts;
  size_t start = 0;
  for (;;) {
    const size_t gt = text.find('>', start);
    parts.push_back(detail::Trim(text.substr(start, gt - start)));
    if (gt == std::string::npos) break;
    start = gt + 1;
  }

  const std::string& base = parts[0];
  if (base.empty()) return false;
  const size_t plus = base.find('+');
  if (plus == std::string::npos) {
    if (!detail::ParseNumber(base, out.offset)) return false;
  } else {
    out.module = detail::Trim(base.substr(0, plus));
    if (out.module.empty() || !detail::ParseNumber(base.substr(plus + 1), out.offset)) {
      return false;
    }
  }

  for (size_t i = 1; i < parts.size(); ++i) {
    uint32_t off = 0;
    if (!detail::ParseNumber(parts[i], off)) return false;
    out.chain.push_back(off);
  }
  return true;
}

}  // namespace wawbf
