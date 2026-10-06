# Testing without Shay: what's possible and the plan

Done (2026-10-06 cleanup): every layer of this 2026-10-02 plan is built and in use: offline server regression/replay
tests (`stobe-tests`), the standalone Kenshi Automation Harness (`Kenshi-Automation-Harness/`, `docs/COMMANDS.md`;
load/spawn/teleport/ko/damage/kill/relation/hunger/... plus screenshots), scenario files and wrappers run by
`tools/automation/run-batch.sh`, and Claude launching/stopping Kenshi itself (`kenshi-ctl.ps1`). What still needs Shay
(sound, feel, tooltips) is `MASTER_TEST_PLAN.md` section 2. The original plan text: `git log -p test-automation-plan.md`.
