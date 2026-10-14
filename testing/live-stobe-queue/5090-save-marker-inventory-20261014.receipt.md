# 5090 test-save marker inventory

Evidence supplied by coordinator `/root` to operator `/root/operator_5090_recover`; this operator did not execute the matcher. Execution was after the coordinator's `2026-10-14T05:19:12Z` clock read and before its `2026-10-14T05:20:46Z` read. Exact command timestamp is unavailable. The full safe output and exact exit remain unavailable to this operator; do not invent them.

Reported exact route: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1 -BashBodyPath C:\KenshiModding\pending-fixes\rig5090-validation\chat006-save-campaign-matcher-body.sh` through `require_escalated`.

Candidate pins: reader SHA256 `5979D629BE1F57F4C09AB212C5862EB13EE880F8F32CA48376B4E1F5B77FE387`; body SHA256 `94C4030BCF72C959284BF73188D484C40F22E81C3EE1FDA6AFF5BFCCD5A4BB25`; packet SHA256 `DD59DF74310CE4F805D3188F0DBF5200652F3639AD377C1F88D4F816A026BDC8`; wrapper SHA256 `9E14992B65197BD1CDFF61768C3340008CE9FE389EBECC3EE51AE7F0C00156FC`. Independent review receipt SHA256 `1374AD9B9A6BC44EAA498CC59C74392F54E1437BAF9CB1F6167A9B301C5B6ABC`.

Coordinator-reported safe facts:

- Envelope `result="OK"`, `canonical_valid=true`.
- Every listed test copy had `matches_canonical=false`; no valid matching marker was found.
- `kah-5090-legacy-auth-20261013-1740` was the sole candidate considered for fallback and is available/markerless (`marker_present=false`, `marker_valid=false`).

No marker value, token, campaign identity, or identity fingerprint is recorded here. Inventory alone is not session readiness or in-game testing. Normal legacy-load recovery remains unexecuted pending exact review and fresh Validator CLEAR.

Recovery preparation owner `/root/operator_5090_recover/native_readiness_packet`: preserve markerless source, make fail-if-existing isolated copy `kah-5090-session-recovery-20261014`, prove quick.save/hash-manifest parity, then use documented normal load/session handshake. No marker/token edits or campaign auto-switch.
