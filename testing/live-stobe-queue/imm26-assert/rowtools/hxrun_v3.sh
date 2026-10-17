#!/usr/bin/env bash
# hxrun_v3.sh 16-bx <lane> [options]   (imm26-fix16bx) = hxrun_v2.sh for 16-bx only, verdict from imm26-assert/v3/assert_stance.py (HX_ASSERT_DIR=v3):
#   the word count / friendliness check looks only at the NPC's reply to the player's chat turn (chat rows after the last inputtext, addressed to the player,
#   status not cancelled), not the NPC-to-NPC monologue in the same bundle window.  Scene (hxdefs_v2.sh rd_16bx), options and exit codes exactly as hxrun_v2.sh.
#   hxrun_v2.sh / hxdefs*.sh / v2/* are NOT edited.  Offline selftest: python -I imm26-assert/v3/selftest_16bx.py.   (hxrun_v2.sh header follows)
# hxrun_v2.sh <ROW> <lane> [options]   (imm26-sfU2) = hxrun.sh for 02-ax 02-cx 16-bx with the v2 asserters (HX_ASSERT_DIR=imm26-assert/v2) and rd_16bx from hxdefs_v2.sh
#   (stale combat/knockout/major_damage/limb_loss/recovered eventlog rows deleted after BOTH loads, so the 16-bx scene is clean).  hxrun.sh/hxdefs.sh are NOT edited.
#   Options and exit codes exactly as hxrun.sh.  Selftest: rowtools/hx-selftest_v2.sh.   (original header follows)
# hxrun.sh <ROW> <lane> [options]   ONE call per hardening rerun: 17-bx 18-cx 16-bx 15-bx 13-ax 02-ax (IMM- prefix optional).
#   Does: reload the lane's base save (tr_reload) -> preflight -> go-row (attempt guard + timing log; rows in hxdefs.sh, bundles under $HX_OUT/<ROW> or the evidence
#   dir) -> verdict by hxcheck.py (runs assert_claims / assert_stance / assert_witness / assert_principle; rowcheck.py/rowdefs.sh/go-row.sh are NOT edited) ->
#   up to 6 `EVIDENCE <ROW> ...` lines and exactly ONE `RESULT <ROW> ...` line (or `ROW-NEEDS-FIXER ...`).  Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.
#   Options: --save <name> (base save; i3 kah-imm26-5090-hxA, i4 kah-imm26-i4-hx0, other lanes need it)  --save2 <name> (second load of 15/16/18/02, default = --save)
#            --out <dir> (bundles to <dir>/<ROW>/<label>, e.g. C:/KenshiTestRuns/imm26-5090-hx)  --no-reload  --dry  --allow-retry "<reason>"  --native (ctxpush before every say)
#            --item <name> (17-bx, Sabreclaw)  --ctl <npc> (16-bx Malzin | 02-ax Thoke)  --faction <f> (18-cx/15-bx spawn faction)  --spot "x y z"  --out-dist <u> (15-bx, 300)
#            --runs "P1 N1" (13-ax subset, keeps the other run dirs)  --saves "s1 s2 s3 s4 s5" (13-ax: P1 P2 N1 N2 C1)
# Details and the row -> command table: rowtools/README_HX.md.
HX_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HX_HERE/../go-row.sh"
. "$HX_HERE/hxdefs.sh"
[ -f "$HX_HERE/hxdefs_b.sh" ] && . "$HX_HERE/hxdefs_b.sh"   # family B rows (imm26-hxB: 05-cx) via HXB_ROWS
[ -f "$HX_HERE/hxdefs_a.sh" ] && { . "$HX_HERE/hxdefs_a.sh"; HXB_ROWS="${HXB_ROWS:-} $HXA_ROWS"; }   # family A rows (imm26-hxA: 01-bx 01-cx 02-cx) share the HXB_ROWS gate
. "$HX_HERE/hxdefs_v2.sh"   # imm26-sfU2: redefines rd_16bx (purges stale combat/knockout eventlog rows after both loads)
export HX_ASSERT_DIR="$(cd "$HX_HERE/../v3" && pwd)"   # v2 asserters (imm26-sfU); hxcheck.py/hxcheck_a.py read it at start
PY="$HX_HERE/pywrap_hx.sh"
hx_usage() { echo "usage: hxrun_v3.sh <16-bx> <lane: $(lt_lanes)> [--save S] [--save2 S] [--out DIR] [--no-reload] [--dry] [--allow-retry 'why'] [--native] [--item I] [--ctl NPC] [--faction F] [--spot 'x y z'] [--out-dist U] [--runs 'P1 N1'] [--saves 'a b c d e']" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export HX_SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;; --native) export HX_NATIVE=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --item) export HX17_ITEM="$2"; shift 2;; --faction) export HX18_FACTION="$2" HX15_FACTION="$2"; shift 2;;
  --ctl) export HX16_CTL="$2" HX02_CTL="$2"; shift 2;; --spot) export HX_SPOT="$2"; shift 2;; --out-dist) export HX15_OUT="$2"; shift 2;;
  --runs) export HX13_RUNS="$2" HX_KEEP=1; shift 2;; --saves) export HX13_SAVES="$2"; shift 2;;
  -h|--help) hx_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; hx_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { hx_usage; exit 2; }
norm="${ROW#IMM-}"
case "$norm" in 16-bx) ;; *) echo "RESULT $ROW SETUP-FAIL hxrun_v3.sh handles 16-bx only (use hxrun_v2.sh for 02-ax 02-cx)"; exit 2;; esac
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
ROW_NPC="${ROW_NPC:-$HX_NPC_DEF}"; export ROW_NPC
if [ -n "${HX_KEEP:-}" ]; then   # partial 13-ax: keep the evidence dir (and the run dirs of the earlier calls)
  rl_begin() { RL_ROW="$1"; EV="$LT_OUT/$1"; RL_REASON=""; RL_NPC_ID=""; mkdir -p "$EV"; date >> "$EV/started.txt"; echo "$LT_LANE" > "$EV/lane.txt"; }
fi
# the save the first phase starts from (13-ax: the save of the first requested run)
FIRST="${HX_SAVE:-$(hxd_lane_save)}"
if [ "$norm" = 13-ax ]; then
  read -r -a SV <<<"${HX13_SAVES:-$(hx13_default_saves)}"; f1=$(echo "${HX13_RUNS:-P1}" | awk '{print $1}')
  case "$f1" in P1) FIRST="${SV[0]:-}";; P2) FIRST="${SV[1]:-}";; N1) FIRST="${SV[2]:-}";; N2) FIRST="${SV[3]:-}";; C1) FIRST="${SV[4]:-}";; esac
fi
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  [ -n "$FIRST" ] || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL no base save known for lane $LANE (use --save S; 13-ax: --saves 'a b c d e')"; exit 2; }
  TRIP_SAVE="$FIRST" tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
  export HX_PRELOADED=1
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
n=0; for f in phases.txt runs.txt spawn.txt roster.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && [ $n -lt 6 ] && { echo "EVIDENCE $ROW $f: $(tail -${HX_EVLINES:-5} "$LT_OUT/$ROW/$f" | tr '\n' ' ' | cut -c1-300)"; n=$((n+1)); }
done
echo "$out" | head -1
exit $rc
