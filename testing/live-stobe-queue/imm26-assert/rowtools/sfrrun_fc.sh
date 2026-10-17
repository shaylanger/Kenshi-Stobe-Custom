#!/usr/bin/env bash
# sfrrun_fc.sh (imm26-sfFixC): sfrrun.sh + tripdefs_sffc.sh sourced last (20-a: s2 retry, deterministic PROPOSE fallback). sfrrun.sh is untouched; sffc_selftest.sh asserts this file = sfrrun.sh + that one line.
# sfrrun.sh <ROW: 23-b 22-b 20-a> <lane> [options]   ONE call per row (imm26-sfR2): recipe v2 for the three rows fxB classed as test defects.
#   Optional reload of the lane's ready save -> preflight -> go-row (rd_23b / rd_22b / rd_20a from sfrdefs.sh) -> `EVIDENCE` lines -> exactly ONE
#   `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh. Verdicts: sfrcheck.py via sfrpy.sh (20-a: unblockcheck_c.py -> rowcheck.py unchanged + the
#   placement rule). rowdefs.sh / tripdefs.sh / unblockdefs_c.sh / unblock*check* are NOT edited; rd_* are redefined only inside this process.
#   Usage: KAH_PF_ISOLATION=0 bash rowtools/sfrrun.sh 23-b 4080-i4 --allow-retry "sfR recipe v2"
#   Options: --save <name> (4080-i4 default kah-imm26-4080-i4h)  --no-reload  --dry (runs the whole recipe against the OFFLINE fake lane, no game)
#            --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of the same row on the lane: go-row refuses to rerun it otherwise)
#            23-b : --limit-h <n> (2: FollowExpiryGameHours written to the lane StobeCustom.ini, restored after the row)  --no-ini (ini untouched, limit 24 h, ~25 h advanced)  --extra-h <n> (1)
#            22-b : --ticks <n> (2 attempts for the arrival claim before the silent tick)  --back <u> (400)  --speed <1-3> (1)  --tries <n> (30 walk cycles ~8 s each)  --dest <town>  --gate "x y z"
#            20-a : --maxdist <u> (70: Shay must be this close to the walking NPC before every turn)  --alt "<place>"  --dest <town>
#   --restore-ini <lane> : no row; restores the lane StobeCustom.ini from StobeCustom.ini.sfR.bak (after a killed 23-b run) and prints one line.
#   Evidence lines: 23-b limit_hours time0 time_mid time1 ini_set ini_restore; 22-b arrival sr_ticks sr_summary; 20-a place_dist. Selftest: rowtools/sfr_selftest.sh. Operator note: inbox\operators\sfR.txt.
SRR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SRR_HERE/../go-row.sh"
. "$SRR_HERE/reloaddefs_a.sh"
. "$SRR_HERE/reloaddefs_b.sh"
. "$SRR_HERE/unblockdefs_a.sh"
. "$SRR_HERE/tripdefs_sfk.sh"
. "$SRR_HERE/sfrdefs.sh"
. "$SRR_HERE/tripdefs_sffc.sh"   # sfFixC: s2 retry + fallback + rd19_trip guard
PY="$SRR_HERE/sfrpy.sh"
sr_usage() { echo "usage: sfrrun.sh <ROW: 23-b 22-b 20-a> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--limit-h N] [--no-ini] [--extra-h N] [--ticks N] [--back U] [--speed N] [--tries N] [--dest T] [--alt P] [--gate 'x y z'] [--maxdist U] | --restore-ini <lane>" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=(); RESTORE=""
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --gate) export TRIP_GATE="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;; --alt) export TRIP_ALT="$2"; shift 2;;
  --limit-h) export SR_23B_LIMIT_H="$2"; shift 2;; --no-ini) export SR_23B_NO_INI=1; shift;; --extra-h) export SR_23B_EXTRA_H="$2"; shift 2;;
  --ticks) export SR_22B_TICKS="$2"; shift 2;; --back) export SFK_23A_BACK="$2"; shift 2;; --speed) export SFK_23A_SPEED="$2"; shift 2;; --tries) export SFK_23A_TRIES="$2"; shift 2;;
  --maxdist) export SR_20A_MAXDIST="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --restore-ini) RESTORE="$2"; shift 2;;
  -h|--help) sr_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; sr_usage; exit 2; fi; shift;;
esac; done
if [ -n "$RESTORE" ]; then   # recovery: no row, no go-row bookkeeping
  lt_load "$RESTORE" >/dev/null || { echo "RESULT restore-ini SETUP-FAIL unknown lane '$RESTORE'"; exit 2; }
  EV="${TMPDIR:-/tmp}/sfr-restore.$$"; mkdir -p "$EV"; sr_ini_restore
  echo "RESULT restore-ini DONE lane=$RESTORE $(tail -1 "$EV/ini_restore.txt" | cut -c1-200)"; rm -rf "$EV"; exit 0
fi
[ -n "$ROW" ] && [ -n "$LANE" ] || { sr_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "$LANE" = 4080-i4 ] && : "${TRIP_SAVE:=kah-imm26-4080-i4h}" && export TRIP_SAVE
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
case "$norm" in 23-b|22-b|20-a) ;; *) echo "RESULT $ROW SETUP-FAIL not an sfR row (23-b 22-b 20-a)"; exit 2;; esac
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ]; then   # dry run = the full recipe against the offline fake lane (sfrfake.py, a passing scenario); no game, ssh or DB is touched
  case "$norm" in 23-b) SRR_SC=sfr23-pass;; 22-b) SRR_SC=sfr22-pass;; *) SRR_SC=sfr20-pass;; esac
  export FAKE_SCEN="${TMPDIR:-/tmp}/sfr-dry-scen.$$.json" FAKE_STATE="${TMPDIR:-/tmp}/sfr-dry-state.$$.json" KAH_ROW_FAKE_LOG="${KAH_ROW_FAKE_LOG:-$LT_OUT/$ROW.dry.log}"
  export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0; : > "$KAH_ROW_FAKE_LOG"; rm -f "$FAKE_STATE" "$FAKE_STATE".*
  "$(command -v python3 || command -v python)" "$SRR_HERE/sfrscen.py" "$SRR_SC" > "$FAKE_SCEN" || { echo "RESULT $ROW SETUP-FAIL dry-run scenario failed"; exit 2; }
  lt_fake() { "$(command -v python3 || command -v python)" "$SRR_HERE/sfrfake.py" "$@"; }
fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
case "$norm" in
  23-b) evf="limit_hours.txt time0.txt time_mid.txt time1.txt ini_set.txt ini_restore.txt";;
  22-b) evf="arrival.txt sr_ticks.txt sr_summary.txt";;
  *)    evf="place_dist.txt";;
esac
for f in $evf; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -3 "$LT_OUT/$ROW/$f" | cut -c1-240 | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
