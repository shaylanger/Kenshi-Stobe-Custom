# imm26-fix15bx05cx / fix15bx05cx2 (2026-10-16): 05-cx keep regex + 15-bx v3 scene

All files are NEW (no existing script edited, nothing to swap in place). Root causes: `C:/KenshiTestRuns/agents/out/imm26-inv15bx/out-20261016-134157.md`.

## 05-cx (use `hxrun_cx3.sh`, not `hxrun_cx2.sh`)
`bash rowtools/hxrun_cx3.sh 05-cx <lane> [--save S] [--allow-retry "why"] ...` (same options as hxrun_cx2.sh). Files: `hxdefs_cx3.sh` (replaces `hxdefs_cx2.sh` for this runner), `hxrun_cx3.sh` (replaces `hxrun_cx2.sh`), `hxscen_cx3.py`, `hx-selftest_cx3.sh`.
- Fix: `hx05_keep` = `Shay #|(^ *|: )<Npc> ` (the FIRST entry of a `chars` reply is "N within R: Cind ..."; the old `^ *Cind ` missed it, so Cind was exiled to HX_FAR next to the pinned Malzin; the earlier i3 05-cx E PASS was false).
- New guards: Cind within 60 u of Shay asserted before every E sample (SETUP-FAIL "not within 60 u of Shay"); infonpc rows deleted once Malzin is pinned far (stale row listed her next to Cind).
- Earlier 05-cx E PASS (i3) and SETUP-FAIL (i5) results are invalid: re-run on the lane with `--allow-retry`.

## 15-bx (use `unblockdefs_c_v3.sh`, not `unblockdefs_c_v2.sh`)
`bash rowtools/unblockdefs_c_v3.sh 15-bx <lane> [--allow-retry "v3 scene"] [--away far|near] ...`. Files: `unblockdefs_c_v3.sh`, `unblock_c_v3_selftest.sh` (v2 files untouched; verdict checker `unblockcheck_c_v2.py` unchanged).
- S1 is put down with `ko <s1> 900` (not `sleep`: a spawned NPC drops SLEEP_ON_FLOOR at once), gate SETUP-FAILs in seconds unless stobe_state shows `"unconscious":true`; `ko <s1> 120` re-issued right before the S1 sample.
- ub15_scene retires all active `social_rumor` rows (stale "you saw it yourself" claims); ub15_pair waits <= 20 s for the server rename of the spawns and takes the starter from a renamed fighter.

## Selftests (run in WSL; Git Bash works but takes ~7 min and 2 hx cx3 checks fail there on Windows-path artifacts: backslash bundle names in assert argv, roster stub)
`MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/hx-selftest_cx3.sh` -> HXCX3 ALL PASS 29/29;
`.../unblock_c_v3_selftest.sh` -> UNBLOCK-C-V3 ALL PASS 47/47.

## Not part of this ticket (fix20a19e)
`hxdefs.sh.candidate` + `hxd_winpath_selftest.sh` (bundle_dir.txt as C:/): hxrun_cx3.sh / unblockdefs_c_v3.sh source `hxdefs.sh`; swapping the candidate in later is compatible.
