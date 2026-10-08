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

namespace {

// Writes one pointer-sized slot that normally lives in read-only memory.
bool WriteSlot(void** slot, void* value) {
  DWORD protection = 0;
  if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &protection)) return false;
  *slot = value;
  VirtualProtect(slot, sizeof(void*), protection, &protection);
  return true;
}

}  // namespace

void* PatchImport(const char* dll, const char* name, void* replacement) {
  const HMODULE provider = GetModuleHandleA(dll);
  void* target = provider ? reinterpret_cast<void*>(GetProcAddress(provider, name)) : nullptr;
  if (!target) return nullptr;

  auto* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
  auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
  auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  const IMAGE_DATA_DIRECTORY& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!dir.VirtualAddress) return nullptr;

  for (auto* desc = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + dir.VirtualAddress);
       desc->Name; ++desc) {
    if (_stricmp(reinterpret_cast<const char*>(base + desc->Name), dll) != 0) continue;
    for (auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA*>(base + desc->FirstThunk);
         thunk->u1.Function; ++thunk) {
      if (reinterpret_cast<void*>(thunk->u1.Function) != target) continue;
      return WriteSlot(reinterpret_cast<void**>(&thunk->u1.Function), replacement) ? target : nullptr;
    }
  }
  return nullptr;
}

}  // namespace wawbf::mem
