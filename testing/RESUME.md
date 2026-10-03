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
- 2026-10-03 00:30 run m2 (Stobe E36506E5, KenshiFP 0D2E3A1F, PG 475B9508 Forced+InGameTest). STOBE fixer subagent fixed 64–72 live; REL builder delivered phases 1–3 (merge server `68c0c25`, `pending-fixes/rel-native-phase3.patch`, see `isolated/relationships-phase1/DELIVERY.md`), now on phases 4–5; PG agent delivered scenarios (`tests/ingame/RUN_ORDER.md`, 4 launches) and DLL 475B9508. PG auto-home scenarios running via `C:\KenshiTestRuns\m2\run-pg.sh` (CSVs there). Next: Crafting base + Trader files, then restart: integrate REL p1–3 + new fixer builds, PG launches 2–4, REL scenarios.
- 2026-10-03 02:10 after run m3. Installed: Stobe D64BBA22 (REL 1–5 merged, Capture=0), KenshiFP 603C456E, harness 542B90BF, PG FAA5B471 (Forced+InGameTest). Server live = REL 3cd48b5 + fixes up to 69d/77 (`d22ecdc`), SOCIAL_RELATIONSHIP_MODE=off. Subagents (die with this session): STOBE fixer (bugs 64–78; 78 in progress), PG agent (waiting for reruns: pg-02,03,07,08,11,21 + launches 2–4), REL builder (phases 1–5 delivered; idle), harness helper (idle), crash analyst (m3 crash dump `C:\KenshiTestRuns\crash-m3\`).
- Next: read crash analysis -> fix -> run m4 = Capture=1 launch (StobeCustom.ini [SocialRelationships] Capture=1): REL p1-02..04, p2-01..05, p3, p4, p5 (RUN_ORDER in WSL `/root/stobe-work/social-phase1/server/tests/social_relationship/ingame/`), PG reruns, STOBE retests 76, 69, 78, A11 (ground-floor NPC), A3, 16, 60 tier 0. Then PG launches 2–4 (set_test_mode.ps1), REL batch end: `--set-mode off`, `--purge-all --yes`, Capture=0.
