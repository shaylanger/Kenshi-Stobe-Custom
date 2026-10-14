#ifndef STOBE_PORTRAIT_FAULT_INJECTION_H
#define STOBE_PORTRAIT_FAULT_INJECTION_H

#include <cstdint>

namespace StobePortraitFaultInjection {

enum Mode {
  NONE = 0,
  PRIVATE_RENDER_UNAVAILABLE = 1,
  ALL_RENDER_PATHS_UNAVAILABLE = 2
};

// A one-shot fault request bound to the currently displayed NPC. A target
// change consumes and discards it, so a queued fault can never affect another
// character. This policy is independent of Ogre/game objects.
class OneShot {
public:
  OneShot() : mode_(NONE), targetSerial_(0) {}

  bool arm(Mode mode, std::uint32_t targetSerial) {
    if ((mode != PRIVATE_RENDER_UNAVAILABLE &&
         mode != ALL_RENDER_PATHS_UNAVAILABLE) || targetSerial == 0)
      return false;
    mode_ = mode;
    targetSerial_ = targetSerial;
    return true;
  }

  Mode takeFor(std::uint32_t targetSerial) {
    const Mode requested = mode_;
    const std::uint32_t requestedTarget = targetSerial_;
    clear();
    return requestedTarget != 0 && requestedTarget == targetSerial
               ? requested : NONE;
  }

  void clear() {
    mode_ = NONE;
    targetSerial_ = 0;
  }

  Mode mode() const { return mode_; }
  std::uint32_t targetSerial() const { return targetSerial_; }

private:
  Mode mode_;
  std::uint32_t targetSerial_;
};

} // namespace StobePortraitFaultInjection

#endif
