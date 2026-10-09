// Phase 2: Battlefront II's first-person weapon and HUD, drawn over World at
// War's picture.
//
// How the weapon is cut out of SWBF2's frame was found with the frame probe
// (docs/PHASE2.md). SWBF2 draws the world, clears the depth buffer, and only
// then draws the first-person weapon and after it the HUD. If the picture is
// cleared to transparent black at that same clear, what is left at the end of
// the frame is the weapon and the HUD and nothing else, and the frame's own
// alpha channel says where they are: solid things write full alpha, the HUD's
// blended parts write part, and everything untouched stays at none.
//
// That cut loses whatever belongs to the player but is drawn with the world:
// their shots, and in third person their character. So the arena was changed
// to draw nothing but the player, and the probe is asked instead to keep the
// whole frame and make its black background see-through (docs/PHASE2.md,
// "Nothing to cut"). Either way the frame's alpha channel is the mask.
//
// The publishing side (SWBF2) asks the probe for one or the other, and at the
// end of each frame copies its back buffer into shared memory. The drawing side
// (WaW) copies the newest picture into a texture and draws it across the
// screen at the end of its own frame.
//
// It goes through main memory both ways, which costs a few milliseconds a
// frame and puts the weapon a frame or so behind. Sharing the surface on the
// graphics card would avoid both but needs Direct3D 9Ex, which these games do
// not use.
#pragma once

struct IDirect3DDevice9;

namespace wawbf::overlay {

// SWBF2. Publish() is called once per frame, before the frame is presented;
// it does nothing unless SetPublish(true).
void SetPublish(bool on);
void Publish(IDirect3DDevice9* device);
// While true the picture published is empty: a picture still arrives, so the
// other side carries on as it was, but there is nothing in it. For the moment
// one character is taken away and the next put in its place.
void SetBlank(bool blank);

// WaW. Draw() is called just before the end of each scene; it does nothing
// unless SetDraw(true), or if no picture has arrived for half a second.
void SetDraw(bool on);
void Draw(IDirect3DDevice9* device);
// True while the other game's picture is really going onto the screen: a
// picture was drawn within the last half second.
bool Drawing();
// While true the picture is left off the screen, though it still counts as
// being drawn: for the moments this game shows something of its own where
// the other's would be (its knife).
void SetStandAside(bool aside);
// A crosshair drawn over the picture: where, from -1 to 1 across the view and
// from -1 (bottom) to 1 (top) up it. For the view from behind the character:
// it marks the spot the next shot is pointed at.
void SetMark(bool on, float x, float y);

}  // namespace wawbf::overlay
