# Handoff: multi-feature test loop (coordinator) — state 2026-10-03 ~17:35 (end of run m17)

You are the **coordinator** (see `testing/README.md`). Goal (Shay): run every automatable test of STOBE, KenshiFP, PG,
REL and the harness, log bugs, fix (yourself or via owner subagents), rebuild, reinstall, retest; Shay-only checks ->
`MASTER_TEST_PLAN.md` section 3, missing setups -> section 2. Concise answers. Commit + push often.

## Read first
`CLAUDE.md`, `testing/README.md`, `MASTER_TEST_PLAN.md`, run log `archive/test-run-2026-10-03-m17.md` (+ m16),
`C:\KenshiTestFixtures\FIXTURES.md`, harness `docs/COMMANDS.md`, local `handoff/4080-test-rig.md` (second machine).

## State now
- **No game running** (5090 and 4080 both stopped). 5090 lock `C:\KenshiTestRuns\game.lock` owner `coordinator`.
- **No subagents running** (PG agent finished; STOBE fixer for 107 and the 4080 rig operator were stopped before doing work).
- Installed on the 5090 and the 4080: harness `F6A3FC31`, PG `D7A60E49` (Forced + InGameTest). 5090 only: Stobe `478D8AA6`, KenshiFP `5719BEA5`. Server live `31b8c75` (items to 106). StobeCustom.ini Capture=1. Nothing built and waiting.
- 4080 has a leftover save copy `kah-home` (delete when done).

## Next steps (in order)
1. **Item 107** (STOBE 21 on Full-Base: Beaks' unpaid pay-later deal never BREACHED_PLAYER): investigate/fix (STOBE plan section D row 107 has evidence). Then STOBE 18 Full-Base FAIL (directive sent, no betrayal).
2. Launch (`kenshi-ctl.ps1 launch -Save auto-home`, `stobe-say on` first) and run the rest of the m17 batch:
   `C:\KenshiTestRuns\m17\next2.sh` minus the Full-Base loop already done (Squin 14/A3/15, auto-home 61, rel-enslaved,
   rel-theft, 1g trading modes `STOBE-102-104-relationship-trading.sh <mode>`, A8 auto-home + GROW, 18/21/22 home),
   then `m17\rerun.sh` (generic + 16 Full-Base, now with `fullbase-guard.sh`), then `m17\pg.sh` (pg-09 soak + Full-Base pg-50..55).
   Run long WSL jobs with Bash `run_in_background` + `wsl.exe … bash -s <<'EOF'` heredoc, `< /dev/null` on each script.
3. 4080 rig (PG/harness only): PG 254 (pg-74), 120 (pg-73), 132/133/240 (import/newgame, last in a launch), Squin 220-227/217/108,
   balance 161-199 except pg-50..55, pg-01..08 regression. Results `C:\KenshiTestRuns\m17-4080\` labelled -4080.
4. PG: pg-15 on launch 3 (PG disabled) to close rows 151-152; optional pg-13/pg-14 reruns (PG a97c28a scenario fixes).
5. End: Capture=0, REL mode off, PG `set_test_mode.ps1 -Mode Normal -Rules Normal`, close Kenshi, final summary.

## Gotchas learned in m17
- **Full-Base gets world raids** (Band of Bones, Kral's Chosen) that KO/kill the squad mid-test: every Full-Base wrapper now runs
  `tests/ingame/stobe/fullbase-guard.sh` (protect squad + `calm_raiders` KO within 400 m) right after the load.
- `stobe-fight-lib.sh` is sourced by every wrapper: run `bash -n` on it after any edit (an apostrophe inside `${2:-…}` broke it once).
- Don't run Windows `python3` in Git Bash (hangs on the Store stub); use WSL python3.
- Earlier gotchas: see the bottom of `testing/HANDOFF.md` history in git (`git log -p testing/HANDOFF.md`) and CLAUDE.md "Test bed".
