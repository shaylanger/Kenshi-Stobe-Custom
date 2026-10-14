# 4080 elevated readiness probe receipt — 2026-10-14

Scope: exactly one Agent-Validator-cleared setup-only helper-hash probe through `tools/automation/remote-bash-stdin-4080.ps1`; no gameplay, KAH/chat/service action, retry, fallback, ACL change, or config/identity substitution.

Preflight: all five approved SHA256 pins matched immediately before invocation. Candidate basename matched `native-minimal-readiness-4080i3.sh`; the pinned wrapper enforces host `DESKTOP-NQQPA73` and isolated `KAH_INSTANCE=3` / `C:\KenshiInst\3` route. No raw config or credential material was read or recorded.

Sanitized result:

- stdout: `SANITIZER_HELPER present=false`
- stderr summary: `READINESS_STDERR captured=true category=known_clixml_prefix receiver_stage=post_route_guard lines=2`
- process exit: `2`
- interpretation: the wrapper confirmed the remote receiver passed its host/i3 route guard. The fixed helper file was not present at the requested path on that route, so no helper hash was obtained. The sanitized stderr category is recorded without raw text.

This single invocation is spent. Stop here; do not retry or change permissions/routes. This is readiness evidence only; neither rig gameplay status changes as a result.
