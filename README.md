# Kenshi-Stobe-Custom

Personal development workspace for the custom STOBE + KenshiFP setup used for a voice-driven, first-person Kenshi playthrough.

This repository intentionally combines the project/Claude workspace with snapshots of the two native codebases that are modified alongside the STOBE server fork.

## Layout

- CLAUDE.md - working instructions and current environment notes for coding agents.
- pending-fixes/ - patch scripts and staged fixes used during development.
- tools/ - regression, automation, debugging, and test utilities.
- archive/ and test-run files - historical in-game test results.
- components/STOBE/ - snapshot of the customized native STOBE DLL source. Upstream: Dwemer-Dynamics/STOBE.
- components/KenshiFP/ - snapshot of the customized KenshiFP source. Upstream: linguine2552/KenshiFP.
- build-support/StobeDLL/ - the custom Windows/VS2010 build scripts and small compatibility headers used for the deployed STOBE DLL.
- CUSTOM_CHANGES.md - broad summary of the important differences from the baseline mods.

## Live source locations

The active development/build trees currently remain outside this repository:

- Native STOBE source: /root/STOBE-src in WSL.
- STOBE Windows build copy: C:\StobeBuild.
- KenshiFP source: /root/KenshiFP in WSL.
- STOBE PHP server: /var/www/html/StobeServer, tracked separately in shaylanger/StobeServer.

The component directories in this repository are source snapshots for version history. Before committing native changes, refresh the relevant snapshot from the live source tree so Git records the actual deployed source.

Generated DLLs, compiler/SDK payloads, models, logs, and runtime game state are intentionally excluded.
