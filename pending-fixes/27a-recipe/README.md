# 27a-recipe (imm26-fix27a): row 27-a recipe/assertion fix

Diagnosis: `C:\KenshiTestRuns\agents\out\imm26-inv-27a\latest.md` ("Smallest fix"). Test tooling only: no game, lane, DLL or server change.

## What changes (`patch27a.py`, anchor-asserted, idempotent; `patch27a_tests.py` for the TESTS.md wording)
- `reloadcheck_a.py`: new `BG_NEAR` (default 100, env `RW_BG_NEAR`). `c_27a`: pre `a1 <= BG_NEAR`; post `closes = b1 <= BG_NEAR and b1 < b0`; new evidence file `chase_ctrl.txt` (negative control): control end >= 0.8 x start (and start >= 60) else `SETUP-FAIL "NPC approaches Shay without a contract ... (needs: recipe)"`.
- `reloaddefs_a.sh` and `unblockdefs_b.sh` `rd_27a`: `local RW_AWAY=${RW_AWAY_BG:-200}` (rw_chase sees it), a control chase `rw_chase ctrl` + `rd19_place near` BEFORE the hire (`bg_set`), then the usual hire / pre chase / save+load / post chase.
- Fakes + selftests: `reloadfake.py` (scenario key `chase_d` = [start,end] per chase: control, pre, post), `reloadscen.py` (27a scenarios use 50-67 u stand-off ends; new `27a-ctrl-approaches`, `27a-pre-wander`, `27a-post-standoff-edge`), `unblockscen_b.py`, `reload-selftest.sh`, `unblock_b_selftest.sh` (`unblockfake_b.py` needs no change: it forwards to reloadfake.py).
- `NPC_IMMERSION_26_TESTS.md` row IMM-27-a wording (verdict stays FAIL until the live rerun).

## Apply (when no job sources the rowtools scripts: the 4080-i4 operator must be idle)
    bash C:/KenshiModding/pending-fixes/27a-recipe/apply.sh          # live rowtools dir + TESTS.md, idempotent
    # or:  bash apply.sh <rowtools dir> <TESTS.md>

Then verify (WSL, ~5 min each, can run in parallel):
    wsl.exe -d DwemerAI4Skyrim3 bash /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/reload-selftest.sh
    wsl.exe -d DwemerAI4Skyrim3 bash /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/unblock_b_selftest.sh

## Live rerun (from the diagnosis report; 4080-i4 only, harness eeed8c93 already installed, row save kah-imm26-4080-i4h, no build/install, ~4 min)
    unblockrun_b.sh 27-a 4080-i4 --save kah-imm26-4080-i4h --allow-retry "threshold 35 -> 100, RW_AWAY 200, ctrl"
(from `testing/live-stobe-queue/imm26-assert/rowtools`). Expect: control ~200 -> ~200, pre ~200 -> <=100, post ~200 -> <=100, hours_left < 24. Env knobs: `RW_AWAY_BG` (200), `RW_BG_NEAR` (100), `RW_CHASE_S` (30).

`work/` (a patched copy of imm26-assert used for the selftests) is git-ignored and reproducible: copy the live dir, then `python3 -I patch27a.py work/imm26-assert/rowtools`.
