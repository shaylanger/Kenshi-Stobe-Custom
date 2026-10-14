#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-006. Prints instructions only; no rig access.
cat <<'ROW'
ROW KAH-CHAT-006 — read-only Stobe target identity resolver confirmation
Purpose: confirm the reviewed exact `#serial/index` resolver in the built candidate, separately from KAH-CHAT-005. This row sends no chat, changes no state, and does not block an otherwise valid fresh @nearest greeting.

HARD DEPENDENCY: the operator must first record an exact loaded Stobe DLL SHA whose reviewed source manifest includes the target identity patch described in `pending-fixes/stobe-target-identity/TEST-INBOX-TARGET-IDENTITY-RECEIPT-20261013.md` (receipt SHA256 `8ABA25E2798B8FA44803B6937286A6475851B9BC36E449E36F13DB27F85C3E93`). The source-only receipt is not an install pin. Do not execute against the current installed DLL, where serial-reference syntax returned usage.

At a safe boundary, verify isolated rig/instance/PID, actual current world/save/backend/session identity, exact loaded Stobe SHA, and input isolation. Then collect one fresh native target list and run only read-only queries:
  stobe-auto chars 80
  stobe-auto where "<exact displayed name>"
  stobe-auto where "#<current serial>/<current index>"
Record raw request/response and native log lines. Confirm the exact handle returns the same live actor identity and sensible distance; compare with the exact-name response without requiring aliases in `chars` to be equal. If the actor has despawned or its handle changed, stop without querying a stale serial. No `stobe_say`, no state-changing order, no UI, and no keyboard/mouse/focus action.

PASS:
  RESULT KAH-CHAT-006 PASS rig=<4080|5090> instance=<n> candidate_sha=<exact loaded DLL> name=<current name> handle=<serial/index> chars=<receipt> where_name=<receipt> where_handle=<receipt> same_actor=yes
Setup stop:
  RESULT KAH-CHAT-006 FAIL setup: <candidate install/hash/world/session/target gate>
Resolver failure:
  RESULT KAH-CHAT-006 FAIL <read-only identity mismatch/unsupported serial reference with exact receipts>
ROW
