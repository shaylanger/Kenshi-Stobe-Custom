#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-008. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-008 — 5090 main-i1 fresh-session greeting with same-target state receipts
Purpose: one new confirmation request for the simple greeting. This is a new row; do not reuse the KAH-CHAT-001 send or its incomplete evidence. Do not retry this row unchanged.

HARD BUILD PIN: loaded Stobe DLL SHA-256 must be exactly
  AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C
The authorized route is the 5090 isolated main instance 1 only. Record the actual loaded DLL path resolved from that running instance and hash that exact file. Do not infer a path from another instance or use instance 3/D3. If the runtime cannot establish the loaded path and hash, stop before chat.

Fresh setup gates (read-only; any failure stops before sending):
1. Confirm host is the 5090, isolated main instance 1, live PID, input isolation ON, focused=0, and no UI/OS input path is used. Record current save/world identity from the running game and KAH status.
2. Confirm the current backend endpoint belongs to this isolated instance, health is ready, and obtain a fresh native session/readiness receipt for the same world/save. Reject stale receipts, identity mismatch, invalid session, or backend-instance disagreement.
3. Hash the actual loaded Stobe DLL path from this instance; require the hard pin above. Record path, hash, and loaded-instance mapping in the receipt. No other candidate/old build is acceptable.
4. Take one fresh `stobe-auto stobe_ping`; require exactly one named nearest target and capture the ACK/native handle. Using the documented current KAH readout or native `CHAT_SEND_STAGE`, establish that this same actor/handle is alive and within TalkRadius=80. If nearest is none/ambiguous, the handle cannot be bound to the actor, target is dead, or range is >80, stop before send. Do not use stale `chars` data to override a mismatch.
5. Before sending, capture the target's current trip, goal, and order state using the supported read-only backend/native state receipts. Include actor identity/handle, world/save identity, request correlation window, and timestamp. If a same-target baseline cannot be captured without mutation, stop before send. Also capture backend/LLM dialogue tail or correlation cursor so later events can be attributed to this request.

Only after every gate above passes, send exactly once through the validated isolated direct KAH route (never `ui`, UI, OS input, or focus changes):
  stobe-auto stobe_say @nearest "Hello there. How are you doing today?"
Preserve the exact command/request ID and send time. The target must remain the preflight actor/handle; if the route cannot guarantee that identity, stop before dispatch.

After the send, collect the native Stobe log's matching `TEST_INBOX: say` with the complete exact text and same target handle; the correlated backend/LLM request/event and response for the same actor/request/time; the target's native NPC reply; and fresh post-chat trip/goal/order state for that same actor/handle and world. Compare all three state fields against the pre-chat baseline and explain any delta. A queue ACK or player SAY echo alone is not a reply or PASS. If no reply/backend record/state receipt appears, report evidence failure or inconclusive; never fabricate or infer missing evidence.

PASS requires one complete correlated bundle: fresh host/build/save/world/backend/session/target setup receipts, exact native inbox utterance, correlated backend/LLM record, native NPC reply, and same-target pre/post trip+goal+order state:
  RESULT KAH-CHAT-008 PASS rig=5090 instance=1 world=<identity> save=<identity> session=<receipt> backend=<endpoint+receipt> dll_path=<actual-loaded-path> dll=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C target=<name+handle+alive+distance<=80> native_say=<log-line+exact-text> backend_llm=<correlated-record> reply=<native-log-line> state_before=<same-target-receipt> state_after=<same-target-receipt>
Setup stop, no send:
  RESULT KAH-CHAT-008 FAIL setup: <specific host/instance/build-path/hash/save/world/backend/session/target/range/state-baseline gate>
Post-send evidence stop:
  RESULT KAH-CHAT-008 FAIL evidence: <specific missing or mismatched native/backend/reply/state evidence; include request id and receipt paths>
ROW
