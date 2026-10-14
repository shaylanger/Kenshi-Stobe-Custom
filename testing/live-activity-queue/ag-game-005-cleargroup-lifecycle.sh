#!/usr/bin/env bash
# Immutable AG-GAME-005 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-005 — grounded ClearGroup fixed-set action, completion, and cleanup
STATUS: BLOCKED. Exact composed release SHA is unsupplied. Requires a dedicated fresh ClearGroup agreement/grant and AG-GAME-002 route/arrival/fresh-scan PASS for the same fixed target scope. Do not borrow another activity's grant.

Ground only on the post-arrival fresh scan's visible, active, hostile group. Record the group identity and exact agreed target serial set before acceptance (maximum 32 per capability boundary); verify every target remains eligible/reachable and the agreement binds exactly that set. Capture allied/non-target nearby characters separately as exclusions. No unseen reinforcements are included.

Allow only native ClearGroup actions against the fixed agreed serial set. Record per-target native order start, combat/terminal outcome, non-target order audit, completion report/activity ID/revision, and cleanup confirming no member of the row's native task/body/movement remains active. Verify completion is not reported while any agreed target is unresolved. Record any explicit reward only if the authenticated service reports it and the native participation receipt supports it; otherwise record `reward=none` without treating it as a defect.

Bound: one fixed group, max 10 real minutes with progress every 5. If new enemies appear, do not add them; preserve the agreed set and classify the row according to the candidate's bounded-set behavior. No claims about unseen groups.
PASS: RESULT AG-GAME-005 PASS rig=<4080|5090> composed_sha=<exact> agreement=<id/rev> route=<candidateId/endpoint> arrival_rescan=<receipt> agreed_targets=<serial set> native_orders=<per-target receipts> terminal_report=<activity event> excluded_targets=<audit> reward=<receipt|none> cleanup=<receipt>
Setup: RESULT AG-GAME-005 FAIL setup: <specific release/scope/group/arrival gate and receipt>
Evidence: RESULT AG-GAME-005 FAIL evidence: <missing per-target order/outcome/report/exclusion/cleanup receipt>
ROW
