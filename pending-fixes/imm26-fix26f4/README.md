# imm26-fix26f4: row 26-f, availability gate for in_combat (design B)

Problem (4080-i4 op17, stobeserver.log 22:27:20): the sfO seam made Cind's chat turn a real ClearGroup PROPOSE, but ActivityChat.php rejected it
("Activity availability rejected", npc_availability.php reason `in_combat`: she is fighting the very group she is asked to clear). The same gate re-checks at ACCEPT.

Design B: the seam (test-only, lane gate `/tmp/stobe-*/site` + private DB socket) opens ONLY the availability gate, and only when the armed marker carries
`bypass_availability:true`. Production files (npc_availability.php, ActivityChat.php, apply.py's one guarded call) are not touched. Grounding, willingness, consent evidence
and the native scope check stay real; consent is never created by the seam (no ACCEPT injected without real consent evidence from the player's Yes).

## Files
- `patch.py` (anchor-asserted, idempotent; arg = repo root) edits `pending-fixes/imm26-sfO/ActivityTestInject.php` + `imm26_sfO_inject_propose.php` (tests J1..J11). Already applied in the tree.
- `patch_rowtools.py <rowtools dir>`: `inject-propose.sh` gets `--bypass-availability [--bypass-window 60..1800]` and `--disarm-all`; `--disarm` keeps a phase-2 accept marker.
- `rowtools/reloaddefs_sfe.sh.candidate`: `rs_inject_arm` passes `--bypass-availability` (opt out `RW_INJECT_BYPASS=0`), `rd_26f` wrapper calls `rs_inject_end` (`--disarm-all`, evidence `inject_end.txt`) on every exit path.
  NOT swapped into `reloaddefs_sfe.sh`: the lane operator copies it over (`cp reloaddefs_sfe.sh.candidate reloaddefs_sfe.sh`) at a row boundary.

## Deploy to a lane site (4080-i4 / any isolated lane; never the live tree)
1. `bash testing/live-stobe-queue/imm26-assert/rowtools/inject-propose-deploy.sh --check 4080-i4` then `... inject-propose-deploy.sh 4080-i4`
   (re-copies the new ActivityTestInject.php + test file, php -l, backup in `<lane>/bak-pre-sfO`; no game restart, opcache ~1 min).
2. Swap the candidate (`cp rowtools/reloaddefs_sfe.sh.candidate rowtools/reloaddefs_sfe.sh`), then `bash rowtools/reload-run-sfe.sh 26-f 4080-i4 --save <ready save>`.
3. Evidence in `rows/26-f/`: `inject_arm.txt` (bypass_availability=1), `inject_status.txt`, `inject_end.txt`; server log lines `availability bypassed` (shows was_reasons=[in_combat]) and `accept injected`.

## Proof run (offline, staged copy of rowtools with the candidate swapped in; no game, lane or live server)
- `php -l` ActivityTestInject.php, imm26_sfO_inject_propose.php: no syntax errors.
- `inject-propose-selftest.sh`: SELFTEST-RESULT PASS 36 checks (includes lane-mode PHP seam run, C11..C14 bypass flag / --disarm keeps phase 2 / --disarm-all / bad window).
- `reload-sfe-selftest.sh` (1500 s timeout, takes ~12 min): SELFTEST SFE ALL PASS 57/57. `fix26f-selftest.sh`: fails=0.
