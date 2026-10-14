#!/usr/bin/env bash
# Immutable AG-GAME-006 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-006 — explicit cancel/revoke and native cleanup
STATUS: BLOCKED. Exact composed release SHA is unsupplied. Requires a fresh, exact, accepted activity record and native action lifecycle on the same isolated rig; do not use a stale or another actor's agreement.

Choose one safe copied-save activity whose exact actor/requester/world, purpose scope, route scope, agreement ID/revision and current native order are recorded. Record state immediately before cancellation. Use a direct, explicit cancellation/revocation utterance that names only the current displayed activity; do not alter or broaden its scope. Preserve native chat/reply and authenticated server transition to cancelled/revoked with revision/consent evidence.

Verify native cancellation is acknowledged, movement/task/body cleanup completes, and no continued dispatch, activity action, transfer, reward, or completion report occurs after revocation. Preserve terminal native order state and post-cancel activity/outbox state. Do not manually kill/teleport or otherwise alter the target to manufacture cleanup.

Bound: one active agreement, one cancellation, max 5 real minutes to terminal cleanup; progress at 2-minute intervals. If cleanup remains active at bound, fail with exact remaining native task/order and keep the row from passing; do not start another activity row.
PASS: RESULT AG-GAME-006 PASS rig=<4080|5090> composed_sha=<exact> agreement=<id/rev> scopes=<activity+route receipts> cancel=<utterance/native reply> server_terminal=<cancelled|revoked revision> native_cleanup=<receipt> post_cancel_action_transfer_reward=none
Setup: RESULT AG-GAME-006 FAIL setup: <specific release/record/order/identity gate and receipt>
Evidence: RESULT AG-GAME-006 FAIL evidence: <missing cancel/revocation or cleanup/post-cancel audit receipt>
ROW
