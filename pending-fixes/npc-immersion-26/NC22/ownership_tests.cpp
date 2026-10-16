// NC22 unit test for ActivityOwnership.h (row 14-d). g++ -std=c++14 -I<dir with ActivityOwnership.h> ownership_tests.cpp
#include "ActivityOwnership.h"
#include <cstdio>
#include <cstring>
using Stobe::Activity::Ownership::Decide;
static int fails = 0;
static void T(const char* name, const char* got, const char* want) {
 const bool ok = !strcmp(got, want);
 printf("%s %s got='%s' want='%s'\n", ok ? "PASS" : "FAIL", name, got, want); if(!ok) ++fails;
}
int main() {
 // The 14-d bug: spawned wild bandit, non-zero owner handle, not a slave, not chained, no cage -> valid target.
 T("spawned_bandit_nonzero_owner_serial", Decide(false, 2773071360u, 0, false, false), "");
 T("spawned_bandit_owner_serial_1", Decide(false, 1u, 0, false, false), "");
 T("bandit_no_owner", Decide(false, 0, 0, false, false), "");
 // Genuine protection stays.
 T("player_slave_is_slave", Decide(false, 12345u, 1, true, false), "owned_target");
 T("slave_state_only", Decide(false, 0, 1, false, false), "owned_target");
 T("escaping_slave", Decide(false, 12345u, 2, false, false), "owned_target");
 T("ex_slave_with_owner", Decide(false, 12345u, 3, false, false), "owned_target");
 T("chained_only", Decide(false, 0, 0, true, false), "owned_target");
 T("captive_in_cage", Decide(false, 0, 0, false, true), "captive_target");
 T("captive_in_cage_with_owner", Decide(false, 777u, 1, true, true), "captive_target");
 // Animals keep the strict rule: any owner handle protects (pets/owned animals).
 T("owned_animal", Decide(true, 999u, 0, false, false), "owned_target");
 T("wild_animal", Decide(true, 0, 0, false, false), "");
 T("caged_animal", Decide(true, 0, 0, false, true), "captive_target");
 printf("failures=%d\n", fails);
 return fails ? 1 : 0;
}
