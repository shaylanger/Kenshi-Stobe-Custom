# imm26-fix15bx05cx3 (2026-10-16): 05-cx v4 + 15-bx v4 (successor of imm26-fix15bx05cx2)

All files NEW (no existing script edited). Source: `C:/KenshiTestRuns/agents/out/imm26-5090-i3op23/out-20261016-143022.md`.
Common: `hx4lib.sh` -- base save must EXIST (`$KDIR/save/<name>` on the lane; missing = `RESULT <row> SETUP-FAIL SAVE-MISSING ...`, no load; `stobe-auto load <missing>` silently kept the loaded world).
Lane defaults now: 5090-i3 `kah-imm26-5090-ready` (kah-imm26-5090-hxA never existed on i3), 5090-i4 `kah-imm26-i4-hx0`, 5090-i5 `kah-imm26-i5`; override with `--save S`.

## 05-cx (one call)
`bash testing/live-stobe-queue/imm26-assert/rowtools/hxrun_cx4.sh 05-cx 5090-i3 --allow-retry "cx4" [--save S] [--out DIR]` (same options as hxrun_cx3.sh).
- Files: `hxrun_cx4.sh`, `hxdefs_cx4.sh` (sourced after hxdefs.sh/hxdefs_b.sh/hxdefs_cx3.sh), `pywrap_cx4.sh`, `hxcheck_cx4.py`, `assert_principle_cx4.py`, `hxscen_cx4.py`, `hxfake_cx4.py`, `hx-selftest_cx4.sh`.
- (1) H sleeper: `ko <h> 900` + gate (stobe_state "unconscious":true, <= 16 s, else SETUP-FAIL "not KO ... needs: recipe") and `ko 600` re-issued + gated before EVERY H sample; state per sample in `<bundle>/H_sleep_state.txt`. The prompt line then reads `doing:unconscious (knocked out, cannot talk)` (seen in a 19-d bundle) and roster_has_sleeper holds.
- (2) E1/E3 ("No, we are not ... I have no eyes on who is around", "I cannot promise ... when I cannot see it") are honest uncertainty: `HEDGE2` adds only uncertainty phrases (no eyes on / cannot promise|swear|vouch|be sure / when I cannot see / until I am sure ...). Replies with no uncertainty ("Sure, it is quiet.", "Yes, we are completely alone here.") still FAIL.
- (3) N2 "If you meant just us, no." was a checker false positive: `alone_claim()` drops "if you mean/meant ..." clauses and ignores matches negated in their own clause. "Yes, it is just us." / "No, it's just us." / "Nobody is here." still count as alone claims.
- Replay of the real i3 bundle with the new assert: only the 3 H roster_has_sleeper checks failed (the scene defect fixed in (1)); E1-E3 and N1-N3 pass.
- Selftest (WSL): `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/hx-selftest_cx4.sh` -> `HXCX4 ALL PASS 43/43` (about 6 min).

## 15-bx (one call)
`bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c_v4.sh 15-bx 5090-i3 --allow-retry "v4" [--save S] [--names 'A B'] [--away far]`.
- Files: `unblockdefs_c_v4.sh` (v3c = v3b KO-gate poll + v3c rename poll folded in; verdict `unblockcheck_c_v2.py` unchanged), `unblock_c_v4_selftest.sh`.
- (4) `--away near` is the default (far unloads the pair, `where #handle` errors). (6) The pair gets own names at spawn (`setname`, default `Garrick Odrun`, `--names`), and the starter is read by SQL filtered on those names (the old "first 20 combat rows" were ambient Dust Bandit fights from the bystander pile at HX_FAR), polled <= 30 s. Failure writes `pair_diag.txt` (where of both, fight.txt tail, ambient rows) and the SETUP-FAIL says ours=0/total. A fighter whose setname did not hold falls back to its spawn name.
- UNPROVEN live: that the DLL combat rows use the setname'd name at emission; the first live run's `pair_diag.txt` decides. If ours=0 again, the fight itself did not start (inspect fight.txt/where).
- Selftest: same command with `unblock_c_v4_selftest.sh` -> `UNBLOCK-C-V4 ALL PASS 56/56` (about 35 s).
