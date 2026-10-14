# 5090 Stobe isolated-source excerpt packet

State: **LOCAL PACKET PREPARATION ONLY**. This packet is restricted to exact route metadata and sanitized matching tokens from six previously allowlisted, non-protected PHP files. It excludes `lib/playthrough_switching.php` (protected source) and `lib/negotiation_engine.php` (not in the previous allowlist); therefore it cannot prove or repair the negotiation throttle unless that file receives separate authorization.

## Pinned route

- Host identity enforced by `run.ps1`: `DESKTOP-JFLPK99` (the documented 5090 alias).
- WSL distro and transport: `DwemerAI4Skyrim3` through the existing `invoke-wsl-captured.ps1` route, working directory `/mnt/c/KenshiModding`. The transport stages the complete UTF-8 Bash body from stdin to a private temporary file before executing it, so a fail-fast Bash body cannot close the input pipe while the host is still sending it. The runner pins the current transport helper SHA-256 before invoking it.
- Exact roots and expected commits:
  - live: `/var/www/html/StobeServer`, commit `4722ddd96d838e84ddb9a49da0ee893f45bcaab7`
  - merge: `/root/stobe-work/ss-merge`, commit `7aff5ba605a956d33accc8080f712dfba4015246`
- Source allowlist: `interaction.php`, `lib/playthrough_preferences.php`, `lib/playthrough_runtime.php`, `lib/travel_companionship.php`, `lib/chat_helper_functions.php`, `lib/activity/ActivityService.php`.

The body rejects root/symlink or commit mismatches, verifies each file is tracked and clean at the pinned commit, prints every allowlisted file's SHA-256, and emits only line-numbered exact matches for `/var/lib/stobe` or temporary-throttle tokens. The pinned-path check uses Git tree metadata and a no-lazy-fetch object-existence check to distinguish an absent tree path from an unavailable blob; either fails closed before reading that file. It never prints full lines or neighboring source. It does not inspect config, credentials, environment, saves, logs, DB, or services. `lib/playthrough_switching.php` remains excluded despite being present in the older metadata-only allowlist because it is protected and must stay unread. `lib/negotiation_engine.php`, where the documented shared temporary throttle resides, is outside the currently authorized list; the packet's receipt must mark throttle verification incomplete.

## Local checks

`selftest.ps1` tests pinned roots/commits, the literal source allowlist, protected-file exclusion, output-token filters, and PowerShell/Bash syntax without WSL or rig contact. It also creates a temporary local Git fixture to verify distinct results for a present blob, an absent tree entry, an unavailable blob, and an invalid commit; failure cases stop before source scanning. A synthetic canary fixture verifies that only the three allowed match tokens and line numbers print, never surrounding text. The transport self-test additionally stages a synthetic body before execution and simulates a child that closes stdin early, checking that the original child stdout/stderr/exit are still surfaced. The one-shot `run.ps1` is not to be invoked unless the exact packet files/hash have independent CLEAR and all route pins match.
