#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-002. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-002 — local knowledge question
Dependency: KAH-CHAT-001 PASS; rerun common host/build/save/NPC/session gates and verify Sho-Battai as the current city from the city-start/location receipt.
Pre-chat KAH reads: stobe-auto status; stobe-auto where "<exact verified NPC name>"; stobe-auto where @selected
Record Sho-Battai and baseline backend dialogue plus durable trip state. If a pre-existing trip cannot be inspected before/after, do not run this row.
Exact row command (substitute only the verified NPC's exact in-world name):
  stobe-auto stobe_say "<exact verified NPC name>" "What do you know about Sho-Battai?"

PASS requires native `TEST_INBOX: say` + the NPC's native reply, matching backend dialogue/event record, and before/after trip state proving the question caused no new trip/dispatch and preserved any existing trip unchanged. Judge the answer against the verified city context; this row records uncertainty rather than requiring invented local knowledge.
Expected RESULT PASS form:
  RESULT KAH-CHAT-002 PASS native_say=<log:line> reply=<log:line> backend=<event-id> town=<verified-town> trip_before_after=<receipt> target=<serial/index>
Setup stop form (no chat command issued):
  RESULT KAH-CHAT-002 FAIL setup: <specific observed host/build/save/NPC/session/dependency mismatch>
Evidence stop form (chat may have occurred; do not call it setup failure):
  RESULT KAH-CHAT-002 FAIL evidence: <specific missing native reply/backend/trip receipt>
ROW
