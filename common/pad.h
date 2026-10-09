// A controller's buttons, read directly.
//
// Almost everything the bridges take from the player comes from the games'
// own records of their actions, so that it does not matter what is bound to
// what. A few things are no action of either game (the next ability, the
// next character, first or third person), and for those a button has to be
// looked at itself.
#pragma once

#include <cstdint>

namespace wawbf::pad {

// XInput's numbers for the d-pad, for wawbf.ini.
constexpr uint32_t kUp = 0x0001, kDown = 0x0002, kLeft = 0x0004, kRight = 0x0008;

// The buttons held on any controller, as XInput numbers them, or 0 if there
// is no controller or no XInput on this machine. It answers whichever window
// is in front.
uint32_t Buttons();

}  // namespace wawbf::pad
