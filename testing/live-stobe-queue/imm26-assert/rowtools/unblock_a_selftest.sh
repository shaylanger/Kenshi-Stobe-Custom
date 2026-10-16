#!/usr/bin/env bash
# unblock_a_selftest.sh: OFFLINE self-test of the unblock rows 08-e 08-d 11-b (unblockdefs_a.sh / unblockcheck_a.py / unblockrun_a.sh / unblockpy_a.sh).
# No game, ssh, WSL or DB: lanes are simulated by unblockfake_a.py (-> reloadfake.py -> tripfake.py -> fakelane.py) with scenarios from unblockscen_a.py. For every defect scenario the
# EXACT set of failing checks is asserted, plus recipe statements (targeted request shape, push before the request, real walk staging, no harness order on the walker, combat scene).
# FAST: run in WSL (WSL python3, ~5 min; Git Bash/Windows python is ~10x slower): wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_a_selftest.sh
# Prints `SELFTEST unblock-<name> PASS|FAIL` lines and `SELFTEST UNBLOCK ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_a_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 TRIP_WALK_TRIES=2
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT U08D_NEG TRIP_WALK_BACK TRIP_WALK_SPEED U_BORED_TRIES U11B_FACTION U11B_DIST
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblock-$1 PASS ${3:-}"; else echo "SELFTEST unblock-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"
PY="$ST_HERE/unblockpy_a.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_a.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_a.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
bad_set() {  # comma-joined sorted names of the failing checks (the checker run in-process with V.emit replaced)
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import unblockcheck_a as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
# expect <name> <scenario> <row> <RESULT prefix> [FAIL: exact failing-check set | other: substring that must occur in the line]
expect() {
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ "$pre" = "RESULT $row FAIL" ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}

# --- 08-e
expect 08-e-pass 08e-pass 08-e "RESULT 08-e PASS" "claimed_once_after_reload"
expect 08-e-topic-lost 08e-lost 08-e "RESULT 08-e FAIL" "topic_survives_load"
expect 08-e-claimed-twice 08e-double 08-e "RESULT 08-e FAIL" "claimed_once_after_reload"
expect 08-e-request-failed-setup-fail 08e-http 08-e "RESULT 08-e SETUP-FAIL" "never reached the server"
expect 08-e-tick-delivered-no-claim-is-server-gate 08e-gate 08-e "RESULT 08-e SETUP-FAIL" "server-side claim gate"
# --- 08-d (real walk)
expect 08-d-pass 08d-pass 08-d "RESULT 08-d PASS" "topic_closed_outcome_completed"
expect 08-d-topic-still-open 08d-open 08-d "RESULT 08-d FAIL" "topic_closed_outcome_completed"
expect 08-d-claim-written 08d-claim 08-d "RESULT 08-d FAIL" "no_situated_remark_claim_for_closed_topic"
expect 08-d-trip-not-completed-setup-fail-names-walk 08d-notrip 08-d "RESULT 08-d SETUP-FAIL" "walk: completed=0"
expect 08-d-request-failed-setup-fail 08d-http 08-d "RESULT 08-d SETUP-FAIL" "targeted bored request failed"
export U08D_NEG=1
expect 08-d-negative-pass 08d-neg-pass 08-d "RESULT 08-d PASS" "negative_trip_not_completed_topic_stays_open"
expect 08-d-negative-topic-closed 08d-neg-closed 08-d "RESULT 08-d FAIL" "negative_trip_not_completed_topic_stays_open"
expect 08-d-negative-trip-completed-voids-control 08d-neg-completed 08-d "RESULT 08-d SETUP-FAIL" "control is void"
scen 08d-neg-pass; run 08-d $L >/dev/null
! grep -q 'teleport .* dist 350' "$KAH_ROW_FAKE_LOG" && chk 08-d-negative-does-not-walk ok || chk 08-d-negative-does-not-walk bad
unset U08D_NEG
# --- 11-b
expect 11-b-pass 11b-pass 11-b "RESULT 11-b PASS" "exactly_one_claim_after_combat"
expect 11-b-claim-in-combat-no-snapshot 11b-claim-nosnap 11-b "RESULT 11-b FAIL" "ask_count_unchanged_in_combat,no_claim_in_combat_without_snapshot"
expect 11-b-claim-in-combat-fresh-snapshot 11b-claim-snap 11-b "RESULT 11-b FAIL" "ask_count_unchanged_in_combat,no_claim_in_combat_with_fresh_snapshot"
expect 11-b-no-claim-after-combat 11b-noclaim-after 11-b "RESULT 11-b FAIL" "ask_count_plus_1_after_claim,exactly_one_claim_after_combat"
expect 11-b-not-in-combat-setup-fail 11b-notcombat 11-b "RESULT 11-b SETUP-FAIL" "not in proven combat"
expect 11-b-npc-gone-setup-fail 11b-gone 11-b "RESULT 11-b SETUP-FAIL" "vanished"
expect 11-b-combat-never-ended-setup-fail 11b-nocalm 11-b "RESULT 11-b SETUP-FAIL" "combat did not end"
expect 11-b-request-failed-setup-fail 11b-http 11-b "RESULT 11-b SETUP-FAIL" "targeted bored request failed"
expect 11-b-no-topic-setup-fail 11b-notopic 11-b "RESULT 11-b SETUP-FAIL" "no open personal_plan"
expect 11-b-spawn-failed-setup-fail 11b-spawnfail 11-b "RESULT 11-b SETUP-FAIL" "enemy spawn failed"

# --- recipe statements (fake-lane transcript)
F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
scen 08e-pass; run 08-e $L >/dev/null
grep -q 'stream.php?DATA=' "$F" && grep -q 'profile=Cind' "$F" && grep -q 'optional=1' "$F" && grep -q 'mode=autochat' "$F" && grep -q 'people=' "$F" && chk i4-bored-request-shape ok || chk i4-bored-request-shape bad
grep -q 'stream.php?DATA=\$D&profile' "$F" && chk i4-bored-DATA-is-first-query-parameter ok || chk i4-bored-DATA-is-first-query-parameter bad
[ "$(awk '/stobe_ctxpush/{p=1} /# u:stream/{if(!p)bad++; p=0} END{print bad+0}' "$F")" = 0 ] && grep -q 'u:stream' "$F" && chk i4-bored-push-before-request ok || chk i4-bored-push-before-request bad
grep -q 'stobe-auto save kah-imm26-rw-followup-4080-i4' "$F" && grep -q 'stobe-auto load kah-imm26-rw-followup-4080-i4' "$F" && chk 08-e-save-then-load ok || chk 08-e-save-then-load bad
[ "$(fl 'stobe-auto save')" -lt "$(fl 'stobe-auto load')" ] && [ "$(fl 'stobe-auto load')" -lt "$(fl 'u:stream')" ] && chk 08-e-tick-after-load ok || chk 08-e-tick-after-load bad
[ "$(grep -c 'stobe_drawn sheathe' "$F")" -ge 3 ] && chk 08-e-npc-sheathed-before-and-after-load ok || chk 08-e-npc-sheathed-before-and-after-load bad "$(grep -c 'stobe_drawn sheathe' "$F")"
scen 08e-gate; U_BORED_TRIES=3 run 08-e $L >/dev/null
[ "$(grep -c 'u:stream' "$F")" = 3 ] && chk 08-e-tries-env-three-ticks ok || chk 08-e-tries-env-three-ticks bad "$(grep -c 'u:stream' "$F")"
scen 08e-gate; U_BORED_TRIES=1 run 08-e $L >/dev/null
[ "$(grep -c 'u:stream' "$F")" = 1 ] && chk 08-e-tries-env-one-tick ok || chk 08-e-tries-env-one-tick bad
scen 08d-pass; run 08-d $L >/dev/null
grep -q 'stobe-auto teleport .*-62380 330 16250 dist 350' "$F" && chk walk-staged-350-short-of-gate ok || chk walk-staged-350-short-of-gate bad
grep -q 'stobe-auto speed 2 ' "$F" && chk walk-speed-2 ok || chk walk-speed-2 bad
! grep -E 'stobe-auto order ' "$F" | grep -v 'order Shay' | grep -q . && chk walk-gives-the-npc-no-harness-order ok || chk walk-gives-the-npc-no-harness-order bad
[ "$(fl 'dist 350')" -lt "$(fl 'u:stream')" ] && chk 08-d-walk-before-tick ok || chk 08-d-walk-before-tick bad
grep -q 'completed=1' "$EVB/08-d/walk_done.txt" && chk walk-done-evidence ok || chk walk-done-evidence bad "$(cat "$EVB/08-d/walk_done.txt" 2>/dev/null)"
scen 08d-pass; TRIP_WALK_BACK=200 TRIP_WALK_SPEED=3 run 08-d $L >/dev/null
grep -q 'dist 200' "$F" && grep -q 'stobe-auto speed 3 ' "$F" && chk walk-env-overrides ok || chk walk-env-overrides bad
scen 11b-pass; run 11-b $L >/dev/null
grep -q "stobe-auto spawn \"Hungry Bandit\" 'Holy Nation Outlaws' near 'Cind \[Hungry Bandit\]' dist 20 count 1" "$F" && chk 11-b-enemy-spawned-near-npc ok || chk 11-b-enemy-spawned-near-npc bad
grep -q 'stobe-auto fight ' "$F" && [ "$(grep -c 'stobe-auto protect .* on' "$F")" -ge 2 ] && chk 11-b-both-protected-and-fight ok || chk 11-b-both-protected-and-fight bad
[ "$(grep -c 'u:stream' "$F")" = 3 ] && chk 11-b-three-ticks ok || chk 11-b-three-ticks bad "$(grep -c 'u:stream' "$F")"
grep -q 'no ctxpush' "$EVB/11-b/ctxpush.txt" && chk 11-b-first-tick-without-snapshot ok || chk 11-b-first-tick-without-snapshot bad
grep -q "stobe-auto teleport 'Vren \[Hungry Bandit\]' -53200 957 4893" "$F" && grep -q "order 'Cind \[Hungry Bandit\]' NULL_TASK" "$F" && chk 11-b-combat-ended-enemy-removed ok || chk 11-b-combat-ended-enemy-removed bad
[ "$(fl 'stobe-auto fight')" -lt "$(fl 'u:stream')" ] && chk 11-b-fight-before-first-tick ok || chk 11-b-fight-before-first-tick bad
scen 11b-pass; U11B_FACTION="Dust Bandits" U11B_DIST=40 run 11-b $L >/dev/null
grep -q "'Dust Bandits' near .* dist 40" "$F" && chk 11-b-env-overrides ok || chk 11-b-env-overrides bad

# --- CLI: unblockrun_a.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_a.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen 08e-pass; o=$(cli unblockrun_a.sh 08-e $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 08-e PASS' && [ $rc = 0 ] && chk cli-08e-one-result-line ok || chk cli-08e-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'stobe-auto load kah-imm26-4080-i4h' "$KAH_ROW_FAKE_LOG" && chk cli-4080-i4-default-ready-save ok || chk cli-4080-i4-default-ready-save bad
echo "$o" | grep -q '^EVIDENCE 08-e bored_ticks.txt ' && chk cli-evidence-line ok || chk cli-evidence-line bad
scen 08e-pass; o=$(cli unblockrun_a.sh 08-e $L --save my-save --allow-retry selftest); grep -q 'load my-save' "$KAH_ROW_FAKE_LOG" && chk cli-save-option ok || chk cli-save-option bad
scen 08e-pass; o=$(cli unblockrun_a.sh 08-e $L --no-reload --allow-retry selftest); ! grep -q 'stobe-auto load kah-imm26-4080-i4h' "$KAH_ROW_FAKE_LOG" && chk cli-no-reload ok || chk cli-no-reload bad
scen 08e-pass; o=$(cli unblockrun_a.sh 08-e $L --dry); echo "$o" | grep -q '^RESULT 08-e DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
scen 08e-http; o=$(cli unblockrun_a.sh 08-e $L --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 08-e SETUP-FAIL' && [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen 08e-double; o=$(cli unblockrun_a.sh 08-e $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
scen 08d-neg-pass; o=$(cli unblockrun_a.sh 08-d $L --neg --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 08-d PASS.*negative_trip_not_completed' && chk cli-08d-neg-flag ok || chk cli-08d-neg-flag bad "$(echo "$o" | tail -1 | cut -c1-300)"
scen 08d-pass; o=$(cli unblockrun_a.sh 08-d $L --back 150 --speed 3 --allow-retry selftest); grep -q 'dist 150' "$KAH_ROW_FAKE_LOG" && grep -q 'stobe-auto speed 3 ' "$KAH_ROW_FAKE_LOG" && chk cli-08d-back-speed-options ok || chk cli-08d-back-speed-options bad
scen 11b-pass; o=$(cli unblockrun_a.sh 11-b $L --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 11-b PASS' && chk cli-11b ok || chk cli-11b bad "$(echo "$o" | tail -1 | cut -c1-300)"
o=$(cli unblockrun_a.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not an unblock row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
o=$(cli unblockrun_a.sh 08-e nolane); echo "$o" | grep -q 'RESULT 08-e SETUP-FAIL PREFLIGHT-FAIL unknown lane' && chk cli-unknown-lane ok || chk cli-unknown-lane bad "$o"

# --- shim + isolation from the live operators' files
"$ST_HERE/unblockpy_a.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
grep -q 'unblockdefs_a\|rd_11b\|i4_bored' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/hunt26a-scene.sh" "$ST_HERE/reloaddefs_a.sh" 2>/dev/null && chk originals-not-hooked bad "an operator file references unblockdefs_a" || chk originals-not-hooked ok
for f in unblockdefs_a.sh unblockrun_a.sh unblockpy_a.sh unblock_a_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST UNBLOCK ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK ALL FAIL $ok/$n"; exit 1; fi
