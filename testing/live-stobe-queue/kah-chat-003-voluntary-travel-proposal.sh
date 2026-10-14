#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-003. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-003 — voluntary travel-willingness proposal
Dependency: KAH-CHAT-002 PASS; rerun common host/build/save/NPC/session gates. Confirm Heft is a valid destination in the current world and capture baseline trip/goal/dispatch state. If a prior active trip exists, do not run unless its identity and lifecycle can be distinguished from any new proposal.
Pre-chat KAH reads: stobe-auto status; stobe-auto where "<exact verified NPC name>"; stobe-auto where @selected
Exact row command (substitute only the verified NPC's exact in-world name):
  stobe-auto stobe_say "<exact verified NPC name>" "Would you want to travel with me to Heft sometime? It is completely your choice."

PASS requires native `TEST_INBOX: say` + the NPC's native reply, matching backend dialogue/decision record, and before/after durable trip/goal/dispatch state. Record whether the response is willing, unwilling, or unclear. A proposal is not acceptance: unless the NPC explicitly consents, there must be no accepted agreement, trip start, or movement dispatch. Do not treat proposal creation as acceptance or movement.
Expected RESULT PASS form:
  RESULT KAH-CHAT-003 PASS native_say=<log:line> reply=<log:line> backend=<event-id> decision=<observed> trip_before_after=<receipt> dispatch=<none unless explicit consent> target=<serial/index>
Setup stop form (no chat command issued):
  RESULT KAH-CHAT-003 FAIL setup: <specific observed host/build/save/NPC/session/dependency/destination/trip-state mismatch>
Evidence stop form (chat may have occurred; do not call it setup failure):
  RESULT KAH-CHAT-003 FAIL evidence: <specific missing native reply/backend/decision/trip receipt>
ROW
