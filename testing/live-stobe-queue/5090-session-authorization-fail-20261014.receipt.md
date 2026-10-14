# 5090 one-shot session authorization diagnostic

Owner `/root/operator_5090_recover`. Independently exact-reviewed candidate and fresh Agent Validator CLEAR; executed once via `require_escalated`.

Exact command: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1 -BashBodyPath C:\KenshiModding\pending-fixes\rig5090-validation\chat006-session-read-once-body.sh`.

Reader SHA256 `1BC65EF399331B38ADB68B66167BBF489A61287196DC880E3D2710ADAA660A0A`; body SHA256 `E6E1BF3D40877759B17BCE1E361ADB7A3DF5B3B59B0F0669AD70D92B45663B21`; packet SHA256 `8346DD615174DDC0D520A2373FA531A7485C7C7CB5D072084671114F7A0CC518`; wrapper SHA256 `9E14992B65197BD1CDFF61768C3340008CE9FE389EBECC3EE51AE7F0C00156FC`.

Exit 1, no stderr; allowlisted output:

```
{"result":"FAIL","failure_kind":"readiness_gate_failed","session_present":true,"status":"pending","auth_mode":"current_campaign","generation_present":true,"manager_ready_matches":true,"canonical_session_identity_match":false}
```

The prior native snapshot established world `kah-fresh-start-5090-copy-20261013-152239`, unpaused speed1, focus0, isolation ON and nearby Bangs. This session read is a separate one-shot snapshot; it does not prove unchanged generation across invocations or bind native PID/save by itself.

No session initialization, token/marker edits, auto-switch, POST, game/KAH/input/order/chat, or save changes occurred. This is a setup authorization failure, not a product gameplay failure or test PASS.

Next: read-only canonical/isolated-test-save marker comparison, then an independently reviewed and freshly cleared normal-load recovery path. A newgame against an already bound different canonical is not assumed to fix identity; the documented authenticated handshake retains this guard.
