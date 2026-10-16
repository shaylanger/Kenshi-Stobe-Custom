#!/usr/bin/env bash
# reload-a2-selftest.sh: OFFLINE self-test of the 08-e recipe v2 (reloaddefs_a2.sh, reload-run-a2.sh; imm26-sfG2). Scenario 08e-react: a fake server log whose only Cind request is a
# drawn-weapon reaction turn (react=drawn_weapon) and no claim. BEFORE (reloaddefs_a.sh only) the verdict blames the "server-side claim gate"; AFTER (a2 defs) it is the recipe verdict
# "NO tick with the NPC as speaker". Also: a real director tick without a claim still blames the server gate; the pass path still passes; the chunk loop re-quiets/sheathes/holds each chunk;
# counters (cind_ticks / cind_ticks_react / cind_ticks_log) have the right content; reload-run-a2.sh runs as a separate process.  Usage: bash rowtools/reload-a2-selftest.sh
# Prints `SELFTEST reload-a2-<name> PASS|FAIL` and `SELFTEST RELOAD-A2 ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json" FAKE_SRVLOG="$T/srv.log"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_ADV RW_TICK_CHUNKS
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST reload-a2-$1 PASS ${3:-}"; else echo "SELFTEST reload-a2-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"
PY="$ST_HERE/reload-py.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/reloadfake_a2.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EVB="$KAH_ROWS_BASE/imm26-5090-i3/rows"
# srvlog <kind>: 100 filler lines (before the load) + the post-load lines of the case
srvlog() {
  { for i in $(seq 1 100); do echo "2026-10-16 08:00:00 old line $i profile=Cind&mode=autochat before the load"; done
    case "$1" in
      react) echo '2026-10-16 16:19:23 req_6ad GET /x?profile=Cind&mode=autochat&gamets=283395&react=drawn_weapon&react_kind=warn&react_detail=Machete'
             echo '2026-10-16 16:19:23 Drawn weapon reaction turn {speaker Cind, listener Shay, kind warn, weapon Machete, meters 1}'
             echo '2026-10-16 16:19:30 req_7 GET /x?profile=Bong&mode=director&gamets=283400'
             echo '2026-10-16 16:19:30 Director bored turn claimed a social remark {speaker Bong}';;
      director) echo '2026-10-16 16:19:23 req_9 GET /x?profile=Cind&mode=director&gamets=283395'
                echo '2026-10-16 16:19:24 Targeted optional request: nothing claimable';;
      none) echo '2026-10-16 16:19:30 req_7 GET /x?profile=Bong&mode=director&gamets=283400';;
    esac; } > "$FAKE_SRVLOG"
}
verdict() { run 08-e $L; }

# --- BEFORE (old definitions): the reaction-only log blames the server claim gate (the defect)
scen 08e-noclaim; srvlog react; r=$(verdict)
echo "$r" | grep -q 'RESULT 08-e SETUP-FAIL' && echo "$r" | grep -q 'server-side claim gate' && chk old-defs-blame-server-gate ok || chk old-defs-blame-server-gate bad "$(echo "$r" | cut -c1-300)"

. "$ST_HERE/reloaddefs_a2.sh"
# --- AFTER: 08e-react = reaction tick only, no claim -> recipe verdict
scen 08e-noclaim; srvlog react; r=$(verdict)
echo "$r" | grep -q 'RESULT 08-e SETUP-FAIL' && echo "$r" | grep -q 'NO tick with the NPC as speaker' && ! echo "$r" | grep -q 'server-side claim gate' && echo "$r" | grep -q 'needs: recipe' && chk 08e-react-recipe-verdict ok || chk 08e-react-recipe-verdict bad "$(echo "$r" | cut -c1-300)"
EV="$EVB/08-e"
[ "$(cat "$EV/cind_ticks.txt" 2>/dev/null)" = 0 ] && chk counter-claim-capable-ticks-0 ok || chk counter-claim-capable-ticks-0 bad "$(cat "$EV/cind_ticks.txt" 2>/dev/null)"
[ "$(cat "$EV/cind_ticks_react.txt" 2>/dev/null)" = 1 ] && chk counter-react-ticks-1 ok || chk counter-react-ticks-1 bad "$(cat "$EV/cind_ticks_react.txt" 2>/dev/null)"
grep -q 'Drawn weapon reaction turn' "$EV/cind_ticks_log.txt" && grep -q 'Director bored turn claimed' "$EV/cind_ticks_log.txt" && ! grep -q 'GET /x' "$EV/cind_ticks_log.txt" && ! grep -q 'old line' "$EV/cind_ticks_log.txt" && chk log-has-server-lines-not-uri ok || chk log-has-server-lines-not-uri bad "$(cut -c1-200 "$EV/cind_ticks_log.txt")"
# --- a real director tick with no claim still blames the server gate (the verdict is not just muted)
scen 08e-noclaim; srvlog director; r=$(verdict)
echo "$r" | grep -q 'RESULT 08-e SETUP-FAIL' && echo "$r" | grep -q 'server-side claim gate' && chk 08e-director-noclaim-still-server-gate ok || chk 08e-director-noclaim-still-server-gate bad "$(echo "$r" | cut -c1-300)"
[ "$(cat "$EV/cind_ticks.txt")" = 1 ] && [ "$(cat "$EV/cind_ticks_react.txt")" = 0 ] && chk counter-director-1-react-0 ok || chk counter-director-1-react-0 bad
# --- no Cind request at all
scen 08e-noclaim; srvlog none; r=$(verdict)
echo "$r" | grep -q 'NO tick with the NPC as speaker' && chk 08e-none-recipe-verdict ok || chk 08e-none-recipe-verdict bad "$(echo "$r" | cut -c1-300)"
# --- pass path unchanged
scen 08e-pass; srvlog director; r=$(verdict)
echo "$r" | grep -q 'RESULT 08-e PASS' && echo "$r" | grep -q 'claimed_once_after_reload' && chk 08e-pass-still-passes ok || chk 08e-pass-still-passes bad "$(echo "$r" | cut -c1-300)"
scen 08e-lost; srvlog director; r=$(verdict)
echo "$r" | grep -q 'RESULT 08-e FAIL' && chk 08e-lost-still-fails ok || chk 08e-lost-still-fails bad "$(echo "$r" | cut -c1-200)"
# --- recipe: every chunk re-quiets, sheathes and holds; 16 chunks of 30 s when nothing claims
scen 08e-noclaim; srvlog react; run 08-e $L >/dev/null
F="$KAH_ROW_FAKE_LOG"
hp=$(grep -c 'HOLD_POSITION keep' "$F"); sh=$(grep -c "stobe_drawn sheathe '.*Cind" "$F"); sp=$(grep -c 'sleep 30$' "$F")
[ "$hp" = 16 ] && chk recipe-hold-position-each-chunk ok || chk recipe-hold-position-each-chunk bad "count=$hp"
[ "$sh" -ge 17 ] && chk recipe-sheathe-each-chunk ok || chk recipe-sheathe-each-chunk bad "count=$sh"
[ "$sp" = 16 ] && chk recipe-adv-30s-x16 ok || chk recipe-adv-30s-x16 bad "sleep30 count=$sp"
tq=$(grep -c 'stobe-auto teleport Malzin Shay' "$F"); [ "$tq" -ge 18 ] && chk recipe-tr-quiet-each-chunk ok || chk recipe-tr-quiet-each-chunk bad "tr_quiet count=$tq"
! grep -q 'i4_bored\|bored_08e' "$F" && chk recipe-no-targeted-tick ok || chk recipe-no-targeted-tick bad
# the >= 31 s real wait after the s2 chat: rd_08e calls rw_sleep with the 31 s default between the s2 chat and the chunk loop (rw_sleep is a no-op in fake mode, so check the order in the body)
declare -f rd_08e | tr '\n' ' ' | grep -q 'rl_say 2 .*rw_sleep "\${RW_08E_GATE_WAIT:-31}".*seq 1' && chk recipe-sleep-31-after-s2 ok || chk recipe-sleep-31-after-s2 bad
declare -f rd_08e | grep -q 'RW_ADV:-30' && declare -f rd_08e | grep -q 'RW_TICK_CHUNKS:-16' && chk recipe-defaults-adv30-chunks16 ok || chk recipe-defaults-adv30-chunks16 bad
# --- CLI: separate process
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_a2.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/reload-run-a2.sh' \"\$@\"" _ "$@" 2>/dev/null; }
scen 08e-noclaim; srvlog react; o=$(cli 08-e $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | grep -q 'RESULT 08-e SETUP-FAIL.*NO tick with the NPC as speaker' && [ $rc = 2 ] && chk cli-reload-run-a2 ok || chk cli-reload-run-a2 bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen 26d-pass; o=$(cli 26-d $L --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && chk cli-other-rows-unchanged ok || chk cli-other-rows-unchanged bad "$(echo "$o" | tail -1 | cut -c1-200)"
# --- originals untouched
(cd "$A" && git diff --quiet -- rowtools/reloaddefs_a.sh rowtools/reloadcheck_a.py rowtools/reload-run.sh) && chk originals-unmodified ok || chk originals-unmodified bad
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST RELOAD-A2 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST RELOAD-A2 ALL FAIL $ok/$n"; exit 1; fi
