#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-001. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-001 — direct greeting/readiness
Dependency: common preconditions and a fresh successful native session/readiness receipt.
Pre-chat KAH reads: stobe-auto status; stobe-auto where "<exact verified NPC name>"; stobe-auto where @selected
Record baseline backend dialogue tail/window and durable trip state for this target before the utterance.
Exact row command (substitute only the verified NPC's exact in-world name):
  stobe-auto stobe_say "<exact verified NPC name>" "Hello there. How are you doing today?"

PASS requires native `TEST_INBOX: say` + the NPC's native reply, matching backend dialogue/event record, and before/after trip state proving no trip/dispatch was created by this greeting. Save the evidence paths/IDs and time window with the row receipt.
Expected RESULT PASS form:
  RESULT KAH-CHAT-001 PASS native_say=<log:line> reply=<log:line> backend=<event-id> trip_before_after=<receipt> target=<serial/index>
Setup stop form (no chat command issued):
  RESULT KAH-CHAT-001 FAIL setup: <specific observed host/build/save/NPC/session gate mismatch>
Evidence stop form (chat may have occurred; do not call it setup failure):
  RESULT KAH-CHAT-001 FAIL evidence: <specific missing native reply/backend/trip receipt>
ROW
