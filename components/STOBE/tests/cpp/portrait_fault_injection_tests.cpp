#include "PortraitFaultInjection.h"

#include <cstdio>
#include <stdexcept>

using namespace StobePortraitFaultInjection;

static int g_checks = 0;
static void check(bool condition, const char *message) {
  ++g_checks;
  if (!condition)
    throw std::runtime_error(message);
}

int main() {
  try {
    OneShot hook;
    check(!hook.arm(NONE, 101), "cannot arm an empty mode");
    check(!hook.arm(PRIVATE_RENDER_UNAVAILABLE, 0),
          "cannot arm without a target identity");
    check(hook.arm(PRIVATE_RENDER_UNAVAILABLE, 101),
          "private failure is armed for the displayed target");
    check(hook.mode() == PRIVATE_RENDER_UNAVAILABLE &&
              hook.targetSerial() == 101,
          "status exposes the pending mode and bound target");
    check(hook.takeFor(202) == NONE && hook.mode() == NONE,
          "a target switch discards rather than retargets a pending fault");

    check(hook.arm(PRIVATE_RENDER_UNAVAILABLE, 101),
          "private failure can be armed again");
    check(hook.takeFor(101) == PRIVATE_RENDER_UNAVAILABLE,
          "matching target consumes private failure");
    check(hook.takeFor(101) == NONE,
          "private failure is one-shot");

    check(hook.arm(ALL_RENDER_PATHS_UNAVAILABLE, 303),
          "dual-path failure is armed for the displayed target");
    check(hook.takeFor(303) == ALL_RENDER_PATHS_UNAVAILABLE,
          "matching target consumes dual-path failure");
    check(hook.mode() == NONE && hook.targetSerial() == 0,
          "dual-path failure clears its identity after consumption");

    check(hook.arm(PRIVATE_RENDER_UNAVAILABLE, 404),
          "clear-path test can arm a request");
    hook.clear();
    check(hook.takeFor(404) == NONE,
          "explicit clear prevents a pending fault");
  } catch (const std::exception &error) {
    std::printf("FAIL portrait_fault_injection_tests: %s (after %d checks)\n",
                error.what(), g_checks);
    return 1;
  }
  std::printf("PASS portrait_fault_injection_tests (%d checks)\n", g_checks);
  return 0;
}
