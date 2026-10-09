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

}  // namespace wawbf::callhook
