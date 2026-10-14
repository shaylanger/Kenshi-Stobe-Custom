#include "TestInboxTargetRef.h"

#include <cstdio>
#include <stdexcept>
#include <string>

using namespace Stobe::Harness;

typedef TestInboxTargetCandidate<int> Candidate;

static int g_checks = 0;
static void check(bool ok, const std::string &what) {
  ++g_checks;
  if (!ok)
    throw std::runtime_error(what);
}

int main() {
  try {
    TestInboxTargetRef ref = ParseTestInboxTargetRef("Ulvik");
    check(!ref.isReference, "ordinary exact names retain the name lookup path");

    ref = ParseTestInboxTargetRef("#520507808/7");
    check(ref.isReference && ref.valid && ref.serial == 520507808u &&
              ref.index == 7u,
          "chars handle parses as serial/index");
    check(MatchesTestInboxTargetRef(520507808u, 7u, ref),
          "printed serial/index resolves to the same handle");
    check(!MatchesTestInboxTargetRef(520507808u, 8u, ref),
          "same serial with a different index is not the target");
    check(!MatchesTestInboxTargetRef(520507809u, 7u, ref),
          "same index with a different serial is not the target");

    std::vector<Candidate> updateList;
    updateList.push_back(Candidate{1, "ulvik", 100u, 2u, 75.0f});
    updateList.push_back(Candidate{2, "ulvik", 101u, 3u, 72.5f});
    std::vector<Candidate> nearby;
    nearby.push_back(Candidate{3, "ulvik", 520507808u, 7u, 72.0f});
    const Candidate *named = ResolveNamedTarget(updateList, nearby, "ulvik");
    check(named && named->target == 2,
          "nearest exact update-list name preserves the existing selection even when nearby has a closer duplicate");
    updateList.clear();
    named = ResolveNamedTarget(updateList, nearby, "ulvik");
    check(named && named->target == 3,
          "nearby-only exact name is a fallback when absent from the update list");
    ref = ParseTestInboxTargetRef("#520507808/7");
    const Candidate *byHandle = ResolveHandleTarget(updateList, nearby, ref);
    check(byHandle && byHandle->target == 3,
          "printed handle resolves a nearby candidate absent from the update list");
    updateList.push_back(Candidate{4, "ulvik", 520507808u, 8u, 71.0f});
    byHandle = ResolveHandleTarget(updateList, nearby, ref);
    check(byHandle && byHandle->target == 3,
          "handle resolution checks both serial and index across candidate pools");

    const char *bad[] = {"#520507808", "#520507808/", "#/7", "#52x/7",
                         "#520507808/7/2", "#4294967296/7"};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
      ref = ParseTestInboxTargetRef(bad[i]);
      check(ref.isReference && !ref.valid,
            std::string("malformed handle is rejected: ") + bad[i]);
    }

    std::puts("all native test-inbox target reference tests passed");
    return 0;
  } catch (const std::exception &e) {
    std::fprintf(stderr, "FAIL %s\n", e.what());
    return 1;
  }
}
