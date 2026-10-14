# 5090 sanitized source-excerpt invocation receipt

- Timestamp: 2026-10-14 09:16 UTC
- Packet host gate: PASS (`DESKTOP-JFLPK99`)
- Current independent exact-hash review: CLEAR; latest Agent Validator scope review: CLEAR for exactly one new invocation
- Local selftest: PASS (13 checks; sanitizer fixture 3 tokens; shell syntax pass; transport pin acceptance+mismatch rejection; fake invocation count 0)
- Invocation: authorized one-shot completed; no retry is authorized
- Transport: pinned documented elevated `invoke-wsl-captured.ps1`, distro `DwemerAI4Skyrim3`, cwd `/mnt/c/KenshiModding`, exact approved WSL argv
- Result: FAIL at live-root integrity gate: Git could not resolve the pinned `commit:path` blob for `lib/travel_companionship.php`. The prior packet used one `rev-parse` check and its receipt does not distinguish an absent tree entry from an unavailable object.
- Bounded evidence: root canonical path and pinned commit matched. The first three allowlisted files were checked and scanned; each had `MATCH=none`. The fourth file failed before content scan; the remaining allowlisted files and merge root were not inspected. No excerpt token matches were emitted.
- Retry/fallback: prohibited; the one-shot is consumed
- Scope: setup/source evidence only. It does not establish merge contents, route readiness, or launchability. `lib/negotiation_engine.php` remains excluded and throttle verification incomplete; `lib/playthrough_switching.php` remains excluded.
- Gameplay: no game or gameplay row was started; this invocation is not a gameplay test.
