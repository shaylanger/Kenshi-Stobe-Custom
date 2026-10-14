# 4080 i3 retention source provenance body

Preparation only. `body.sh` has not been executed and no host was contacted. No installation, queue, game, save, or service action is included. The previous attempt reported the remote standalone route helper missing; this revision does not call that path.

The body requires the guarded `remote-bash-stdin-4080.ps1 -BodyPath <absolute path>` transport. It begins with the exact i3 preamble and sources the pinned `rig-env.sh` immediately after it. It runs `rig4080_i3_preflight` from that sourced helper and then applies an embedded copy of the local standalone route helper's complete post-source gate logic. The embedded executable gate statements were compared with the locally pinned helper; blank lines, wrapper indentation, output-only `echo`/`printf` statements, and its redundant `export RIG=4080` are omitted. That assignment is already set by the required preamble, and the original diagnostic strings included assignment syntax that the wrapper rejects anywhere in the tail. Fixed messages remain for route failures. The self-check confirms the rig-env function's path, inbox/lock, and harness-directory checks. It models the wrapper's tail guard and tests that route reassignment, unset, and extra source commands are rejected. Therefore the body preserves both isolation layers without requiring the missing remote standalone helper file. The body then checks the unique 127.0.0.1:18084 listener, privately compares its argv to the one expected PHP server command without emitting argv, requires one matching process, canonicalizes the fixed service root, and hashes only `lib/playthrough_retention.php` under that root. Output is restricted to i3 route, listener PID, service root, that file's SHA-256, and a boolean for whether normalized source line 40 matches the local candidate operation fingerprint.

The candidate being compared is `pending-fixes/stobe-session-readiness-20261013/staged/lib/playthrough_retention.php`, SHA-256 `2ACC102277DAAA2FCD5F88577EEBBFCDCE6D8CE5D911A57C5DA4378449A826C6`. Its trimmed line-40 operation fingerprint is `791954730045326a47dd46fc9a6caba34748e53e2e710b0bab734dc4f1d47518`. The body does not print source text, argv, environment, secrets, tokens, or backend data. A match proves only that the current file bytes/line operation under the listener's exact configured document root match the local candidate; it does not prove historical in-memory code identity or DB binding.

Current helper pins from the inspected packet/HANDOFF: wrapper `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`; `rig-env.sh` `A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D`; local source helper `instance-route-preflight.sh` `408FD0CAC181FEE32EF5DD0D0512CBD10494962CF1E251412EB900AF80E6EF51`. The local route-helper hash is checked by `selfcheck.py`; it is not expected to exist remotely. Local loaded-module helper pin reported in HANDOFF is `121956C2A61A4B59854BB12AC414C788A15B9A599D05680D98F78971D705A31F`; this provenance body does not need or invoke it.

Proposed invocation (not run):

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-i3-retention-provenance-20261014\body.sh
```

Local syntax/hash check (does not contact the host):

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -n testing/live-stobe-queue/packets/4080-i3-retention-provenance-20261014/body.sh
Get-FileHash -Algorithm SHA256 testing/live-stobe-queue/packets/4080-i3-retention-provenance-20261014/body.sh,testing/live-stobe-queue/packets/4080-i3-retention-provenance-20261014/README.md
```

Local route-equivalence/self-check (synthetic fixtures and local source files only):

```powershell
python testing/live-stobe-queue/packets/4080-i3-retention-provenance-20261014/selfcheck.py
```

Current artifact hashes: body `1A70A5D797F4F01B4087D8AC04BE313EF6BF979E90EBCB6ABC752675727724C2`; self-check `009D6D2B173C5F040DD0B2816BEF5933C2916FC3CA2BC90D0DB5BFFEB7802AFF`. README hash is reported with the local validation receipt.
