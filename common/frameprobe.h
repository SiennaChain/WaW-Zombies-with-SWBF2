// Records how a game draws one frame.
//
// Phase 2 lays Battlefront II's first-person weapon over World at War's
// picture, which means knowing where in a frame the weapon is drawn and what
// sets that part off from the rest: a depth clear, a change of render target,
// a different viewport. Nothing says, so the frame is written down.
//
// On request the next whole frame is recorded: every clear, every change of
// render target, depth buffer, viewport and projection, and how many draw
// calls came between them. The picture so far is saved as a .bmp at each
// depth-only clear, at the end of the frame, and before any draw calls asked
// for by number, which is how the draw call the weapon first appears in gets
// bisected.
//
// It costs one flag test per hooked call while not recording, but it is still
// only installed when asked for ([debug] frame_probe = 1 at start-up).
#pragma once

#include <string>

struct IDirect3DDevice9;

namespace wawbf::frameprobe {

// Hooks the device's drawing calls. Safe to call for every device created.
void Install(IDirect3DDevice9* device);

// Call from the Present hook, before the real Present.
void OnPresent(IDirect3DDevice9* device);

// The current value of [debug] frame_dump: "<any label>" or
// "<label>: 120, 240, 360" to also save the picture before those draw calls.
// A recording starts when the value changes; the first value seen after
// start-up is only remembered. Output goes to `directory` as
// wawbf_frame_<label>.txt and wawbf_frame_<label>_*.bmp.
void Request(const std::wstring& directory, const std::string& value);

// An experiment in cutting the frame in two. With nth > 0, the nth depth-only
// clear of every frame also clears the picture to `colour` (alpha, red,
// green, blue), so that only what is drawn after it is left at the end.
// In Battlefront II the second such clear comes just before the first-person
// weapon and the HUD. 0 turns it off.
void SetCut(int nth, unsigned long colour);

// The other way to end up with only the player's side of a frame: a world
// with nothing in it. Then nothing has to be cut away, but two things would
// still make the picture solid from edge to edge, and with this on neither
// does:
//
// - The game starts each picture as solid black. Every clear of a picture
//   is to transparent black instead.
// - Part-way through, Battlefront II lays its far scene (a picture it drew
//   earlier in the frame) in behind what is already there, solid. A draw
//   call in the world's part of the frame that takes its picture from an
//   earlier one keeps its colour but no longer writes alpha.
//
// What the frame did not draw on then stays see-through.
void SetTransparentClears(bool on);

// Two more things the whole-frame picture is better without, both of them the
// game's own and neither something it can be told to leave out.
//
// - The ground. A world cannot be built without a terrain, and with none of
//   it switched on the game will not put the player into the world. So one
//   small square is left on, and the game draws it (a strip of triangles,
//   always the same number of corners and of triangles) wherever the player
//   is: as a line of grass on the horizon. A draw call of a strip with
//   exactly `vertices` corners and `primitives` triangles, before the frame
//   reaches the HUD, is not made. 0, 0 for none.
// - Most of the HUD. The game draws its HUD last, through a lens of its own
//   that never changes (`lens`: the projection's x scale, 1.7321 at 16:9).
//   From the first time that lens is set after the frame's second depth-only
//   clear, every draw call is confined to one part of the picture (left,
//   top, right, bottom, each 0 to 1 across or down it), and what the HUD
//   would have drawn elsewhere is not drawn.
void SetHiddenShape(unsigned vertices, unsigned primitives);
void SetHudKeep(bool on, float left, float top, float right, float bottom, float lens);

// A second part of the HUD that can be kept: the middle of the picture, where
// the game draws its crosshair. It must not overlap the first. Only with
// SetHudKeep on.
void SetHudMiddle(bool on, float left, float top, float right, float bottom);

// Which of the two parts are drawn just now: `keep` the one SetHudKeep names,
// `middle` the one SetHudMiddle names. Neither: nothing of the HUD is drawn.
// The weapons go while the game is zoomed in (it draws something else where
// they were); the crosshair is wanted only when there is something to aim.
void SetHudShown(bool keep, bool middle);

// Told of every SetTransform the game makes, on its rendering thread, before
// the call goes through: which transform (D3DTS_VIEW is 2, D3DTS_WORLD 256),
// and where in the game the call came from. A game sets these at fixed points
// in its drawing, so "this transform, from that address" names a moment in
// the frame; Battlefront II's camera is readied at one. One observer at a
// time; null for none. It must be quick.
using TransformObserver = void (*)(unsigned state, void* caller);
void SetTransformObserver(TransformObserver observer);

}  // namespace wawbf::frameprobe
