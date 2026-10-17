#!/usr/bin/env bash
# unblockrun_14d.sh 14-d <lane> [options]   ONE call for row IMM-14-d (imm26-sfFixB2): ClearGroup for a hostile bandit group of exactly 5 (accept leg), the 5-serial set, a distant 6th bandit untouched.
#   = optional reload (ONLY when --save/TRIP_SAVE is given: the lane's already-loaded configured save is used otherwise) -> preflight -> go-row (rd_14d from unblockdefs_14d.sh, verdict
#   unblockcheck_14d.py via pywrap_u14d.sh) -> up to 6 `EVIDENCE` lines -> exactly ONE `RESULT 14-d PASS|FAIL|SETUP-FAIL|GATED ...` line. Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.
#   SETUP-FAIL names its cause: spawn count, senses, `agreedTargets=n of 5` + per-member ACTIVITY_CLEARGROUP_MEMBER diag (selected / visible / protected+protReason / ownerSerial slaveState chained prison).
#   LANE DLL: NC22 or newer (NC30 / NC31 contain the ownership fix, de423966); an older DLL ends SETUP-FAIL "owned_target ... lane DLL older than NC22". Needs the Rebirth scene coordinates of the
#   Cind saves (D14_BASE) and Cind + Shay in the loaded world. Runs on the lane's configured save only; never set KAH_PF_ISOLATION=0.
#   Options: --save <name>  --no-reload  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of 14-d on the lane)  --ask "<text>" (default "Hunt the 5 bandits."; second run: --ask "Hunt 5 bandits.")
#            --accept "<text>"  --hold <s> (watch after the accept, 90)  --spawnt "<squad template>" (one platoon)  --base "x y z"  --rounds <n> (probe rounds, 3)
#   Env: all D14_* of unblockdefs_14d.sh.  Selftest: rowtools/unblock_14d_selftest.sh (offline, fake lane).  Never run on a lane an operator is using unless you are that operator.
U14_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$U14_HERE/../go-row.sh"
. "$U14_HERE/reloaddefs_a.sh"
. "$U14_HERE/unblockdefs_14d.sh"
PY="$U14_HERE/pywrap_u14d.sh"
u14_usage() { echo "usage: unblockrun_14d.sh 14-d <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--ask t] [--accept t] [--hold s] [--spawnt T] [--base 'x y z'] [--rounds n]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --ask) D14_ASK="$2"; shift 2;; --accept) D14_ACCEPT="$2"; shift 2;; --hold) D14_HOLD="$2"; shift 2;;
  --spawnt) D14_SPAWNT="$2"; shift 2;; --base) D14_BASE="$2"; shift 2;; --rounds) D14_ROUNDS="$2"; shift 2;;
  -h|--help) u14_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; u14_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { u14_usage; exit 2; }
case "${ROW#IMM-}" in 14-d) ;; *) echo "RESULT $ROW SETUP-FAIL unblockrun_14d.sh runs 14-d only"; exit 2;; esac
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "${KAH_PF_ISOLATION:-1}" = 0 ] && { echo "RESULT $ROW SETUP-FAIL KAH_PF_ISOLATION=0 is not allowed for 14-d (configured lane save only)"; exit 2; }
tr_cfg; export ROW_NPC D14_ASK D14_ACCEPT D14_HOLD D14_SPAWNT D14_BASE D14_ROUNDS
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -n "${TRIP_SAVE:-}" ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
n=0; for f in scene.txt set_probe.txt rec_ask.txt rec_final.txt cleargroup_member_lines.txt atk_post.txt; do
  p="$LT_OUT/$ROW/$f"
  [ -s "$p" ] && [ $n -lt 6 ] && { echo "EVIDENCE $ROW $f: $(grep -a -v '^#' "$p" | tail -2 | cut -c1-260 | tr '\n' '|')"; n=$((n+1)); }
done
echo "$out" | head -1
exit $rc
