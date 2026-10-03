# How to pick up the multi-feature test loop

For a fresh coordinator session (e.g. "Helper agent standby") taking over from the previous one.

## Goal (Shay, 2026-10-02)
Run every automatable test of every feature (STOBE, KenshiFP, Profession Gear, relationship system,
harness) in combined Kenshi launches, log bugs, fix them (or have the owner agent fix them), rebuild,
reinstall, relaunch, retest; **don't stop until everything automatable passes**. Things only Shay can
judge go to MASTER_TEST_PLAN.md section 3, things needing a situation we can't build to section 2.
Commit + push often in all 4 repos (workspace, StobeServer, harness, PG; REL branch too).

## Read first
1. `CLAUDE.md` (workspace rules, test bed, tools) and `testing/README.md` (roles, loop, scenario format).
2. `MASTER_TEST_PLAN.md` (index + status of every row + open bugs) and the newest `archive/test-run-*-m<n>.md` (what was being run, results so far).
3. `C:\KenshiTestFixtures\FIXTURES.md`, `Kenshi-Automation-Harness/docs/COMMANDS.md`.

## State to check before doing anything
- Is Kenshi running? `powershell -File tools/automation/kenshi-ctl.ps1 status`; lock: `... lock` (owner `coordinator`; take over with `$env:KAH_OWNER='coordinator'`).
- Background subagents of the previous session (PG agent, REL builder) die with that session. Check their outputs in git instead:
  - PG: `Kenshi-Profession-Gear-Progression` git log, `INGAME_STATUS.md`, `tests/ingame/RUN_ORDER.md`, `ACTIVE_CONTEXT.md`.
  - REL: `isolated/relationships-phase1/DELIVERY.md`, `PHASE1_HANDOFF.md`, WSL `/root/stobe-work/social-phase1/server` git log (branch `feature/social-phase1`).
  - Restart them with the prompts' intent from `testing/README.md` roles if their work is unfinished.

## Progress log (newest last; the coordinator appends a line at each milestone)
- 2026-10-02 23:45 setup done (master plan, roles, lock, PG install target), PG agent + REL builder started.
- 2026-10-02 23:48 run m1 started on auto-home (plan in `archive/test-run-2026-10-02-m1.md`). A7 PASS, A6 -> bug 65, goal "Home" -> bug 66. Next: 43 (Malzin was asked for all bread + meat; answered "All of it?", confirm), then 41, A4, 54/56, A1/A2, 14/15/A3, fights, 59.
