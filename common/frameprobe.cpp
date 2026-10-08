#include "frameprobe.h"

#include <windows.h>

#include <d3d9.h>

#include <atomic>
#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "log.h"
#include "memory.h"

namespace wawbf::frameprobe {
namespace {

// Vtable slots of IDirect3DDevice9, from d3d9.h.
enum Slot {
  kStretchRect = 34,
  kSetRenderTarget = 37,
  kSetDepthStencilSurface = 39,
  kBeginScene = 41,
  kClear = 43,
  kSetTransform = 44,
  kSetViewport = 47,
  kDrawPrimitive = 81,
  kDrawIndexedPrimitive = 82,
  kDrawPrimitiveUP = 83,
  kDrawIndexedPrimitiveUP = 84,
};

using StretchRectFn = HRESULT(WINAPI*)(IDirect3DDevice9*, IDirect3DSurface9*, const RECT*,
                                       IDirect3DSurface9*, const RECT*, D3DTEXTUREFILTERTYPE);
using SetRenderTargetFn = HRESULT(WINAPI*)(IDirect3DDevice9*, DWORD, IDirect3DSurface9*);
using SetDepthFn = HRESULT(WINAPI*)(IDirect3DDevice9*, IDirect3DSurface9*);
using BeginSceneFn = HRESULT(WINAPI*)(IDirect3DDevice9*);
using ClearFn = HRESULT(WINAPI*)(IDirect3DDevice9*, DWORD, const D3DRECT*, DWORD, D3DCOLOR, float, DWORD);
using SetTransformFn = HRESULT(WINAPI*)(IDirect3DDevice9*, D3DTRANSFORMSTATETYPE, const D3DMATRIX*);
using SetViewportFn = HRESULT(WINAPI*)(IDirect3DDevice9*, const D3DVIEWPORT9*);
using DrawPrimitiveFn = HRESULT(WINAPI*)(IDirect3DDevice9*, D3DPRIMITIVETYPE, UINT, UINT);
using DrawIndexedFn = HRESULT(WINAPI*)(IDirect3DDevice9*, D3DPRIMITIVETYPE, INT, UINT, UINT, UINT, UINT);
using DrawUpFn = HRESULT(WINAPI*)(IDirect3DDevice9*, D3DPRIMITIVETYPE, UINT, const void*, UINT);
using DrawIndexedUpFn = HRESULT(WINAPI*)(IDirect3DDevice9*, D3DPRIMITIVETYPE, UINT, UINT, UINT,
                                         const void*, D3DFORMAT, const void*, UINT);

StretchRectFn g_stretchRect = nullptr;
SetRenderTargetFn g_setRenderTarget = nullptr;
SetDepthFn g_setDepth = nullptr;
BeginSceneFn g_beginScene = nullptr;
ClearFn g_clear = nullptr;
SetTransformFn g_setTransform = nullptr;
SetViewportFn g_setViewport = nullptr;
DrawPrimitiveFn g_drawPrimitive = nullptr;
DrawIndexedFn g_drawIndexed = nullptr;
DrawUpFn g_drawUp = nullptr;
DrawIndexedUpFn g_drawIndexedUp = nullptr;

// 0 = idle, 1 = start at the next Present, 2 = recording. Only the rendering
// thread moves it past 1; the bridge thread only ever moves it from 0 to 1.
std::atomic<int> g_state{0};

// SetCut: which depth-only clear of the frame also clears the picture, and to what.
std::atomic<int> g_cutNth{0};
std::atomic<unsigned long> g_cutColour{0};
int g_depthClears = 0;  // depth-only clears so far this frame; rendering thread only

std::mutex g_requestMutex;       // guards the request below until the recording starts
std::wstring g_directory;
std::string g_label;
std::set<int> g_wanted;          // draw call numbers to save the picture before
std::string g_lastValue;
bool g_haveLastValue = false;

// Rendering thread only, while recording.
std::vector<std::string> g_lines;
std::wstring g_recDirectory;
std::string g_recLabel;
std::set<int> g_recWanted;
int g_draws = 0;        // draw calls so far this frame
int g_drawsLogged = 0;  // up to where the log has accounted for them
int g_snapshots = 0;
const int kMaxSnapshots = 40;

bool Recording() { return g_state.load(std::memory_order_relaxed) == 2; }

void Line(const char* format, ...) {
  char text[512];
  va_list args;
  va_start(args, format);
  std::vsnprintf(text, sizeof(text), format, args);
  va_end(args);
  g_lines.emplace_back(text);
}

// Draw calls are not logged one by one; each other event first says how many
// came before it.
void FlushDraws() {
  if (g_draws > g_drawsLogged) {
    Line("    draw calls %d to %d (%d)", g_drawsLogged, g_draws - 1, g_draws - g_drawsLogged);
    g_drawsLogged = g_draws;
  }
}

std::string Describe(IDirect3DSurface9* surface) {
  if (!surface) return "none";
  D3DSURFACE_DESC desc{};
  surface->GetDesc(&desc);
  char text[96];
  std::snprintf(text, sizeof(text), "%p %ux%u format %d%s%s", static_cast<void*>(surface), desc.Width,
                desc.Height, static_cast<int>(desc.Format),
                desc.MultiSampleType != D3DMULTISAMPLE_NONE ? " multisampled" : "",
                (desc.Usage & D3DUSAGE_RENDERTARGET) ? "" : " (not a render target)");
  return text;
}

// Saves what is in render target 0 right now as a 32-bit .bmp.
void Snapshot(IDirect3DDevice9* device, const char* why) {
  if (g_snapshots >= kMaxSnapshots) return;
  IDirect3DSurface9* target = nullptr;
  if (FAILED(device->GetRenderTarget(0, &target)) || !target) return;
  D3DSURFACE_DESC desc{};
  target->GetDesc(&desc);

  // A multisampled target cannot be read back directly; resolve it first.
  IDirect3DSurface9* resolved = nullptr;
  IDirect3DSurface9* source = target;
  if (desc.MultiSampleType != D3DMULTISAMPLE_NONE) {
    if (SUCCEEDED(device->CreateRenderTarget(desc.Width, desc.Height, desc.Format, D3DMULTISAMPLE_NONE, 0,
                                             FALSE, &resolved, nullptr)) &&
        SUCCEEDED(g_stretchRect(device, target, nullptr, resolved, nullptr, D3DTEXF_NONE))) {
      source = resolved;
    } else {
      source = nullptr;
    }
  }

  IDirect3DSurface9* copy = nullptr;
  bool saved = false;
  char name[160];
  std::snprintf(name, sizeof(name), "wawbf_frame_%s_%02d_d%04d_%s.bmp", g_recLabel.c_str(), g_snapshots,
                g_draws, why);
  if (source &&
      SUCCEEDED(device->CreateOffscreenPlainSurface(desc.Width, desc.Height, desc.Format,
                                                    D3DPOOL_SYSTEMMEM, &copy, nullptr)) &&
      SUCCEEDED(device->GetRenderTargetData(source, copy))) {
    D3DLOCKED_RECT locked{};
    const bool readable = desc.Format == D3DFMT_X8R8G8B8 || desc.Format == D3DFMT_A8R8G8B8;
    if (readable && SUCCEEDED(copy->LockRect(&locked, nullptr, D3DLOCK_READONLY))) {
      const std::wstring path = g_recDirectory + std::wstring(name, name + std::strlen(name));
      if (FILE* file = _wfopen(path.c_str(), L"wb")) {
        BITMAPFILEHEADER fileHeader{};
        BITMAPINFOHEADER info{};
        info.biSize = sizeof(info);
        info.biWidth = static_cast<LONG>(desc.Width);
        info.biHeight = -static_cast<LONG>(desc.Height);  // top row first
        info.biPlanes = 1;
        info.biBitCount = 32;
        info.biCompression = BI_RGB;
        fileHeader.bfType = 0x4D42;
        fileHeader.bfOffBits = sizeof(fileHeader) + sizeof(info);
        fileHeader.bfSize = fileHeader.bfOffBits + desc.Width * desc.Height * 4;
        std::fwrite(&fileHeader, sizeof(fileHeader), 1, file);
        std::fwrite(&info, sizeof(info), 1, file);
        for (UINT y = 0; y < desc.Height; ++y) {
          std::fwrite(static_cast<const BYTE*>(locked.pBits) + y * locked.Pitch, 4, desc.Width, file);
        }
        std::fclose(file);
        saved = true;
      }
      copy->UnlockRect();
    }
  }
  Line(saved ? "    [picture saved: %s]" : "    [picture NOT saved: %s]", name);
  if (saved) ++g_snapshots;
  if (copy) copy->Release();
  if (resolved) resolved->Release();
  target->Release();
}

void BeforeDraw(IDirect3DDevice9* device) {
  if (g_recWanted.count(g_draws)) {
    FlushDraws();
    Snapshot(device, "asked");
  }
  ++g_draws;
}

HRESULT WINAPI StretchRectHook(IDirect3DDevice9* self, IDirect3DSurface9* source, const RECT* sourceRect,
                               IDirect3DSurface9* destination, const RECT* destinationRect,
                               D3DTEXTUREFILTERTYPE filter) {
  if (Recording()) {
    FlushDraws();
    Line("StretchRect %s -> %s", Describe(source).c_str(), Describe(destination).c_str());
  }
  return g_stretchRect(self, source, sourceRect, destination, destinationRect, filter);
}

HRESULT WINAPI SetRenderTargetHook(IDirect3DDevice9* self, DWORD index, IDirect3DSurface9* target) {
  if (Recording()) {
    FlushDraws();
    Line("SetRenderTarget %lu = %s", index, Describe(target).c_str());
  }
  return g_setRenderTarget(self, index, target);
}

HRESULT WINAPI SetDepthHook(IDirect3DDevice9* self, IDirect3DSurface9* depth) {
  if (Recording()) {
    FlushDraws();
    Line("SetDepthStencilSurface %s", Describe(depth).c_str());
  }
  return g_setDepth(self, depth);
}

HRESULT WINAPI BeginSceneHook(IDirect3DDevice9* self) {
  if (Recording()) {
    FlushDraws();
    Line("BeginScene");
  }
  return g_beginScene(self);
}

HRESULT WINAPI ClearHook(IDirect3DDevice9* self, DWORD count, const D3DRECT* rects, DWORD flags,
                         D3DCOLOR color, float z, DWORD stencil) {
  const bool depthOnly = (flags & D3DCLEAR_ZBUFFER) && !(flags & D3DCLEAR_TARGET);
  const int cut = g_cutNth.load(std::memory_order_relaxed);
  const bool cutHere = depthOnly && cut > 0 && ++g_depthClears == cut;
  if (Recording()) {
    FlushDraws();
    // A depth-only clear part-way through a frame is the classic sign of a
    // first-person weapon about to be drawn over the world: keep the picture.
    if (depthOnly && g_draws > 0) Snapshot(self, "depthclear");
    Line("Clear%s%s%s%s colour %08lX z %.3f%s", (flags & D3DCLEAR_TARGET) ? " target" : "",
         (flags & D3DCLEAR_ZBUFFER) ? " depth" : "", (flags & D3DCLEAR_STENCIL) ? " stencil" : "",
         count ? " (part of the target)" : "", color, z, cutHere ? "  <- the picture is cut here" : "");
  }
  if (cutHere) {
    return g_clear(self, 0, nullptr, flags | D3DCLEAR_TARGET, g_cutColour.load(std::memory_order_relaxed), z,
                   stencil);
  }
  return g_clear(self, count, rects, flags, color, z, stencil);
}

HRESULT WINAPI SetTransformHook(IDirect3DDevice9* self, D3DTRANSFORMSTATETYPE state, const D3DMATRIX* m) {
  if (Recording() && state == D3DTS_PROJECTION && m) {
    FlushDraws();
    Line("SetTransform projection: x scale %.4f, y scale %.4f, m33 %.5f, m43 %.4f, m34 %.1f", m->_11,
         m->_22, m->_33, m->_43, m->_34);
  }
  return g_setTransform(self, state, m);
}

HRESULT WINAPI SetViewportHook(IDirect3DDevice9* self, const D3DVIEWPORT9* viewport) {
  if (Recording() && viewport) {
    FlushDraws();
    Line("SetViewport %lu,%lu %lux%lu depth %.3f to %.3f", viewport->X, viewport->Y, viewport->Width,
         viewport->Height, viewport->MinZ, viewport->MaxZ);
  }
  return g_setViewport(self, viewport);
}

HRESULT WINAPI DrawPrimitiveHook(IDirect3DDevice9* self, D3DPRIMITIVETYPE type, UINT start, UINT count) {
  if (Recording()) BeforeDraw(self);
  return g_drawPrimitive(self, type, start, count);
}

HRESULT WINAPI DrawIndexedHook(IDirect3DDevice9* self, D3DPRIMITIVETYPE type, INT baseVertex,
                               UINT minIndex, UINT vertices, UINT start, UINT count) {
  if (Recording()) BeforeDraw(self);
  return g_drawIndexed(self, type, baseVertex, minIndex, vertices, start, count);
}

HRESULT WINAPI DrawUpHook(IDirect3DDevice9* self, D3DPRIMITIVETYPE type, UINT count, const void* data,
                          UINT stride) {
  if (Recording()) BeforeDraw(self);
  return g_drawUp(self, type, count, data, stride);
}

HRESULT WINAPI DrawIndexedUpHook(IDirect3DDevice9* self, D3DPRIMITIVETYPE type, UINT minIndex,
                                 UINT vertices, UINT count, const void* indices, D3DFORMAT format,
                                 const void* data, UINT stride) {
  if (Recording()) BeforeDraw(self);
  return g_drawIndexedUp(self, type, minIndex, vertices, count, indices, format, data, stride);
}

template <class Fn>
void Hook(IDirect3DDevice9* device, int slot, void* replacement, Fn& real) {
  if (void* previous = mem::PatchVtable(device, slot, replacement)) real = reinterpret_cast<Fn>(previous);
}

void Finish(IDirect3DDevice9* device) {
  FlushDraws();
  Snapshot(device, "end");
  Line("Present: %d draw calls in the frame", g_draws);
  char name[96];
  std::snprintf(name, sizeof(name), "wawbf_frame_%s.txt", g_recLabel.c_str());
  const std::wstring path = g_recDirectory + std::wstring(name, name + std::strlen(name));
  if (FILE* file = _wfopen(path.c_str(), L"w")) {
    for (const std::string& line : g_lines) std::fprintf(file, "%s\n", line.c_str());
    std::fclose(file);
  }
  log::Info("frame probe: recorded a frame of %d draw calls, %d pictures, to %s", g_draws, g_snapshots, name);
  g_lines.clear();
}

}  // namespace

void Install(IDirect3DDevice9* device) {
  Hook(device, kStretchRect, &StretchRectHook, g_stretchRect);
  Hook(device, kSetRenderTarget, &SetRenderTargetHook, g_setRenderTarget);
  Hook(device, kSetDepthStencilSurface, &SetDepthHook, g_setDepth);
  Hook(device, kBeginScene, &BeginSceneHook, g_beginScene);
  Hook(device, kClear, &ClearHook, g_clear);
  Hook(device, kSetTransform, &SetTransformHook, g_setTransform);
  Hook(device, kSetViewport, &SetViewportHook, g_setViewport);
  Hook(device, kDrawPrimitive, &DrawPrimitiveHook, g_drawPrimitive);
  Hook(device, kDrawIndexedPrimitive, &DrawIndexedHook, g_drawIndexed);
  Hook(device, kDrawPrimitiveUP, &DrawUpHook, g_drawUp);
  Hook(device, kDrawIndexedPrimitiveUP, &DrawIndexedUpHook, g_drawIndexedUp);
  log::Info("frame probe: installed ([debug] frame_dump records a frame)");
}

void SetCut(int nth, unsigned long colour) {
  g_cutColour.store(colour);
  if (g_cutNth.exchange(nth) != nth) {
    if (nth > 0) {
      log::Info("frame probe: cutting the picture at depth-only clear %d of each frame (colour %08lX)", nth, colour);
    } else {
      log::Info("frame probe: no longer cutting the picture");
    }
  }
}

void OnPresent(IDirect3DDevice9* device) {
  g_depthClears = 0;
  const int state = g_state.load();
  if (state == 2) {
    Finish(device);
    g_state.store(0);
  } else if (state == 1) {
    {
      std::lock_guard<std::mutex> lock(g_requestMutex);
      g_recDirectory = g_directory;
      g_recLabel = g_label;
      g_recWanted = g_wanted;
    }
    g_lines.clear();
    g_draws = g_drawsLogged = g_snapshots = 0;
    g_state.store(2);
  }
}

void Request(const std::wstring& directory, const std::string& value) {
  std::lock_guard<std::mutex> lock(g_requestMutex);
  if (!g_haveLastValue) {
    g_haveLastValue = true;
    g_lastValue = value;
    return;
  }
  if (value == g_lastValue || value.empty() || !g_clear) {
    g_lastValue = value;
    return;
  }
  g_lastValue = value;
  if (g_state.load() != 0) return;  // still busy with the last one

  // "<label>" or "<label>: 120, 240"
  const size_t colon = value.find(':');
  std::string label = value.substr(0, colon);
  g_label.clear();
  for (const char c : label) {
    if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_') g_label += c;
  }
  if (g_label.empty()) g_label = "frame";
  g_wanted.clear();
  if (colon != std::string::npos) {
    const char* p = value.c_str() + colon + 1;
    while (*p) {
      char* end = nullptr;
      const long n = std::strtol(p, &end, 10);
      if (end == p) {
        ++p;
        continue;
      }
      g_wanted.insert(static_cast<int>(n));
      p = end;
    }
  }
  g_directory = directory;
  g_state.store(1);
}

}  // namespace wawbf::frameprobe
