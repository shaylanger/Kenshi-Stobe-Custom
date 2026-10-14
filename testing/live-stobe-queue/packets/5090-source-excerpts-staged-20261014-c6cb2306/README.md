# 5090 Stobe isolated-source excerpt packet

State: **PREPARED ONLY — NOT AUTHORIZED TO RUN.** Unique invocation ID: `5090-source-excerpts-staged-20261014-c6cb2306`. Snapshot path: `C:\KenshiModding\testing\live-stobe-queue\packets\5090-source-excerpts-staged-20261014-c6cb2306\`. Do not invoke this packet until its frozen hashes receive independent exact review and a fresh Agent Validator CLEAR for that exact invocation.

## Exact target and transport

- Host gate: `DESKTOP-JFLPK99`.
- WSL distro: `DwemerAI4Skyrim3`; working directory: `/mnt/c/KenshiModding`.
- Runner calls `C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1`, pinned to SHA-256 `ED417184EAC849DEFCDCB9F49F969B037A6159B67431051E53FCF450E70667DF`. The transport sends UTF-8 over stdin to a fixed Bash receiver that stages the complete body in a private temporary file before executing it with `bash -s`; the EXIT trap removes the staged file. The packet includes a byte-identical local helper snapshot for offline review only; the runner uses the pinned shared helper path above.
- The consumed earlier invocation receipt records argv `wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding -- bash -s`. This frozen packet uses the revised staged-input helper; its code constructs `wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding -- bash -c <fixed staging receiver>`. The receiver source is in the pinned helper snapshot and covered by its offline transport self-test.
- Exact source roots/commits are unchanged: live `/var/www/html/StobeServer` at `4722ddd96d838e84ddb9a49da0ee893f45bcaab7`; merge `/root/stobe-work/ss-merge` at `7aff5ba605a956d33accc8080f712dfba4015246`.

- Exact helper receiver argument text: tmp=$(mktemp) || exit $?; trap 'rm -f -- "$tmp"' EXIT; cat >"$tmp" || exit $?; bash -s <"$tmp"; exit $?

## Source and output scope

The excluded paths remain excluded from the scan and outside the currently authorized list. The protected switching file remains excluded.

The exact six-file allowlist is `interaction.php`, `lib/playthrough_preferences.php`, `lib/playthrough_runtime.php`, `lib/travel_companionship.php`, `lib/chat_helper_functions.php`, and `lib/activity/ActivityService.php`. The only fixed query tokens are `/var/lib/stobe`, `stobe_negotiation_`, and `sys_get_temp_dir`. Protected `lib/playthrough_switching.php` and out-of-scope `lib/negotiation_engine.php` remain excluded; the throttle question therefore remains unanswered.

The body requires the pinned root/commit, tracked blob, exact canonical paths, clean tracked files, and no lazy fetch. It outputs fixed root/commit metadata and per-file SHA/Git-blob hashes, plus only the fixed token and line number; it never emits source text or neighboring context. It caps match records at 100. A successful two-root run is bounded to at most 136 output lines (100 match records plus at most 36 fixed/non-match records); exceeding the match cap fails closed, with at most 137 total lines including the overflow failure record. It reads no config, credentials, environment values, saves, logs, DB, or services.

## Offline validation and freeze

`selftest.ps1` and `transport-helper.tests.ps1` use local synthetic fixtures/Git and Git Bash only; they must not invoke WSL, SSH, a device, source site, service, or game. The packet selftest checks the six-file allowlist, three exact tokens, match-output cap, no-context output, pinned commits, and distinct synthetic Git outcomes. The transport tests check PS5.1 parse, staged complete-body delivery when the child exits immediately, and preservation of child streams/status if stdin closes early. `packet.manifest.tsv` records exact local and external artifact hashes; all files are marked read-only after review/freeze. Preparation and passing offline checks do not authorize execution. Any attempt needs fresh independent exact-hash review and a fresh Agent Validator CLEAR naming this invocation ID and packet hashes.
