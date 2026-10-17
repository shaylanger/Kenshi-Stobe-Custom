#!/usr/bin/env bash
# unblock_f3_selftest.sh (imm26-sfFixB): OFFLINE self-test of unblockrun_f3.sh / unblockdefs_f3.sh / unblockcheck_f3.py / pywrap_uf3.sh (rows 13-c, 13-c-neg with a participation-qualified walk).
# No game, ssh, WSL or DB: lane simulated by unblockfake_f.py (scenarios from unblockscen_f.py, mutated here). Prints `SELFTEST uf3-<name> PASS|FAIL` and `SELFTEST UNBLOCK-F3 ALL PASS|FAIL n/m`.
# Checks marked [f-fails] FAIL under the old runner (`SELFTEST_F=1` runs the same scenarios through unblockdefs_f.sh/pywrap_uf.sh only, to show which expectations are new).
# Usage (WSL or Git Bash): bash rowtools/unblock_f3_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
P=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json" UNBLOCK_B_DEBUG=1
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 TRIP_13C_TRIES=3 UF3_KEEP_CALLS=3
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_13C_NEG TRIP_13C_STAGE TRIP_13C_SPEED SFK_KEEP_N SFK_KEEP_SLEEP SFK_KEEP_CHK SFK_KEEP_WH
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST uf3-$1 PASS ${3:-}"; else echo "SELFTEST uf3-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_b.sh"; . "$ST_HERE/unblockdefs_f.sh"; . "$ST_HERE/unblockdefs_f3.sh"
PY="$ST_HERE/pywrap_uf3.sh"
export TRIP_13C_SPEED=0.5
lt_fake() { "$P" "$ST_HERE/unblockfake_f.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$P" "$ST_HERE/unblockscen_f.py" "$1" > "$FAKE_SCEN" || echo "SCENARIO ERROR $1" >&2
  if [ -n "${2:-}" ]; then "$P" - "$FAKE_SCEN" "$2" <<'PY'
import json, sys
p = sys.argv[1]; S = json.load(open(p))
START1 = '[10:00:00] NATIVE_TRAVEL_START target=requested_reachable participation_bound=1 participation_why=ok_hand_fallback goal=-62380,330,16250'
START0 = '[10:00:00] NATIVE_TRAVEL_START target=requested_reachable participation_bound=0 participation_why=actor_no_identity goal=-62380,330,16250'
FIN = '[10:01:10] NATIVE_TRAVEL_FINISH phase=completed reason=measured_route_arrival planar=11.2'
QD = 'participation_diag=samples:2,span:8,best_span:779,actor_d:15,partner_d:0,progress:14,max_sep:15,brk_sep:36'
PH = lambda q, d='': '[10:01:10] NATIVE_TRAVEL: task=order:1:1 phase=completed terminal=1 arrived=1 participation_qualified=%d %s' % (q, d)
exec(sys.argv[2]); json.dump(S, open(p, 'w'))
PY
  fi
  : > "$KAH_ROW_FAKE_LOG"; }
L=4080-i4
run() { gr_main --no-preflight --allow-retry selftest "$@" 2>/dev/null; }
expect() { local name="$1" r="$2" row="$3" kind="$4" has="$5"; r=$(run "$row" $L)
  case "$r" in "RESULT $row $kind"*) if echo "$r" | grep -qF -- "$has"; then chk "$name" ok; else chk "$name" bad "missing '$has': $r"; fi;; *) chk "$name" bad "$r";; esac; }

# ---- 13-c positive: bound + qualified + new sharedexp row = PASS
scen f13c-pass 'S["ndump"]=[START1,FIN,PH(1)]'; expect 13-c-pass x 13-c PASS "sharedexp_kept_promise_row"
F="$KAH_ROW_FAKE_LOG"; D="$KAH_ROWS_BASE/imm26-4080-i4/rows/13-c"
grep -q "seq 1 80" "$F" && grep -q "sleep 0.5" "$F" && chk 13-c-uses-keeper-loop ok || chk 13-c-uses-keeper-loop bad   # [f-fails]
grep -q "stobe-auto speed 0.5" "$F" && ! grep -q "stobe-auto speed 1" "$F" && chk 13-c-walk-speed-0.5 ok || chk 13-c-walk-speed-0.5 bad   # [f-fails]
grep -q 're here. Thanks for the walk' "$F" && chk 13-c-sends-arrival-line ok || chk 13-c-sends-arrival-line bad
grep -q 'participation_qualified=1' "$D/native_travel.txt" 2>/dev/null && chk 13-c-evidence-keeps-terminal-participation-line ok || chk 13-c-evidence-keeps-terminal-participation-line bad
# ---- 13-c: completed but NO row: unbound / unqualified are SETUP-FAIL with the cause, not a FAIL of the award path   [f-fails: FAIL]
scen f13c-pass 'S["ndump"]=[START0,FIN,PH(0)]; S["sx"]=[[],[]]; S["award"]=[]'; expect 13-c-unbound-setupfail x 13-c SETUP-FAIL "NOT BOUND"
scen f13c-pass 'S["ndump"]=[START1,FIN,PH(0,QD)]; S["sx"]=[[],[]]; S["award"]=[]'; expect 13-c-unqualified-setupfail x 13-c SETUP-FAIL "NOT QUALIFIED"
scen f13c-pass 'S["ndump"]=[START1,FIN,PH(0,QD)]; S["sx"]=[[],[]]; S["award"]=[]'; r=$(run 13-c $L); echo "$r" | grep -qF "brk_sep:36" && chk 13-c-unqualified-names-diag ok || chk 13-c-unqualified-names-diag bad "$r"
scen f13c-pass 'S["ndump"]=[START1,FIN,PH(1)]; S["sx"]=[[],[]]; S["award"]=[]'; r=$(run 13-c $L); case "$r" in "RESULT 13-c PASS"*) chk 13-c-bound-qualified-but-no-row-not-pass bad "$r";; *) echo "$r" | grep -qE 'NOT BOUND|NOT QUALIFIED' && chk 13-c-bound-qualified-but-no-row-not-pass bad "$r" || chk 13-c-bound-qualified-but-no-row-not-pass ok;; esac
# ---- 13-c-neg: PASS only with a BOUND, UNQUALIFIED proof and no row
scen f13cneg-completed-pass 'S["ndump"]=[START1,FIN,PH(0,QD)]'; expect 13-c-neg-bound-unqualified-pass x 13-c-neg PASS "no_sharedexp_row_when_shay_far"
F="$KAH_ROW_FAKE_LOG"
! grep -q "seq 1 80" "$F" && grep -q "teleport Shay -62380 330 16250 dist 550" "$F" && chk 13-c-neg-keeps-hop-walk-shay-behind ok || chk 13-c-neg-keeps-hop-walk-shay-behind bad
[ "$(grep -c "teleport Shay 'Cind" "$F")" = 0 ] && chk 13-c-neg-never-moves-shay-onto-cind ok || chk 13-c-neg-never-moves-shay-onto-cind bad
# ---- inv13cneg: NATIVE_TRAVEL_START is logged at the ACCEPT turn inside tr_trip_setup, BEFORE rd_13c sets UF_N0: the native_travel.txt dump must start at the mark taken BEFORE the setup (UF_NS), the OBS window stays at UF_N0
scen f13cneg-completed-pass 'S["ndump"]=[START1,FIN,PH(0,QD)]'; run 13-c-neg $L >/dev/null
nd=$(grep -a 'uf:ndump' "$KAH_ROW_FAKE_LOG" | head -1 | sed -nE 's/.*tail -n \+([0-9]+) .*/\1/p'); no=$(grep -a 'uf:nobs' "$KAH_ROW_FAKE_LOG" | head -1 | sed -nE 's/.*tail -n \+([0-9]+) .*/\1/p')
[ -n "$nd" ] && [ -n "$no" ] && [ "$nd" -lt "$no" ] && chk 13-c-neg-dump-window-starts-before-trip-setup ok "dump=+$nd obs=+$no" || chk 13-c-neg-dump-window-starts-before-trip-setup bad "dump=+$nd obs=+$no"   # [f3-before-fix: FAIL]
scen f13cneg-completed-pass 'S["ndump"]=[START0,FIN,PH(0,QD)]'; expect 13-c-neg-unbound-setupfail x 13-c-neg SETUP-FAIL "unbound proof"   # [f-fails: PASS]
scen f13cneg-completed-pass 'S["ndump"]=[START1,FIN,PH(1)]'; expect 13-c-neg-qualified-setupfail x 13-c-neg SETUP-FAIL "QUALIFIED although Shay was held behind"   # [f-fails: PASS]
scen f13cneg-completed-pass 'S["ndump"]=[START1,FIN]'; expect 13-c-neg-no-terminal-line-setupfail x 13-c-neg SETUP-FAIL "no terminal NATIVE_TRAVEL participation_qualified line"
scen f13cneg-failed-row 'S["ndump"]=[START1,FIN,PH(0)]'; expect 13-c-neg-row-awarded-still-FAIL x 13-c-neg FAIL "no_sharedexp_row_when_trip_not_completed"
# ---- unchanged f behaviours still hold through the f3 checker
scen f13c-timeout-old-dll; expect 13-c-timeout-old-dll x 13-c SETUP-FAIL "NC18 Stobe.dll"
scen f13c-failed-defect; expect 13-c-arrival-defect x 13-c SETUP-FAIL "arrival defect"
# ---- runner + hygiene
bash "$ST_HERE/unblockrun_f3.sh" 99-z 4080-i4 2>/dev/null | grep -q 'not a row of the sfF set' && chk runner-rejects-unknown-row ok || chk runner-rejects-unknown-row bad
for f in unblockrun_f3.sh unblockdefs_f3.sh pywrap_uf3.sh unblock_f3_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
"$P" -m py_compile "$ST_HERE/unblockcheck_f3.py" 2>/dev/null && chk py-compile ok || chk py-compile bad
cd "$A/.." && dd=$(git diff --name-only -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_b.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_f.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_f2.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_f.py testing/live-stobe-queue/imm26-assert/rowtools/unblockrun_f.sh testing/live-stobe-queue/imm26-assert/rowtools/sfr22b_keep.sh 2>/dev/null)
[ -z "$dd" ] && chk existing-files-untouched ok || chk existing-files-untouched bad "$dd"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-F3 ALL PASS $ok/$n"; else echo "SELFTEST UNBLOCK-F3 ALL FAIL $ok/$n"; fi
rm -rf "$T"
