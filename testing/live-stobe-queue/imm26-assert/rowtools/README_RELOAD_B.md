# Reload rows, set B (imm26-reloadrows-B): 14-e 13-f 13-g 10-e 19-e 19-f

Save/load RESUME rows for deals, the restitution scope and trips. One call per row, one `RESULT` line. Set A (23-e 27-a ...) is `reload-run.sh` / `reloaddefs_a.sh`; the two sets do not share files, `rowdefs.sh` / `tripdefs.sh` / `rowcheck*.py` / `go-row.sh` are not edited (verdict script swapped through `pywrap_b.sh`).

```
bash rowtools/reloadrun-b.sh <ROW> <lane> [--save S] [--no-reload] [--dry] [--allow-retry "why"]
     [--backdate s] [--n k] [--mode target|cap] [--cap n] [--dest T] [--wait s]
```
Does: reload the lane's ready save (`tr_reload`) -> preflight -> `go-row` (attempt guard, timing log) -> `rd_<row>` of `reloaddefs_b.sh` -> verdict by `reloadcheck_b.py` -> up to 6 `EVIDENCE` lines + ONE `RESULT` line (exit 0 PASS, 1 FAIL, 2 SETUP-FAIL, 3 GATED, 4 needs fixer). Offline self-test (no game, ~7 min under WSL): `bash rowtools/reloadselftest_b.sh` -> `SELFTEST RELOAD-B ALL PASS n/n`.

Lanes: 5090 sessions are paused by Shay (2026-10-15): run on 4080 lanes only (`4080-i3`, `4080-i4`; `--save <ready save>` is needed there, only 5090-i3/i4 have a default).

| Row | Command | What it proves | PASS evidence (in `<runs>\<lane-dir>\rows\<ROW>\`) |
|---|---|---|---|
| 14-e | `reloadrun-b.sh 14-e <lane> [--backdate 540]` | counter-offer open, reload, accept: the offer is not expired by the load (wpR2 pause) and the deal performs | `deal_s1/backdated/post/end.txt`: same contract id, PROPOSED/COUNTERED after load, ACCEPTED/AWAITING_PERFORMANCE with `GIVE_ITEM:VERIFIED`, `resume_shift_total` in (0,1200], `resume_shifts` non-empty, Bread +1 (`inv_*.txt`), 2 NEG_TEST_INJECT steps fired. SETUP-FAIL if the accept came <= (600 - age) s after the backdate (the row would not prove the pause) |
| 13-g | `reloadrun-b.sh 13-g <lane>` | pay-later deal accepted, reload, one chat turn, pay -> COMPLETE | `deal_pre/post/talk/end.txt`, `price.txt`, `effects_deal.txt`: alive after load, new `clock_post.txt` load token, shift > 0, COMPLETE, both legs VERIFIED, one `kept_promise` 1..3 on `deal:<id>`, no `broken_promise` |
| 13-f | `reloadrun-b.sh 13-f <lane>` | same deal, NOT paid, deadline forced past after the reload -> BREACHED_PLAYER (the obligation survived the load) | `BREACHED_PLAYER`, one `broken_promise` -15..-5, no `kept_promise`. (My reading of the audit's 13-f: the ticket text said "pay-later deal"; the care-window variant is not built) |
| 10-e | `reloadrun-b.sh 10-e <lane>` (needs `SOCIAL_RELATIONSHIP_MODE` enabled on the lane, else SETUP-FAIL) | restitution scope across a REAL load: `repairprobe.php` (read-only, in-memory agreements frozen at the real pre-load scope) | `probe_pre.json`, `probe_eval.json`: later load of the same campaign keeps the term alive; other save / older epoch -> IMPOSSIBLE `exact_restitution_scope_changed`; unprovable after reload -> IMPOSSIBLE (not UNMET); same-load deadline control stays UNMET. The banked-VERIFIED-proof leg is NOT covered: row 10-f, SETUP-FAIL `needs: native` (durable item id, plan in `agents/out/imm26-wpR2/latest.md`) |
| 19-e | `reloadrun-b.sh 19-e <lane> [--dest Squin] [--wait 30]` | trip resume is LAZY (Shay 2026-10-15): no resume on load, the NEXT chat line resumes the same agreement | `quiet.txt` (`owned_travel_accepted=0` in the silent window = the CORRECT state), `agr_ctl.txt` (no `requested`/`running` row after the load), then `s4` ("Where were we going?") has exactly one `OWNED_TRAVEL accepted=1`, `agr_all.txt` chain `interrupted_by_load -> requested (new request_id, generation up) -> running`, same agreement id, native order to the stored destination (`post_s4.txt`) |
| 19-f | `reloadrun-b.sh 19-f <lane> [--n 4] [--mode target or cap] [--cap n]` | repeated reloads of one trip. `target` (default): all N reloads resume, `resume_count == i`. `cap`: reload `cap+1` ends honestly FAILED `resume_failure=resume_count`, no OWNED_TRAVEL, no re-proposal | `agr_r<i>.txt`, `sr<i>/reply.txt`, `post_r<i>.txt`. **target is expected to FAIL on a build with the resume cap of 3** (reload 4); `--mode cap` verifies the honest terminal. `--cap n` sets `general_settings STOBE_TRIP_RESUME_MAX_COUNT` for the run and removes it after |

Knobs (env, see the head of `reloaddefs_b.sh`): `ROW_NPC` (Cind [Hungry Bandit]), `ROW_BACKDATE_S` (540), `ROW_19E_QUIET_S` (30), `ROW_19E_SPEED` (2), `ROW_19F_N` (4), `ROW_19F_MODE`, `ROW_19F_CAP`, `ROW_13_TALK` (1: one chat turn after the load, also the first negotiation tick of the new load).

Deals are made deterministic with `NEG_TEST_INJECT` (replaces the model reply before the logic under test, as row 13-a); it is removed again at the end of every row.

## Not covered live
- The 7200-gamets age cap of a resumed trip is NOT a live row: it needs a non-resuming first post-load turn and a game-time jump. It is offline-only (server regression tests, `imm26_wpR2_resume_regression.php` and the trip-resume tests), nothing in this set exercises it in game.
- FOLLOW / bodyguard recipes: set A (23-e, 27-a).
- 10-f (exact return banked as VERIFIED proof after a reload): needs native durable item ids.

## Files
`reloaddefs_b.sh` (rd_14e rd_13f rd_13g rd_10e rd_19e rd_19f + rb_* helpers) · `reloadcheck_b.py` (verdicts; `--has <ROW>`) · `reloadrun-b.sh` · `pywrap_b.sh` · `repairprobe.php` · `reloadfake_b.py` / `reloadscen_b.py` / `reloadselftest_b.sh` (offline).

## Engine repricing (13-g / 13-f / 14-e, imm26-rowfix-reload 2026-10-15)
A plain Cats-for-item buy is priced by the engine at her relationship price (e.g. 353 for 1 Bread at aff 75), and `negotiation_phase1.php` turns an injected ACCEPT at the wrong price (the 20 in `RB_TERMS`) into a COUNTER. So after s1 the rows read the price (`rb_price`: `term_state` first, else the `terms` column while the contract is still COUNTERED/PROPOSED) and re-inject the ACCEPT at that price (`rb_reprice_inject`, evidence `reprice.txt`); `price.txt` is then non-empty. Selftest scenario `13g-counter353` (s1 COUNTERED, price 353) asserts the second `NEG_TEST_INJECT` carries `"amount":353`. If no price is readable the old injection is kept and the later price check reports it.
