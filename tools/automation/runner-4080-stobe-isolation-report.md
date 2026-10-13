# 4080 Stobe runner gate

The main `-Rig 4080` runner continues to reject every Stobe list because it uses shared instance 1. Lane `4080b` accepts a Stobe list only when it declares instance 3, the exact copied save in both `# stobe-save:` and `# launch:`, and reviewed Stobe DLL SHA256 `40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D`. The remote gate verifies the instance marker, local-save setting, copied `quick.save`, exact DLL hash, single-link files, and non-reparse paths. Lane 4080b then routes to `C:\KenshiInst\3`, skips instance sync/save-copy, and proves the contract again immediately before launch. Stobe filler and filming lists remain rejected.

Supported input is a numeric `*.list` placed in `C:\KenshiTestRuns\queue\4080b\` with `# gfx: low` and these headers:

```text
# stobe-instance: 3
# stobe-save: kah-stobe-travel-validation-20261013
# launch: kah-stobe-travel-validation-20261013
# stobe-dll-sha256: 40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D
```

Every row's save field must be `-` or `kah-stobe-travel-validation-20261013`. Run through the 4080b queue runner; direct `itrun` bypasses lane proof, admission, dry-run, and progress tracking. The main 4080 lane remains barred.

Validation performed without starting/stopping a game or touching physical queues:

- `stobe-isolation-gate.ps1 -SelfTest`: PASS, 8 cases (isolated path accepted; unknown/shared path, hard link, Stobe/save junction, wrong hash, and mismatched save rejected).
- `rig-lane2-4080.ps1 -SelfTest`: PASS, 71 cases (accepted contract, missing/invalid declarations, row-save mismatch, instance-3 routing, no-sync rule, film/filler rejection).
- `runner-parse-ok.ps1 -Rig 4080b`: PASS.
- Git Bash `bash -n list-rigcheck.sh`: PASS.
- `rig-runner.ps1 -SelfTest`: the Stobe guard/proof/lane tests passed; the suite ended FAIL because its separate row-cache suite reported 4 `miss` cases (`ROWCACHE-SELFTEST FAIL 4 19 cases`). This patch does not modify row-cache logic.

No game was launched or stopped by this change. The supported next speed-up is to measure the two proof round trips on the first queued list; if they dominate, combine script/save checks with the final isolation proof while retaining a pre-switch proof.
