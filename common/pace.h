// A frame cap for Battlefront II.
//
// Its window is never shown, so nothing slows it down: not the screen's
// refresh, not the game itself. Left alone it draws, reads back and copies
// frames as fast as it can, and every frame beyond the ones World at War
// draws is thrown away, while it takes graphics time and memory bandwidth
// from World at War. On a PC whose one graphics chip runs both games, that
// is World at War's frame rate.
//
// So SWBF2 is held to World at War's own rate, which World at War's bridge
// writes into the picture mapping every frame (FrameHeader::readerFrameUs),
// with a tenth over so a new picture is nearly always ready.
//
// The wait is taken just after Present returns: the game's next frame then
// starts after it, with World at War's newest position, so it adds nothing to
// how late the picture is.
#pragma once

namespace wawbf::pace {

// What [overlay] max_fps means.
constexpr int kMatch = -1;     // as fast as World at War draws, and a tenth
constexpr int kFallback = 60;  // with kMatch, while World at War is not drawing

// fps > 0: at most that many frames a second. 0: no cap. kMatch: as above.
void Set(int fps);

// On the rendering thread, straight after each Present.
void AfterPresent();

}  // namespace wawbf::pace
