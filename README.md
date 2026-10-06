# Kenshi-Stobe-Custom

Personal development workspace for the custom STOBE + KenshiFP setup used for a voice-driven, first-person Kenshi playthrough.

This repository intentionally combines the project/Claude workspace with snapshots of the two native codebases that are modified alongside the STOBE server fork.

## Layout

- CLAUDE.md - working instructions and environment notes for coding agents; `testing/HANDOFF.md` - current state.
- MASTER_TEST_PLAN.md, STOBE_full_test_plan.md - open test rows and open STOBE items only.
- docs/ - reference: commands/test bed/gotchas (`REFERENCE.md`), NPC info panel, relationship system (REL) design, architecture and results.
- testing/ - roles, subagent prompts, handoff state.
- tests/ingame/stobe/ - in-game STOBE test wrappers and scenario files (run with `tools/automation/run-batch.sh`).
- tools/ - regression, automation, debugging, and test utilities.
- pending-fixes/ - anchor-asserting patch scripts while a fix is in flight (removed once committed).
- archive/ - recent run logs, old bug numbering, one-off reports.
- components/STOBE/ - snapshot of the customized native STOBE DLL source. Upstream: Dwemer-Dynamics/STOBE.
- components/KenshiFP/ - snapshot of the customized KenshiFP source (first-person only since 2026-10-06). Upstream: linguine2552/KenshiFP.
- build-support/StobeDLL/ - the custom Windows/VS2010 build scripts and small compatibility headers used for the deployed STOBE DLL.
- training-data/ - curated historical server logs (raw live capture is gitignored).
- CUSTOM_CHANGES.md - broad summary of the important differences from the baseline mods.
- Separate repos checked out here (gitignored): Kenshi-Automation-Harness/, Kenshi-Profession-Gear-Progression/.

## Live source locations

The active development/build trees currently remain outside this repository:

- Native STOBE source: /root/STOBE-src in WSL.
- STOBE Windows build copy: C:\StobeBuild.
- KenshiFP source: /root/KenshiFP in WSL.
- STOBE PHP server: /var/www/html/StobeServer, tracked separately in shaylanger/StobeServer.

The component directories in this repository are source snapshots for version history. Before committing native changes, refresh the relevant snapshot from the live source tree so Git records the actual deployed source.

Generated DLLs, compiler/SDK payloads, models, logs, and runtime game state are intentionally excluded.
