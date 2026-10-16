#!/usr/bin/env bash
# sfxrun.sh 12-d <lane> [options]   ONE call: 12-d v2 (imm26-sfX; clean-conversation positive control, real gate-log check, own-reply attribution; see sfxdefs.sh header).
#   preflight -> go-row (rd_12d from sfxdefs.sh + verdict sfxcheck.py via the sfx_py shim) -> `EVIDENCE` lines -> exactly ONE `RESULT 12-d PASS|FAIL|SETUP-FAIL|GATED ...` line;
#   exit 0/1/2/3/4 as go-row.sh (GATED = rc 3 = positive control declined by the LLM, server gate fine: a coordinator decision, not a fixer ticket).  No save reload (12-d needs none).
#   rowdefs.sh / rowcheck.py / go-row.sh stay as they were (the plain `go-row.sh 12-d` path is unchanged).
#   Options: --asks N (aff85 asks, default 3)  --npc2 NAME (run the aff85 controls on a second armed outsider within 80 u)  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of 12-d on the lane)
#   Evidence: s1 (aff40), s2.. (aff85), purge.txt sfx_mark.txt haff-aff40.txt haff-aff85.txt inv_before<k>/after<k>.txt result.txt.  Selftest: rowtools/sfx_selftest.sh.
SFX_RUN_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SFX_RUN_HERE/../go-row.sh"
. "$SFX_RUN_HERE/sfxdefs.sh"      # redefines rd_12d, defines sfx_py
PY=sfx_py
sfx_usage() { echo "usage: sfxrun.sh 12-d <lane: $(lt_lanes)> [--asks N] [--npc2 NAME] [--dry] [--allow-retry 'why']" >&2; }
ROW=""; LANE=""; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --asks) export SFX_ASKS="$2"; shift 2;; --npc2) export SFX_NPC2="$2"; shift 2;;
  --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) sfx_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; sfx_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { sfx_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "${ROW#IMM-}" = 12-d ] || { echo "RESULT $ROW SETUP-FAIL sfxrun.sh runs 12-d only"; exit 2; }
case "${SFX_ASKS:-3}" in ''|*[!0-9]*|0) echo "RESULT $ROW SETUP-FAIL --asks must be a positive integer"; exit 2;; esac
mkdir -p "$LT_OUT"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
pf=$(pf_run "$LANE" "${ROW_NPC:-Cind}" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in sfx_mark.txt purge.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -4 "$LT_OUT/$ROW/$f" | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
