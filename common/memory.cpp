#include "memory.h"

#include <windows.h>

namespace wawbf::mem {

uintptr_t Resolve(const AddressSpec& spec) {
  uintptr_t address = spec.offset;
  if (!spec.module.empty()) {
    const HMODULE module = GetModuleHandleA(spec.module.c_str());
    if (!module) return 0;
    address += reinterpret_cast<uintptr_t>(module);
  }
  for (const uint32_t offset : spec.chain) {
    uint32_t pointer = 0;  // both games are 32-bit
    if (!Read(address, &pointer, sizeof(pointer)) || pointer == 0) return 0;
    address = static_cast<uintptr_t>(pointer) + offset;
  }
  return address;
}

bool Read(uintptr_t address, void* out, size_t size) {
  SIZE_T done = 0;
  return address != 0 &&
         ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(address), out, size,
                           &done) &&
         done == size;
}

bool Write(uintptr_t address, const void* data, size_t size) {
  SIZE_T done = 0;
  return address != 0 &&
         WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(address), data, size,
                            &done) &&
         done == size;
}

}  // namespace wawbf::mem
