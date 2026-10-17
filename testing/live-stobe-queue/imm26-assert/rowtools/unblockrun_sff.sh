#!/usr/bin/env bash
# unblockrun_sff.sh <ROW> <lane> [options]   ONE call for row 03-b (imm26-sfFixA, FORCED WITNESS LINE; sfz recipe otherwise unchanged): optional reload of the lane's ready save -> preflight -> go-row (rd_03b from
#   unblockdefs_sff.sh over sfz/d2/d) -> `EVIDENCE` lines -> exactly ONE `RESULT 03-b PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh.
#   Options: --save <name> (ready save to reload first; default for 4080-i4: kah-imm26-4080-i4h)  --no-reload  --dry  --allow-retry "<why>"
#            --b "<full name>" (force B)  --real-tries <n> (try n REAL LLM pair requests first, default 0 = forced line only)  --text "<line>" (the scripted witness line)  --max-rows <n>  --no-attack (use Cind's existing newest Shay row)
#   sff = sfz + the Cind -> B line is FORCED by calling the server's own gossip hook (sharehook.php -> stobeKnowledgeShareFromSpeech, the call bored.php makes after every NPC line): no LLM lottery, no server change,
#         no lane deploy. B is then asked in game and its prompt is captured as before. The RESULT line carries seed=forced-line. Details: unblockdefs_sff.sh header, inbox operators sff.txt.
UR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$UR_HERE/../go-row.sh"
. "$UR_HERE/reloaddefs_a.sh"
. "$UR_HERE/unblockdefs_a.sh"
. "$UR_HERE/unblockdefs_d.sh"
. "$UR_HERE/unblockdefs_d2.sh"
. "$UR_HERE/unblockdefs_sfz.sh"
. "$UR_HERE/unblockdefs_sff.sh"
PY="$UR_HERE/unblockpy_sff.sh"
ur_usage() { echo "usage: unblockrun_sff.sh <ROW: 03-b> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--b 'Full Name'] [--real-tries N] [--text LINE] [--max-rows N] [--no-attack]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --b) export U03B_B="$2"; shift 2;; --real-tries) export SFF_REAL_TRIES="$2"; shift 2;; --text) export SFF_TEXT="$2"; shift 2;;
  --max-rows) export U03B_MAX_ROWS="$2"; shift 2;; --no-attack) export U03B_NO_ATTACK=1; shift;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) ur_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; ur_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { ur_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "$LANE" = 4080-i4 ] && : "${TRIP_SAVE:=kah-imm26-4080-i4h}" && export TRIP_SAVE
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
case "$norm" in 03-b) ;; *) echo "RESULT $ROW SETUP-FAIL not a rowtools-03b row (03-b)"; exit 2;; esac
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in b.txt cind_row.txt gossip_ok.txt seed_mode.txt hearsay_row.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -3 "$LT_OUT/$ROW/$f" | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
