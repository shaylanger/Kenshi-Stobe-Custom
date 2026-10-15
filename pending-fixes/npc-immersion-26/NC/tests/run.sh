#!/bin/bash
# NC native tests (WSL). Builds every portable test against NC/src and prints one RESULT line per test.
cd "$(dirname "$0")"
S=$(pwd)/../src
T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
A=/mnt/c/KenshiModding/pending-fixes/activity-composed-release/native-aef-candidate/tests
W=/tmp/nc_tests; rm -rf $W; mkdir -p $W
fail=0
run() { # name std extra-flags sources...
  local n=$1 std=$2 fl=$3; shift 3
  if g++ -std=$std $fl -I$S "$@" -o $W/$n >$W/$n.build 2>&1 && $W/$n >$W/$n.out 2>&1; then
    echo "RESULT $n PASS $(tail -1 $W/$n.out | cut -c1-110)"
  else echo "RESULT $n FAIL see $W/$n.build $W/$n.out"; fail=$((fail+1)); fi
}
run n1_logic c++03 "" n1_logic_tests.cpp
run n2_logic c++11 "-Wall" n2_logic_tests.cpp
run n2_entity c++11 "-Wall" n2_entity_tests.cpp $S/SocialEventProtocol.cpp
run social_protocol c++14 "" $T/social_protocol_tests.cpp $S/SocialEventProtocol.cpp
run native_travel_receipt c++14 "" $T/native_travel_receipt_tests.cpp
run activity_candidate_policy c++14 "" $T/activity_candidate_policy_tests.cpp
run chat_interrupt_policy c++14 "" $T/chat_interrupt_policy_tests.cpp
run chat_hotkey_policy c++14 "" $T/chat_hotkey_policy_tests.cpp
run drawn_weapon_policy c++14 "" $T/drawn_weapon_policy_tests.cpp
run npc_panel_request_policy c++14 "" $T/npc_panel_request_policy_tests.cpp
run test_inbox_target_ref c++14 "" $T/test_inbox_target_ref_tests.cpp
run portrait_fault_injection c++14 "" $T/portrait_fault_injection_tests.cpp
run shop_pricing c++14 "" $T/shop_pricing_tests.cpp $S/ShopPricing.cpp
run stobe_portable c++14 "" $T/stobe_text_tests.cpp $S/AutonomyMonitor.cpp $S/AutonomyProtocol.cpp $S/AutonomySafetyProbePolicy.cpp $S/StobeChatMode.cpp $S/StobeIdentityRename.cpp $S/StobeText.cpp $S/StobeTiming.cpp $S/StobeEventPolicy.cpp
# activity v2 tests (aef candidate suite), _finite mapped for g++
FIN="-include cmath -D_finite=std::isfinite"
run activity_goal_route_lifecycle c++14 "$FIN" $A/activity_goal_route_lifecycle_tests.cpp $S/ActivityGoals.cpp
run activity_discovery_ref c++14 "$FIN" $A/activity_discovery_ref_contract_tests.cpp
run activity_status_snapshot c++14 "$FIN" -I$S/../tests $A/activity_status_snapshot_tests.cpp
if python3 playthrough_session_retry_source_tests.py >$W/pt.out 2>&1; then echo "RESULT playthrough_session_retry_source PASS $(tail -1 $W/pt.out)"; else echo "RESULT playthrough_session_retry_source FAIL $W/pt.out"; fail=$((fail+1)); fi
echo "SUMMARY failures=$fail"
exit $fail
