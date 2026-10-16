# Hardening rows: one call per row (imm26-rowtools43/44)

Rows 17-bx 18-cx 16-bx 15-bx 13-ax 02-ax. Offline-tested only (`bash rowtools/hx-selftest.sh` -> `SELFTEST HX ALL PASS 49/49`); no lane or Kenshi was touched. First live run: `--dry`, then one row.

```
bash testing/live-stobe-queue/imm26-assert/rowtools/hxrun.sh <ROW> <lane> [--save S] [--save2 S] [--out DIR] [--no-reload] [--dry] [--allow-retry "why"] [--native]
     [--item I] [--ctl NPC] [--faction F] [--spot "x y z"] [--out-dist U] [--runs "P1 N1"] [--saves "a b c d e"]
```
Flow: reload the base save (tr_reload) -> preflight -> go-row attempt guard -> `rd_<row>` (hxdefs.sh) -> `hxcheck.py` runs the assert -> up to 6 `EVIDENCE` lines + ONE `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ...` line. Exit 0/1/2/3 (4 = attempt guard needs a fixer). Use `KAH_PF_ISOLATION=0` as the operators did.

| Row | Bundles (flat dirs under `--out/<ROW>` or the evidence dir) | Assert run by hxcheck.py | Extra |
|---|---|---|---|
| 17-bx | F1-F3 (item in the NPC pack), T1-T3 (item moved to Malzin); inv.txt, seed row = visible accusation | `assert_claims.py 17-bx --false F* --true T* --item <item>` | `--item` (Sabreclaw), two loads |
| 18-cx | C1-C3 strict 1v1 vs a spawned bandit, K1-K3 after reload; state.txt, target.txt, roster.txt (<= 3 within 300 u) | `assert_claims.py 18-cx --combat C* --calm K* --target <t>` | `--faction` (Holy Nation Outlaws) |
| 16-bx | R1-R3 reserved Cind at aff +60, O1-O3 outgoing control (speechstyle+occupation set, lock_profile) | `assert_stance.py 16-bx --target R* --ctl O* --trait reserved` | `--ctl` (Malzin), two loads |
| 15-bx | X1-X3 (>= 250 u away), P1-P3 (<= 15 u), S1 asleep within 100 u; distance.txt, fighters.txt, starter.txt | `assert_witness.py 15-bx --out X* --inrange P* --asleep S1 --fighters F --starter S` | `--out-dist` (300), `--faction` |
| 13-ax | P1 P2 (paid), N1 N2 (breached), C1 (talk only), one saved game each; deal.txt cats.txt haff_*.txt | `assert_witness.py 13-ax --pos P1 P2 --neg N1 N2 --ctl C1` | one call = 5 runs (~25 min); `--runs "N1 N2"` reruns a subset and keeps the other dirs; fewer than 5 run dirs = `GATED PARTIAL` |
| 02-ax | T1-T3 (Cind, profile.txt), F1-F3 (Thoke blanked, profile.txt after the chat) | `assert_principle.py 02-ax --target T* --ctl F*` | `--ctl` (Thoke); backup table `hx_bak_core_npc_master` |

Base saves: lane 5090-i3 `kah-imm26-5090-hxA`, 5090-i4 `kah-imm26-i4-hx0` (second load = `--save2`, default the same); 13-ax saves default on 5090-i4 only (`kah-imm26-i4-13ax1..5`, order P1 P2 N1 N2 C1). 4080 lanes need `--save` / `--saves`.

Env knobs (also read from the environment): `ROW_NPC HX_SAVE HX_SAVE2 HX_SPOT HX_FAR HX_OUT HX_SETTLE(12) HX_NATIVE HX17_ITEM HX18_FACTION HX16_CTL HX15_OUT HX15_FACTION HX15_WAIT HX13_RUNS HX13_SAVES HX02_CTL HX_ASSERT_DIR` (the last points hxcheck.py at stub asserts; selftest only). Asserts are never loosened (no `--lenient`); a missing bundle dir is SETUP-FAIL naming it.

## Unverified guesses (first live run must confirm; the selftest fakes them)
- `stobe-auto give Cind Sabreclaw` and `transfer Cind Malzin Sabreclaw` exist and move the item (else 17-bx SETUP-FAIL "could not make the item").
- `stobe-auto sleep <npc>` works on a spawned Drifter (15-bx S1).
- Spawn reply parses as `^spawned n/m <tmpl>: <name> #s/i` (else SETUP-FAIL "spawn failed or unparseable").
- `stobe_state` JSON has an `"in_combat"` key (else 18-cx falls back to the prompt "Action Flags ... in combat").
- Eventlog `combat` row data is `<name>: Initiated attack ...` (15-bx starter).
- `teleport <npc> <npc2>` lands within 15 u (15-bx P phase distance).
- 16-bx SQL columns: `core_npc_master` / `core_npc` `speechstyle occupation`, `lock_profile` (core_npc.lock_profile may not exist: the statement then errors in profile_set.txt, check it).
- 02-ax blanking Thoke's profile in `core_npc_master`/`core_npc` and the server regenerating it at the first chat.
- 15-bx: fighters.txt/starter.txt come from the IN phase (the X-phase starter is saved as starter_x.txt, not asserted). `hxd_trim` deletes eventlog rows after the phase mark between phases.

## Family B rows (imm26-hxB)
05-cx: `hxrun.sh 05-cx 5090-i3 [--dry]` (hxdefs_b.sh, hxcheck_b.py; E empty roster + H one sleeper on load 1, N 3+ visible on load 2; verdict assert_principle.py 05-cx). Selftest: `bash rowtools/hx-selftest_b.sh` -> `SELFTEST HXB ALL PASS 21/21`. 03-cx has no script: the TESTS row already holds a 4080 PASS.

## v3 fixes (imm26-fix15bx05cx, from imm26-inv15bx; NEW files, nothing existing edited)
- 05-cx v3: `bash rowtools/hxrun_cx3.sh 05-cx <lane> [same options as hxrun_cx2.sh] --allow-retry "cx3 keep regex"` (hxdefs_cx3.sh). Fix: the keep regex now matches the first `chars` entry (`N within R: Cind`), so Cind is no longer exiled next to the pinned Malzin; new SETUP-FAIL "NPC under test not within 60 u of Shay" before every E sample; infonpc rows are deleted after Malzin is pinned. Selftest: `bash rowtools/hx-selftest_cx3.sh`.
- 15-bx v3: `bash rowtools/unblockdefs_c_v3.sh 15-bx <lane> [same options as v2] --allow-retry "v3 scene: ko"`. S1 is KO'd (`ko <s1> 900`, gate on "unconscious":true, `ko <s1> 120` re-issued before the sample) instead of `sleep`; active social_rumor claims are retired in ub15_scene; ub15_pair waits <= 20 s for the server rename. Env HX15_KO_S (900). Selftest: `bash rowtools/unblock_c_v3_selftest.sh`. (v2 holds 15-bx only, there is no 16-bx entry in it.)

## Row runners 02-bx / 02-dx
See `README_02BD.md`: `hxrun_02bd.sh <02-bx|02-dx> <lane> --save A --save2 B` (imm26-rr02).
