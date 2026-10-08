// Keeps a Battlefront II match playing when its window is not the focused one.
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
#pragma once

namespace wawbf::focus {

// Call every bridge tick with the current keep_running setting. Nothing in
// the game is touched until the first time it is true; after that, false
// makes the hooks pass everything through unchanged.
void Tick(bool enabled);

}  // namespace wawbf::focus
