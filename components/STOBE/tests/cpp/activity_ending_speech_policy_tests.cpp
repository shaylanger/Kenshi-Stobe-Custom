// imm26 huntA1: retry policy of the give-up line (header-only, no game SDK).
// Build: g++ -std=gnu++11 -I<dir with ActivityEndingSpeech.h> activity_ending_speech_policy_tests.cpp
#include "ActivityEndingSpeech.h"
#include <cstdio>
using namespace Stobe::Activity::EndingSpeechPolicy;
static int failures = 0;
#define CHECK(c) do { if (!(c)) { ++failures; std::printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)
int main() {
  CHECK(Decide(1000, 1000, 1000 + kSettleMs, true) == Wait);              // settling: the server has not stored the event yet
  CHECK(Decide(1000 + kSettleMs, 1000, 1000 + kSettleMs, true) == Dispatch);
  CHECK(Decide(1000 + kSettleMs, 1000, 1000 + kSettleMs, false) == Wait); // a gate is closed (TTS / other request)
  CHECK(Decide(1000 + kGiveUpMs, 1000, 2000, true) == Expire);            // 90 s: stop asking
  CHECK(Decide(1000 + kGiveUpMs - 1, 1000, 2000, true) == Dispatch);
  CHECK(NextDue(5000) == 5000 + kRetryMs);
  // GetTickCount wraps every ~49.7 days
  CHECK(Decide(10, 0xFFFFFFF0u, 5, true) == Dispatch);
  CHECK(Decide(0xFFFFFFF0u, 0xFFFFFFE0u, 3, true) == Wait);
  if (failures) { std::printf("RESULT activity_ending_speech_policy FAIL %d\n", failures); return 1; }
  std::printf("RESULT activity_ending_speech_policy PASS\n"); return 0;
}
