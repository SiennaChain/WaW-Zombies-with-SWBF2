// wawbf.ini lives next to the bridge DLL in each game's folder. Addresses
// are kept out of the code so they can be iterated on during reverse
// engineering without rebuilding.
#pragma once

#include <string>

#include "address_spec.h"
#include "wawbf_protocol.h"

namespace wawbf {

class Config {
 public:
  explicit Config(std::wstring path) : path_(std::move(path)) {}

  const std::wstring& path() const { return path_; }
  std::string GetString(const char* section, const char* key, const char* fallback = "") const;
  int GetInt(const char* section, const char* key, int fallback) const;
  float GetFloat(const char* section, const char* key, float fallback) const;
  // "x, y, z"; returns fallback if missing or not three numbers.
  Vec3 GetVec3(const char* section, const char* key, Vec3 fallback) const;

  // False if the key is missing/empty or malformed (malformed is logged).
  bool GetAddress(const char* section, const char* key, AddressSpec& out) const;

 private:
  std::wstring path_;
};

}  // namespace wawbf
