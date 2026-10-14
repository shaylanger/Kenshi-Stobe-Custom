#include "NpcPanelRequestPolicy.h"

#include <cstdio>
#include <stdexcept>
#include <string>

using namespace StobeNpcPanelRequestPolicy;

static int g_checks = 0;
static void check(bool ok, const char *message) {
  ++g_checks;
  if (!ok) throw std::runtime_error(message);
}

int main() {
  try {
    // Regression: Stennic's card was opened from chat (serial 3465088000),
    // then selection moved to Malzin while the card stayed open. The initial
    // selection (Shay) differs from Stennic, but that mismatch alone must not
    // be mistaken for a new selection.
    const unsigned int stennic = 3465088000u;
    const unsigned int shay = 1001u;
    const unsigned int malzin = 123456789u;
    check(!ShouldRefreshForSelection(true, 0, shay, stennic),
          "first open-panel tick records selection without replacing chat target");
    const unsigned int selectionBeforeInfoRequest = shay;
    const unsigned int selectionAtInfoRequest = malzin;
    const unsigned int rebasedSelection = SelectionBaselineAfterRequest(
        true, selectionAtInfoRequest, selectionBeforeInfoRequest);
    check(rebasedSelection == malzin &&
              !ShouldRefreshForSelection(true, rebasedSelection,
                                         selectionAtInfoRequest, stennic),
          "Info request rebases selection changed before the request");
    check(SelectionBaselineAfterRequest(false, malzin, shay) == shay,
          "failed Info request leaves the previous observation intact");
    check(!ShouldRefreshForSelection(true, shay, shay, stennic),
          "unchanged selection does not replace a chat target card");
    check(ShouldRefreshForSelection(true, shay, malzin, stennic),
          "open panel refreshes for a different selected target");
    check(!ShouldRefreshForSelection(true, shay, stennic, stennic),
          "selecting the target already shown does not duplicate its request");
    check(!ShouldRefreshForSelection(true, shay, 0, stennic),
          "invalid selection does not replace the current card");
    check(!ShouldRefreshForSelection(false, shay, malzin, stennic),
          "closed panel does not request a selection refresh");

    // A transient target-resolution failure must not consume the selection
    // edge. The next tick should try the refresh again, then remember it only
    // after success.
    const unsigned int afterFailedAttempt = SelectionBaselineAfterTick(
        true, false, malzin, shay);
    check(afterFailedAttempt == shay &&
              ShouldRefreshForSelection(true, afterFailedAttempt, malzin,
                                        stennic),
          "failed selection refresh retries on the next tick");
    const unsigned int afterSuccessfulAttempt = SelectionBaselineAfterTick(
        true, true, malzin, afterFailedAttempt);
    check(afterSuccessfulAttempt == malzin &&
              !ShouldRefreshForSelection(true, afterSuccessfulAttempt, malzin,
                                         stennic),
          "successful refresh consumes the selection edge exactly once");

    // Starting the Malzin request advances generation and changes key. A late
    // Stennic response must not overwrite the new title, text, or portrait.
    const long oldGeneration = 10;
    const long newGeneration = 11;
    const std::string oldKey = "3465088000|Shay";
    const std::string newKey = "123456789|Shay";
    check(!ReplyMatches(oldGeneration, newGeneration, oldKey, newKey),
          "late old-target response is rejected after selection refresh");
    check(!ReplyMatches(newGeneration, newGeneration, oldKey, newKey),
          "old key is rejected even if a generation is reused");
    check(ReplyMatches(newGeneration, newGeneration, newKey, newKey),
          "current target response is accepted");
  } catch (const std::exception &e) {
    std::printf("FAIL npc_panel_request_policy_tests: %s (after %d checks)\n",
                e.what(), g_checks);
    return 1;
  }
  std::printf("PASS npc_panel_request_policy_tests (%d checks)\n", g_checks);
  return 0;
}
