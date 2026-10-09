// Keeps the game's sound playing while another window has the keyboard.
//
// The game plays its sound through DirectSound, which goes quiet for a
// program the moment it is not the one in front, unless a sound was made
// with "global focus" asked for. This game never asks. Played under World at
// War it is never in front, so none of it was heard at all: not its blasters,
// not its lightsabers.
//
// KeepPlaying makes every sound the game creates from then on one that plays
// regardless: the one routine of DirectSound's that creates a sound is sent
// through ours first, which adds the request. Call it before the game has
// started its own sound up (the bridge is loaded before anything of the
// game's runs). What the game is given back, and everything it does with it,
// is DirectSound's own.
#pragma once

namespace wawbf::sound {

// Returns false if DirectSound is not there to change (no sound device, say).
bool KeepPlaying();

// How many sounds have been made to play regardless so far.
unsigned Made();

// Says in the log how many, whenever that has changed. For the bridge's
// once-a-second turn.
void Report();

// Says in the log what the first few sounds are doing now: playing or not,
// how loud the game has set each. For [debug] log_sound = 1.
void Describe();

}  // namespace wawbf::sound
