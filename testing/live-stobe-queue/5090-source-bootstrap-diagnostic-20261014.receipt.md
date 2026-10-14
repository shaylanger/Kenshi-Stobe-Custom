# 5090 source bootstrap diagnostic

Owner `/root/operator_5090_recover`. Independently reviewed exact packet/body and fresh Agent Validator CLEAR; executed once through approved `require_escalated` flow.

Command: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1 -BashBodyPath C:\KenshiModding\pending-fixes\rig5090-validation\chat006-source-bootstrap-probe.sh`.

Wrapper SHA256 `9E14992B65197BD1CDFF61768C3340008CE9FE389EBECC3EE51AE7F0C00156FC`; body SHA256 `83E1BB52669F14AF762C97080621650BCFEB5A27B1860B20E3DAB5B8055BA0ED`; packet SHA256 `07C387EF518AC5B64DA45713793C9BCBAD01326CE9943A56FAB81165D62B2656`.

Exit 0, no stderr. Filename-only search identified `function ptp_connect` in `/var/www/html/StobeServer/lib/playthrough_preferences.php`, and `manager.ready` in `/var/www/html/StobeServer/lib/playthrough_runtime.php`. Searches were limited to `lib/*.php`, not a global absence/presence audit.

Designated source hashes:

- `/var/www/html/StobeServer/lib/playthrough_switching.php`: `3c17728e9f776ec487ca78fc8458edb8bbceca4bf45c3efc446b852edd0b1450`.
- `/var/www/html/StobeServer/lib/playthrough_preferences.php`: `6c82749ae9f9b7b5deb135b7551fc76dd0658ae0822882d7ab7c407dae436555`.

Workspace reader lint: `No syntax errors detected in /mnt/c/KenshiModding/pending-fixes/rig5090-validation/chat006-session-read-once.php`, at reader SHA256 `B487A33DC022A7FBF98DE08E441ED658D8B2CB6667137DA81D13BF21B64EFD5B`. Reader revisions after this probe need fresh syntax/behavior checks.

No application PHP execution, DB/backend/KAH request, game/input/service/save/queue change. Not an in-game test PASS. Next: fresh-cleared native KAH snapshot in parallel with exact sanitized reader review.
