#!/usr/bin/env bash
# Immutable AG-GAME-002 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-002 — exact native route dispatch, verified arrival, then fresh source scan
STATUS: BLOCKED. No exact composed release SHA supplied. Requires AG-GAME-001 PASS for the same actor/world and exact accepted activity/route grant, on the same verified loaded composition.

Use a copied save/private matching backend on each rig. Reconfirm composition SHA and all rig/session/schema pins. Before dispatch capture agreement/grant revision, activity discoveryRef, routeRef.candidateId plus server-authenticated route kind/label/endpoint, actor/world, and current native goal/order. Dispatch only that accepted route scope; do not substitute another endpoint or infer movement from dialogue. Capture one native route order start receipt and its exact activity/outbox correlation.

Wait for observed arrival at the authenticated candidate endpoint. Record a native position/location receipt and arrival timestamp. Only after arrival, perform the activity's fresh native scan; record its scan timestamp and exact source identities. The scan must be later than arrival. Do not accept a source from the pre-travel snapshot as the post-arrival result. No Hunt/Mine/ClearGroup action begins in this row.

Bound: one route only; progress receipt every 5 real minutes, maximum 10 real minutes to arrival. If the route does not arrive by the bound, capture native order cleanup/current state and classify INCONCLUSIVE/FAIL; do not start a fresh scan or action. Do not queue another row until the route order is inactive.
PASS: RESULT AG-GAME-002 PASS rig=<4080|5090> composed_sha=<exact> agreement=<id/rev> activity_scope=<receipt> route=<candidateId/kind/label/endpoint> native_order_start=<receipt> arrival=<timestamp/location> fresh_scan=<later timestamp/source IDs> order_end=<receipt>
Setup: RESULT AG-GAME-002 FAIL setup: <specific release/grant/identity/route gate and receipt>
Evidence: RESULT AG-GAME-002 FAIL evidence: <missing native start, arrival, later fresh-scan, or cleanup receipt>
ROW
