#!/usr/bin/env bash
# reload-sfj-selftest.sh (imm26-sfJ): OFFLINE self-test of reloaddefs_sfj.sh / reloadcheck_sfj.py / reload-run-sfj.sh / reload-py-sfj.sh (rows 23-e and 20-d recipes).
# No game, ssh, WSL or DB: lanes are simulated by reloadfake_sfj.py (-> reloadfake.py -> tripfake.py -> fakelane.py) with scenarios from reloadscen_sfj.py. Every defect scenario asserts the
# EXACT set of failing checks. Prints "SELFTEST sfj-<name> PASS|FAIL" and "SELFTEST SFJ ALL PASS|FAIL n/m".  Usage: bash rowtools/reload-sfj-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_ALT RW_SAVE_NAME RW_AWAY_F RW_AWAY_DIR RW_CHASE_S RW_FOLLOW_NEAR RW_FOLLOW_MIN_START RW_20D_RESUME_FIRST RW_20D_CONFIRM1 RW_20D_CONFIRM2 RW_20D_CONFIRM3
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfj-$1 PASS ${3:-}"; else echo "SELFTEST sfj-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_sfj.sh"
PY="$ST_HERE/reload-py-sfj.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/reloadfake_sfj.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sj"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sfj.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EVB="$KAH_ROWS_BASE/imm26-5090-i3/rows"
bad_set() {   # comma-joined sorted failing check names (checker in-process, V.emit replaced)
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import reloadcheck_sfj as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.ra.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
expect() {   # expect <name> <scenario> <row> <RESULT prefix> [exact failing set | substring]
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [[ "$pre" == *" FAIL" ]]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}

# --- 23-e legacy FOLLOW with control chase
expect 23-e-pass sj23e-pass 23-e "RESULT 23-e PASS" "follow_ticks_after_load"
expect 23-e-pass-edge-69.9 sj23e-edge-in 23-e "RESULT 23-e PASS"
expect 23-e-edge-70.1-setup-fail sj23e-edge-out 23-e "RESULT 23-e SETUP-FAIL" "BEFORE the save"
expect 23-e-follow-lost sj23e-lost 23-e "RESULT 23-e FAIL" "follow_ticks_after_load,post_load_follower_closes_distance"
expect 23-e-control-approaches-setup-fail sj23e-ctrl-approaches 23-e "RESULT 23-e SETUP-FAIL" "approaches Shay without a FOLLOW order"
expect 23-e-control-too-close-setup-fail sj23e-ctrl-short 23-e "RESULT 23-e SETUP-FAIL" "control chase: Shay only"
expect 23-e-pre-follower-far-setup-fail sj23e-pre-far 23-e "RESULT 23-e SETUP-FAIL" "BEFORE the save"
expect 23-e-no-follow-setup-fail sj23e-nofollow 23-e "RESULT 23-e SETUP-FAIL" "FOLLOW target resolved"
scen sj23e-pass; run 23-e $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
[ "$(grep -c 'order Shay HOLD_POSITION' "$F")" = 3 ] && chk 23-e-three-chases-ctrl-pre-post ok || chk 23-e-three-chases-ctrl-pre-post bad "$(grep -c 'order Shay HOLD_POSITION' "$F")"
[ "$(grep -n 'order Shay HOLD_POSITION' "$F" | head -1 | cut -d: -f1)" -lt "$(grep -n 'stobe_say' "$F" | head -1 | cut -d: -f1)" ] && chk 23-e-control-before-follow-me ok || chk 23-e-control-before-follow-me bad
[ "$(grep -c 'sleep 5$' "$F")" -ge 18 ] && chk 23-e-sampled-every-5s-45s ok || chk 23-e-sampled-every-5s-45s bad "$(grep -c 'sleep 5$' "$F")"
grep -q 'protect Shay on' "$F" && chk 23-e-protect-shay ok || chk 23-e-protect-shay bad
[ -s "$EVB/23-e/chase_ctrl.series" ] && [ -s "$EVB/23-e/chase_pre.series" ] && [ -f "$EVB/23-e/follow_log_chase_pre.txt" ] && chk 23-e-series-evidence ok || chk 23-e-series-evidence bad
grep -q "teleport Shay -50850 1533.0 2965.0" "$F" && chk 23-e-away-120 ok || chk 23-e-away-120 bad "$(grep 'teleport Shay' "$F" | head -2)"
scen sj23e-pass; RW_AWAY_F=150 RW_AWAY_DIR=-z RW_CHASE_S=20 run 23-e $L >/dev/null
grep -q 'teleport Shay -50970.0 1533.0 2815' "$KAH_ROW_FAKE_LOG" && [ "$(grep -c 'sleep 5$' "$KAH_ROW_FAKE_LOG")" -le 14 ] && chk 23-e-env-away-dir-chase-s ok || chk 23-e-env-away-dir-chase-s bad
RW_FOLLOW_NEAR=75 expect 23-e-env-follow-near sj23e-edge-out 23-e "RESULT 23-e PASS"; unset RW_FOLLOW_NEAR

# --- 20-d pending plan change with the insistence turn
expect 20-d-pass sj20d-pass 20-d "RESULT 20-d PASS" "pending_change_survives_load"
expect 20-d-second-wording-pass sj20d-second 20-d "RESULT 20-d PASS" "pending_change_survives_load"
expect 20-d-third-wording-pass sj20d-third 20-d "RESULT 20-d PASS" "pending_change_survives_load"
expect 20-d-never-pending-setup-fail sj20d-never 20-d "RESULT 20-d SETUP-FAIL" "pending plan change"
expect 20-d-lost-on-load sj20d-nopending-after-load 20-d "RESULT 20-d FAIL" "pending_change_survives_load"
expect 20-d-yes-does-not-replace sj20d-lost 20-d "RESULT 20-d FAIL" "bare_yes_after_reload_ends_old_or_replaces"
scen sj20d-pass; run 20-d $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
grep -q "Actually, go to the Stumble Inn instead" "$EVB/20-d/s3/utterance.txt" && grep -q "Yes, I mean it. I am sure, change it to the Stumble Inn." "$EVB/20-d/s3c1/utterance.txt" && [ ! -d "$EVB/20-d/s3c2" ] && chk 20-d-insistence-wording-stops-at-first ok || chk 20-d-insistence-wording-stops-at-first bad
[ "$(cat "$EVB/20-d/insist_turns.txt")" = 1 ] && chk 20-d-insist-turns-1 ok || chk 20-d-insist-turns-1 bad
[ "$(grep -n 'stobe_say' "$F" | sed -n 4p | cut -d: -f1)" -lt "$(grep -n 'stobe-auto save' "$F" | head -1 | cut -d: -f1)" ] && chk 20-d-insist-before-save ok || chk 20-d-insist-before-save bad
[ "$(grep -n 'stobe-auto save' "$F" | head -1 | cut -d: -f1)" -lt "$(grep -n 'stobe-auto load' "$F" | head -1 | cut -d: -f1)" ] && chk 20-d-save-before-load ok || chk 20-d-save-before-load bad
grep -q '^Yes\.$' "$EVB/20-d/s4/utterance.txt" && chk 20-d-bare-yes-after-load ok || chk 20-d-bare-yes-after-load bad
grep -q 'protect Shay on' "$F" && grep -q 'stobe_drawn sheathe Shay' "$F" && chk 20-d-calm ok || chk 20-d-calm bad
scen sj20d-third; run 20-d $L >/dev/null
[ "$(cat "$EVB/20-d/insist_turns.txt")" = 3 ] && grep -q "Please change the plan" "$EVB/20-d/s3c3/utterance.txt" && chk 20-d-third-wording-text ok || chk 20-d-third-wording-text bad
scen sj20d-never; run 20-d $L >/dev/null
! grep -q 'stobe-auto save' "$KAH_ROW_FAKE_LOG" && chk 20-d-no-save-when-no-pending ok || chk 20-d-no-save-when-no-pending bad
scen sj20d-pass; RW_20D_CONFIRM1="Yes, swap it." run 20-d $L >/dev/null
grep -q '^Yes, swap it\.' "$EVB/20-d/s3c1/utterance.txt" && chk 20-d-env-confirm-override ok || chk 20-d-env-confirm-override bad

# --- CLI: reload-run-sfj.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sfj.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen sj23e-pass; o=$(cli reload-run-sfj.sh 23-e $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 23-e PASS' && [ $rc = 0 ] && chk cli-23e ok || chk cli-23e bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen sj20d-pass; o=$(cli reload-run-sfj.sh 20-d $L --alt "Squin Hub" --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 20-d' && grep -q 'Squin Hub' "$EVB/20-d/s3/utterance.txt" && chk cli-20d-alt-option ok || chk cli-20d-alt-option bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen sj23e-lost; o=$(cli reload-run-sfj.sh 23-e $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
scen sj23e-ctrl-approaches; o=$(cli reload-run-sfj.sh 23-e $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
o=$(cli reload-run-sfj.sh 27-a $L); echo "$o" | grep -q 'RESULT 27-a SETUP-FAIL not a reload row handled by reload-run-sfj.sh' && chk cli-other-rows-refused ok || chk cli-other-rows-refused bad "$o"
scen sj23e-pass; o=$(cli reload-run-sfj.sh 23-e $L --dry); echo "$o" | grep -q '^RESULT 23-e DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
scen sj23e-pass; cli reload-run-sfj.sh 23-e $L --save my-save --allow-retry selftest >/dev/null; grep -q 'load my-save' "$KAH_ROW_FAKE_LOG" && chk cli-save-option ok || chk cli-save-option bad

# --- shim: other rows still go to the set-A checker; untouched originals
"$ST_HERE/reload-py-sfj.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
grep -q 'reloaddefs_sfj\|reloadcheck_sfj' "$ST_HERE/reloaddefs_a.sh" "$ST_HERE/reload-run.sh" "$ST_HERE/reload-py.sh" "$ST_HERE/reloadcheck_a.py" "$ST_HERE/rowdefs.sh" "$ST_HERE/tripdefs.sh" 2>/dev/null && chk originals-not-hooked bad || chk originals-not-hooked ok

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFJ ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFJ ALL FAIL $ok/$n"; exit 1; fi
