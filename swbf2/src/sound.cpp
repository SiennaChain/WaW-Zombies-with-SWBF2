#include "sound.h"

#include <windows.h>

#include <mmsystem.h>

#include <dsound.h>

#include <algorithm>
#include <atomic>
#include <cstring>

#include "log.h"

namespace wawbf::sound {
namespace {

// IDirectSound and IDirectSound8 both create a sound with the fourth routine
// in their table, with the same arguments.
using CreateBuffer = HRESULT(__stdcall*)(void* self, LPCDSBUFFERDESC what, LPDIRECTSOUNDBUFFER* made, LPUNKNOWN outer);
const int kCreateBuffer = 3;

CreateBuffer g_create = nullptr;   // IDirectSound's own
CreateBuffer g_create8 = nullptr;  // IDirectSound8's own
std::atomic<unsigned> g_made{0};       // sounds made to play regardless
std::atomic<unsigned> g_refused{0};    // sounds DirectSound would not make that way, made as the game asked
std::atomic<unsigned> g_untouched{0};  // the primary buffer, and any that asked for global focus themselves
std::atomic<unsigned long> g_refusedFlags{0}, g_refusedResult{0}, g_lastFlags{0};
// The first few sounds made, kept (with a hold on each) so that Report can say what the game does with them.
const int kWatched = 8;
std::atomic<IDirectSoundBuffer*> g_watched[kWatched];
std::atomic<int> g_watchedCount{0};

// Asks for the same sound, to be played whoever is in front. Not for the
// primary buffer (the mixer itself, which has no such thing), and if
// DirectSound will not have the sound that way, as the game asked for it.
HRESULT Create(CreateBuffer own, void* self, LPCDSBUFFERDESC what, LPDIRECTSOUNDBUFFER* made, LPUNKNOWN outer) {
  if (what && what->dwSize >= sizeof(DSBUFFERDESC1) && !(what->dwFlags & (DSBCAPS_PRIMARYBUFFER | DSBCAPS_GLOBALFOCUS))) {
    DSBUFFERDESC ours{};
    std::memcpy(&ours, what, std::min<size_t>(what->dwSize, sizeof(ours)));
    ours.dwFlags = (ours.dwFlags & ~static_cast<DWORD>(DSBCAPS_STICKYFOCUS)) | DSBCAPS_GLOBALFOCUS;
    const HRESULT result = own(self, &ours, made, outer);
    if (SUCCEEDED(result)) {
      g_made.fetch_add(1, std::memory_order_relaxed);
      g_lastFlags.store(ours.dwFlags, std::memory_order_relaxed);
      const int place = g_watchedCount.fetch_add(1, std::memory_order_relaxed);
      if (place < kWatched && made && *made) {
        (*made)->AddRef();
        g_watched[place].store(*made, std::memory_order_relaxed);
      }
      return result;
    }
    g_refused.fetch_add(1, std::memory_order_relaxed);
    g_refusedFlags.store(what->dwFlags, std::memory_order_relaxed);
    g_refusedResult.store(static_cast<unsigned long>(result), std::memory_order_relaxed);
  } else {
    g_untouched.fetch_add(1, std::memory_order_relaxed);
  }
  return own(self, what, made, outer);
}

HRESULT __stdcall Create1(void* self, LPCDSBUFFERDESC what, LPDIRECTSOUNDBUFFER* made, LPUNKNOWN outer) {
  return Create(g_create, self, what, made, outer);
}

HRESULT __stdcall Create8(void* self, LPCDSBUFFERDESC what, LPDIRECTSOUNDBUFFER* made, LPUNKNOWN outer) {
  return Create(g_create8, self, what, made, outer);
}

// Every object of one kind shares one table of routines, so changing the
// table changes it for the game's object too, whenever that is made. One
// pointer, written in one go.
void** Redirect(IUnknown* object, CreateBuffer ours, CreateBuffer* own, void** already) {
  void** table = *reinterpret_cast<void***>(object);
  if (table == already) return table;  // the two kinds share a table: done once
  DWORD old = 0;
  if (!VirtualProtect(&table[kCreateBuffer], sizeof(void*), PAGE_READWRITE, &old)) return nullptr;
  *own = reinterpret_cast<CreateBuffer>(table[kCreateBuffer]);
  InterlockedExchangePointer(&table[kCreateBuffer], reinterpret_cast<void*>(ours));
  VirtualProtect(&table[kCreateBuffer], sizeof(void*), old, &old);
  return table;
}

}  // namespace

bool KeepPlaying() {
  // By name, so that it is whichever dsound.dll the game itself is given.
  const HMODULE dsound = LoadLibraryW(L"dsound.dll");
  if (!dsound) {
    log::Error("sound: no dsound.dll (error %lu); the game stays silent while it is not in front", GetLastError());
    return false;
  }
  using Make8 = HRESULT(WINAPI*)(LPCGUID, LPDIRECTSOUND8*, LPUNKNOWN);
  using Make1 = HRESULT(WINAPI*)(LPCGUID, LPDIRECTSOUND*, LPUNKNOWN);
  const auto make8 = reinterpret_cast<Make8>(GetProcAddress(dsound, "DirectSoundCreate8"));
  const auto make1 = reinterpret_cast<Make1>(GetProcAddress(dsound, "DirectSoundCreate"));
  void** table8 = nullptr;
  void** table1 = nullptr;
  IDirectSound8* eight = nullptr;
  if (make8 && SUCCEEDED(make8(nullptr, &eight, nullptr)) && eight) {
    table8 = Redirect(eight, &Create8, &g_create8, nullptr);
    eight->Release();
  }
  IDirectSound* one = nullptr;
  if (make1 && SUCCEEDED(make1(nullptr, &one, nullptr)) && one) {
    table1 = Redirect(one, &Create1, &g_create, table8);
    one->Release();
  }
  if (!table8 && !table1) {
    log::Error("sound: DirectSound could not be started here; the game stays silent while it is not in front");
    return false;
  }
  log::Info("sound: every sound the game makes from now on plays whether or not its window is in front");
  return true;
}

unsigned Made() { return g_made.load(std::memory_order_relaxed); }

void Report() {
  static unsigned saidMade = 0, saidRefused = 0;
  const unsigned made = g_made.load(std::memory_order_relaxed), refused = g_refused.load(std::memory_order_relaxed);
  if (made == saidMade && refused == saidRefused) return;
  saidMade = made;
  saidRefused = refused;
  log::Info("sound: %u sounds made to play in the background (the last asked for 0x%lX), %u left alone, %u that DirectSound would not make that way (the last asked for 0x%lX and got 0x%lX)",
            made, g_lastFlags.load(std::memory_order_relaxed), g_untouched.load(std::memory_order_relaxed), refused,
            g_refusedFlags.load(std::memory_order_relaxed), g_refusedResult.load(std::memory_order_relaxed));
}

void Describe() {
  for (int i = 0; i < kWatched; ++i) {
    IDirectSoundBuffer* buffer = g_watched[i].load(std::memory_order_relaxed);
    if (!buffer) continue;
    LONG volume = 0, pan = 0;
    DWORD status = 0, rate = 0, play = 0, write = 0, got = 0;
    unsigned char format[64] = {};
    DSBCAPS caps{};
    caps.dwSize = sizeof(caps);
    buffer->GetVolume(&volume);
    buffer->GetPan(&pan);
    buffer->GetStatus(&status);
    buffer->GetFrequency(&rate);
    buffer->GetCurrentPosition(&play, &write);
    buffer->GetCaps(&caps);
    buffer->GetFormat(reinterpret_cast<WAVEFORMATEX*>(format), sizeof(format), &got);
    const auto* wave = reinterpret_cast<const WAVEFORMATEX*>(format);
    log::Info("sound %d: %s%s, volume %ld (hundredths of a decibel), pan %ld, %lu Hz, %u channel(s) of %u bits, %lu bytes long, playing at byte %lu",
              i + 1, (status & DSBSTATUS_PLAYING) ? "playing" : "stopped", (status & DSBSTATUS_LOOPING) ? " round and round" : "",
              volume, pan, rate, wave->nChannels, wave->wBitsPerSample, caps.dwBufferBytes, play);
  }
}

}  // namespace wawbf::sound
