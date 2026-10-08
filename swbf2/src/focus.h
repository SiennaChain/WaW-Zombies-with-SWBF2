// Lets Battlefront II be the hidden game: playing on when its window is not
// the focused one, and with no window showing at all.
//
// Windowed, the game keeps rendering when another window is clicked, but a
// match pauses. The hidden game has to play on behind World at War, so with
// [swbf2] keep_running = 1 the game is told it always has the focus: its
// GetForegroundWindow / GetFocus calls answer with its own window, and the
// window messages that announce losing focus are withheld from it.
//
// "Is it still running" has to be judged by whether units move
// (tools/probe/bfsim.ps1). Memory activity looks healthy while paused, which
// is how this was wrongly written off as unnecessary once already.
//
// With [swbf2] hidden = 1 its window is not shown either. The game goes on
// drawing frames and playing the match with its window hidden (checked with
// bfsim.ps1), which is what lets its picture be taken and laid over World at
// War's later. Leave it 0 while there are menus to click through.
#pragma once

namespace wawbf::focus {

// Call every bridge tick with the current settings. Nothing in the game is
// hooked until the first time keepRunning is true; after that, false makes
// the hooks pass everything through unchanged. hidden can be switched at any
// time.
void Tick(bool keepRunning, bool hidden);

}  // namespace wawbf::focus
