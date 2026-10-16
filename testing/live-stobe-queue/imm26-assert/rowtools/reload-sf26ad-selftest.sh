#!/usr/bin/env bash
# reload-sf26ad-selftest.sh (imm26-fix26ad): OFFLINE selftest of reloaddefs_sf26ad.sh / reload-run-sf26ad.sh (26-d bounded resume poll) and hunt26a-run.sh (26-a follow loop). No game, ssh, WSL or DB.
# The candidates (*.candidate) are staged under their final names in a TEMP COPY of imm26-assert (or the finals are used after the swap); nothing in the live tree is touched.
# Prints `SELFTEST sf26ad-<name> PASS|FAIL` and `SELFTEST SF26AD ALL PASS|FAIL n/m`. Usage: bash rowtools/reload-sf26ad-selftest.sh
ST_REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); cp -r "$ST_REAL/.." "$T/a" && rm -rf "$T/a/__pycache__" "$T/a/rowtools/__pycache__"
ST_HERE="$T/a/rowtools"
for f in reloaddefs_sf26ad.sh reload-run-sf26ad.sh hunt26a-run.sh; do [ -f "$ST_HERE/$f" ] || cp "$ST_HERE/$f.candidate" "$ST_HERE/$f"; done
export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_FACTION RW_REFACTION RW_APOLOGY RW_GOATS RW_PIN_GOATS RW_OFFER2 RW_INJECT_PROPOSE RW_INJECT_TARGET RW_RESUME_POLL RW_RESUME_POLL_STEP RW_RESUME_TELEPORT
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sf26ad-$1 PASS ${3:-}"; else echo "SELFTEST sf26ad-$1 FAIL ${3:-}"; fi; }
L=5090-i3; F="$KAH_ROW_FAKE_LOG"
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sf26ad.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
cli() {   # cli <script> args: reload rows on the sf26bd fake
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sf26bd.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
lineno() { grep -n -- "$1" "$F" | head -"${2:-1}" | tail -1 | cut -d: -f1; }
rd() { find "$KAH_ROWS_BASE" -type d -name "$1" | head -1; }
TP="stobe-auto teleport Shay 'Malzin'"

# ---- 26-d
scen 26d-pass; o=$(cli reload-run-sf26ad.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && [ $rc = 0 ] && [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && chk 26d-immediate-pass ok || chk 26d-immediate-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
d=$(rd 26-d); sed -n 2p "$d/resume_poll.txt" | grep -q '^t=0s RESUMED' && chk 26d-immediate-no-wait ok || chk 26d-immediate-no-wait bad "$(cat "$d/resume_poll.txt")"
scen 26d-delayed; o=$(cli reload-run-sf26ad.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && [ $rc = 0 ] && chk 26d-delayed-pass ok || chk 26d-delayed-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
d=$(rd 26-d); w=$(grep -c '^t=.*waiting' "$d/resume_poll.txt"); grep -q 'RESUMED' "$d/resume_poll.txt" && [ "$w" = 2 ] && chk 26d-delayed-polled-twice-then-resumed ok "waiting=$w" || chk 26d-delayed-polled-twice-then-resumed bad "waiting=$w $(cat "$d/resume_poll.txt")"
grep -qE '^activity-bbbb\|' "$d/act_post.txt" && chk 26d-final-dump-has-continuation ok || chk 26d-final-dump-has-continuation bad "$(cat "$d/act_post.txt")"
# assertions are NOT weakened: a continuation that never appears is still a FAIL (not SETUP-FAIL, not PASS), after the full window
scen 26d-never; o=$(cli reload-run-sf26ad.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d FAIL' && [ $rc = 1 ] && chk 26d-never-resumes-still-fails ok || chk 26d-never-resumes-still-fails bad "rc=$rc $(echo "$o" | cut -c1-300)"
d=$(rd 26-d); grep -q 'NOT RESUMED' "$d/resume_poll.txt" && [ "$(grep -c '^t=.*waiting' "$d/resume_poll.txt")" -ge 15 ] && chk 26d-never-polled-whole-window ok || chk 26d-never-polled-whole-window bad "$(tail -2 "$d/resume_poll.txt")"
scen 26d-never; o=$(RW_RESUME_POLL=0 cli reload-run-sf26ad.sh 26-d $L --allow-retry selftest); d=$(rd 26-d)
[ "$(grep -c '^t=.*waiting' "$d/resume_poll.txt")" = 1 ] && chk 26d-poll-window-knob ok || chk 26d-poll-window-knob bad
# teleport of Shay before the s3 say, in the same harness body
scen 26d-pass; cli reload-run-sf26ad.sh 26-d $L --allow-retry selftest >/dev/null
tl=$(lineno "$TP"); sl=$(lineno "stobe_say .* 'Are we still"); [ -n "$tl" ] && [ -n "$sl" ] && [ "$tl" -lt "$sl" ] && [ $((sl-tl)) -le 3 ] && chk s3-teleport-before-say ok "tp@$tl say@$sl" || chk s3-teleport-before-say bad "tp=$tl say=$sl"
scen 26d-pass; o=$(RW_RESUME_TELEPORT=0 cli reload-run-sf26ad.sh 26-d $L --allow-retry selftest)
grep -q "$TP" "$F" && chk s3-teleport-switch-off bad || chk s3-teleport-switch-off ok
# 26-dx unchanged: no poll, cancel teleport still there; 26-e runs
scen 26dx-pass; o=$(cli reload-run-sf26ad.sh 26-dx $L --allow-retry selftest); rc=$?
d=$(rd 26-dx); echo "$o" | tail -1 | grep -q '^RESULT 26-dx PASS' && [ ! -e "$d/resume_poll.txt" ] && grep -q "$TP" "$F" && chk 26dx-unchanged-no-poll ok || chk 26dx-unchanged-no-poll bad "rc=$rc $(echo "$o" | cut -c1-200)"
scen 26e-pass; o=$(cli reload-run-sf26ad.sh 26-e $L --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 26-e PASS' && chk 26e-still-passes ok || chk 26e-still-passes bad "$(echo "$o" | cut -c1-200)"

# ---- 26-a (hunt26a-run.sh)
a_scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".* "$T/stubcount"; export FAKE_SCEN="$T/scen_a.json"; "$REAL_PY" "$ST_HERE/hunt26ascen.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
a_run() {   # a_run <outdir> [VAR=value...]
  local od="$1"; shift
  env STUB_COUNT="$T/stubcount" HUNT26A_SCENE="$ST_HERE/hunt26a-scene-stub.sh" HUNT26A_INJECT="$ST_HERE/hunt26a-inject-stub.sh" "$@" \
    bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/hunt26afake.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/hunt26a-run.sh' '$od'" 2>/dev/null
}
OFFER_OK="Shall we travel to hunt one goat together?"
FIGHT="Not now, I am in the middle of a fight."
a_scen pass; o=$(a_run "$T/o1" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 PASS' && [ $rc = 0 ] && chk 26a-pass ok "$(echo "$o" | cut -c1-160)" || chk 26a-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q "stobe-auto give .*Katana" "$F" && chk 26a-gives-katana-when-missing ok || chk 26a-gives-katana-when-missing bad
grep -q 'stobe-auto equip .*Katana' "$F" && grep -q 'stobe-auto blood .* 100' "$F" && grep -q 'stobe-auto hunger .* 250' "$F" && chk 26a-equip-blood-hunger ok || chk 26a-equip-blood-hunger bad
[ "$(grep -c 'stobe-auto kill ' "$F")" -ge 2 ] && chk 26a-kills-leftover-goats ok || chk 26a-kills-leftover-goats bad "$(grep -c 'stobe-auto kill ' "$F")"
[ "$(grep -c 'stobe-auto teleport Shay ' "$F")" -ge 3 ] && chk 26a-shay-follows-npc ok "teleports=$(grep -c 'stobe-auto teleport Shay ' "$F")" || chk 26a-shay-follows-npc bad "$(grep -c 'stobe-auto teleport Shay ' "$F")"
grep -q "id not in ('activity-old1')" "$F" && chk 26a-ignores-old-records ok || chk 26a-ignores-old-records bad
[ -s "$T/o1/follow.log" ] && [ -s "$T/o1/verdict.txt" ] && chk 26a-evidence-files ok || chk 26a-evidence-files bad
a_scen pass-katana; o=$(a_run "$T/o2" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
grep -q "stobe-auto give" "$F" && chk 26a-no-give-when-katana-present bad || chk 26a-no-give-when-katana-present ok "$(echo "$o" | cut -c1-60)"
a_scen failed; o=$(a_run "$T/o3" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
echo "$o" | grep -q "^HUNT26A-RUN 5090-i5 FAIL.*ended 'failed' reason='timeout'" && [ $rc = 1 ] && chk 26a-failed-record-is-fail ok || chk 26a-failed-record-is-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
a_scen noinv; o=$(a_run "$T/o4" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 FAIL' && [ $rc = 1 ] && chk 26a-no-inventory-delta-not-pass ok || chk 26a-no-inventory-delta-not-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
a_scen nopart; o=$(a_run "$T/o4b" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 FAIL' && [ $rc = 1 ] && chk 26a-no-participation-not-pass ok || chk 26a-no-participation-not-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
# the fight refusal: retried (fresh goats, new arm), then the hunt runs; refused every time = SETUP-FAIL
a_scen pass; o=$(a_run "$T/o5" "STUB_TEXT_SEQ=$FIGHT;$FIGHT;$OFFER_OK"); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 PASS' && [ "$(cat "$T/stubcount")" = 3 ] && chk 26a-fight-retry-then-pass ok || chk 26a-fight-retry-then-pass bad "rc=$rc tries=$(cat "$T/stubcount") $(echo "$o" | cut -c1-200)"
a_scen pass; o=$(a_run "$T/o6" "STUB_TEXT_SEQ=$FIGHT" RW_FIGHT_TRIES=2); rc=$?
echo "$o" | grep -q "^HUNT26A-RUN 5090-i5 SETUP-FAIL.*middle of a fight.*all 2 tries" && [ $rc = 2 ] && chk 26a-fight-forever-setup-fail ok || chk 26a-fight-forever-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
a_scen pass; o=$(a_run "$T/o7" "STUB_TEXT_SEQ=BAD"); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 SETUP-FAIL scene not ok' && [ $rc = 2 ] && chk 26a-bad-scene-setup-fail ok || chk 26a-bad-scene-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-200)"
a_scen proposed; o=$(a_run "$T/o8" "STUB_TEXT_SEQ=$OFFER_OK" RW_ACCEPT_WAIT=8 RW_FOLLOW_STEP=4); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 SETUP-FAIL the Yes did not move the Hunt record' && [ $rc = 2 ] && chk 26a-accept-not-landed-setup-fail ok || chk 26a-accept-not-landed-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-200)"

# ---- originals untouched, syntax
R=testing/live-stobe-queue/imm26-assert/rowtools
if git -C "$ST_REAL" diff --quiet -- hunt26a-scene.sh reloaddefs_sfi.sh reloaddefs_sf26bd.sh reload-run-sf26bd.sh reloadcheck_a.py reloaddefs_a.sh reloaddefs_sfo.sh reloaddefs_sfp.sh 2>/dev/null; then chk originals-unmodified ok; else chk originals-unmodified bad; fi
bad=0; for f in reloaddefs_sf26ad.sh reload-run-sf26ad.sh hunt26a-run.sh hunt26a-scene-stub.sh hunt26a-inject-stub.sh reload-sf26ad-selftest.sh; do bash -n "$ST_HERE/$f" || bad=1; done
[ $bad = 0 ] && chk bash-syntax ok || chk bash-syntax bad
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SF26AD ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SF26AD ALL FAIL $ok/$n"; exit 1; fi
