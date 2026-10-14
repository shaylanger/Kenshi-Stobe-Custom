#!/usr/bin/env bash
# Immutable AG-GAME-007 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-007 — source-unavailable fail-closed behavior
STATUS: BLOCKED. Exact composed release SHA is unsupplied. Requires one exact accepted agreement/grant and route arrival, plus a truthful post-arrival fresh scan proving the agreed source unavailable. Do not alter a production/shared source or fabricate an empty scan.

On an isolated copied save/private backend, use only a naturally unavailable or safely prepared copied-save source condition whose provenance is recorded. Preserve the accepted activity/source/resource/quantity or fixed target scope, exact route candidate and route endpoint, native order start, observed arrival and post-arrival fresh scan. The fresh scan must actually execute after arrival and report no suitable source or the agreed source absent/unreachable; retain its timestamp and native/server evidence.

Verify fail-closed terminal behavior: no native Hunt/Mine/ClearGroup action, no alternate source/target substituted under the old grant, no unrelated route or task dispatch, no transfer/reward, and an authenticated unavailable/failed report tied to the same agreement ID/revision. Preserve native cleanup and final server/outbox state. If an eligible source is found, this row is not applicable; do not remove/kill it to force a pass.

Bound: one route and one fresh scan, max 10 real minutes with progress every 5. A scan timeout or missing telemetry is INCONCLUSIVE, not source-unavailable evidence.
PASS: RESULT AG-GAME-007 PASS rig=<4080|5090> composed_sha=<exact> agreement=<id/rev> route=<candidateId/endpoint> arrival=<receipt> fresh_scan=<timestamp no suitable source> native_action=none substitution=none transfer_reward=none server_report=<unavailable event> cleanup=<receipt>
Setup: RESULT AG-GAME-007 FAIL setup: <specific release/agreement/route/scan-provenance gate and receipt>
Evidence: RESULT AG-GAME-007 FAIL evidence: <missing post-arrival empty-source scan/fail-closed/native-cleanup receipt>
ROW
