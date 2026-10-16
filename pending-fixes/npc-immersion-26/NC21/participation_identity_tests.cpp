// NC21 pure tests for ParticipationIdentity.h (no Kenshi types). Run: see NC21/offline-tests.sh.
#include <cstdio>
#include <string>
#include "ParticipationIdentity.h"

namespace I = Stobe::Participation::Identity;
static int g_pass = 0, g_fail = 0;
static void Check(const char *name, bool ok, const std::string &detail = std::string()) {
  if (ok) { ++g_pass; std::printf("PASS %s\n", name); } else { ++g_fail; std::printf("FAIL %s %s\n", name, detail.c_str()); }
}

int main() {
  const std::string uid("uid-1"), empty;
  Check("id: uid wins", I::StorageId(&uid, 7) == "uid-1");
  Check("id: empty uid -> hand_serial (same format as Context.cpp GetStorageIDFor)", I::StorageId(&empty, 2529907200u) == "hand_2529907200", I::StorageId(&empty, 2529907200u));
  Check("id: NULL uid -> hand_serial", I::StorageId(0, 971557632u) == "hand_971557632");
  Check("id: no uid and serial 0 -> empty (unusable)", I::StorageId(0, 0).empty());
  Check("hand detect", I::IsHandFallback("hand_1") && !I::IsHandFallback("uid-1") && !I::IsHandFallback(""));
  const std::string a("hand_1"), b("hand_2");
  Check("decide: ok", I::Decide(true, true, 1, 2, true, a, b) == I::BIND_OK);
  Check("decide: actor unresolved first", I::Decide(false, false, 1, 2, true, a, b) == I::BIND_ACTOR_UNRESOLVED);
  Check("decide: partner unresolved", I::Decide(true, false, 1, 2, true, a, b) == I::BIND_PARTNER_UNRESOLVED);
  Check("decide: same serial", I::Decide(true, true, 5, 5, true, a, b) == I::BIND_SAME_SERIAL);
  Check("decide: empty scope", I::Decide(true, true, 1, 2, false, a, b) == I::BIND_SCOPE_EMPTY);
  Check("decide: actor no identity", I::Decide(true, true, 1, 2, true, empty, b) == I::BIND_NO_ACTOR_IDENTITY);
  Check("decide: partner no identity", I::Decide(true, true, 1, 2, true, a, empty) == I::BIND_NO_PARTNER_IDENTITY);
  Check("decide: same identity", I::Decide(true, true, 1, 2, true, a, a) == I::BIND_SAME_IDENTITY);
  Check("name: hand fallback", std::string(I::VerdictName(I::BIND_OK, a)) == "ok_hand_fallback");
  Check("name: uid", std::string(I::VerdictName(I::BIND_OK, uid)) == "ok_uid");
  std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
