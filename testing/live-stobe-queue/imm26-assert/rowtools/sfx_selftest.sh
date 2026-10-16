#!/usr/bin/env bash
# sfx_selftest.sh: OFFLINE self-test of 12-d v2 (sfxdefs.sh / sfxcheck.py / sfxrun.sh / sfxfake.py / sfxscen.py, imm26-sfX). No game, ssh, WSL-only tools or DB:
# the lane is simulated by sfxfake.py (-> fakelane.py) with scenarios from sfxscen.py. Run in WSL or Git Bash:
#   bash rowtools/sfx_selftest.sh        (from testing/live-stobe-queue/imm26-assert)
# Prints `SELFTEST sfx-<name> PASS|FAIL` and `SELFTEST SFX ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 RW_SAY_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY SFX_ASKS SFX_NPC2 SFX_AFF_CTL
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfx-$1 PASS ${3:-}"; else echo "SELFTEST sfx-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/sfxdefs.sh"
PY=sfx_py
lt_fake() { "$REAL_PY" "$ST_HERE/sfxfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/sfxscen.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EV12="$KAH_ROWS_BASE/imm26-5090-i3/rows/12-d"
# --- the originals this ticket must not touch
BADORIG=""; for f in rowdefs.sh rowcheck.py rowlib.sh lane.sh; do git -C "$ST_HERE" diff --quiet HEAD -- "$f" 2>/dev/null || BADORIG="$BADORIG $f"; done
git -C "$A" diff --quiet HEAD -- go-row.sh 2>/dev/null || BADORIG="$BADORIG go-row.sh"
[ -z "$BADORIG" ] && chk originals-untouched ok || chk originals-untouched bad "differs from HEAD:$BADORIG"
# --- PASS: s3 transfers; stale s1 line before s2's own send is not shown as the s2 reply; gate line seen at aff40
scen pass-s3; r=$(run 12-d $L)
case "$r" in "RESULT 12-d PASS"*) chk pass-s3 ok;; *) chk pass-s3 bad "$(echo "$r" | cut -c1-500)";; esac
echo "$r" | grep -q "aff85_transferred=s3 shay_gained={'Katana': 1}" && chk transfer-step-named ok || chk transfer-step-named bad "$r"
echo "$r" | grep -q "aff40_gate_log=exercised (Blocked low-trust outsider)" && chk real-gate-line-detected ok || chk real-gate-line-detected bad "$r"
echo "$r" | grep -q "s2: 'Still no, my blade is my life.' (+1 stale line(s)" && ! echo "$r" | grep -q "s2: 'If you need a weapon" && chk stale-line-not-the-s2-reply ok || chk stale-line-not-the-s2-reply bad "$r"
[ ! -d "$EV12/s4" ] && [ -d "$EV12/s3" ] && grep -q 'transfer at s3' "$EV12/sfx_mark.txt" && chk stops-asking-after-transfer ok || chk stops-asking-after-transfer bad "$(ls "$EV12" | tr '\n' ' ')"
[ "$(echo "$r" | wc -l)" = 1 ] && chk one-result-line ok || chk one-result-line bad
# --- recipe statements (fake log + evidence files)
grep -q "delete from eventlog where type in ('chat','inputtext') and data like 'Shay: %sword%'" "$KAH_ROW_FAKE_LOG" && chk old-asks-purged-at-start ok || chk old-asks-purged-at-start bad
[ "$(grep -c "delete from eventlog where type in ('chat','inputtext') and rowid > 100" "$KAH_ROW_FAKE_LOG")" = 2 ] && chk purge-before-each-control-ask ok || chk purge-before-each-control-ask bad "$(grep -c 'rowid > 100' "$KAH_ROW_FAKE_LOG")"
grep -q 'purge: mark=100 left=' "$EV12/purge.txt" && chk purge-verified-in-evidence ok || chk purge-verified-in-evidence bad "$(cat "$EV12/purge.txt" 2>&1 | head -3)"
[ -s "$EV12/haff-aff40.txt" ] && [ -s "$EV12/haff-aff85.txt" ] && grep -q ' 85 platonic' "$KAH_ROW_FAKE_LOG" && grep -q ' 40 platonic' "$KAH_ROW_FAKE_LOG" && ! grep -q ' 75 platonic' "$KAH_ROW_FAKE_LOG" && chk aff-40-then-85 ok || chk aff-40-then-85 bad
u1=$(cat "$EV12/s1/utterance.txt"); u2=$(cat "$EV12/s2/utterance.txt"); u3=$(cat "$EV12/s3/utterance.txt")
[ "$u1" = "Can I have your sword as a gift?" ] && [ "$u2" != "$u1" ] && [ "$u3" != "$u2" ] && echo "$u2$u3" | grep -q sword && chk fresh-wordings ok || chk fresh-wordings bad "$u1 | $u2 | $u3"
# --- GATED: all clean asks refused -> never FAIL; the false-positive gate regex of v1 is NOT used (gate_relative / threshold noise)
scen declined; r=$(run 12-d $L); rc=$?
case "$r" in "RESULT 12-d GATED SERVER-GATE-PASS"*"LLM-DECLINED"*) chk declined-is-gated-not-fail ok;; *) chk declined-is-gated-not-fail bad "$(echo "$r" | cut -c1-400)";; esac
echo "$r" | grep -q 'aff40_gate_log=not exercised' && ! echo "$r" | grep -q 'aff40_gate_log=exercised' && chk gate-not-exercised-on-noise ok || chk gate-not-exercised-on-noise bad "$r"
[ $rc = 3 ] && chk declined-exit-3 ok || chk declined-exit-3 bad "rc=$rc"
v1=$("$REAL_PY" "$ST_HERE/rowcheck.py" 12-d "$EV12" 2>&1 | tail -1)
echo "$v1" | grep -q 'aff40_gate_reason_in_log=found' && chk v1-false-positive-reproduced ok || chk v1-false-positive-reproduced bad "$(echo "$v1" | cut -c1-300)"
[ -d "$EV12/s4" ] && [ ! -d "$EV12/s5" ] && chk three-controls-then-stop ok || chk three-controls-then-stop bad "$(ls "$EV12" | tr '\n' ' ')"
# --- SETUP-FAIL contaminated / FAIL leak / FAIL blocked at aff85
scen contam; r=$(run 12-d $L)
case "$r" in "RESULT 12-d SETUP-FAIL contaminated control"*) chk contaminated-control-setup-fail ok;; *) chk contaminated-control-setup-fail bad "$(echo "$r" | cut -c1-300)";; esac
scen aff40-leak; r=$(run 12-d $L); case "$r" in "RESULT 12-d FAIL aff40_refused_no_transfer"*) chk aff40-transfer-fails ok;; *) chk aff40-transfer-fails bad "$(echo "$r" | cut -c1-300)";; esac
scen blocked85; r=$(run 12-d $L); case "$r" in "RESULT 12-d FAIL aff85_not_blocked_by_gate"*) chk gate-block-at-85-fails ok;; *) chk gate-block-at-85-fails bad "$(echo "$r" | cut -c1-300)";; esac
# --- knobs
scen declined; SFX_ASKS=1 run 12-d $L >/dev/null; [ -d "$EV12/s2" ] && [ ! -d "$EV12/s3" ] && chk asks-knob ok || chk asks-knob bad "$(ls "$EV12" | tr '\n' ' ')"
scen pass-s3; SFX_NPC2=Malzin run 12-d $L >/dev/null; grep -q "stobe-auto where 'Malzin'" "$KAH_ROW_FAKE_LOG" && chk npc2-resolved ok || chk npc2-resolved bad
# --- CLI
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$REAL_PY\" '$ST_HERE/sfxfake.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/sfxrun.sh' \"\$@\"" _ "$@" 2>/dev/null; }
export REAL_PY
scen pass-s3; o=$(cli 12-d $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 12-d PASS' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
echo "$o" | grep -q '^EVIDENCE 12-d purge.txt' && chk cli-evidence-lines ok || chk cli-evidence-lines bad "$o"
scen declined; o=$(cli 12-d $L --asks 1 --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 12-d GATED.*s2\.\.s2' && chk cli-asks-flag ok || chk cli-asks-flag bad "$(echo "$o" | cut -c1-300)"
scen pass-s3; o=$(cli 12-d $L --dry); echo "$o" | grep -q '^RESULT 12-d DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
o=$(cli 11-b $L); echo "$o" | grep -q 'RESULT 11-b SETUP-FAIL sfxrun.sh runs 12-d only' && chk cli-other-row-refused ok || chk cli-other-row-refused bad "$o"
o=$(cli 12-d $L --asks x); echo "$o" | grep -q 'SETUP-FAIL --asks must be a positive integer' && chk cli-bad-asks-refused ok || chk cli-bad-asks-refused bad "$o"
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFX ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFX ALL FAIL $ok/$n"; exit 1; fi
