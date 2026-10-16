#!/usr/bin/env bash
# unblock_sfk_selftest.sh: OFFLINE self-test of the sfK2 recipe v2 for rows 23-a and 11-b (tripdefs_sfk.sh / unblockdefs_sfk.sh / unblockrun_sfk.sh; checkers unchanged: rowcheck.py 23-a,
# unblockcheck_a.py 11-b via unblockpy_a.sh). No game, ssh, WSL or DB: lanes are simulated by unblockfake_sfk.py with scenarios from unblockscen_sfk.py. For every defect scenario the
# exact failing checks / SETUP-FAIL text is asserted, plus recipe statements (gate, real walk, no harness order, serial addressing, no time advance, claimable edit after combat is proven).
# FAST: run in WSL: wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_sfk_selftest.sh
# Prints `SELFTEST sfk-<name> PASS|FAIL` lines and `SELFTEST SFK ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 SFK_23A_TRIES=3 U11B_CALM_TRIES=2 SFK_KO_WAIT=1 SFK_23A_WAIT=10
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT SFK_23A_BACK SFK_23A_SPEED U11B_FACTION U11B_DIST SFK_SQUIN_GATE
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfk-$1 PASS ${3:-}"; else echo "SELFTEST sfk-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/tripdefs_sfk.sh"; . "$ST_HERE/unblockdefs_sfk.sh"
PY="$ST_HERE/unblockpy_a.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sfk.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sfk.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
bad_set() {
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import unblockcheck_a as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
# expect <name> <scenario> <row> <RESULT prefix> [11-b FAIL: exact failing-check set | other: substring that must occur in the line]
expect() {
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ "$pre" = "RESULT $row FAIL" ] && [ "$row" = 11-b ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}

# ------------------------------------------------------------------ 23-a
expect 23-a-pass sfk23-pass 23-a "RESULT 23-a PASS"
expect 23-a-destpoint-gate-used sfk23-destpoint 23-a "RESULT 23-a PASS"
grep -q -- '-100 200 -300 dist 400' "$F" && chk 23-a-agreement-destination-point-preferred ok || chk 23-a-agreement-destination-point-preferred bad "$(grep -m2 'dist 400' "$F" | cut -c1-120)"
expect 23-a-ko-recovers-passes sfk23-ko-recovers 23-a "RESULT 23-a PASS"
grep -q 'events_since_walk_start=2' "$EVB/23-a/shay_guard.txt" 2>/dev/null && grep -q 'after_wait=2' "$EVB/23-a/shay_guard.txt" && chk 23-a-guard-evidence ok || chk 23-a-guard-evidence bad
expect 23-a-shay-still-attacked-setup-fail-before-say sfk23-ko-attacked 23-a "RESULT 23-a SETUP-FAIL" "still being attacked"
[ "$(grep -c 'stobe_say' "$F")" -le 2 ] && chk 23-a-no-arrival-say-when-shay-down ok || chk 23-a-no-arrival-say-when-shay-down bad "say count $(grep -c 'stobe_say' "$F")"
expect 23-a-no-native-arrival-setup-fail sfk23-timeout 23-a "RESULT 23-a SETUP-FAIL" "no native arrival"
expect 23-a-agreement-failed-is-a-real-fail sfk23-failed 23-a "RESULT 23-a FAIL" "agreement_COMPLETED=FAILED"
scen sfk23-pass; run 23-a $L >/dev/null
grep -q -- '-62461 328.779 16346.8 dist 400' "$F" && ! grep -q -- '-62380 330 16250' "$F" && chk 23-a-default-gate-is-agreement-point-not-y330 ok || chk 23-a-default-gate-is-agreement-point-not-y330 bad
! grep -E 'stobe-auto order ' "$F" | grep -v 'order Shay' | grep -q . && chk 23-a-npc-gets-no-harness-order ok || chk 23-a-npc-gets-no-harness-order bad
[ "$(fl 'dist 400')" -lt "$(grep -n 'stobe_say' "$F" | sed -n 3p | cut -d: -f1)" ] && chk 23-a-walk-staged-before-arrival-say ok || chk 23-a-walk-staged-before-arrival-say bad
grep -q 'stobe-auto speed 1 ' "$F" && chk 23-a-walk-speed-1 ok || chk 23-a-walk-speed-1 bad
grep -q 'end=ARRIVED' "$EVB/23-a/arrival.txt" && chk 23-a-arrival-evidence ok || chk 23-a-arrival-evidence bad "$(cat "$EVB/23-a/arrival.txt" 2>/dev/null)"
scen sfk23-pass; TRIP_GATE="1 2 3" run 23-a $L >/dev/null
grep -q -- '1 2 3 dist 400' "$F" && chk 23-a-explicit-gate-wins ok || chk 23-a-explicit-gate-wins bad
scen sfk23-pass; SFK_23A_BACK=250 SFK_23A_SPEED=2 run 23-a $L >/dev/null
grep -q 'dist 250' "$F" && grep -q 'stobe-auto speed 2 ' "$F" && chk 23-a-env-overrides ok || chk 23-a-env-overrides bad

# ------------------------------------------------------------------ 11-b
expect 11-b-pass sfk11-pass 11-b "RESULT 11-b PASS" "exactly_one_claim_after_combat"
expect 11-b-claim-in-combat-no-snapshot sfk11-claim-nosnap 11-b "RESULT 11-b FAIL" "ask_count_unchanged_in_combat,no_claim_in_combat_without_snapshot"
expect 11-b-crowded-scene-setup-fail sfk11-crowded 11-b "RESULT 11-b SETUP-FAIL" "scene not isolated"
expect 11-b-spawn-without-serial-setup-fail sfk11-spawn-noserial 11-b "RESULT 11-b SETUP-FAIL" "no #serial"
expect 11-b-calm-teleport-wrong-enemy-setup-fail sfk11-calm-wrong-enemy 11-b "RESULT 11-b SETUP-FAIL" "calm teleport did not move the spawned enemy #77/1"
expect 11-b-fight-not-started-setup-fail sfk11-fight-fail 11-b "RESULT 11-b SETUP-FAIL" "fight command did not start"
expect 11-b-claimable-edit-failed-setup-fail sfk11-update-fail 11-b "RESULT 11-b SETUP-FAIL" "could not make the topic claimable"
expect 11-b-combat-never-ended-setup-fail sfk11-nocalm 11-b "RESULT 11-b SETUP-FAIL" "combat did not end"
expect 11-b-recombat-setup-fail sfk11-recombat 11-b "RESULT 11-b SETUP-FAIL" "re-engaged"
scen sfk11-pass; run 11-b $L >/dev/null
grep -q "stobe-auto spawn \"Hungry Bandit\" 'Dust Bandits' near 'Cind \[Hungry Bandit\]' dist 20 count 1" "$F" && chk 11-b-enemy-faction-dust-bandits-not-hno ok || chk 11-b-enemy-faction-dust-bandits-not-hno bad
grep -q "stobe-auto protect '#77/1' on" "$F" && grep -q "stobe-auto fight 'Cind \[Hungry Bandit\]' '#77/1'" "$F" && chk 11-b-enemy-addressed-by-serial ok || chk 11-b-enemy-addressed-by-serial bad
grep -q "stobe-auto teleport '#77/1' -53200 957 4893" "$F" && chk 11-b-calm-teleports-the-spawned-serial ok || chk 11-b-calm-teleports-the-spawned-serial bad
! grep -q 'stobe-auto speed 10' "$F" && chk 11-b-no-time-advance ok || chk 11-b-no-time-advance bad
[ "$(grep -c 'u:stream' "$F")" = 3 ] && chk 11-b-three-ticks ok || chk 11-b-three-ticks bad "$(grep -c 'u:stream' "$F")"
[ "$(fl 'stobe-auto fight')" -lt "$(fl 'update eventlog')" ] && [ "$(fl 'update eventlog')" -lt "$(fl 'u:stream')" ] && chk 11-b-claimable-edit-after-fight-before-first-tick ok || chk 11-b-claimable-edit-after-fight-before-first-tick bad
grep -q "regexp_replace(data,'\"not_before_gamets\":\[0-9\]+','\"not_before_gamets\":1')" "$F" && chk 11-b-update-only-touches-not_before ok || chk 11-b-update-only-touches-not_before bad
[ "$(grep -c 'stobe-auto chars' "$F")" -ge 3 ] && [ "$(fl 'stobe-auto chars')" -lt "$(fl 'stobe-auto spawn')" ] && chk 11-b-scene-cleared-and-checked-before-spawn ok || chk 11-b-scene-cleared-and-checked-before-spawn bad "chars calls $(grep -c 'stobe-auto chars' "$F")"
grep -q 'not_before_gamets":1[,}]' "$EVB/11-b/fu_pre.txt" && grep -q 'not_before_gamets":3600' "$EVB/11-b/fu_pre0.txt" && chk 11-b-fu_pre-redumped-and-original-kept ok || chk 11-b-fu_pre-redumped-and-original-kept bad
[ -s "$EVB/11-b/calm_poll.txt" ] && grep -q 'in_combat=false' "$EVB/11-b/calm_poll.txt" && chk 11-b-calm-poll-evidence ok || chk 11-b-calm-poll-evidence bad "$(cat "$EVB/11-b/calm_poll.txt" 2>/dev/null)"
grep -q 'no ctxpush' "$EVB/11-b/ctxpush.txt" && chk 11-b-first-tick-without-snapshot ok || chk 11-b-first-tick-without-snapshot bad
scen sfk11-pass; U11B_FACTION="Skin Bandits" U11B_DIST=40 run 11-b $L >/dev/null
grep -q "'Skin Bandits' near .* dist 40" "$F" && chk 11-b-env-overrides ok || chk 11-b-env-overrides bad

# ------------------------------------------------------------------ CLI: unblockrun_sfk.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_sfk.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen sfk23-pass; o=$(cli unblockrun_sfk.sh 23-a $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 23-a PASS' && [ $rc = 0 ] && chk cli-23a-one-result-line ok || chk cli-23a-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'stobe-auto load kah-imm26-4080-i4h' "$F" && chk cli-4080-i4-default-ready-save ok || chk cli-4080-i4-default-ready-save bad
echo "$o" | grep -q '^EVIDENCE 23-a arrival.txt ' && chk cli-evidence-line ok || chk cli-evidence-line bad
scen sfk23-pass; o=$(cli unblockrun_sfk.sh 23-a $L --no-reload --gate "7 8 9" --back 123 --speed 3 --allow-retry selftest); grep -q '7 8 9 dist 123' "$F" && grep -q 'stobe-auto speed 3 ' "$F" && ! grep -q 'stobe-auto load kah-imm26-4080-i4h' "$F" && chk cli-23a-options ok || chk cli-23a-options bad
scen sfk11-pass; o=$(cli unblockrun_sfk.sh 11-b $L --allow-retry selftest --faction "Skin Bandits" --calm-tries 1); echo "$o" | tail -1 | grep -q '^RESULT 11-b PASS' && grep -q "'Skin Bandits'" "$F" && chk cli-11b ok || chk cli-11b bad "$(echo "$o" | tail -1 | cut -c1-300)"
scen sfk11-crowded; o=$(cli unblockrun_sfk.sh 11-b $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen sfk23-failed; o=$(cli unblockrun_sfk.sh 23-a $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
scen sfk11-pass; o=$(cli unblockrun_sfk.sh 11-b $L --dry); echo "$o" | grep -q '^RESULT 11-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
o=$(cli unblockrun_sfk.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not an sfK row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
o=$(cli unblockrun_sfk.sh 23-a nolane); echo "$o" | grep -q 'RESULT 23-a SETUP-FAIL PREFLIGHT-FAIL unknown lane' && chk cli-unknown-lane ok || chk cli-unknown-lane bad "$o"

# ------------------------------------------------------------------ isolation from the live operators' files
for f in unblockdefs_sfk.sh tripdefs_sfk.sh unblockrun_sfk.sh unblock_sfk_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
grep -q 'unblockdefs_sfk\|tripdefs_sfk' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/unblockdefs_a.sh" "$ST_HERE/unblockcheck_a.py" "$ST_HERE/reloaddefs_a.sh" 2>/dev/null && chk originals-not-hooked bad "an operator file references the sfk files" || chk originals-not-hooked ok
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- tripdefs.sh unblockdefs_a.sh unblockcheck_a.py unblockrun_a.sh unblockpy_a.sh rowdefs.sh && chk queued-scripts-unmodified ok || chk queued-scripts-unmodified bad "git diff shows an edit"
fi

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFK ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFK ALL FAIL $ok/$n"; exit 1; fi
