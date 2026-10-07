// Safe reads/writes of the host game's own memory. Goes through
// Read/WriteProcessMemory on the current process so a wrong address from
// wawbf.ini fails cleanly instead of crashing the game.
#pragma once

#include <cstddef>
#include <cstdint>

#include "address_spec.h"

namespace wawbf::mem {

// Resolves module base + pointer chain to a final address. 0 on failure.
uintptr_t Resolve(const AddressSpec& spec);

bool Read(uintptr_t address, void* out, size_t size);
bool Write(uintptr_t address, const void* data, size_t size);

inline bool ReadFloat3(uintptr_t address, float out[3]) {
  return Read(address, out, sizeof(float) * 3);
}
inline bool WriteFloat3(uintptr_t address, const float v[3]) {
  return Write(address, v, sizeof(float) * 3);
}

}  // namespace wawbf::mem
