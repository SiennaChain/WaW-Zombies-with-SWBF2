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
//
// And one for World at War, which matters more. Its own com_maxfps does not
// hold it in a map started this way: measured on a laptop with one integrated
// graphics chip, it drew 182 frames a second for a screen that shows 60, and
// Battlefront II, the window not in front, was left 18 to 43 (12 at worst),
// with 10 to 40 ms of each frame spent waiting for the chip to hand its
// picture back. The character is only as smooth as Battlefront II draws. So
// World at War's bridge holds it to the screen's refresh rate ([overlay]
// max_fps in its wawbf.ini), and what it no longer draws is Battlefront II's.
#pragma once

namespace wawbf::pace {

// What [overlay] max_fps means.
constexpr int kMatch = -1;     // as fast as World at War draws, and a tenth
constexpr int kFallback = 60;  // with kMatch, while World at War is not drawing

// fps > 0: at most that many frames a second. 0: no cap. kMatch: as above.
void Set(int fps);

// Battlefront II. Asks Windows to put this process's drawing ahead of other
// programs' on the graphics card: its window is never the one in front, and
// the one in front is otherwise served first. Once; later calls do nothing.
void RaiseGraphicsPriority();

// On the rendering thread, straight after each Present (World at War: each
// EndScene, see proxy_d3d9.cpp).
void AfterPresent();

}  // namespace wawbf::pace
