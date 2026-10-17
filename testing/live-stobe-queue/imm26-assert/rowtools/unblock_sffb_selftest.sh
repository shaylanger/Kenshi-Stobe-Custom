#!/usr/bin/env bash
# unblock_sffb_selftest.sh (imm26-sfFixA3): OFFLINE self-test of the 11-b recipe v3 (unblockdefs_sffb.sh / unblockrun_sffb.sh; checker unchanged: unblockcheck_a.py via unblockpy_a.sh).
# No game, ssh, WSL or DB: lane 4080-i4 simulated by unblockfake_sffb.py with scenarios from unblockscen_sffb.py. Asserts the new recipe statements (KO not teleport, serial track/recall,
# serial state fallback, single escalation, isolation=0 refused) and that the original scripts are not hooked/edited. KAH_PF_ISOLATION stays at its default.
# Run in WSL: wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_sffb_selftest.sh
# Prints `SELFTEST sffb-<name> PASS|FAIL` lines and `SELFTEST SFFB ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 U11B_CALM_TRIES=2 SFK_KO_WAIT=1
unset KAH_AGENT_NAME KAH_ROW_DRY KAH_PF_ISOLATION TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT U11B_FACTION U11B_DIST U11B_END U11B_RECALL_DIST
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sffb-$1 PASS ${3:-}"; else echo "SELFTEST sffb-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/tripdefs_sfk.sh"; . "$ST_HERE/unblockdefs_sfk.sh"; . "$ST_HERE/unblockdefs_sffb.sh"
PY="$ST_HERE/unblockpy_a.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sffb.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sffb.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
# expect <name> <scenario> <RESULT prefix> <substring of the RESULT line>
expect() {
  local name="$1" sc="$2" pre="$3" want="${4-}" r
  scen "$sc"; r=$(run 11-b "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ -n "$want" ]; then echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"; else chk "$name" ok; fi
}
FAR="teleport '#77/1' -53200 957 4893"

# ------------------------------------------------------------------ KO end
expect ko-pass ko-pass "RESULT 11-b PASS" "exactly_one_claim_after_combat"
! grep -q -- "$FAR" "$F" && ! grep -q "order 'Cind.*NULL_TASK" "$F" && chk ko-path-no-far-teleport-no-null-task ok || chk ko-path-no-far-teleport-no-null-task bad "$(grep -m2 -- "$FAR\|NULL_TASK" "$F" | cut -c1-100)"
grep -q "stobe-auto ko '#77/1' 900" "$F" && chk ko-addresses-spawned-serial-900 ok || chk ko-addresses-spawned-serial-900 bad "$(grep -m1 'sffb:ko' "$F" | cut -c1-120)"
[ "$(grep -c 'sffb:ko' "$F")" = 1 ] && [ "$(fl 'sffb:ko')" -gt "$(fl 'stobe-auto fight')" ] && [ "$(fl 'sffb:ko')" -lt "$(fl 'sffb:track')" ] && chk ko-once-after-fight-before-first-track ok || chk ko-once-after-fight-before-first-track bad
grep -q 'end=ko enemy #77/1' "$EVB/11-b/calm_track.txt" && grep -q 'recalled=0' "$EVB/11-b/calm_track.txt" && ! grep -q 'sffb:recall' "$F" && chk near-npc-not-recalled ok || chk near-npc-not-recalled bad "$(cat "$EVB/11-b/calm_track.txt" 2>/dev/null | head -3)"
[ "$(grep -c 'stobe-auto where .* # sffb:track' "$F")" = 1 ] && chk track-by-serial-once-per-poll ok || chk track-by-serial-once-per-poll bad
grep -q 'knocked out' "$EVB/11-b/ko.txt" && chk ko-evidence ok || chk ko-evidence bad

# ------------------------------------------------------------------ escalation (still in combat after the KO)
expect ko-still-in-combat-escalates-and-passes ko-still-combat-escalate-pass "RESULT 11-b PASS"
[ "$(grep -c -- "$FAR" "$F")" = 1 ] && [ "$(grep -c "order 'Cind.*NULL_TASK" "$F")" = 1 ] && [ "$(fl 'sffb:ko')" -lt "$(fl "$FAR")" ] && chk escalation-exactly-once-after-ko ok || chk escalation-exactly-once-after-ko bad "far=$(grep -c -- "$FAR" "$F")"
grep -q 'ESCALATE' "$EVB/11-b/calm_track.txt" && chk escalation-recorded ok || chk escalation-recorded bad

# ------------------------------------------------------------------ name lookup lost, serial read works
expect name-lost-serial-read-passes name-lost-serial-ok "RESULT 11-b PASS"
grep -q 'name-lookup-failed state_combat_pre.txt' "$EVB/11-b/combat_probe.txt" && grep -q "stobe_state '#[0-9]*/[0-9]*'" "$F" && chk serial-fallback-used-and-logged ok || chk serial-fallback-used-and-logged bad "$(head -3 "$EVB/11-b/combat_probe.txt" 2>/dev/null | cut -c1-120)"
grep -q 'in_combat=true' "$EVB/11-b/state_combat_pre.txt" && chk serial-state-feeds-evidence ok || chk serial-state-feeds-evidence bad "$(cat "$EVB/11-b/state_combat_pre.txt" 2>/dev/null)"

# ------------------------------------------------------------------ Cind strays: recalled by serial
U11B_CALM_TRIES=4 expect strayed-npc-recalled-and-passes strayed-recall "RESULT 11-b PASS"
[ "$(grep -c 'sffb:recall' "$F")" = 1 ] && grep -q "teleport '#[0-9]*/[0-9]*' Shay" "$F" && grep -q '^1 dist=300 recalled=1' "$EVB/11-b/calm_track.txt" && grep -q '^2 dist=20 recalled=0' "$EVB/11-b/calm_track.txt" && chk recall-once-by-serial-to-shay ok || chk recall-once-by-serial-to-shay bad "$(cat "$EVB/11-b/calm_track.txt" 2>/dev/null | head -4)"
! grep -q 'ESCALATE' "$EVB/11-b/calm_track.txt" && chk no-escalation-when-calm ok || chk no-escalation-when-calm bad
U11B_RECALL_DIST=500 expect recall-dist-env-respected strayed-recall "RESULT 11-b PASS"
! grep -q 'sffb:recall' "$F" && chk recall-dist-env ok || chk recall-dist-env bad

# ------------------------------------------------------------------ both reads fail: SETUP-FAIL vanished, evidence kept, recall attempted
expect gone-by-name-and-serial-setup-fail gone-both "RESULT 11-b SETUP-FAIL" "vanished"
grep -q 'dist=none' "$EVB/11-b/calm_track.txt" && grep -q 'sffb:recall' "$F" && grep -q 'in_combat=gone' "$EVB/11-b/state_calm.txt" && chk gone-evidence-and-recall-attempt ok || chk gone-evidence-and-recall-attempt bad "$(head -2 "$EVB/11-b/calm_track.txt" 2>/dev/null)"

# ------------------------------------------------------------------ KO refused / old end
expect ko-refused-setup-fail ko-fail "RESULT 11-b SETUP-FAIL" "ko of the spawned enemy #77/1 failed"
echo "$(run 11-b "$L" 2>/dev/null)" >/dev/null
scen ko-fail; r=$(run 11-b $L); echo "$r" | grep -q 'U11B_END=far' && chk ko-refused-names-the-fallback ok || chk ko-refused-names-the-fallback bad
scen far-pass; U11B_END=far run 11-b $L >/dev/null
[ "$(grep -c -- "$FAR" "$F")" = 1 ] && ! grep -q 'sffb:ko' "$F" && grep -q 'end=far' "$EVB/11-b/calm_track.txt" && chk end-far-is-the-old-end ok || chk end-far-is-the-old-end bad
scen ko-pass; U11B_FACTION="Skin Bandits" U11B_DIST=40 run 11-b $L >/dev/null
grep -q "'Skin Bandits' near .* dist 40" "$F" && chk env-overrides-kept ok || chk env-overrides-kept bad
scen ko-pass; run 11-b $L >/dev/null
grep -q "stobe-auto spawn \"Hungry Bandit\" 'Dust Bandits' near 'Cind \[Hungry Bandit\]' dist 20 count 1" "$F" && [ "$(grep -c 'u:stream' "$F")" = 3 ] && ! grep -q 'stobe-auto speed 10' "$F" && chk v2-setup-kept ok || chk v2-setup-kept bad

# ------------------------------------------------------------------ CLI: unblockrun_sffb.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_sffb.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen ko-pass; o=$(cli unblockrun_sffb.sh 11-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 11-b PASS' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'stobe-auto load kah-imm26-4080-i4 ' "$F" || grep -q 'stobe-auto load kah-imm26-4080-i4$' "$F" && chk cli-4080-i4-configured-save-default ok || chk cli-4080-i4-configured-save-default bad "$(grep -m1 'stobe-auto load' "$F")"
echo "$o" | grep -q '^EVIDENCE 11-b calm_track.txt ' && chk cli-evidence-calm-track ok || chk cli-evidence-calm-track bad
scen ko-pass; o=$(KAH_PF_ISOLATION=0 cli unblockrun_sffb.sh 11-b $L --allow-retry selftest); rc=$?
[ $rc = 2 ] && echo "$o" | grep -q 'ISOLATION=0 is not allowed' && ! grep -q 'stobe-auto' "$F" && chk cli-refuses-isolation-off ok || chk cli-refuses-isolation-off bad "rc=$rc $o"
scen ko-pass; o=$(cli unblockrun_sffb.sh 11-b $L --no-reload --end bogus --allow-retry selftest); rc=$?
[ $rc = 2 ] && echo "$o" | grep -q -- '--end must be ko or far' && chk cli-bad-end-refused ok || chk cli-bad-end-refused bad "rc=$rc $o"
scen far-pass; o=$(cli unblockrun_sffb.sh 11-b $L --no-reload --end far --calm-tries 1 --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 11-b PASS' && grep -q -- "$FAR" "$F" && ! grep -q 'stobe-auto load' "$F" && chk cli-end-far-no-reload ok || chk cli-end-far-no-reload bad "$(echo "$o" | tail -1 | cut -c1-300)"
scen gone-both; o=$(cli unblockrun_sffb.sh 11-b $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen ko-pass; o=$(cli unblockrun_sffb.sh 11-b $L --dry); echo "$o" | grep -q '^RESULT 11-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
o=$(cli unblockrun_sffb.sh 23-a $L); echo "$o" | grep -q 'RESULT 23-a SETUP-FAIL not an sffb row' && chk cli-other-row-refused ok || chk cli-other-row-refused bad "$o"
o=$(cli unblockrun_sffb.sh 11-b nolane); echo "$o" | grep -q 'RESULT 11-b SETUP-FAIL PREFLIGHT-FAIL unknown lane' && chk cli-unknown-lane ok || chk cli-unknown-lane bad "$o"

# ------------------------------------------------------------------ hygiene
for f in unblockdefs_sffb.sh unblockrun_sffb.sh unblock_sffb_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
grep -q 'unblockdefs_sffb' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/unblockdefs_a.sh" "$ST_HERE/unblockdefs_sfk.sh" "$ST_HERE/unblockcheck_a.py" "$ST_HERE/reloaddefs_a.sh" 2>/dev/null && chk originals-not-hooked bad || chk originals-not-hooked ok
grep -h 'KAH_PF_ISOLATION=0' "$ST_HERE/unblockdefs_sffb.sh" "$ST_HERE/unblockrun_sffb.sh" | grep -v 'is not allowed\|NEVER' | grep -q . && chk no-isolation-off-in-new-files bad || chk no-isolation-off-in-new-files ok
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- tripdefs.sh unblockdefs_a.sh unblockdefs_sfk.sh unblockcheck_a.py unblockrun_a.sh unblockrun_sfk.sh unblockpy_a.sh rowdefs.sh && chk queued-scripts-unmodified ok || chk queued-scripts-unmodified bad "git diff shows an edit"
fi

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFFB ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFFB ALL FAIL $ok/$n"; exit 1; fi
