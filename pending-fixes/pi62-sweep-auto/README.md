# PI-62: Stop-hook sweep -Auto (swap note)

Committed and live now: `tools\automation\testruns-sweep.ps1 -Auto` (+ `-DryRun`, `-AutoMinHours`, `-NewestNC`) and its selftest.
Not live until the one-line hook swap below (the coordinator may not edit hooks/settings; Shay or a permitted session does the swap).

## What `-Auto` does (only items already STALE and >= 24 h old; never corpus, inflight, agents, queue, logs, scenarios, game*.lock, KenshiTestFixtures, reparse points, anything named by a RUNNING/STOPPED-CONTEXT status, inflight marker or queue file)
- AUTO-DELETE (5090 root, top level only; logged to `C:\KenshiTestRuns\sweep-auto.log`): `selftest-run*.txt`, `selftest-all*`, `scratch-*`, `coordinator.heartbeat.*.tmp`, `dur_run*.sh` (Shay 2026-10-16), `pd` (dir), `*.brief.md` strays, `imm26-nc<N>[-suffix]` with N <= newest NC number - 2 (newest = highest `imm26-nc<N>` tree) and no RUNNING status naming `nc<N>`; the NC rule needs `git rev-list @{u}..HEAD` = 0 in C:\KenshiModding.
- AUTO-KEEP 7 days (standard reason `AUTO(PI-62): ...` in `sweep-keep.tsv`, logged, once per path; an expired auto-keep resurfaces as a normal STALE): `pi<N>-stage`, `*-report.txt|md`, 4080 launch-log dumps (`*before-launch`, `launch*.log|txt`), recent `imm26-nc<N>` trees. Same pushed-git gate.
- Everything else stays a normal STALE (extend the lists in `Invoke-AutoSweep` if wanted).

## Swap (hook change)
One command, AFTER the PI-51 swap: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\pending-fixes\pi62-sweep-auto\swap.ps1` (refuses if PI-51 is not live; backs up, swaps, runs the selftests). Manual steps below.
Candidate: `tools\automation\hooks\kenshi-waker-guard.ps1.pi62.candidate` = the PI-51 candidate (kenshi-waker-guard.ps1.candidate, i.e. the live hook after the PI-51 swap) with the sweep line changed to `... testruns-sweep.ps1') check -Auto 2>$null` (CRLF, parses clean).
1. `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\testruns-sweep-selftest.ps1` -> `SELFTEST-SUMMARY 30 pass / 0 fail`.
2. Dry run on the live root: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\testruns-sweep.ps1 check -Auto -DryRun -Local` (shows what would be deleted/kept).
3. Back up: `Copy-Item C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1 C:\KenshiTestRuns\backup\kenshi-waker-guard.ps1.pre-pi62`
4. Swap: `Copy-Item C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1.pi62.candidate C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1 -Force`
5. Check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\waker-lanes-selftest.ps1` (and `selftest-all.ps1 -Only waker*`), then commit the hook (git rm the .candidate).

## Rollback
Copy the backup from step 3 back over the hook (or `git checkout` the hook file). Without the hook change, `-Auto` is simply unused; running `testruns-sweep.ps1 check -Auto` by hand is the same action.
