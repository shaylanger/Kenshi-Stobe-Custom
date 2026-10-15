// N2a: terminal activity report carries an allow-listed `reason` and a `handBack` object (imm26 rows 26-a, 26-c).
// Build: g++ -std=c++14 -I<src> tests/activity_report_reason_tests.cpp -o t -DNC_SRC='"<src dir>"'
// Pure-header logic tests plus source checks that ActivityTransport.cpp really emits both fields.
#include "ActivityReportReason.h"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#ifndef NC_SRC
#define NC_SRC "."
#endif
using namespace Stobe::Activity::ReportReason;
static int failures = 0, checks = 0;
static void Eq(const char* what, const std::string& got, const std::string& want) {
 ++checks;
 if (got != want) { ++failures; std::printf("FAIL %s: got [%s] want [%s]\n", what, got.c_str(), want.c_str()); }
}
static void Has(const char* what, const std::string& hay, const std::string& needle) {
 ++checks;
 if (hay.find(needle) == std::string::npos) { ++failures; std::printf("FAIL %s: missing [%s]\n", what, needle.c_str()); }
}
static const char* kAllow[] = {"no_observed_suitable_reachable_target","target_lost","timeout","expired","cancelled_by_player",
 "actor_incapacitated","route_unreachable","threat_too_high","inventory_full"};
static bool Allowed(const std::string& s) { for (size_t i = 0; i < sizeof(kAllow) / sizeof(kAllow[0]); ++i) if (s == kAllow[i]) return true; return false; }
int main() {
 // 26-c: the compound string built at ActivityGoals.cpp:210-212.
 Eq("compound replan", MapReason("replan; no_observed_suitable_reachable_target"), "no_observed_suitable_reachable_target");
 Eq("compound with path_failed", MapReason("path_failed; no_observed_suitable_reachable_target"), "no_observed_suitable_reachable_target");
 Eq("plain target", MapReason("no_observed_suitable_reachable_target"), "no_observed_suitable_reachable_target");
 Eq("cleanup prefix", MapReason("owned_order_cleanup_pending: inventory_full"), "inventory_full");
 Eq("cleanup prefix path", MapReason("owned_order_cleanup_pending: path_failed"), "route_unreachable");
 Eq("target lost", MapReason("target_unavailable_or_identity_changed"), "target_lost");
 Eq("target unloaded", MapReason("target_unloaded"), "target_lost");
 Eq("no progress", MapReason("activity_no_verified_progress"), "timeout");
 Eq("expired", MapReason("agreement_expired_or_clock_reset"), "expired");
 Eq("unknown", MapReason("something_new_and_unmapped"), "");
 Eq("empty", MapReason(""), "");
 Eq("replan only", MapReason("replan"), "");
 // Every mapped value must be on the server allow-list.
 const char* samples[] = {"path_failed","route_travel_failed","route_dispatch_rejected","target_scope_or_reachability_changed",
  "target_no_longer_authorized_or_usable","target_identity_or_protection","resource_identity_changed","recipient_full","inventory_full","timeout"};
 for (size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i) { ++checks; if (!Allowed(MapReason(samples[i]))) { ++failures; std::printf("FAIL not allow-listed: %s\n", samples[i]); } }
 // Phase gate: completed jobs and in-flight phases carry no reason.
 Eq("failed phase", ForPhase("failed", "replan; no_observed_suitable_reachable_target"), "no_observed_suitable_reachable_target");
 Eq("cancelled phase", ForPhase("cancelled", "target_unloaded"), "target_lost");
 Eq("complete phase", ForPhase("complete", "agreed_quantity_delivered"), "");
 Eq("complete phase even mapped", ForPhase("complete", "timeout"), "");
 // 26-a: handBack object.
 Eq("delivered", HandBackJson("delivered", "exact_resource_handed_to_requester"), "{\"status\":\"handed_over\"}");
 Eq("not applicable", HandBackJson("not_applicable", "handback_not_requested"), "{\"status\":\"not_applicable\"}");
 Eq("pending omitted", HandBackJson("pending", ""), "");
 Eq("empty omitted", HandBackJson("", ""), "");
 Eq("unknown status omitted", HandBackJson("weird", ""), "");
 Eq("activity not completed", HandBackJson("kept_by_npc", "activity_not_completed"), "{\"status\":\"not_applicable\"}");
 Eq("timeout", HandBackJson("kept_by_npc", "handback_timeout"), "{\"status\":\"failed\",\"reason\":\"timeout\"}");
 Eq("follow failed", HandBackJson("kept_by_npc", "follow_failed"), "{\"status\":\"failed\",\"reason\":\"route_unreachable\"}");
 Eq("follow rejected", HandBackJson("kept_by_npc", "follow_rejected:whatever"), "{\"status\":\"failed\",\"reason\":\"route_unreachable\"}");
 Eq("transfer full", HandBackJson("kept_by_npc", "transfer_failed:recipient_full"), "{\"status\":\"failed\",\"reason\":\"inventory_full\"}");
 Eq("transfer other", HandBackJson("kept_by_npc", "transfer_failed:postcondition"), "{\"status\":\"failed\"}");
 Eq("reward absent", HandBackJson("kept_by_npc", "reward_not_in_actor_inventory"), "{\"status\":\"failed\"}");
 // Source check: the report body built in ActivityTransport.cpp must use both helpers.
 const std::string path = std::string(NC_SRC) + "/ActivityTransport.cpp"; std::ifstream in(path.c_str(), std::ios::binary);
 std::stringstream ss; ss << in.rdbuf(); const std::string src = ss.str();
 ++checks; if (src.empty()) { ++failures; std::printf("FAIL cannot read %s/ActivityTransport.cpp\n", NC_SRC); }
 Has("include", src, "ActivityReportReason.h");
 Has("reason field", src, "\\\"reason\\\":\\\"");
 Has("handBack field", src, "\\\"handBack\\\":");
 Has("reads goal reason", src, "ReportReason::ForPhase(phase,state.get<std::string>(\"reason\"");
 Has("reads handback status", src, "state.get<std::string>(\"handBackStatus\"");
 std::printf("%s checks=%d failures=%d\n", failures ? "FAILED" : "activity_report_reason PASS", checks, failures);
 return failures ? 1 : 0;
}
