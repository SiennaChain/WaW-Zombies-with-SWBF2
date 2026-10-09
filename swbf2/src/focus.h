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
// War's later. Leave it 0 while there are menus to click through. The window
// is not hidden after it has appeared but kept from appearing: the game's
// calls to show it are answered without being carried out. A window that
// never shows never comes to the front either, which matters once World at
// War has the whole screen: anything coming in front of that puts it away.
//
// And the pointer. The game puts the pointer back in the middle of its window
// every frame it believes it is in front, which with keep_running is every
// frame: the pointer could not be used for anything else, World at War's
// menus included. With [swbf2] pointer_in_background = 0 the game only moves
// the pointer while its window really is the one in front.
#pragma once

namespace wawbf::focus {

// Call once, before the game has made its window: the hooks that keep the
// window from showing and the pointer from being moved have to be in place
// before the game first shows the one and moves the other.
void Start(bool hidden, bool pointerInBackground);

// Call every bridge tick with the current settings. Nothing in the game is
// hooked for keepRunning until the first time it is true; after that, false
// makes those hooks pass everything through unchanged. All three can be
// switched at any time.
void Tick(bool keepRunning, bool hidden, bool pointerInBackground);

}  // namespace wawbf::focus
