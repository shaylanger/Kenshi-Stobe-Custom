# 4080 KAH-INT-003 executable packet — exact row/list review CLEAR; Validator pending

This packet adapts the already approved portrait/target-refresh acceptance case to the existing `run-batch.sh` + isolated i3 KAH route. It is local review material only; it has not been copied into `C:\KenshiTestRuns\queue\4080`, and no rig/KAH/queue action was taken.

## Exact files

- Row script: `tests/ingame/stobe/STOBE-INT003-TWO-HUMANOIDS-4080.sh`
  - SHA-256: `FA66F38206993E808F7B9747C312306EAA7F7E34D5B68791CE0570030378C498`
- Runner list: `testing/live-stobe-queue/ready-4080-int003-portrait.list`
  - SHA-256: `CD773555657CC60897817D42C9A294CC3BD4E9018590A5D83786007881117890`
- Shared portrait helper: `tests/ingame/stobe/portrait-row-lib.sh`
  - SHA-256: `64780F2411742D407291CD775FFAE49DB58A6CA500A2BA1070E985A4A6A88784`
- Immutable acceptance row: `testing/live-stobe-queue/integrated-AEF84C0A/kah-int-003-portrait-two-humanoids.sh`
  - SHA-256: `0DC6C629D833E20205DFFD9ABCDBD8050C3F73E9B392D526F6575249BFC35B9B`

## Existing runner invocation

`tools/automation/rig-runner.ps1` consumes a single `*.list` placed in `C:\KenshiTestRuns\queue\4080\`; its established 4080 path runs that list through `C:\KAH\itrun.ps1` and `tools/automation/run-batch.sh`. The exact local list above names the existing test-copy save `kah-stobe-4080-standalone-active`, player/speaker Bark, an eight-minute bound, the pinned Stobe and Harness builds, and the executable row script. After exact review and fresh row-specific Validator clearance, the coordinator/operator may stage that exact list into the 4080 queue. The running runner takes it FIFO; no alternate input transport is introduced.

The old immutable `kah-int-003-portrait-two-humanoids.sh` emits instructions only. It is not invoked as the gameplay command. The old `STOBE-PORTRAIT-ABSENT-4080.sh` is also not used: it tests a single actor and its default DLL pin is a different build.

## Fail-closed setup gates

The script exits before panel actions unless all these fresh checks pass:

1. `RIG=4080`, `KAH_INSTANCE=3`, the existing `rig4080_i3_preflight` route/inbox guard, and host `DESKTOP-NQQPA73`.
2. Exact i3 process/module-path proof checks that the loaded Stobe and Harness paths are precisely under `C:\KenshiInst\3\mods\...`; on-disk hashes must match Stobe `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` and Harness `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`. Private `127.0.0.1:18084` config and healthy ready schema are also required.
3. A fresh sanitized `PLAYTHROUGH_SESSION` read with session present, `status=ready`, numeric game time, a SHA-256 load marker, generation present, and generation/manager match. A reader/WSL failure is `FAIL setup` and cannot be bypassed.
4. The expected copied save in a live unpaused world; Stobe ping responds; input isolation already reads `on`, and both input-isolation and FP-state reads show focus `0`. The script never enables isolation, changes focus, or activates the window.
5. Bark is present as the speaker; Solka `[Samurai Police Aina]` and Apothecary Matsuyo resolve to two distinct current handles, both must report the expected `race=Greenlander`, be alive/conscious, have equipped inventory, and at least one must have equipped headgear. Any missing or mismatched evidence is `FAIL setup` before the portrait panel opens.

## Row actions and assertions

Using only the existing `stobe-auto` KAH route, the script opens/refreshes the panel on A, selects B, then returns to A. Each stage waits at most ten seconds for exact target key, loaded portrait, and a strictly newer generation before taking a screenshot. It correlates each target to a new `PROFILE_PORTRAIT` log event, checks equipped headgear meshes are absent from the private portrait scene when present, hashes all three screenshots, and compares both actors’ equipped-inventory snapshots before/after. Isolation/focus are reread at the end.

The script emits a mechanical RESULT marked `visual_review=required overall=provisional` plus artifact paths/hashes. The acceptance row still requires a recorded human visual review of both targets for a recognizable camera-facing face, no portrait headgear, natural color, and correct A/B/A target/image correspondence. Do not treat the runner's mechanical PASS as final acceptance until that review is recorded; setup failures and product/evidence failures remain separately reported. No chat request ID is expected.

## Local checks and outstanding reviews

Git Bash `bash -n tests/ingame/stobe/STOBE-INT003-TWO-HUMANOIDS-4080.sh` passed on this exact script revision. The standard `dryrun.sh` could not run locally: it requires WSL root (`DRYRUN-SUMMARY FAIL dryrun.sh needs root (wsl.exe -u root)`); this is not a row/product result. No row execution or dry-run override was made.

The first independent exact review returned `REVISE` for missing module-path checks and unverified source/payload RESULT fields; the revision added exact i3 module-path checks and removed those fields. The second returned `REVISE` because the actor race test accepted Skeleton; the latest revision requires both pinned actors to report `race=Greenlander` and marks its mechanical PASS as provisional pending human visual review. The third exact review returned `CLEAR` for the exact row script/list; a subsequent packet factual-alignment review also returned `CLEAR`. Fresh row-specific Agent Validator clearance is pending. Do not stage the list or contact the rig until Validator returns CLEAR. The earlier INT-003 4080 attempt is only `FAIL setup` because focus was 1 and session-generation proof was absent; it performed no panel action and does not count as a product result.
