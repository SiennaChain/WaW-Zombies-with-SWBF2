#include "config.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>

#include "log.h"

namespace wawbf {

std::string Config::GetString(const char* section, const char* key, const char* fallback) const {
  wchar_t wsection[128], wkey[128], wbuf[512];
  MultiByteToWideChar(CP_UTF8, 0, section, -1, wsection, 128);
  MultiByteToWideChar(CP_UTF8, 0, key, -1, wkey, 128);
  const DWORD n = GetPrivateProfileStringW(wsection, wkey, L"", wbuf, 512, path_.c_str());
  if (n == 0) return fallback;

  char buf[512];
  WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, buf, sizeof(buf), nullptr, nullptr);
  // GetPrivateProfileString keeps trailing ";" comments; strip them.
  std::string value(buf);
  const size_t semi = value.find(';');
  if (semi != std::string::npos) value.erase(semi);
  value = detail::Trim(value);
  return value.empty() ? fallback : value;
}

int Config::GetInt(const char* section, const char* key, int fallback) const {
  const std::string s = GetString(section, key);
  if (s.empty()) return fallback;
  return static_cast<int>(std::strtol(s.c_str(), nullptr, 0));
}

float Config::GetFloat(const char* section, const char* key, float fallback) const {
  const std::string s = GetString(section, key);
  if (s.empty()) return fallback;
  return std::strtof(s.c_str(), nullptr);
}

Vec3 Config::GetVec3(const char* section, const char* key, Vec3 fallback) const {
  const std::string s = GetString(section, key);
  Vec3 v{};
  if (s.empty() || std::sscanf(s.c_str(), "%f , %f , %f", &v.x, &v.y, &v.z) != 3) {
    return fallback;
  }
  return v;
}

bool Config::GetAddress(const char* section, const char* key, AddressSpec& out) const {
  const std::string s = GetString(section, key);
  if (s.empty()) return false;
  if (!ParseAddressSpec(s, out)) {
    log::Error("[%s] %s: can't parse address \"%s\"", section, key, s.c_str());
    return false;
  }
  return true;
}

bool Config::Changed() {
  // A missing file counts as write time 0, so it is reported once and then
  // again if the file appears.
  uint64_t written = 0;
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (GetFileAttributesExW(path_.c_str(), GetFileExInfoStandard, &data)) {
    written = (uint64_t{data.ftLastWriteTime.dwHighDateTime} << 32) | data.ftLastWriteTime.dwLowDateTime;
  }
  if (written == lastWrite_) return false;
  lastWrite_ = written;
  return true;
}

}  // namespace wawbf
