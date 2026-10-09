// Sends one of the game's own calls through a function of ours first.
//
// Some things can only be done at a particular moment inside the game's
// frame: after it has worked something out and before it uses it. The game
// has no hook for that, but it does make calls, and a call can be pointed
// somewhere else. Install takes the address of one five-byte `call` in the
// game and makes it call a few bytes of ours instead; those save every
// register, call the handler, put every register back, and go on to the
// function the game meant to call, which never knows.
//
// The handler is given what the game had in esi at that point, since the two
// routines hooked so far keep the object they are working on there.
#pragma once

#include <cstdint>

namespace wawbf::callhook {

using Handler = void(__cdecl*)(void* esi);

// `site` is where the call is, and `expected` the five bytes it should be
// found as (E8 and the distance to the function called). If they are anything
// else this is not the build the address was found in: nothing is changed and
// false is returned.
//
// The change is one four-byte store. If those four bytes do not sit on a
// four-byte boundary the store is not atomic, and this must then be called
// from the game's own thread (or at some other time that thread cannot be
// making the call).
bool Install(uintptr_t site, const unsigned char expected[5], Handler handler);

// The same, the other way round: the function the game meant to call is
// called first, and the handler afterwards, to look at what it gave back or
// to change it. The handler is given where the game's arguments to that call
// sit on the stack (arguments[0] is the first), and the word just below them,
// reinterpret_cast<uint32_t*>(arguments)[-1], is what the function returned,
// which the game is then handed (changed, if the handler changed it).
//
// Only for a call whose caller takes the arguments off the stack again, and
// that is never under way twice at once: the way back is kept in one place.
using After = void(__cdecl*)(void** arguments);
bool InstallAfter(uintptr_t site, const unsigned char expected[5], After handler);

}  // namespace wawbf::callhook
