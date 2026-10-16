#!/usr/bin/env bash
# unblockrun_sftrav_fn.sh = unblockrun_sftrav.sh + sfs_fullname.sh (full-name bored tick, imm26 op25) [orig: (imm26-sfTrav: unblockrun_sfs.sh + tripdefs_sftrav.sh = deterministic travel PROPOSE before s1; env SFT_INJECT=0 disables; needs inject-travel-deploy.sh on the lane)
# unblockrun_sftrav.sh 08-d <lane> [options]   ONE call: 08-d v2 (imm26-sfS; the targeted bored tick sends attn={"in_combat":false}; the no-ask check looks only after tick 1).
#   Same shape as unblockrun_a.sh: optional reload of the lane's ready save -> preflight -> go-row (rd_08d from unblockdefs_sfs.sh + verdict unblockcheck_sfs.py via unblockpy_sfs.sh)
#   -> `EVIDENCE` lines -> exactly ONE `RESULT 08-d PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh.  unblockrun_a.sh / unblockdefs_a.sh stay as they were (08-e / 11-b).
#   Options: --save <name> (default for 4080-i4: kah-imm26-4080-i4h)  --no-reload  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of 08-d on the lane)
#            --neg (negative control: no walk, topic must stay open)  --back <u> --speed <1-3> (real-walk staging, defaults 350 / 2)  --attn '<json>' (default {"in_combat":false}; '' = none, the v1 request)
#   Evidence: bored_attn.txt bored_after1_mark.txt bored_log.txt bored_log_after1.txt (plus the unblockdefs_a.sh files).  Selftest: rowtools/unblock_sfs_selftest.sh.
US2_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$US2_HERE/../go-row.sh"
. "$US2_HERE/reloaddefs_a.sh"
. "$US2_HERE/unblockdefs_a.sh"
. "$US2_HERE/unblockdefs_sfs.sh"     # redefines i4_bored and rd_08d
. "$US2_HERE/tripdefs_sftrav.sh"       # imm26-sfTrav: redefines tr_trip_setup (arms inject-travel.sh before s1)
. "$US2_HERE/sfs_fullname.sh"          # op25: full-name bored tick (see header)
PY="$US2_HERE/unblockpy_sfs.sh"
us2_usage() { echo "usage: unblockrun_sftrav.sh 08-d <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--neg] [--back U] [--speed N] [--attn 'json']" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --neg) export U08D_NEG=1; shift;; --back) export TRIP_WALK_BACK="$2"; shift 2;;
  --speed) export TRIP_WALK_SPEED="$2"; shift 2;; --attn) export U_BORED_ATTN="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) us2_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; us2_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { us2_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "$LANE" = 4080-i4 ] && : "${TRIP_SAVE:=kah-imm26-4080-i4h}" && export TRIP_SAVE
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
[ "$norm" = 08-d ] || { echo "RESULT $ROW SETUP-FAIL unblockrun_sftrav.sh runs 08-d only (08-e 11-b: unblockrun_a.sh)"; exit 2; }
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in walk_done.txt bored_attn.txt bored_after1_mark.txt bored_ticks.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -3 "$LT_OUT/$ROW/$f" | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
