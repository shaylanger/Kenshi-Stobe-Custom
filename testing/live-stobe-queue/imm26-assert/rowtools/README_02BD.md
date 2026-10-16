# Row runners 02-bx and 02-dx (imm26-rr02, PI-22)

One call per row (same shape as `hxrun.sh` / `hxrun_v2.sh`; new files only, no existing script changed):

```
bash testing/live-stobe-queue/imm26-assert/rowtools/hxrun_02bd.sh <02-bx|02-dx> <lane> --save <saveA> --save2 <saveB> [--out DIR] [--no-reload] [--dry] [--allow-retry "why"] [--faction F] [--victim NPC]
```
Example: `hxrun_02bd.sh 02-bx 4080-i3 --save kah-imm26-<fresh1> --save2 kah-imm26-<fresh2> --out C:/KenshiTestRuns/imm26-4080-hx`
(`go-row.sh` itself only knows the `rowdefs.sh` rows; like every hardening row these two are run through their `hxrun*` wrapper, which calls `gr_main` = the go-row attempt guard + timing log.)
Output: up to 6 `EVIDENCE` lines and ONE `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4. Verdict = the v2 `assert_principle.py` (never loosened).

| Row | Save A (`--save`) | Save B (`--save2`) | Assert |
|---|---|---|---|
| 02-bx | T1-T3: Cind with the anti-slavery sentence appended to personality (core_npc_master + core_npc; md5 recorded, restored after; principle rows deleted first). Per dir: principle_rows.txt, state_after.txt (stobe_state of the victim Malzin + status), effects_full.txt; server_log.txt (IMM26_PRINCIPLE_VOICED lines since the phase start) in all T dirs | S1-S3: spawned `Slave Traders` NPC, no principle text, H-AFF +20 | `assert_principle.py 02-bx --target T1 T2 T3 --ctl S1 S2 S3 --principle slavery --voice-min 3` |
| 02-dx | T1-T3: Cind with the principle, H-AFF +60 platonic; haff.txt per dir | C1-C3: same NPC and text, H-AFF 0 | `assert_principle.py 02-dx --target T1 T2 T3 --ctl C1 C2 C3 --principle slavery` |

Requests are the verbatim lines of the TESTS rows (02-dx: the same three in both cases, the third offers 500 cats). Base save on 4080 lanes must be given (`--save`); use two different fresh saves.
Env knobs: `HX02C_TEXT HX02C_PRIN` (shared with 02-cx), `HX02B_VICTIM` (Malzin), `HX02B_FACTION` ("Slave Traders"), `HX02B_CTL_AFF` (20), `HX02D_HI` (60), `HX02D_LO` (0), `HX02B_VOICE_MIN` (3), `HX_ASSERT_DIR`.
Bundles: `<--out>/<ROW>/<label>` (or the evidence dir `<runs>/<lane dir>/rows/<ROW>`); a missing bundle dir is SETUP-FAIL naming it; the profile text is restored on every exit path (profile_md5_original/restored.txt).

Selftest (offline, fake lane + stub asserts + the real v2 assert over stored 5090 evidence): `bash rowtools/hx-selftest_02bd.sh` -> `SELFTEST 02BD ALL PASS 34/34`.
The lane server needs the chain-up regex fix (`lib/imm26_c1_principles.php:54`) for 02-bx T2 'Chain up this prisoner' (the stored 5090 evidence fails only there: `T2:touches_principle_line`).

## Unverified guesses (first live run must confirm; the selftest fakes them)
- The spawned control keeps a resolvable name: the runner tries the last full name, the `#serial/idx` id, then the spawn reply name (the server renames spawned bandits at the first chat).
- Spawning the template "Hungry Bandit" into faction `Slave Traders` gives a slaver-faction NPC (the 5090 operator used a Slave Traders guard).
- `stobe_state <victim>` JSON (first 1800 chars) holds no word `captive|shackle|imprison` (the 5090 T1/T3 evidence passed with Malzin).
- The principle row is derived by the server during T1 (the 5090 evidence: marker row + slavery row ~6 s apart); if the T1 prompt lacks `<principles>` the row needs a prep sample as in 02-cx.
