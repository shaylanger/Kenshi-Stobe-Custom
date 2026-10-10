# Multi-feature testing: roles and rules

Since 2026-10-02 one coordinator session runs Kenshi for every feature, so one game launch tests
STOBE, KenshiFP, Profession Gear (PG), the relationship system (REL) and the harness together.
The master list is `C:\KenshiModding\MASTER_TEST_PLAN.md` (the coordinator is the only writer).

## Roles

| Role | Owns | May | Must not |
|---|---|---|---|
| **Coordinator** (main session) | Kenshi, installs, fixtures, `MASTER_TEST_PLAN.md`, run logs, STOBE + KenshiFP + harness fixes, merging REL into live | launch/stop Kenshi, install DLLs, deploy the live server, start helper subagents | - |
| Helper subagents | whatever the coordinator assigns | that task only | anything above unless told |

Only the coordinator drives the game (exception since 2026-10-05: the FP combat session, lock owner `fpcombat`, see
`FP_COMBAT_COORDINATION_CONTEXT.md`). The REL builder role ended when REL went live (m18). The lock is `C:\KenshiTestRuns\game.lock`
(`tools/automation/kenshi-ctl.ps1 lock|release`); launch/stop/restart refuse if someone else holds it.

## Rig runners (Shay 2026-10-10: a script runs each rig, not an agent)

- `tools/automation/rig-runner.ps1` runs one hidden daemon per rig (5090 local, 4080 over ssh), started by
  `session-start.ps1` (`-Ensure`; `-Status`, `-Stop`). It replaces rig-watchdog.ps1 (now a shim).
- Work = `*.list` files (run-batch.sh format + header comments, see the script header) in
  `C:\KenshiTestRuns\queue\5090\`, `queue\4080\`, `queue\any\` (Stobe rows go to the 5090 only); FIFO by name.
- Per batch: list -> `queue\running\`, install the wanted/newest staged KenshiFP (Kenshi stopped, SHA checked),
  dryrun.sh the list, run a snapshot of run-batch.sh from the out dir (editing run-batch.sh never kills a batch),
  `queue\done\<list>` + `.result` + `.SUMMARY.txt`, a note to the list owner, next list at once. Failures before the
  game (dryrun, install, missing save) -> `queue\failed\<list>.result` + note; the runner goes on.
- Recording/analysis split: a take calls `pf_game_done` after its game part; run-batch.sh starts the next row while
  the take's checks finish in the background; `<out>/GAMEDONE` frees the rig for the next batch, `DONE` comes after
  every analysis.
- Every 60 s during a batch (`rig-runner-probe.sh`): stuck (Kenshi gone/crashed, not in the world, harness silent,
  game time frozen) >= 2 min with no out-dir change -> the row's step is killed (second hit: the game), ALERT, note;
  game idle while a row analyses in the foreground -> ALERT + note (add pf_game_done); empty queue >= 2 min -> ALERT +
  note to the coordinator. `rig-health.sh` and the Stop hook block on `ALERT-*.txt`; it clears when the rig works.
- Pause a rig: `kenshi-ctl.ps1 idle "<reason>"` / `idle4080 "<reason>"` (60 min). Lock owners: `runner-5090`, `rig4080`.
- Offline lab jobs run through `tools/automation/labnice.sh` (nice 15, ionice idle, nproc/2 slots in total).

## The loop

1. Feature agents write **in-game scenario files** (format: `stobe-auto run --help`,
   `Kenshi-Automation-Harness/docs/COMMANDS.md`) and tell the coordinator where they are.
2. The coordinator runs a batch: one launch per fixture, all features' scenarios for that fixture,
   reloading the fixture between scenarios that need a clean state.
3. Every failure becomes a bug row in the master plan with an **owner** (STOBE, KFP, PG, REL, KAH).
   The coordinator sends each owner its bugs.
4. Owners fix and report "ready: <commit>, <dll hash>" (no installs). The coordinator installs all
   ready builds together at the next restart and reruns the affected scenarios.

## Scenario file header (required)

```
# id: PG-crafting-01
# covers: PG 85, 86, 306
# fixture: Crafting base            (auto-home | Trader | Crafting base)
# reset: fresh                      (fresh = reload the fixture first | keep = runs on current state)
# needs: <builds/settings, e.g. ProfessionGear.ini Mode=Forced>
# verify: what proves a pass besides the regex steps (log lines, files)
```

Rules for scenario steps: name characters explicitly (never `@player`), start with `speed 0`,
check real state (inv/where/hp/stat/building/logs), never rely on an NPC's words,
leave the game paused at the end, no `save` except to a `kah-*` name.
Fixtures and what's in them: `C:\KenshiTestFixtures\FIXTURES.md`.

## Reporting to the coordinator

Subagents: return a short report (what changed, commits, hashes, scenario files, open questions).
Keep repo context files current (`testing/HANDOFF.md` "Current state", component `ACTIVE_CONTEXT.md`) so a fresh agent can resume; no separate handoff files.
Commit identity in every repo: `shaylanger <shaylanger2@gmail.com>` (check `git config user.email`;
use `git -c user.email=shaylanger2@gmail.com -c user.name=shaylanger commit` if it's wrong).
Push right after each commit. Never commit logs, DLLs, saves or runtime state.
