# imm26-fix15bxv5 (2026-10-16): 15-bx v4 P placement with a pinned fighter

Problem (op25, 5090-i3, `rows/15-bx`): `SETUP-FAIL P could not be placed within 15 u of the fight at P3 (17.4)`. The moving fighter F1 ran off between the `teleport P F1 dist d` and the distance read.
Fix (candidate, nothing live changed): `ub15_place_p` pins F1 with `stobe-auto order F1 HOLD_POSITION keep` (`ub4_pin`, reply in `<row>/pin.txt`) before EVERY placement try (d = 10 / 6 / 3). The <= 15 u guard and its SETUP-FAIL are unchanged. Only the IN phase uses place_p (OUT phase / X / S1 untouched).

Files: `unblockdefs_c_v4.sh.candidate` (only diff to `unblockdefs_c_v4.sh`: ub4_pin + the call), `unblock_c_v4_selftest.sh` (section 8, new checks v5-*; `UC_U=<file>` runs it against a candidate, default the live file).
Check before the swap: `UC_U=$PWD/unblockdefs_c_v4.sh.candidate bash testing/live-stobe-queue/imm26-assert/rowtools/unblock_c_v4_selftest.sh` -> `ALL PASS 60/60` (the live v4 file gives 57/60: the moving fighter ends 23 u away).
Swap (only when no queued/running list uses unblockdefs_c_v4.sh): `cd testing/live-stobe-queue/imm26-assert/rowtools && mv unblockdefs_c_v4.sh.candidate unblockdefs_c_v4.sh`, then rerun the selftest without UC_U.
Live caveat: whether the harness keeps F1 held while F2 attacks it is only provable in-game; if P still ends > 15 u, `pin.txt` + `distance.txt` show whether the order was accepted.
