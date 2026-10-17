#!/usr/bin/env bash
# reload-sff-selftest.sh (imm26-sfFixA2): OFFLINE self-test of reloaddefs_sff.sh (anchor ping-pong chase with validated landing) + reload-run-sff.sh for row 23-e.
# No game, ssh, WSL or DB: the lane is simulated by reloadfake_sff.py (positions + chase distances) with scenarios from reloadscen_sff.py (sfJ scenarios + tele_dy = cliff height per Shay teleport).
# KAH_PF_ISOLATION stays at its default (1): the runner must work (and refuse =0) without it. Prints "SELFTEST sff-<name> PASS|FAIL" and "SELFTEST SFF ALL PASS|FAIL n/m".
# Usage: bash rowtools/reload-sff-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY KAH_PF_ISOLATION TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_ALT RW_SAVE_NAME RW_AWAY_F RW_AWAY_DIR RW_CHASE_S RW_FOLLOW_NEAR RW_FOLLOW_MIN_START RW_LAND_DY RW_ANCHOR_TOL
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sff-$1 PASS ${3:-}"; else echo "SELFTEST sff-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_sfj.sh"; . "$ST_HERE/reloaddefs_sff.sh"
PY="$ST_HERE/reload-py-sfj.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/reloadfake_sff.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sj" "$FAKE_STATE.sf"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sff.py" "$@" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EV23="$KAH_ROWS_BASE/imm26-5090-i3/rows/23-e"
tx() { grep -v '^\[ -n' "$KAH_ROW_FAKE_LOG" | grep -oE 'teleport Shay -?[0-9.]+ -?[0-9.]+ -?[0-9.]+' | awk '{printf "%.0f ", $3}'; }     # x of every Shay teleport, in order

# --- flat ground: PASS, P1 / P0 / P1 ping-pong, no drift
scen sj23e-pass 0; r=$(run 23-e $L)
echo "$r" | grep -q '^RESULT 23-e PASS' && chk flat-pass ok || chk flat-pass bad "$(echo "$r" | cut -c1-300)"
[ "$(tx)" = "-52972 -53092 -52972 " ] && chk ping-pong-order-P1-P0-P1 ok || chk ping-pong-order-P1-P0-P1 bad "x=$(tx)"
[ "$(sed -n 1p "$EV23/anchor.txt" | awk '{print $1}')" = "-53092.0" ] && [ "$(awk '{print $1}' "$EV23/anchor_far.txt")" = "-52972" ] && [ "$(cat "$EV23/anchor_dir.txt")" = x ] && chk anchor-files ok || chk anchor-files bad "$(cat "$EV23/anchor.txt" "$EV23/anchor_far.txt" 2>&1 | tr '\n' ';')"
[ -s "$EV23/landing_ctrl.txt" ] && [ -s "$EV23/landing_pre.txt" ] && [ -s "$EV23/landing_post.txt" ] && ! grep -q BAD "$EV23"/landing_*.txt && chk landing-evidence-3-chases-all-ok ok || chk landing-evidence-3-chases-all-ok bad "$(cat "$EV23"/landing_*.txt 2>&1 | cut -c1-160 | head -8)"
grep -q 'mode=out' "$EV23/landing_ctrl.txt" && grep -q 'mode=back' "$EV23/landing_pre.txt" && grep -q 'mode=out' "$EV23/landing_post.txt" && chk chase-modes-out-back-out ok || chk chase-modes-out-back-out bad
[ -s "$EV23/chase_ctrl.series" ] && [ -s "$EV23/chase_pre.series" ] && [ -s "$EV23/chase_post.series" ] && [ -f "$EV23/follow_log_chase_pre.txt" ] && chk series-evidence-unchanged ok || chk series-evidence-unchanged bad
[ "$(grep -c 'order Shay HOLD_POSITION' "$KAH_ROW_FAKE_LOG")" = 3 ] && [ "$(grep -c 'sleep 5$' "$KAH_ROW_FAKE_LOG")" -ge 27 ] && chk three-chases-45s-sampling ok || chk three-chases-45s-sampling bad "$(grep -c 'sleep 5$' "$KAH_ROW_FAKE_LOG")"
[ "$(grep -n 'order Shay HOLD_POSITION' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n 'stobe_say' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" ] && chk control-before-follow-me ok || chk control-before-follow-me bad

# --- the cumulative drift of the old recipe: with sfJ the 3 teleports are +120 each from the current spot (x = -52972, -52852, -52732 style); here max |dx| from the anchor is 120
awk -v xs="$(scen sj23e-pass 0; run 23-e $L >/dev/null; tx)" 'BEGIN{n=split(xs,a," "); m=0; for(i=1;i<=n;i++){d=a[i]+53092; if(d<0)d=-d; if(d>m)m=d}; exit !(m<=120)}' && chk no-cumulative-drift-max-120-from-anchor ok || chk no-cumulative-drift-max-120-from-anchor bad

# --- cliff on the first outbound landing: next direction (-x) is used and then kept for the whole row
scen sj23e-pass 250,0; r=$(run 23-e $L)
echo "$r" | grep -q '^RESULT 23-e PASS' && chk cliff-first-then-minus-x-pass ok || chk cliff-first-then-minus-x-pass bad "$(echo "$r" | cut -c1-300)"
grep -q 'out dir=x .* BAD' "$EV23/landing_ctrl.txt" && grep -q 'out dir=-x .* ok' "$EV23/landing_ctrl.txt" && [ "$(cat "$EV23/anchor_dir.txt")" = "-x" ] && chk cliff-first-retry-logged ok || chk cliff-first-retry-logged bad "$(cat "$EV23/landing_ctrl.txt" | cut -c1-170)"
[ "$(tx)" = "-52972 -53092 -53212 -53092 -53212 " ] && chk cliff-first-teleports-x-back-minus-x-anchor-minus-x ok || chk cliff-first-teleports-x-back-minus-x-anchor-minus-x bad "x=$(tx)"
scen sj23e-pass 250,0,250,0; r=$(run 23-e $L)
echo "$r" | grep -q '^RESULT 23-e PASS' && [ "$(cat "$EV23/anchor_dir.txt")" = z ] && chk two-cliffs-then-z-pass ok || chk two-cliffs-then-z-pass bad "$(echo "$r" | cut -c1-200) dir=$(cat "$EV23/anchor_dir.txt" 2>/dev/null)"

# --- every direction is a cliff: SETUP-FAIL with the cliff reason, the chase never starts (no speed 3), no PASS/FAIL judgement
scen sj23e-pass 250; r=$(run 23-e $L)
echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && echo "$r" | grep -q 'cliff' && chk all-cliffs-setup-fail ok || chk all-cliffs-setup-fail bad "$(echo "$r" | cut -c1-300)"
! grep -q 'stobe-auto speed 3' "$KAH_ROW_FAKE_LOG" && chk all-cliffs-no-chase-started ok || chk all-cliffs-no-chase-started bad
[ "$(grep -c 'BAD' "$EV23/landing_ctrl.txt")" = 4 ] && chk all-cliffs-4-directions-tried ok || chk all-cliffs-4-directions-tried bad "$(grep -c BAD "$EV23/landing_ctrl.txt")"
# --- a bad RETURN landing (P0): SETUP-FAIL as well
scen sj23e-pass 0,250; r=$(run 23-e $L)
echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && echo "$r" | grep -q 'cliff' && chk bad-return-landing-setup-fail ok || chk bad-return-landing-setup-fail bad "$(echo "$r" | cut -c1-300)"
# --- landing below the NPC counts as well (dy negative)
scen sj23e-pass -250; r=$(run 23-e $L)
echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && chk landing-below-npc-setup-fail ok || chk landing-below-npc-setup-fail bad "$(echo "$r" | cut -c1-200)"
# --- edge: dy 39 passes, 41 fails (RW_LAND_DY=40)
scen sj23e-pass 39; r=$(run 23-e $L); echo "$r" | grep -q '^RESULT 23-e PASS' && chk dy-39-ok ok || chk dy-39-ok bad "$(echo "$r" | cut -c1-200)"
scen sj23e-pass 41; r=$(run 23-e $L); echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && chk dy-41-bad ok || chk dy-41-bad bad "$(echo "$r" | cut -c1-200)"
scen sj23e-pass 41; r=$(RW_LAND_DY=60 run 23-e $L); echo "$r" | grep -q '^RESULT 23-e PASS' && chk env-land-dy ok || chk env-land-dy bad "$(echo "$r" | cut -c1-200)"

# --- Shay not at the anchor when a chase starts (e.g. he was moved): SETUP-FAIL, not a wrong teleport
scen sj23e-pass 0; RW_ANCHOR_TOL=0.001 run 23-e $L >/dev/null 2>&1   # tolerance so tight the second chase (Shay at P1+rounding) is still at P1 -> pass or setup-fail, but never a crash
scen sj23e-pass 0; r=$(RW_ANCHOR_TOL=0 run 23-e $L); echo "$r" | grep -q '^RESULT 23-e' && chk tight-tolerance-no-crash ok || chk tight-tolerance-no-crash bad "$(echo "$r" | cut -c1-200)"

# --- env: direction, distance, chase seconds
scen sj23e-pass 0; RW_AWAY_F=150 RW_AWAY_DIR=-z RW_CHASE_S=20 run 23-e $L >/dev/null
grep -q 'teleport Shay -53092 990.5 4692' "$KAH_ROW_FAKE_LOG" && [ "$(grep -c 'sleep 5$' "$KAH_ROW_FAKE_LOG")" -le 14 ] && chk env-away-dir-f-chase-s ok || chk env-away-dir-f-chase-s bad "$(grep -m2 'teleport Shay' "$KAH_ROW_FAKE_LOG" | cut -c1-120)"

# --- verdicts of the checker are unchanged (sfJ scenarios, same thresholds)
scen sj23e-lost 0; r=$(run 23-e $L); echo "$r" | grep -q '^RESULT 23-e FAIL' && chk follow-lost-fail ok || chk follow-lost-fail bad "$(echo "$r" | cut -c1-200)"
scen sj23e-ctrl-approaches 0; r=$(run 23-e $L); echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && chk control-approaches-setup-fail ok || chk control-approaches-setup-fail bad "$(echo "$r" | cut -c1-200)"
scen sj23e-pre-far 0; r=$(run 23-e $L); echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && chk pre-follower-far-setup-fail ok || chk pre-follower-far-setup-fail bad "$(echo "$r" | cut -c1-200)"
scen sj23e-nofollow 0; r=$(run 23-e $L); echo "$r" | grep -q '^RESULT 23-e SETUP-FAIL' && chk no-follow-setup-fail ok || chk no-follow-setup-fail bad "$(echo "$r" | cut -c1-200)"

# --- CLI: reload-run-sff.sh as a separate process (KAH_PF_ISOLATION default = 1)
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sff.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen sj23e-pass 0; o=$(cli reload-run-sff.sh 23-e $L --save kah-imm26-5090-ready --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 23-e PASS' && [ $rc = 0 ] && chk cli-23e-pass ok || chk cli-23e-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'load kah-imm26-5090-ready' "$KAH_ROW_FAKE_LOG" && chk cli-loads-the-configured-lane-save ok || chk cli-loads-the-configured-lane-save bad
scen sj23e-pass 0; o=$(cli reload-run-sff.sh 23-e $L --allow-retry selftest); grep -q 'load kah-imm26-5090-ready' "$KAH_ROW_FAKE_LOG" && chk cli-i3-default-save-is-configured-save ok || chk cli-i3-default-save-is-configured-save bad "$(echo "$o" | cut -c1-200)"
scen sj23e-pass 250; o=$(cli reload-run-sff.sh 23-e $L --no-reload --allow-retry selftest); rc=$?; [ $rc = 2 ] && echo "$o" | grep -q 'RESULT 23-e SETUP-FAIL' && chk cli-cliff-exit-2 ok || chk cli-cliff-exit-2 bad "rc=$rc $(echo "$o" | cut -c1-200)"
scen sj23e-lost 0; o=$(cli reload-run-sff.sh 23-e $L --no-reload --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
o=$(KAH_PF_ISOLATION=0 cli reload-run-sff.sh 23-e $L --no-reload); echo "$o" | grep -q 'ISOLATION=0 is not allowed' && chk cli-refuses-isolation-off ok || chk cli-refuses-isolation-off bad "$o"
o=$(cli reload-run-sff.sh 20-d $L); echo "$o" | grep -q 'RESULT 20-d SETUP-FAIL not a reload row handled by reload-run-sff.sh' && chk cli-other-rows-refused ok || chk cli-other-rows-refused bad "$o"
scen sj23e-pass 0; o=$(cli reload-run-sff.sh 23-e $L --dry --no-reload); echo "$o" | grep -q '^RESULT 23-e DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"

# --- hygiene: no script a queued list may use was edited / hooked; no KAH_PF_ISOLATION=0 in the new files (except the refusal text)
grep -q 'reloaddefs_sff\|reload-run-sff' "$ST_HERE/reloaddefs_a.sh" "$ST_HERE/reloaddefs_sfj.sh" "$ST_HERE/reload-run-sfj.sh" "$ST_HERE/reload-run.sh" "$ST_HERE/reloadcheck_sfj.py" "$A/../../tools/automation/row-runners.tsv" 2>/dev/null && chk originals-not-hooked bad || chk originals-not-hooked ok
grep -h 'KAH_PF_ISOLATION=0' "$ST_HERE/reloaddefs_sff.sh" "$ST_HERE/reload-run-sff.sh" | grep -v 'is not allowed\|NEVER' | grep -q . && chk no-isolation-off-in-new-files bad || chk no-isolation-off-in-new-files ok

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFF ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFF ALL FAIL $ok/$n"; exit 1; fi
