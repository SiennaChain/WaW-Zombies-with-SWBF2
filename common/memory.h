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

// A game that keeps its named settings in one table of records, each record
// beginning with a pointer to the setting's name: looks through `size` bytes
// from `from`, four at a time, for one whose name is `name`, and returns where
// that record is, or 0. For a setting that cannot be reached any steadier way
// (through a pointer the game keeps to it): a record's place in the table
// depends on how many settings were made before it, which changes with what
// the game was started with.
uintptr_t FindRecordNamed(uintptr_t from, size_t size, const char* name);

// Redirects the game exe's import of `name` from `dll` to `replacement`.
// Returns the real function so the replacement can call through, or null if
// the exe does not import it.
void* PatchImport(const char* dll, const char* name, void* replacement);

// Replaces one method of a COM object by overwriting its vtable slot, which
// affects every object of that class. Returns the previous method, or null if
// it was already `replacement` or could not be written.
void* PatchVtable(void* object, int index, void* replacement);

}  // namespace wawbf::mem
