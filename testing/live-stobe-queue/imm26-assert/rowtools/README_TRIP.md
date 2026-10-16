# Trip-family rows: one call per row (imm26-triprow)

Shipped offline-tested only (`bash rowtools/trip-selftest.sh` -> `SELFTEST TRIP ALL PASS 46/46`); no lane or Kenshi was touched. First live run: use `--dry` first, then one row.

## Use
```
bash testing/live-stobe-queue/imm26-assert/rowtools/trip-run.sh <ROW> <lane> [--dest Squin] [--alt "the Stumble Inn"] [--save <name>]
        [--gate "x y z"] [--accept "text"] [--trap "x y z"] [--no-reload] [--dry] [--allow-retry "<reason>"]
bash testing/live-stobe-queue/imm26-assert/rowtools/ko13b.sh <lane>            # = trip-run.sh 13-b <lane>
```
`trip-run.sh` = reload the lane's ready save (i3 `kah-imm26-5090-ready`, i4 `kah-imm26-i4-trip2`; other lanes need `--save`), regroup (Shay HOLD, speed 0.5, Cind to Shay, Cind `NULL_TASK`, never IDLE) -> preflight -> `go-row.sh --no-preflight` (attempt guard + timing log apply) -> prints up to 6 `AGREEMENTS <ROW> rowid|status|phase|reason|owned_work_released|agreement_id|destination` lines, then exactly one `RESULT <ROW> ...` line (exit 0 PASS, 1 FAIL, 2 SETUP-FAIL, 3 GATED, 4 ROW-NEEDS-FIXER). The reload happens before preflight on purpose: a trip row leaves Cind > 80 units away, so a plain go-row preflight on the next trip row would fail fast. Rows also run from `go-row.sh`/`go-batch.sh` directly (no reload; the scene must already be at the Hub with Cind < 80 u).

## What every trip row does first (`tr_prep`)
Resolve `Cind [Hungry Bandit]` (plain `Cind` can hit an HNO Cind), delete leftover eventlog rows (`travel_agreement`, `region_plan`, `situated_event`, `situated_remark_claim`), H-AFF Cind->Shay 60 platonic, quiet scene (port of `imm26-5090-i3/clear-hub.sh`; `TRIP_QUIET=0` skips).

## Rows (checks live in `rowcheck_trip.py`; 19-a / 23-b / 24-b keep their existing `rowcheck.py` checks and gain `tr_prep`)
| Row | Steps | Mechanical checks (R~ wording is listed, never decides) |
|---|---|---|
| 23-a | s1 `Take me to <dest>.` (s1b `Would you lead me to <dest>?` if no PROPOSED row), s2 accept (`I'm fine. Yes, let's go.`; s2b `Lead the way.` if no `OWNED_TRAVEL ... accepted=1` line), teleport Cind to the gate + Shay follows (speed 3, 60 s), s3 `We're here. Thanks for guiding me.` | row COMPLETED, owned_work_released true, first_order none + current_goal NULL_TASK, NPC not in Shay's faction, exactly one NPC acknowledgement |
| 20-a | trip as above, s3 `Actually, go to <alt> instead.`, s4 `Yes, I mean it. I am sure, change it to <alt>.` | row unchanged after s3, after s4 old row ENDED or a row for <alt> exists |
| 20-b | trip, then forced failure: `TRIP_TRAP` teleport (real path failure) else harness `order Cind IDLE` (replaces the native order), 25 s at speed 3, s3 `Why did we stop?` | row FAILED with a reason, reply names the destination; **GATED (not PASS) unless the reason is `native_path_or_actor_failure`** |
| 23-c | trip with Cind, s3 `Leave.` (Cind), s4 `Leave.` (Malzin), s5 `Let's call off the trip. I'll go on my own.` | Cind unchanged + trip still ACCEPTED; Malzin's faction changes; trip ENDED; Malzin not touched by the END (END to the already-gone squad member is not sent; the job-survives control is evidenced by 23-d) |
| 23-d | Shay+Cind at Copper Mine V, `clearjobs`, trip, `job Cind "Copper Mine V" task OPERATE_MACHINERY radius 2500`, Shay onto Cind, s3 `Actually, forget the trip. I'll go on my own.` | row ENDED, `owned_order_removed*` receipt reason in the turn, first_order none, permajobs non-empty |
| 24-a | s1 `Where would you take me to find some peace?`, s2 control `What is Vain like?` | prompt has the named-place choices, NO travel_agreement row on s1, no region_plan on s2 |
| 13-b (`ko13b.sh`) | squad together (<= 25 u, 6 s), `protect <Malzin> off`, partner IDLE + `ko 300`, 8 s, leaver (Cind) teleported 108 u away + HOLD, poll <= 90 s for `N2_ABANDON`, `wake`; control phase with a healthy partner (no KO) waits 60 s | armed: `N2_ABANDON ... partner=Malzin state=knocked_out` and a new `abandoned_in_danger` social_effect row naming Malzin with a negative value; control: no `N2_ABANDON`, no new effect row; no N2 lines at all = SETUP-FAIL (needs NC6 3ADDE488) |

Env knobs: `TRIP_DEST TRIP_ALT TRIP_SAVE TRIP_GATE TRIP_ACCEPT TRIP_FOLLOW(60) TRIP_QUIET TRIP_TRAP TRIP_FORCE_WAIT(25) TRIP_PARTNER(Malzin) TRIP_LEAVER TRIP_LEAVE_DIST(108) TRIP_N2_WAIT(90) TRIP_CTRL_WAIT(60) TRIP_SE_TRIES(15)`. The Squin gate defaults to `-62380 330 16250` (i3 COMPLETED run); other destinations use the newest agreement's `destination_point` unless `--gate` is given.

## Unverified guesses to watch on the first live run
`I'm fine. Yes, let's go.` as the accept wording (op32 wrote "I'm fine ... Yes, let's go."; override with `--accept`), the `ACTION_EXEC: LEAVE` token (23-c also decides on the faction change), the N2 leaver being the teleported Cind, the `job` argument order, `se::text` containing the partner name and a `,-19` delta. A wrong guess shows as a FAIL/SETUP-FAIL with the file named in the detail; fix it in `tripdefs.sh`/`rowcheck_trip.py`, never loosen an assertion.

## Hooks into the shared tools (already added; go-row.sh / go-batch.sh untouched)
`rowdefs.sh` last line sources `tripdefs.sh` (defines `rd_13b rd_20a rd_20b rd_23a rd_23c rd_23d rd_24a`, wraps `rd_19a rd_23b rd_24b`); `rowcheck.py` has a 4-line `try: import rowcheck_trip` hook before `norm()`. Optional follow-up for the coordinator: add `trip-selftest` to `selftest.sh` (already appended as one check) and, if you want `go-batch.sh` rows to reload automatically, one line in `gr_run` before `pf_run`: `declare -F "rdpre_${norm//-/}" >/dev/null && "rdpre_${norm//-/}"` (no rdpre_ function exists yet; trip-run.sh does the reload instead).
