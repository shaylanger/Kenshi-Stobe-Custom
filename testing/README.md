# Multi-feature testing: roles and rules

Since 2026-10-02 one coordinator session runs Kenshi for every feature, so one game launch tests
STOBE, KenshiFP, Profession Gear (PG), the relationship system (REL) and the harness together.
The master list is `C:\KenshiModding\MASTER_TEST_PLAN.md` (the coordinator is the only writer).

## Roles

| Role | Owns | May | Must not |
|---|---|---|---|
| **Coordinator** (main session) | Kenshi, installs, fixtures, `MASTER_TEST_PLAN.md`, run logs, STOBE + KenshiFP + harness fixes, merging REL into live | launch/stop Kenshi, install DLLs, deploy the live server, start helper subagents | - |
| **PG agent** | `Kenshi-Profession-Gear-Progression` repo (own git) | edit/build/test PG offline, write PG in-game scenario files, commit + push PG | launch Kenshi, install DLLs, touch the game folder, edit the master plan |
| Helper subagents | whatever the coordinator assigns | that task only | anything above unless told |

Only the coordinator drives the game (exception since 2026-10-05: the FP combat session, lock owner `fpcombat`, see
`FP_COMBAT_COORDINATION_CONTEXT.md`). The REL builder role ended when REL went live (m18). The lock is `C:\KenshiTestRuns\game.lock`
(`tools/automation/kenshi-ctl.ps1 lock|release`); launch/stop/restart refuse if someone else holds it.

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
Keep repo context files (`ACTIVE_CONTEXT.md`, handoffs) current so a fresh agent can resume.
Commit identity in every repo: `shaylanger <shaylanger2@gmail.com>` (check `git config user.email`;
use `git -c user.email=shaylanger2@gmail.com -c user.name=shaylanger commit` if it's wrong).
Push right after each commit. Never commit logs, DLLs, saves or runtime state.
