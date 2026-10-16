#!/usr/bin/env bash
# reload-sfp-selftest.sh (imm26-sfP2): OFFLINE selftest of reloaddefs_sfp.sh / reload-run-sfp.sh (rl_say waits for non-Shay (NPC)|(PC) lines). No game, ssh, WSL or DB (fake transport as
# reload-sfo-selftest.sh). Prints `SELFTEST sfp-<name> PASS|FAIL` and `SELFTEST SFP ALL PASS|FAIL n/m`. Usage: bash rowtools/reload-sfp-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_FACTION RW_REFACTION RW_APOLOGY RW_GOATS RW_PIN_GOATS RW_OFFER2 RW_INJECT_PROPOSE RW_INJECT_TARGET RW_INJECT_TTL
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfp-$1 PASS ${3:-}"; else echo "SELFTEST sfp-$1 FAIL ${3:-}"; fi; }
L=5090-i3; F="$KAH_ROW_FAKE_LOG"
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sfi"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sfi.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sfi.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
# 1. runner: PASS, one RESULT line, rl_say heredoc carries the (NPC|PC) wait
scen 26d-pass; o=$(cli reload-run-sfp.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && [ $rc = 0 ] && [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && chk run-26d-pass ok || chk run-26d-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q '(NPC|PC)' "$F" && chk say-wait-npc-or-pc ok || chk say-wait-npc-or-pc bad
for r in 26-dx 26-e; do
  case $r in 26-dx) sc=26dx-pass;; *) sc=26e-pass;; esac
  scen $sc; o=$(cli reload-run-sfp.sh $r $L --allow-retry selftest); rc=$?
  echo "$o" | tail -1 | grep -q "^RESULT $r PASS" && chk run-$r-pass ok || chk run-$r-pass bad "rc=$rc $(echo "$o" | cut -c1-200)"
done
# 2. sfo inject option still works through the sfp runner (sfp builds on sfo)
scen 26d-pass; o=$(cli reload-run-sfp.sh 26-d $L --inject Hunt --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && grep -q 'STOBE_TEST_ACTIVITY_INJECT_V1' "$F" && chk inject-passthrough ok || chk inject-passthrough bad "rc=$rc"
# 3. other rows refused
o=$(cli reload-run-sfp.sh 26-f $L); echo "$o" | grep -q 'RESULT 26-f SETUP-FAIL not a hunt reload row' && chk other-rows-refused ok || chk other-rows-refused bad
# 4. the wait predicate itself, evaluated on sample logs (the exact line from reloaddefs_sfp.sh)
line=$(grep -m1 'tail -n +' "$ST_HERE/reloaddefs_sfp.sh"); pred=${line#*sleep 2; }; pred=${pred%% && \{*}; pred=${pred//\\$/\$}
mk() { printf '%s\n' "$@" > "$T/log.txt"; }
W() { n0=0; L="$T/log.txt"; eval "$pred" && echo hit || echo miss; }
mk 'ACTION_EXEC: SAY [Cind]: hello there (PC)';  [ "$(W)" = hit ]  && chk wait-pc-line ok  || chk wait-pc-line bad "pred=$pred"
mk 'ACTION_EXEC: SAY [Cind]: hello there (NPC)'; [ "$(W)" = hit ]  && chk wait-npc-line ok || chk wait-npc-line bad
mk 'ACTION_EXEC: SAY [Shay]: hi (PC)';           [ "$(W)" = miss ] && chk wait-ignores-shay ok || chk wait-ignores-shay bad
mk 'ACTION_EXEC: SAY [Shay]: hi (PC)' 'ACTION_EXEC: SAY [Cind]: yo (PC)'; [ "$(W)" = hit ] && chk wait-shay-then-npc ok || chk wait-shay-then-npc bad
mk 'unrelated line' 'ACTION_EXEC: ATTACK [Cind]'; [ "$(W)" = miss ] && chk wait-ignores-other ok || chk wait-ignores-other bad
# 5. original files untouched / not hooked
grep -q 'reloaddefs_sfp\|reload-run-sfp' "$ST_HERE/rowlib.sh" "$ST_HERE/reloaddefs_sfi.sh" "$ST_HERE/reloaddefs_sfo.sh" "$ST_HERE/reload-run-sfi.sh" "$ST_HERE/reload-run-sfo.sh" && chk originals-not-hooked bad || chk originals-not-hooked ok
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFP ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFP ALL FAIL $ok/$n"; exit 1; fi
