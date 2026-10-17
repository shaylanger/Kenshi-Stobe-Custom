#!/usr/bin/env bash
# unblockrun_sffb4.sh <11-b> <lane> [options]   ONE call for row 11-b (imm26-fix11b recipe v4 = v3 sffb + quiet spot/far dump, people as Name|serial with vacuity guards, strays cleared and events aged out
#   before the post-combat tick, eventlog combat proof, enemy unprotected before the KO; unblockdefs_sffb4.sh header). Optional reload of the lane's save -> preflight -> go-row -> `EVIDENCE` lines ->
#   exactly ONE `RESULT 11-b PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh. Verdict: unblockcheck_a.py (unchanged) via unblockpy_a.sh. NEVER set KAH_PF_ISOLATION=0 (refused): run from
#   the lane's configured save (--save kah-imm26-5090 on 5090-i3, --save kah-imm26-4080-i4 on 4080-i4).
#   Options: --save <name>  --no-reload  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of the same row)  --faction "<enemy faction>" (Dust Bandits)  --calm-tries <n> (8, 15 s each)
#            --end ko|far (ko = default)  --recall-dist <u> (120)  --spot "x y z" (-48000 1500 2960)  --dump "x y z" (-62030 330 16250)  --quiet-max <s> (300)
#   Selftest: rowtools/unblock_sffb4_selftest.sh. Operator note: inbox/operators/fix11b.txt.
US_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$US_HERE/../go-row.sh"
. "$US_HERE/reloaddefs_a.sh"
. "$US_HERE/reloaddefs_b.sh"
. "$US_HERE/unblockdefs_a.sh"
. "$US_HERE/tripdefs_sfk.sh"
. "$US_HERE/unblockdefs_sfk.sh"
. "$US_HERE/unblockdefs_sffb.sh"
. "$US_HERE/unblockdefs_sffb4.sh"
PY="$US_HERE/unblockpy_a.sh"
us_usage() { echo "usage: unblockrun_sffb4.sh <ROW: 11-b> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--faction F] [--calm-tries N] [--end ko|far] [--recall-dist U] [--spot 'x y z'] [--dump 'x y z'] [--quiet-max S]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;;
  --faction) export U11B_FACTION="$2"; shift 2;; --calm-tries) export U11B_CALM_TRIES="$2"; shift 2;;
  --end) export U11B_END="$2"; shift 2;; --recall-dist) export U11B_RECALL_DIST="$2"; shift 2;;
  --spot) export U11B_SPOT="$2"; shift 2;; --dump) export U11B_DUMP="$2"; shift 2;; --quiet-max) export U11B_QUIET_MAX_S="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) us_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; us_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { us_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "$LANE" = 4080-i4 ] && : "${TRIP_SAVE:=kah-imm26-4080-i4}" && export TRIP_SAVE
[ "$LANE" = 5090-i3 ] && : "${TRIP_SAVE:=kah-imm26-5090}" && export TRIP_SAVE
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
case "$norm" in 11-b) ;; *) echo "RESULT $ROW SETUP-FAIL not an sffb4 row (11-b only)"; exit 2;; esac
[ "${KAH_PF_ISOLATION:-1}" = 0 ] && { echo "RESULT $ROW SETUP-FAIL KAH_PF_ISOLATION=0 is not allowed (run from the lane's configured save: --save kah-imm26-5090 on 5090-i3, kah-imm26-4080-i4 on 4080-i4)"; exit 2; }
case "${U11B_END:-ko}" in ko|far) ;; *) echo "RESULT $ROW SETUP-FAIL --end must be ko or far"; exit 2;; esac
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in scene_cfg.txt scene_pre.txt.n bored_people.txt unprotect.txt ko.txt calm_poll.txt calm_track.txt recall.txt scene_calm.txt.n quiet_wait.txt enemy.txt claimable.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -3 "$LT_OUT/$ROW/$f" | cut -c1-240 | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
