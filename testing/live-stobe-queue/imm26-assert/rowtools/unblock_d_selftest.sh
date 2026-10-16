#!/usr/bin/env bash
# unblock_d_selftest.sh: OFFLINE self-test of row 03-b (unblockdefs_d.sh / unblockcheck_d.py / unblockrun_d.sh / unblockpy_d.sh).
# No game, ssh, WSL or DB: lanes are simulated by unblockfake_d.py (-> unblockfake_a.py -> reloadfake.py -> tripfake.py -> fakelane.py) with scenarios from unblockscen_d.py.
# For every defect scenario the EXACT set of failing checks is asserted, plus recipe statements (sparse B choice, B kept away during the attack, request shape without optional=1,
# listener = B, chance 100 set + restored, retry until the heard_from row exists, push before the question).
# FAST: run in WSL (WSL python3, ~5 min; Git Bash/Windows python is ~10x slower): wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_d_selftest.sh
# Prints `SELFTEST unblockd-<name> PASS|FAIL` lines and `SELFTEST UNBLOCK-D ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_d_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 RW_SAY_WAIT=0 U03B_ATTACK_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST U03B_B U03B_TRIES U03B_MAX_ROWS U03B_NO_ATTACK U03B_DEMOTE
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblockd-$1 PASS ${3:-}"; else echo "SELFTEST unblockd-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/unblockdefs_d.sh"
PY="$ST_HERE/unblockpy_d.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_d.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub" "$FAKE_STATE.ud"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_d.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
bad_set() {
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import unblockcheck_d as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
expect() {  # expect <name> <scenario> <RESULT prefix> [FAIL: exact failing-check set | other: substring that must occur in the line]
  local name="$1" sc="$2" pre="$3" want="${4-}" r ev got
  scen "$sc"; r=$(run 03-b "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ "$pre" = "RESULT 03-b FAIL" ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set 03-b "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}

expect 03-b-pass 03b-pass "RESULT 03-b PASS" "prompt_shows_hearsay_attributed_to_Cind"
expect 03-b-pass-after-retry 03b-retry "RESULT 03-b PASS" "g2=gossip"
expect 03-b-prompt-without-hearsay 03b-noprompt "RESULT 03-b FAIL" "prompt_shows_hearsay_attributed_to_Cind"
expect 03-b-gossip-only-via-director 03b-director "RESULT 03-b FAIL" "gossip_logged_for_B_by_autochat_not_director"
expect 03-b-pair-never-formed-setup-fail 03b-never "RESULT 03-b SETUP-FAIL" "never produced a heard_from row"
expect 03-b-request-failed-setup-fail 03b-http "RESULT 03-b SETUP-FAIL" "every targeted pair request failed"
expect 03-b-no-sparse-b-setup-fail 03b-no-b "RESULT 03-b SETUP-FAIL" "no sparse B"
expect 03-b-busy-holders-only-setup-fail 03b-busy-only "RESULT 03-b SETUP-FAIL" "no sparse B"
expect 03-b-no-cind-row-setup-fail 03b-no-crow "RESULT 03-b SETUP-FAIL" "no active first-hand social_rumor row"

# --- recipe statements (fake-lane transcript)
F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
fll() { grep -n -- "$1" "$F" | tail -1 | cut -d: -f1; }
scen 03b-retry; run 03-b $L >/dev/null
EV3="$EVB/03-b"
[ "$(cat "$EV3/b.txt" 2>/dev/null)" = "Wren [Trader]" ] && chk b-is-the-sparse-awake-non-slave-digit-serial-npc ok || chk b-is-the-sparse-awake-non-slave-digit-serial-npc bad "$(cat "$EV3/b.txt" 2>/dev/null)"
grep -q 'stream.php?DATA=\$D&profile=Cind' "$F" && grep -q 'mode=autochat' "$F" && grep -q 'people=' "$F" && chk pair-request-shape ok || chk pair-request-shape bad
! grep -q 'optional=1' "$F" && chk pair-request-has-no-optional-1 ok || chk pair-request-has-no-optional-1 bad
grep -q 'talking to: %s)' "$F" && grep -q '"Cind \[Hungry Bandit\]" "Wren \[Trader\]" "Shay"' "$F" && chk listener-is-B-in-event-and-people ok || chk listener-is-B-in-event-and-people bad
[ "$(grep -c 'u3:stream' "$F")" = 2 ] && chk retry-stops-at-first-heard-from-row ok || chk retry-stops-at-first-heard-from-row bad "$(grep -c 'u3:stream' "$F")"
grep -q "update general_settings set value='100' where id='BORED_EVENT_CHANCE'" "$F" && [ "$(fl "BORED_EVENT_CHANCE")" -lt "$(fl 'u3:stream')" ] && chk chance-100-before-first-request ok || chk chance-100-before-first-request bad
grep -q "delete from general_settings where id='BORED_EVENT_CHANCE'" "$F" && chk chance-restored-to-unset ok || chk chance-restored-to-unset bad
grep -q "stobe-auto teleport 'Wren \[Trader\]' -53200 957 4893" "$F" && [ "$(fl "teleport 'Wren \[Trader\]' -53200")" -lt "$(fl 'stobe-auto hit Shay Malzin head 130')" ] && chk B-sent-away-before-the-attack ok || chk B-sent-away-before-the-attack bad
grep -q 'protect .Malzin. off\|protect Malzin off' "$F" && [ "$(fl 'hit Shay Malzin')" -lt "$(fl 'u3:stream')" ] && chk attack-before-pair-request ok || chk attack-before-pair-request bad
[ "$(fl "teleport 'Wren \[Trader\]' Shay")" -gt "$(fll 'u3:stream')" ] && chk B-brought-back-after-last-request ok || chk B-brought-back-after-last-request bad
[ "$(awk '/stobe_ctxpush/{p=1} /stobe_say/{if(!p)bad++} END{print bad+0}' "$F")" = 0 ] && grep -q 'stobe_say' "$F" && chk push-before-the-question ok || chk push-before-the-question bad
grep -q "update social_rumor set game_ts=5000" "$F" && chk cind-row-made-newest ok || chk cind-row-made-newest bad
! grep -q "superseded_03b" "$F" && chk no-demotion-when-in-top-8 ok || chk no-demotion-when-in-top-8 bad
grep -q 'Have you heard anything about me' "$F" && chk question-text ok || chk question-text bad
scen 03b-demote; run 03-b $L >/dev/null
grep -q "set status='superseded_03b'" "$F" && [ -s "$EV3/superseded.txt" ] && chk demote-outranking-rows-when-not-in-top-8 ok || chk demote-outranking-rows-when-not-in-top-8 bad
scen 03b-pass; U03B_DEMOTE=0 run 03-b $L >/dev/null; scen 03b-demote; U03B_DEMOTE=0 run 03-b $L >/dev/null
! grep -q "superseded_03b" "$F" && chk demote-switch-off ok || chk demote-switch-off bad
scen 03b-pass; U03B_NO_ATTACK=1 run 03-b $L >/dev/null
! grep -q 'hit Shay Malzin' "$F" && chk no-attack-switch ok || chk no-attack-switch bad
scen 03b-pass; U03B_B="Stavna [Pacifier Ainsley]" run 03-b $L >/dev/null
grep -q '"Cind \[Hungry Bandit\]" "Stavna \[Pacifier Ainsley\]"' "$F" && ! grep -q 'u3:chars' "$F" && chk forced-b-skips-the-search ok || chk forced-b-skips-the-search bad
scen 03b-never; U03B_TRIES=2 run 03-b $L >/dev/null
[ "$(grep -c 'u3:stream' "$F")" = 2 ] && chk tries-env ok || chk tries-env bad "$(grep -c 'u3:stream' "$F")"

# --- CLI: unblockrun_d.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_d.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen 03b-pass; o=$(cli unblockrun_d.sh 03-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 03-b PASS' && [ $rc = 0 ] && chk cli-03b-one-result-line ok || chk cli-03b-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'stobe-auto load kah-imm26-4080-i4h' "$KAH_ROW_FAKE_LOG" && chk cli-4080-i4-default-ready-save ok || chk cli-4080-i4-default-ready-save bad
echo "$o" | grep -q '^EVIDENCE 03-b b.txt ' && chk cli-evidence-line ok || chk cli-evidence-line bad
scen 03b-pass; o=$(cli unblockrun_d.sh 03-b $L --no-reload --b "Stavna [X]" --tries 3 --allow-retry selftest); ! grep -q 'stobe-auto load kah' "$KAH_ROW_FAKE_LOG" && grep -q '"Cind \[Hungry Bandit\]" "Stavna \[X\]"' "$KAH_ROW_FAKE_LOG" && chk cli-no-reload-and-b-option ok || chk cli-no-reload-and-b-option bad
scen 03b-pass; o=$(cli unblockrun_d.sh 03-b $L --dry); echo "$o" | grep -q '^RESULT 03-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
scen 03b-never; o=$(cli unblockrun_d.sh 03-b $L --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 03-b SETUP-FAIL' && [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen 03b-noprompt; o=$(cli unblockrun_d.sh 03-b $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
o=$(cli unblockrun_d.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not a rowtools-03b row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
o=$(cli unblockrun_d.sh 03-b nolane); echo "$o" | grep -q 'RESULT 03-b SETUP-FAIL PREFLIGHT-FAIL unknown lane' && chk cli-unknown-lane ok || chk cli-unknown-lane bad "$o"

# --- shim + isolation from the live operators' files
"$ST_HERE/unblockpy_d.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
grep -q 'unblockdefs_d\|rd_03b\|i4_gossip' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/hunt26a-scene.sh" "$ST_HERE/reloaddefs_a.sh" "$ST_HERE/unblockdefs_a.sh" "$ST_HERE/unblockrun_a.sh" 2>/dev/null && chk originals-not-hooked bad "an operator file references unblockdefs_d" || chk originals-not-hooked ok
for f in unblockdefs_d.sh unblockrun_d.sh unblockpy_d.sh unblock_d_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST UNBLOCK-D ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-D ALL FAIL $ok/$n"; exit 1; fi
