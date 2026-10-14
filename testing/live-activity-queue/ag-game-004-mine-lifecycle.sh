#!/usr/bin/env bash
# Immutable AG-GAME-004 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-004 — grounded Mine action, completion, and attributable reward/report
STATUS: BLOCKED. Exact composed release SHA is unsupplied. Requires a dedicated fresh Mine agreement/grant and AG-GAME-002 route/arrival/fresh-scan PASS for the same Mine scope. Do not borrow a Hunt/ClearGroup grant or source snapshot.

Ground only on a freshly observed reachable mine/resource source after arrival. Record exact node serial/identity, resource ID (for example raw iron only if returned by the scan), current source/workable state, path evidence and location. Confirm accepted resource and bounded quantity. Capture actor inventory, source quantity/state, native goal/order state, and activity record revision immediately before action.

Allow only the native WorkResource/Mine action for the exact accepted source/resource. Verify native work start, production/output delta, exact bounded transfer to the agreed recipient, before/after inventory counts, authoritative completion report keyed to the activity ID/revision, and native cleanup. A previous or unrelated output stack does not count; use before/after deltas attributable to this row. Do not infer a reward or relationship change.

Bound: one node and one agreed quantity, max 10 real minutes with progress every 5. If the node becomes unavailable or an action is rejected, record the exact native reason and fail closed; no alternate node under the old grant.
PASS: RESULT AG-GAME-004 PASS rig=<4080|5090> composed_sha=<exact> agreement=<id/rev> route=<candidateId/endpoint> arrival_rescan=<receipt> mine_source=<serial/resource> native_work=<receipt> output_delta=<item/count> transfer=<recipient/inventory delta> terminal_report=<activity event> cleanup=<receipt>
Setup: RESULT AG-GAME-004 FAIL setup: <specific release/scope/source/arrival gate and receipt>
Evidence: RESULT AG-GAME-004 FAIL evidence: <missing native work/output/transfer/terminal/cleanup receipt>
ROW
