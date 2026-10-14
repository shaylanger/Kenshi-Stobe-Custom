# KAH-CHAT-007 minimal body preparation (4080 isolated i3)

Preparation only. Neither body has been run and no host, SSH route, game, queue, save, install, or service was contacted or changed.

`roster-body.sh` has the required exact wrapper preamble and sources `rig-env.sh` immediately after it. It uses the documented i3 metadata-only route/inbox preflight, the documented exact-process loaded-module probe, and the read-only `stobe-auto status`, `input_isolation status`, and `chars 300` commands. This verifies route/inbox, PID/process path and loaded Stobe/Harness DLL paths and on-disk hashes, current world/save state, input isolation, and a fresh roster. The row's required AEF Stobe DLL and source-manifest values must be compared against the probe output during review.

The roster is dynamic, so `target-body.template.sh` contains explicit substitutions for the exact current display name and `#serial/index`. The operator must derive both from that fresh roster, replace both tokens, then independently review and hash the complete final bytes before any invocation. The body runs only the two exact read-only `where` queries after repeating route/inbox preflight.

The documented route and read-only command set do not establish a fresh backend health/schema/session-generation binding to the same live world. Existing session-generation inspection material is the separate PHP diagnostic stream; it is outside this minimal body. Therefore backend/session readiness remains an unmet gate and the row must stop as `FAIL setup` unless an independently documented read-only gate is supplied and reviewed. No PASS can be claimed from these bodies alone.

Proposed wrapper invocations (not run):

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-chat007-minimal-20261014\roster-body.sh
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-chat007-minimal-20261014\target-body.final.sh
```

Pinned wrapper SHA-256 required by the cleared scope: `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`.
