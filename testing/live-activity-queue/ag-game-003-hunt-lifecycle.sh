#!/usr/bin/env bash
# Immutable AG-GAME-003 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-003 — grounded Hunt action, completion, and attributable reward/report
STATUS: BLOCKED. Exact composed release SHA is unsupplied. Requires a dedicated fresh Hunt agreement/grant and AG-GAME-002 route/arrival/fresh-scan PASS for the same Hunt scope. Do not borrow a Mine/ClearGroup grant or source snapshot.

Ground only on a freshly observed eligible Hunt source after arrival (for example, a live animal/resource identity explicitly returned by the fresh scan). Record source/target serial, species/resource, observed status and location. Confirm the exact accepted Hunt resource and bounded quantity before action. Capture actor inventory, source state, native goal/order state, and activity record revision immediately before action.

Allow only the native Hunt action authorized by that exact scope. Verify the specific source was acted on and the controller reaches its authoritative terminal status. Capture produced/collected quantity, exact transfer target, before/after inventory counts, reward/report event with activity ID/revision, and native goal cleanup. No reward or relationship change may be inferred from requester identity or NPC speech. No unagreed target/action is permitted.

Bound: one fresh source, one agreed quantity, max 10 real minutes with progress every 5. If the source disappears, becomes invalid, or route/goal identity changes, stop and classify fail-closed/inconclusive; do not substitute another target under the old grant.
PASS: RESULT AG-GAME-003 PASS rig=<4080|5090> composed_sha=<exact> agreement=<id/rev> route=<candidateId/endpoint> arrival_rescan=<receipt> hunt_source=<serial/resource> native_action=<receipt> terminal=<status> collected=<n> transfer=<actor/inventory delta> reward_report=<activity event> cleanup=<receipt>
Setup: RESULT AG-GAME-003 FAIL setup: <specific release/scope/source/arrival gate and receipt>
Evidence: RESULT AG-GAME-003 FAIL evidence: <missing action/terminal/quantity/transfer/report/cleanup receipt>
ROW
