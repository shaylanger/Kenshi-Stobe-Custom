#!/usr/bin/env bash
# Immutable KAH-INT-006 operator packet. Prints instructions only.
cat <<'ROW'
ROW KAH-INT-006 — native travel TTL refresh, provenance, status, and endpoint
STATUS: BLOCKED until Stobe DLL `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`, source manifest `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C`, and the exact matching private backend/API identity are confirmed installed/loaded on a safe isolated copied-save test context. Do not use production/shared server or old expired point107 candidate.

Preflight: record rig/instance/PID/save/world/actor serial, loaded DLL+manifest, exact private backend/API pin, session readiness, and current native goal/order status. Require a fresh native destination candidate and explicit consent. Record its candidate identity, kind, actor/world, exact label and endpoint, anchor serial, map serial, and knowledge provenance. Preserve the accepted consent receipt. No save load or game restart after the candidate is issued.

Keep the same world/PID loaded for strictly more than 600,000 ms after candidate issue; use monotonic timestamps and read-only world/order status checks at least every 2 minutes. Do not pause/refresh/reissue consent. At expiry, dispatch the same accepted target once. Capture dispatch-time fresh native observation and replacement candidate. It must preserve original kind, actor/world, exact endpoint and label, anchor serial, map serial, and knowledge provenance. Confirm standard path/range validation, native owned-goal start ACK, current order/status, actual movement, and observed arrival at the exact agreed endpoint. Record status before, during, and after dispatch; no endpoint substitution or guessed coordinates.

Bound 12 minutes total (including the required >10-minute TTL); progress checks every 2 minutes. If the world reloads/restarts, actor/world changes, or the time bound ends before evidence, stop and classify setup failure/inconclusive; do not retry the stale candidate. Do not use `point107`.
PASS: RESULT KAH-INT-006 PASS rig=<4080|5090> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C backend=<exact API pin> actor_world=<serial/world> wait_ms=>600000 same_pid_world=1 original=<candidate/kind/label/endpoint/anchor/map/provenance> refreshed=<matching fields> path_range=pass native_goal_start=<receipt> status=<before/during/after> moved=1 arrived=<exact endpoint receipt>
Setup: RESULT KAH-INT-006 FAIL setup: <specific isolated save/backend/session/candidate/identity gate and receipt>
Evidence: RESULT KAH-INT-006 FAIL evidence: <specific missing freshness/provenance/order/status/movement/arrival receipt>
ROW
