// Danger interrupt vs. in-flight replies (StobeChatInterruptPolicy.h, m50 D86):
// danger-only supersession keeps action lines, hard interrupts and director
// scenes abort, danger fired only by the chat partner is skipped.
#include "StobeChatInterruptPolicy.h"

#include <cstdio>
#include <set>
#include <stdexcept>
#include <string>

using namespace StobeChatInterrupt;

static int g_checks = 0;
static void check(bool ok, const std::string &what) {
  ++g_checks;
  if (!ok) throw std::runtime_error(what);
}

struct SetPred {
  const std::set<unsigned int> *s;
  bool operator()(unsigned int v) const { return s->count(v) != 0; }
};

int main() {
  try {
    // Reply gen 361 (player send = hard interrupt, lastHard=361).
    check(DecideStreamLine(361, 361, 361, false, true) == LINE_PROCESS, "current reply processes");
    // D86: danger interrupt bumped to 362, lastHard still 361 -> actions only.
    check(DecideStreamLine(361, 362, 361, false, true) == LINE_ACTIONS_ONLY, "danger keeps actions");
    check(DecideStreamLine(361, 370, 361, false, true) == LINE_ACTIONS_ONLY, "repeated danger keeps actions");
    // A newer player message (hard, lastHard=363) ends the old reply.
    check(DecideStreamLine(361, 363, 363, false, true) == LINE_ABORT, "hard interrupt aborts");
    check(DecideStreamLine(361, 365, 363, false, true) == LINE_ABORT, "hard then danger aborts");
    // Director scenes never continue after any interrupt.
    check(DecideStreamLine(361, 362, 361, true, true) == LINE_ABORT, "director aborts on danger");
    check(DecideStreamLine(361, 361, 361, true, true) == LINE_PROCESS, "director current processes");
    // Interaction disabled / no generation.
    check(DecideStreamLine(361, 361, 361, false, false) == LINE_ABORT, "interaction off aborts");
    check(DecideStreamLine(0, 362, 1, false, true) == LINE_ABORT, "gen 0 aborts");
    // Background reply from GetChatInterruptGeneration (above lastHard) then danger.
    check(DecideStreamLine(366, 367, 361, false, true) == LINE_ACTIONS_ONLY, "background reply keeps actions");

    std::set<unsigned int> partners;
    partners.insert(552490240u); // Garro Vex, truce negotiation in flight
    SetPred pred;
    pred.s = &partners;
    DangerActor onlyPartner[] = {{552490240u, 160}};
    check(ShouldSkipDangerInterrupt(onlyPartner, 1, 3000, pred), "partner-only danger skipped");
    DangerActor partnerAndOther[] = {{552490240u, 160}, {27099610u, 900}};
    check(!ShouldSkipDangerInterrupt(partnerAndOther, 2, 3000, pred), "another attacker interrupts");
    DangerActor oldOther[] = {{27099610u, 5000}, {552490240u, 100}};
    check(ShouldSkipDangerInterrupt(oldOther, 2, 3000, pred), "old other attacker ignored");
    DangerActor none[] = {{552490240u, 4000}};
    check(!ShouldSkipDangerInterrupt(none, 1, 3000, pred), "no recent danger -> interrupt");
    check(!ShouldSkipDangerInterrupt(none, 0, 3000, pred), "empty -> interrupt");
    DangerActor unknown[] = {{0u, 100}};
    check(!ShouldSkipDangerInterrupt(unknown, 1, 3000, pred), "unknown actor interrupts");
    partners.clear();
    check(!ShouldSkipDangerInterrupt(onlyPartner, 1, 3000, pred), "no active reply -> interrupt");
  } catch (const std::exception &e) {
    std::printf("FAIL chat_interrupt_policy_tests: %s (after %d checks)\n", e.what(), g_checks);
    return 1;
  }
  std::printf("PASS chat_interrupt_policy_tests (%d checks)\n", g_checks);
  return 0;
}
