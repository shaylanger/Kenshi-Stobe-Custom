#!/usr/bin/env bash
# unblock_sfs_selftest.sh: OFFLINE self-test of 08-d v2 (unblockdefs_sfs.sh / unblockcheck_sfs.py / unblockrun_sfs.sh / unblockpy_sfs.sh, imm26-sfS). No game, ssh, WSL-only tools or DB:
# lanes are simulated by unblockfake_sfs.py (-> unblockfake_a.py -> ...) with scenarios from unblockscen_sfs.py. FAST: run in WSL
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_sfs_selftest.sh
# Prints `SELFTEST sfs-<name> PASS|FAIL` and `SELFTEST SFS ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 TRIP_WALK_TRIES=2
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT U08D_NEG TRIP_WALK_BACK TRIP_WALK_SPEED U_BORED_TRIES U_BORED_ATTN
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfs-$1 PASS ${3:-}"; else echo "SELFTEST sfs-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "${SFS_DEFS:-$ST_HERE/unblockdefs_sfs.sh}"   # SFS_DEFS = a candidate defs file (unblock_sfs_ask_selftest.sh sets it)
PY="$ST_HERE/unblockpy_sfs.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sfs.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sfs.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
bad_set() {  # bad_set <module unblockcheck_a|unblockcheck_sfs> <row> <ev> : comma-joined sorted names of the failing checks
  "$REAL_PY" -I -c '
import importlib, sys
sys.path.insert(0, sys.argv[1])
c = importlib.import_module(sys.argv[2])
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[3], sys.argv[4]])' "$ST_HERE" "$1" "$2" "$3" 2>&1 | sed -n 's/^BAD //p'
}
expect() {  # expect <name> <scenario> <RESULT prefix> [FAIL: exact failing-check set | other: substring]
  local name="$1" sc="$2" pre="$3" want="${4-}" r ev got
  scen "$sc"; r=$(run 08-d "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ "$pre" = "RESULT 08-d FAIL" ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set unblockcheck_sfs 08-d "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}
# --- the originals this ticket must not touch
BADORIG=""; for f in unblockdefs_a.sh unblockrun_a.sh unblockcheck_a.py unblockpy_a.sh rowcheck_trip.py hxdefs_b.sh; do
  git -C "$ST_HERE" diff --quiet HEAD -- "$f" 2>/dev/null || BADORIG="$BADORIG $f"; done
[ -z "$BADORIG" ] && chk originals-untouched ok || chk originals-untouched bad "differs from HEAD:$BADORIG"
# --- verdicts
expect 08-d-pass-arrival-remark-ignored sfs-pass "RESULT 08-d PASS" "topic_closed_outcome_completed"
EV=$(ls -d "$EVB/08-d" 2>/dev/null)
v1=$(bad_set unblockcheck_a 08-d "$EV")   # the v1 checker on the SAME evidence trips on the arrival remark: the defect this fix removes
[ "$v1" = "no_npc_ask_about_the_topic" ] && chk v1-checker-trips-on-arrival-remark ok || chk v1-checker-trips-on-arrival-remark bad "v1 failing='$v1'"
expect 08-d-ask-after-tick1-fails sfs-ask "RESULT 08-d FAIL" "no_npc_ask_about_the_topic"
expect 08-d-topic-still-open-fails sfs-open "RESULT 08-d FAIL" "topic_closed_outcome_completed"
expect 08-d-claim-written-fails sfs-claim "RESULT 08-d FAIL" "no_situated_remark_claim_for_closed_topic"
export U08D_NEG=1; expect 08-d-negative-control-pass sfs-neg "RESULT 08-d PASS" "negative_trip_not_completed"; unset U08D_NEG
# --- recipe statements (fake log + evidence files)
scen sfs-pass; run 08-d $L >/dev/null; D="$EVB/08-d"
grep -q "attn=" "$KAH_ROW_FAKE_LOG" && grep -q "'{\"in_combat\":false}'" "$KAH_ROW_FAKE_LOG" && chk request-carries-attn-in-combat-false ok || chk request-carries-attn-in-combat-false bad
grep -q "mode=autochat&attn=" "$KAH_ROW_FAKE_LOG" && grep -q 'optional=1' "$KAH_ROW_FAKE_LOG" && chk request-shape-unchanged-plus-attn ok || chk request-shape-unchanged-plus-attn bad
grep -q 'attn={"in_combat":false}' "$D/bored_attn.txt" && chk attn-evidence-file ok || chk attn-evidence-file bad "$(cat "$D/bored_attn.txt" 2>&1 | head -2)"
{ [ -f "$D/bored_after1_mark.txt" ] && grep -q '^m1=' "$D/bored_after1_mark.txt" && [ -f "$D/bored_log_after1.txt" ] && [ -f "$D/bored_log.txt" ]; } && chk mark-and-after1-log-written ok || chk mark-and-after1-log-written bad "$(ls "$D" 2>&1 | tr '\n' ' ')"
! grep -q 'Squin' "$D/bored_log_after1.txt" && grep -q 'Squin' "$D/bored_log.txt" && chk arrival-remark-only-in-full-log ok || chk arrival-remark-only-in-full-log bad
# --- the v1 request is reproducible: --attn '' sends no attn
scen sfs-pass; U_BORED_ATTN="" run 08-d $L >/dev/null; grep -q "attn=\$A" "$KAH_ROW_FAKE_LOG" && ! grep -q "'{\"in_combat\":false}'" "$KAH_ROW_FAKE_LOG" && grep -q 'attn=<none>' "$EVB/08-d/bored_attn.txt" && chk attn-empty-is-v1-request ok || chk attn-empty-is-v1-request bad
# --- CLI
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$REAL_PY\" '$ST_HERE/unblockfake_sfs.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/unblockrun_sfs.sh' \"\$@\"" _ "$@" 2>/dev/null; }
export REAL_PY
scen sfs-pass; o=$(cli 08-d $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 08-d PASS' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $o"
echo "$o" | grep -q '^EVIDENCE 08-d bored_attn.txt' && chk cli-evidence-lines ok || chk cli-evidence-lines bad "$o"
scen sfs-neg; o=$(cli 08-d $L --neg --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 08-d PASS.*negative_trip_not_completed' && chk cli-neg-flag ok || chk cli-neg-flag bad "$o"
scen sfs-pass; o=$(cli 08-d $L --dry); echo "$o" | grep -q '^RESULT 08-d DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
o=$(cli 11-b $L); echo "$o" | grep -q 'RESULT 11-b SETUP-FAIL unblockrun_sfs.sh runs 08-d only' && chk cli-other-row-refused ok || chk cli-other-row-refused bad "$o"
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFS ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFS ALL FAIL $ok/$n"; exit 1; fi
