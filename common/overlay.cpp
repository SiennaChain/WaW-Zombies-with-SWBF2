#include "overlay.h"

#include <windows.h>

#include <d3d9.h>

#include <atomic>
#include <cstring>

#include "clock.h"
#include "log.h"
#include "wawbf_protocol.h"

namespace wawbf::overlay {
namespace {

std::atomic<bool> g_publish{false};
std::atomic<bool> g_draw{false};
std::atomic<bool> g_standAside{false};
std::atomic<bool> g_blank{false};
std::atomic<bool> g_mark{false};
std::atomic<float> g_markX{0}, g_markY{0};

// The second mapping. Either side may arrive first; whoever does creates it.
FrameHeader* g_header = nullptr;
BYTE* g_pixels[2] = {nullptr, nullptr};
bool g_mappingFailed = false;

bool OpenMapping() {
  if (g_header) return true;
  if (g_mappingFailed) return false;
  const HANDLE handle = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                           kFrameMappingSize, kFrameMappingName);
  void* view = handle ? MapViewOfFile(handle, FILE_MAP_ALL_ACCESS, 0, 0, kFrameMappingSize) : nullptr;
  if (!view) {
    log::Error("overlay: could not open the picture mapping (%lu)", GetLastError());
    g_mappingFailed = true;
    return false;
  }
  g_header = static_cast<FrameHeader*>(view);
  g_pixels[0] = static_cast<BYTE*>(view) + sizeof(FrameHeader);
  g_pixels[1] = g_pixels[0] + kFrameMaxBytes;
  return true;
}

void Once(bool& said, const char* message) {
  if (!said) log::Info("%s", message);
  said = true;
}

// --- publishing (SWBF2) ------------------------------------------------------

IDirect3DSurface9* g_copy = nullptr;  // a main-memory surface the back buffer is read into
UINT g_copyWidth = 0, g_copyHeight = 0;
D3DFORMAT g_copyFormat = D3DFMT_UNKNOWN;

// --- drawing (WaW) -----------------------------------------------------------

IDirect3DTexture9* g_texture = nullptr;
IDirect3DDevice9* g_textureDevice = nullptr;
UINT g_textureWidth = 0, g_textureHeight = 0;
uint32_t g_drawnSequence = 0;
bool g_haveDrawn = false;
DWORD g_lastNewPicture = 0;  // GetTickCount when the sequence last moved
std::atomic<DWORD> g_lastDrawn{0};  // GetTickCount when a picture was last drawn; 0 = never

struct Vertex {
  float x, y, z, rhw, u, v;
};

}  // namespace

void SetPublish(bool on) {
  if (g_publish.exchange(on) != on) log::Info("overlay: %s", on ? "publishing this game's picture" : "no longer publishing");
}

void SetDraw(bool on) {
  if (g_draw.exchange(on) != on) log::Info("overlay: %s", on ? "drawing the other game's picture over this one" : "no longer drawing");
}

void Publish(IDirect3DDevice9* device) {
  if (!g_publish.load(std::memory_order_relaxed) || !OpenMapping()) return;
  static bool saidWrongFormat = false, saidTooBig = false, saidFailed = false, saidOk = false;

  IDirect3DSurface9* back = nullptr;
  if (FAILED(device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &back)) || !back) return;
  D3DSURFACE_DESC desc{};
  back->GetDesc(&desc);
  if (desc.Format != D3DFMT_A8R8G8B8) {
    // Without an alpha channel there is nothing to say where the weapon is.
    Once(saidWrongFormat, "overlay: the back buffer has no alpha channel; nothing is published");
    back->Release();
    return;
  }
  if (desc.Width > kFrameMaxWidth || desc.Height > kFrameMaxHeight) {
    Once(saidTooBig, "overlay: the picture is larger than the mapping allows; nothing is published");
    back->Release();
    return;
  }
  if (!g_copy || g_copyWidth != desc.Width || g_copyHeight != desc.Height || g_copyFormat != desc.Format) {
    if (g_copy) g_copy->Release();
    g_copy = nullptr;
    if (FAILED(device->CreateOffscreenPlainSurface(desc.Width, desc.Height, desc.Format, D3DPOOL_SYSTEMMEM,
                                                   &g_copy, nullptr))) {
      back->Release();
      return;
    }
    g_copyWidth = desc.Width;
    g_copyHeight = desc.Height;
    g_copyFormat = desc.Format;
  }

  D3DLOCKED_RECT locked{};
  if (SUCCEEDED(device->GetRenderTargetData(back, g_copy)) &&
      SUCCEEDED(g_copy->LockRect(&locked, nullptr, D3DLOCK_READONLY))) {
    const uint32_t slot = 1 - (g_header->front.load(std::memory_order_relaxed) & 1);
    BYTE* out = g_pixels[slot];
    const BYTE* in = static_cast<const BYTE*>(locked.pBits);
    const size_t row = static_cast<size_t>(desc.Width) * 4;
    if (g_blank.load(std::memory_order_relaxed)) {
      std::memset(out, 0, row * desc.Height);  // nothing anywhere: the other game's picture shows through untouched
    } else {
      for (UINT y = 0; y < desc.Height; ++y) std::memcpy(out + y * row, in + y * locked.Pitch, row);
    }
    g_copy->UnlockRect();
    g_header->width[slot] = desc.Width;
    g_header->height[slot] = desc.Height;
    g_header->timeUs[slot] = NowUs();
    g_header->front.store(slot, std::memory_order_release);
    g_header->sequence.fetch_add(1, std::memory_order_release);
    g_header->magic.store(kFrameMagic, std::memory_order_release);
    if (!saidOk) log::Info("overlay: publishing a %ux%u picture each frame", desc.Width, desc.Height);
    saidOk = true;
  } else {
    Once(saidFailed, "overlay: could not read the back buffer back; nothing is published");
  }
  back->Release();
}

void Draw(IDirect3DDevice9* device) {
  if (!g_draw.load(std::memory_order_relaxed) || !OpenMapping()) return;
  if (g_header->magic.load(std::memory_order_acquire) != kFrameMagic) return;
  static bool saidOk = false;

  const DWORD now = GetTickCount();
  const uint32_t sequence = g_header->sequence.load(std::memory_order_acquire);
  const bool fresh = !g_haveDrawn || sequence != g_drawnSequence;
  static uint32_t arrived = 0;
  static bool anyArrived = false;
  if (!anyArrived || sequence != arrived) {
    arrived = sequence;
    anyArrived = true;
    g_lastNewPicture = now;
  }
  // The other game has stopped (closed, loading, crashed): better no weapon than a frozen one.
  if (now - g_lastNewPicture > 500) return;
  // Standing aside: the picture is arriving and would be drawn, and counts as
  // drawn for everyone who asks, but this game is showing something of its own
  // in its place for a moment.
  if (g_standAside.load(std::memory_order_relaxed)) {
    g_lastDrawn.store(now ? now : 1, std::memory_order_relaxed);
    return;
  }

  const uint32_t slot = g_header->front.load(std::memory_order_acquire) & 1;
  const UINT width = g_header->width[slot], height = g_header->height[slot];
  if (!width || !height || width > kFrameMaxWidth || height > kFrameMaxHeight) return;

  // A managed texture survives the device being reset, so there is nothing to
  // release when WaW changes resolution. It does not survive a new device.
  if (!g_texture || g_textureDevice != device || g_textureWidth != width || g_textureHeight != height) {
    if (g_texture && g_textureDevice == device) g_texture->Release();
    g_texture = nullptr;
    if (FAILED(device->CreateTexture(width, height, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &g_texture, nullptr))) {
      return;
    }
    g_textureDevice = device;
    g_textureWidth = width;
    g_textureHeight = height;
    g_haveDrawn = false;
  }
  if (fresh || !g_haveDrawn) {
    D3DLOCKED_RECT locked{};
    if (FAILED(g_texture->LockRect(0, &locked, nullptr, 0))) return;
    const BYTE* in = g_pixels[slot];
    const size_t row = static_cast<size_t>(width) * 4;
    for (UINT y = 0; y < height; ++y) std::memcpy(static_cast<BYTE*>(locked.pBits) + y * locked.Pitch, in + y * row, row);
    g_texture->UnlockRect(0);
    g_drawnSequence = sequence;
    g_haveDrawn = true;
  }

  // Everything this changes is put back: the game keeps its own record of the
  // device's state and must not find it different.
  IDirect3DStateBlock9* saved = nullptr;
  if (FAILED(device->CreateStateBlock(D3DSBT_ALL, &saved)) || !saved) return;

  D3DVIEWPORT9 viewport{};
  device->GetViewport(&viewport);
  const float left = static_cast<float>(viewport.X) - 0.5f, top = static_cast<float>(viewport.Y) - 0.5f;
  const float right = left + static_cast<float>(viewport.Width), bottom = top + static_cast<float>(viewport.Height);
  const Vertex quad[4] = {{left, top, 0, 1, 0, 0}, {right, top, 0, 1, 1, 0}, {left, bottom, 0, 1, 0, 1}, {right, bottom, 0, 1, 1, 1}};

  device->SetVertexShader(nullptr);
  device->SetPixelShader(nullptr);
  device->SetFVF(D3DFVF_XYZRHW | D3DFVF_TEX1);
  device->SetTexture(0, g_texture);
  device->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
  device->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
  device->SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1);
  device->SetTextureStageState(0, D3DTSS_ALPHAARG1, D3DTA_TEXTURE);
  device->SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, 0);
  device->SetTextureStageState(0, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
  device->SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
  device->SetTextureStageState(1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
  device->SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
  device->SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
  device->SetSamplerState(0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
  device->SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  device->SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
  device->SetSamplerState(0, D3DSAMP_SRGBTEXTURE, FALSE);
  device->SetRenderState(D3DRS_ZENABLE, D3DZB_FALSE);
  device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
  device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
  device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
  device->SetRenderState(D3DRS_SEPARATEALPHABLENDENABLE, FALSE);
  device->SetRenderState(D3DRS_BLENDOP, D3DBLENDOP_ADD);
  device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);  // the colour is already multiplied by its alpha
  device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
  device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
  device->SetRenderState(D3DRS_LIGHTING, FALSE);
  device->SetRenderState(D3DRS_FOGENABLE, FALSE);
  device->SetRenderState(D3DRS_STENCILENABLE, FALSE);
  device->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);
  device->SetRenderState(D3DRS_CLIPPLANEENABLE, 0);
  device->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
  device->SetRenderState(D3DRS_COLORWRITEENABLE, D3DCOLORWRITEENABLE_RED | D3DCOLORWRITEENABLE_GREEN | D3DCOLORWRITEENABLE_BLUE);
  device->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, quad, sizeof(Vertex));

  // The crosshair: four short bars round a gap, dark behind and light on top.
  if (g_mark.load(std::memory_order_relaxed)) {
    const float cx = left + (g_markX.load(std::memory_order_relaxed) * 0.5f + 0.5f) * static_cast<float>(viewport.Width);
    const float cy = top + (0.5f - g_markY.load(std::memory_order_relaxed) * 0.5f) * static_cast<float>(viewport.Height);
    const float unit = static_cast<float>(viewport.Height) / 720.0f;
    struct Flat {
      float x, y, z, rhw;
      DWORD colour;
    };
    const auto bar = [&](float x0, float y0, float x1, float y1, DWORD colour) {
      const Flat v[4] = {{x0, y0, 0, 1, colour}, {x1, y0, 0, 1, colour}, {x0, y1, 0, 1, colour}, {x1, y1, 0, 1, colour}};
      device->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, sizeof(Flat));
    };
    device->SetTexture(0, nullptr);
    device->SetFVF(D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
    device->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    device->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_DIFFUSE);
    device->SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1);
    device->SetTextureStageState(0, D3DTSS_ALPHAARG1, D3DTA_DIFFUSE);
    device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
    for (int pass = 0; pass < 2; ++pass) {
      const float grow = pass == 0 ? 1.5f * unit : 0.0f;                 // the dark edge first
      const DWORD colour = pass == 0 ? 0xB0000000 : 0xF0FFFFFF;
      const float gap = 5.0f * unit, length = 9.0f * unit, half = 1.0f * unit;
      bar(cx - gap - length - grow, cy - half - grow, cx - gap + grow, cy + half + grow, colour);
      bar(cx + gap - grow, cy - half - grow, cx + gap + length + grow, cy + half + grow, colour);
      bar(cx - half - grow, cy - gap - length - grow, cx + half + grow, cy - gap + grow, colour);
      bar(cx - half - grow, cy + gap - grow, cx + half + grow, cy + gap + length + grow, colour);
      bar(cx - half - grow, cy - half - grow, cx + half + grow, cy + half + grow, colour);
    }
  }

  saved->Apply();
  saved->Release();
  g_lastDrawn.store(now ? now : 1, std::memory_order_relaxed);
  if (!saidOk) log::Info("overlay: drawing a %ux%u picture over a %lux%lu view", width, height, viewport.Width, viewport.Height);
  saidOk = true;
}

void SetStandAside(bool aside) { g_standAside.store(aside, std::memory_order_relaxed); }

void SetBlank(bool blank) { g_blank.store(blank, std::memory_order_relaxed); }

void SetMark(bool on, float x, float y) {
  g_markX.store(x, std::memory_order_relaxed);
  g_markY.store(y, std::memory_order_relaxed);
  g_mark.store(on, std::memory_order_relaxed);
}

bool Drawing() {
  const DWORD last = g_lastDrawn.load(std::memory_order_relaxed);
  return last != 0 && GetTickCount() - last < 500;
}

}  // namespace wawbf::overlay
