# 5090 captured WSL transport diagnostic

Owner: `/root/operator_5090_recover`. Exact independent review and Agent Validator returned CLEAR for one elevated transport-only call.

Command: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1 -BashBodyPath C:\KenshiModding\pending-fixes\rig5090-validation\chat006-wsl-transport-probe.sh` through `require_escalated`.

Wrapper SHA256 `9E14992B65197BD1CDFF61768C3340008CE9FE389EBECC3EE51AE7F0C00156FC`; body SHA256 `242BAC1F7B967398A73B2570AC5DF8EA615107AA50FEDBFA28390C9CA9E3E676`; packet SHA256 `836D13C1464E4B969FD241BCD1F77A77EC7E75FB542662B65DD6EC138955EDC2`.

Fixed child argv: `wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding -- bash -s`.

Exit 0; stdout:

```
WSL_TRANSPORT_OK
/usr/bin/php
SESSION_SOURCE_PRESENT
```

No stderr. This establishes a working elevated WSL transport, PHP binary presence, and documented session library presence. No PHP execution, database/backend request, KAH, input, game/service/save/queue action occurred. It does not establish session readiness or an active in-game test.

Next: separately cleared filename-only bootstrap/source metadata read and workspace reader syntax check; then review/clear a bounded sanitized session read.
