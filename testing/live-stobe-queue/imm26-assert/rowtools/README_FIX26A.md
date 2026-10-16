# README_FIX26A (imm26-fix26a): SETUP-FAIL ticket 26-a, op10 (lane 5090-i5): participation_qualified=0

Offline only. NEW file `hunt26a-run.sh.candidate` (v2 of the live `hunt26a-run.sh`); the live script is not edited. `hunt26afake.py` gained one branch (the v2 follow call); all assertions/verdict logic unchanged.

## Swap (lane operator; run when no list/batch is using hunt26a-run.sh)
```
cd C:/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools && cp hunt26a-run.sh hunt26a-run.sh.v1 && mv -f hunt26a-run.sh.candidate hunt26a-run.sh
```
Then rerun (needs `--allow-retry` / row-attempts reset): `bash testing/live-stobe-queue/imm26-assert/rowtools/hunt26a-run.sh [outdir]`.

## Cause (op10 evidence: rows/26a-run/follow.log, stobe.log 15:43-15:46)
v1 teleported Shay onto Malzin every 4 s at game speed 0.5. Malzin runs while Shay is parked: the pre-jump separation reached 34.9 u (follow.log), 3D with height more. NC21 `ParticipationEvidence`
Break()s on separation > 35 u and only the LAST unbroken stretch counts (>= 30 game-s): terminal `NATIVE_TRAVEL participation_qualified=0 brk_sep:98 best_span:36`. The record then ended failed/timeout
(`activity_no_verified_progress`). Not a product bug: the recipe did not keep Shay close.

## Fix 1: continuous follow (v2)
One harness call per poll = `RW_FOLLOW_N` (5) x [`where` (logs the separation just before the jump) ; `teleport Shay <Malzin>` ; `sleep RW_FOLLOW_STEP` (1)] = about 1.5 s real per jump (the 13-c recipe,
`tripdefs.sh rd_13c`, which is known to qualify), at game speed `RW_HUNT_SPEED` (default now **1**, restored to 0.5 on every exit). Separation stays ~10-20 u and each per-sample displacement is far below `20*dt+5`
(no brk_jump). No harness order is put on Malzin (the trip stays native). The record poll / terminal states / `RW_HUNT_WAIT` 300 s / `RW_ACCEPT_WAIT` 40 s are unchanged.
Evidence: `follow.log` has `sep_before=[d1,...,d5]` per poll and ` SEP>35 xK` when any jump started above 35 u (evidence only; the verdict still comes from the real record); `native.txt` = the stobe.log
`participation|NATIVE_TRAVEL|ACTIVITY_END_DIAG` lines since the Yes (participation_qualified, brk_sep/jump/gap).

## Fix 2: Katana grep
The game inventory names the item "Chisa Katana"; v1 grepped `"name":"Katana` (never matched), so every run gave another Katana and the delta filter did not drop it. Now both greps use
`"name":"[^"]*katana` (case-insensitive). Give-only-when-absent and equip are otherwise unchanged.

## Nothing weakened
PASS still needs: record proposed->accepted->completed, participationOutcome set (not not_completed), outbox acknowledged, Malzin inventory +>= 1 item (Katana excluded). failed/timeout, still accepted after 300 s,
no inventory, no participation = FAIL; Yes not landing / bad scene / fight = SETUP-FAIL (selftest covers each).

## Selftest (offline, ~1 min)
`bash testing/live-stobe-queue/imm26-assert/rowtools/hunt26a-follow-selftest.sh` -> `SELFTEST FIX26A ALL PASS 21/21` (stages the candidate in a temp copy). If the first live run still shows `SEP>35`, lower
`RW_FOLLOW_STEP` (0.5) or raise `RW_FOLLOW_N`; if `brk_gap`, shorten the poll gap (fewer SQL calls per cycle).
