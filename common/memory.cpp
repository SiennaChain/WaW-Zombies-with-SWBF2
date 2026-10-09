#include "memory.h"

#include <windows.h>

#include <algorithm>
#include <cstring>
#include <vector>

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

uintptr_t FindRecordNamed(uintptr_t from, size_t size, const char* name) {
  const size_t length = std::strlen(name);
  if (!from || !length || length >= 96) return 0;
  // A name is text in the program's own image, so only pointers into that
  // are worth following.
  auto* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
  auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
  const uintptr_t low = reinterpret_cast<uintptr_t>(base), high = low + nt->OptionalHeader.SizeOfImage;
  std::vector<uint32_t> block(0x4000);
  char text[100];
  for (size_t done = 0; done < size; done += block.size() * sizeof(uint32_t)) {
    const size_t take = std::min(block.size() * sizeof(uint32_t), size - done);
    if (!Read(from + done, block.data(), take)) continue;  // not all of the range need be there
    for (size_t i = 0; i < take / sizeof(uint32_t); ++i) {
      const uintptr_t pointer = block[i];
      if (pointer < low || pointer >= high) continue;
      if (Read(pointer, text, length + 1) && text[length] == 0 && std::memcmp(text, name, length) == 0) {
        return from + done + i * sizeof(uint32_t);
      }
    }
  }
  return 0;
}

namespace {

// Writes one pointer-sized slot that normally lives in read-only memory.
bool WriteSlot(void** slot, void* value) {
  DWORD protection = 0;
  // Executable as well as writable: the slot can share a page with code that
  // another thread is running right now.
  if (!VirtualProtect(slot, sizeof(void*), PAGE_EXECUTE_READWRITE, &protection)) return false;
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
    // The slot is found by the name the exe asks for, where it keeps its list
    // of them, and only failing that by what is in the slot: something else
    // loaded into the game may have put a routine of its own there already,
    // and then it is that routine ours has to call on to.
    auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA*>(base + desc->FirstThunk);
    auto* asked = desc->OriginalFirstThunk ? reinterpret_cast<IMAGE_THUNK_DATA*>(base + desc->OriginalFirstThunk) : nullptr;
    for (; thunk->u1.Function; ++thunk) {
      bool found = reinterpret_cast<void*>(thunk->u1.Function) == target;
      if (asked) {
        if (!asked->u1.AddressOfData) break;
        if (!found && !IMAGE_SNAP_BY_ORDINAL(asked->u1.Ordinal)) {
          const auto* by = reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(base + asked->u1.AddressOfData);
          found = std::strcmp(reinterpret_cast<const char*>(by->Name), name) == 0;
        }
        ++asked;
      }
      if (!found) continue;
      void* previous = reinterpret_cast<void*>(thunk->u1.Function);
      if (previous == replacement) return nullptr;
      return WriteSlot(reinterpret_cast<void**>(&thunk->u1.Function), replacement) ? previous : nullptr;
    }
  }
  return nullptr;
}

void* PatchVtable(void* object, int index, void* replacement) {
  void** vtable = *reinterpret_cast<void***>(object);
  void* previous = vtable[index];
  if (previous == replacement) return nullptr;
  return WriteSlot(&vtable[index], replacement) ? previous : nullptr;
}

}  // namespace wawbf::mem
