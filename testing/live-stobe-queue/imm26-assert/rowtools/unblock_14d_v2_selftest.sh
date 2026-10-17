#!/usr/bin/env bash
# unblock_14d_v2_selftest.sh (imm26-fix14dtool F3; copy of unblock_14d_selftest.sh for the v2 row: separate FAR spawn call + exact-set scene gate): OFFLINE self-test of unblockrun_14d.sh / unblockdefs_14d.sh / unblockcheck_14d.py / pywrap_u14d.sh (row 14-d). No game, ssh, WSL or DB: the lane is
# simulated by unblockfake_14d.py (+ fakelane.py) with scenarios from unblockscen_14d.py, mutated here. Prints `SELFTEST u14dv2-<name> PASS|FAIL` and `SELFTEST UNBLOCK-14D-V2 ALL PASS|FAIL n/m`.
# Usage (WSL or Git Bash): bash rowtools/unblock_14d_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
P=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=1 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 D14_HOLD=4 D14_POLL_S=1 ROW_NPC="Cind [Hungry Bandit]"
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_SAVE D14_ASK D14_SPAWNT D14_REFACTION
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST u14dv2-$1 PASS ${3:-}"; else echo "SELFTEST u14dv2-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_14d_v2.sh"
PY="$ST_HERE/pywrap_u14d.sh"
lt_fake() { "$P" "$ST_HERE/unblockfake_14d_v2.py" "$@"; }
scen() {   # scen '<python mutating S>'  (S = the pass scenario; helpers of unblockscen_14d are in scope)
  rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"
  "$P" - "$ST_HERE" "$FAKE_SCEN" "${1:-}" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from unblockscen_14d import *
S = base()
S["spawn"] = "spawned 5/5 Dust Bandit: " + ", ".join("Dust Bandit #%s race=Greenlander" % x for x in NEAR)
S["spawnfar"] = "spawned 1/1 Dust Bandit: Dust Bandit #%s race=Greenlander" % FAR
exec(sys.argv[3])
json.dump(S, open(sys.argv[2], 'w'))
PYEOF
  : > "$KAH_ROW_FAKE_LOG"; }
L=5090-i5
run() { gr_main --no-preflight --allow-retry selftest "$@" 2>/dev/null; }
expect() { local name="$1" row="$2" kind="$3" has="$4" r; r=$(run "$row" $L)
  case "$r" in "RESULT $row $kind"*) if echo "$r" | grep -qF -- "$has"; then chk "$name" ok; else chk "$name" bad "missing '$has': $r"; fi;; *) chk "$name" bad "$r";; esac; }
E="$KAH_ROWS_BASE/imm26-5090-i5/rows/14-d"
NSL=$("$P" -c "import sys;sys.path.insert(0,sys.argv[1]);import unblockscen_14d as u;print(u.ns[4])" "$ST_HERE")
MEM='S["members"] = [[member(i, sel=1 if i < 3 else 0, prot=0 if i < 3 else 1, reason="" if i < 3 else "owned_target", setn=3) for i in range(5)]]'
STEP3='S["steps"] = [{"reply": "x", "prompt": prompt(ns[:3])}] * 4'

# ---- PASS: probe 3 of 5 then 5 of 5, ClearGroup offer with the 5 near serials, accept, attacks on the set, distant 6th alive
scen ''; expect pass 14-d PASS "offer_set_is_the_5_near"
F="$KAH_ROW_FAKE_LOG"
grep -q 'count 5 ' "$F" && ! grep -q 'count 6' "$F" && chk spawns-near-five-in-one-call ok || chk spawns-near-five-in-one-call bad
grep -q 'spawn "Dust Bandit" "Starving Bandits" at .* count 1 .*d14:spawnfar' "$F" && [ "$(grep -c 'd14:spawnfar' "$F")" = 1 ] && chk far-bandit-own-spawn-call-other-faction ok || chk far-bandit-own-spawn-call-other-faction bad "$(grep 'spawnfar' "$F" | cut -c1-200)"
[ "$(grep -c 'stobe_say' "$F")" = 4 ] && chk four-says-2-probes-ask-accept ok || chk four-says-2-probes-ask-accept bad "$(grep -c 'stobe_say' "$F")"
grep -q 'Hunt the 5 bandits' "$F" && grep -q "Yes, let.*s do it" "$F" && chk asks-and-accepts-with-the-row-phrases ok || chk asks-and-accepts-with-the-row-phrases bad
grep -q 'teleport "[^"]*" -47341 725 -55618' "$F" && chk probe-moves-bandits-closer ok || chk probe-moves-bandits-closer bad
grep -q '^FAR #901000001/7' "$E/bandits.txt" && grep -q '^NEAR #111938480/2' "$E/bandits.txt" && chk bandits-near5-far1 ok || chk bandits-near5-far1 bad
grep -q 'KAH_PF_ISOLATION=0' "$F" && chk never-isolation-off bad || chk never-isolation-off ok
grep -q 'teleport "#901000001/7" -47333 725 -55430' "$F" && chk far-bandit-170u-north ok || chk far-bandit-170u-north bad
# ---- second phrasing is a plain ask change
scen ''; D14_ASK="Hunt 5 bandits."; r=$(run 14-d $L); D14_ASK="Hunt the 5 bandits."
case "$r" in "RESULT 14-d PASS"*) grep -q 'Hunt 5 bandits' "$E/s1/utterance.txt" && echo "$r" | grep -qF "Hunt 5 bandits" && chk second-phrasing-pass-and-named ok || chk second-phrasing-pass-and-named bad "$r";; *) chk second-phrasing-pass-and-named bad "$r";; esac
# ---- SETUP-FAIL causes (the scene is bad: never a FAIL of the feature)
scen 'S["spawn"] = "spawned 4/5 Dust Bandit: " + ", ".join("Dust Bandit #%s race=G" % x for x in NEAR[:4])'; expect setupfail-spawn-short 14-d SETUP-FAIL "only 4 of 5 near"
scen 'S["spawnfar"] = "no faction named: Starving Bandits"'; expect setupfail-far-spawn-failed 14-d SETUP-FAIL "only 5 of 6 Dust Bandits spawned (near 5, far 0"
scen 'S["senses"] = "senses x: Cind -> Wulf sees=0 hears=1"'; expect setupfail-senses 14-d SETUP-FAIL "does not see"
scen "$STEP3; $MEM"; expect setupfail-agreed-3-of-5 14-d SETUP-FAIL "agreedTargets=3 of 5"
scen "$STEP3; $MEM"; r=$(run 14-d $L); echo "$r" | grep -qF "protected(owned_target)" && echo "$r" | grep -qF "older than NC22" && chk setupfail-names-member-and-old-dll ok || chk setupfail-names-member-and-old-dll bad "$r"
scen "$STEP3; "'S["members"] = [[member(i, sel=1 if i < 3 else 0, prot=0 if i < 3 else 1, reason="" if i < 3 else "owned_target", owner=0 if i < 3 else 77, setn=3) for i in range(5)]]'
r=$(run 14-d $L); echo "$r" | grep -qF "ownerSerial=77 slaveState=0 chained=0 prison=0" && echo "$r" | grep -qF "still misfires" && chk setupfail-reads-new-diag-owner-slave-chained-prison ok || chk setupfail-reads-new-diag-owner-slave-chained-prison bad "$r"
scen "$STEP3; "'S["members"] = [[member(i, sel=1 if i < 3 else 0, vis=1 if i < 3 else 0, owner=0, setn=3) for i in range(5)]]'
r=$(run 14-d $L); case "$r" in "RESULT 14-d SETUP-FAIL"*) echo "$r" | grep -qF "not_visible" && chk setupfail-flicker-not-visible ok || chk setupfail-flicker-not-visible bad "$r";; *) chk setupfail-flicker-not-visible bad "$r";; esac
scen "$STEP3; "'S["members"] = [[]]'; expect setupfail-no-member-line 14-d SETUP-FAIL "no ACTIVITY_CLEARGROUP_MEMBER line"
scen "$STEP3; "'S["members"] = [[member(i, sel=1 if i < 3 else 0, prot=1 if i >= 3 else 0, reason="captive_target" if i >= 3 else "", owner=0, prison=1, setn=3) for i in range(5)]]'
r=$(run 14-d $L); echo "$r" | grep -qF "protected(captive_target)" && echo "$r" | grep -qF "prison=1" && chk setupfail-names-other-protReason ok || chk setupfail-names-other-protReason bad "$r"
# ---- F3 exact-set gate: 5 serials but a FAR one in the set and a near member missing; and 6 serials (all near + far); neither may reach the ask (rule: SETUP-FAIL with the cause, not a FAIL)
scen 'S["steps"] = [{"reply": "x", "prompt": prompt(ns[:4] + ["901000001"])}] * 4'
r=$(run 14-d $L); case "$r" in "RESULT 14-d SETUP-FAIL"*) echo "$r" | grep -qF "set != near five (not near: [901000001] missing near: [${NSL}]" && chk setupfail-far-in-set-near-missing ok || chk setupfail-far-in-set-near-missing bad "$r";; *) chk setupfail-far-in-set-near-missing bad "$r";; esac
[ "$(grep -c 'stobe_say' "$KAH_ROW_FAKE_LOG")" = 3 ] && chk gate-stops-before-the-ask-3-probe-rounds-only ok || chk gate-stops-before-the-ask-3-probe-rounds-only bad "$(grep -c 'stobe_say' "$KAH_ROW_FAKE_LOG")"
scen 'S["steps"] = [{"reply": "x", "prompt": prompt(ns + ["901000001"])}] * 4'
r=$(run 14-d $L); case "$r" in "RESULT 14-d SETUP-FAIL"*) echo "$r" | grep -qF "not near: [901000001] missing near: []" && chk setupfail-six-serials-incl-far ok || chk setupfail-six-serials-incl-far bad "$r";; *) chk setupfail-six-serials-incl-far bad "$r";; esac
scen 'S["steps"] = [{"reply": "x", "prompt": prompt(ns[:4] + ["901000001"])}, {"reply": "x", "prompt": prompt(ns)}] + [{"reply": "x", "prompt": prompt(ns)}] * 3'
r=$(run 14-d $L); case "$r" in "RESULT 14-d PASS"*) chk gate-recovers-when-a-later-round-offers-exactly-the-near-five ok;; *) chk gate-recovers-when-a-later-round-offers-exactly-the-near-five bad "$r";; esac
# ---- real FAILs (the scene was fine)
scen 'S["recs"] = [[]]'; expect fail-no-offer 14-d FAIL "offer_clearGroup_record"
scen 'S["recs"] = [[rec("proposed", kind="Hunt")]]'; expect fail-hunt-instead-of-cleargroup 14-d FAIL "offer_is_ClearGroup"
scen 'S["recs"] = [[rec("proposed", targets=ns[:4])]]'; expect fail-set-of-4 14-d FAIL "offer_set_is_the_5_near"
scen 'S["recs"] = [[rec("proposed", targets=ns[:4] + ["901000001"])]]'; expect fail-set-includes-distant 14-d FAIL "offer_set_excludes_distant"
scen 'S["atkpre"] = ["[t] UNPROVOKED_FOCUSED_MELEE_ATTACK actor=1 target=%s" % ns[0]]'; expect fail-attack-before-accept 14-d FAIL "no_attack_before_acceptance"
scen 'S["recs"] = [[rec("proposed")]]'; expect fail-accept-did-not-land 14-d FAIL "accept_moved_past_proposed"
scen 'S["outbox"] += ["4|4|true|{\"status\":\"accepted\",\"kind\":\"ClearGroup\"}"]'; expect fail-two-accepted-rows 14-d FAIL "exactly_one_accepted_row=outbox accepted rows=2"
scen 'S["atkpost"].append("[t] UNPROVOKED_FOCUSED_MELEE_ATTACK actor=1 target=901000001")'; expect fail-distant-6th-attacked 14-d FAIL "distant_6th_not_targeted"
scen 'S["alive"] = ["1 within 400: Dust Bandit #%s [Dust Bandits]" % NEAR[0]]'; expect fail-distant-6th-dead 14-d FAIL "distant_6th_alive"
scen 'S["atkpost"] = []; S["actlines"] = []; S["recs"] = [[rec("proposed")], [rec("accepted", rev=2)]]; S["alive"] = ["5 within 400: " + " | ".join("Dust Bandit #%s" % x for x in NEAR + [FAR])]'; expect fail-no-effect-on-set 14-d FAIL "effect_on_the_set"
scen 'S["actlines"].append("[t] ACTIVITY_VERIFY_DIAG reason=outside_fixed_hostile_set target=%s" % ns[2])'; expect fail-near-member-refused-as-outside 14-d FAIL "no_set_member_refused_as_outside"
scen 'S["outbox"] = []'; expect pass-accepted-row-via-record-when-outbox-has-no-status 14-d PASS "via record"
# ---- runner + hygiene
bash "$ST_HERE/unblockrun_14d_v2.sh" 13-c $L 2>/dev/null | grep -q '14-d only' && chk runner-rejects-other-rows ok || chk runner-rejects-other-rows bad
KAH_PF_ISOLATION=0 bash "$ST_HERE/unblockrun_14d_v2.sh" 14-d $L 2>/dev/null | grep -q 'ISOLATION=0 is not allowed' && chk runner-refuses-isolation-off ok || chk runner-refuses-isolation-off bad
bash "$ST_HERE/unblockrun_14d_v2.sh" 14-d nolane 2>/dev/null | grep -q "unknown lane" && chk runner-rejects-unknown-lane ok || chk runner-rejects-unknown-lane bad
for f in unblockrun_14d_v2.sh unblockdefs_14d_v2.sh pywrap_u14d.sh unblock_14d_v2_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
for f in unblockcheck_14d.py unblockfake_14d.py unblockfake_14d_v2.py unblockscen_14d.py; do "$P" -m py_compile "$ST_HERE/$f" 2>/dev/null && chk "py-compile-$f" ok || chk "py-compile-$f" bad; done
cd "$A/.." && dd=$(git diff --name-only -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_14d.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockrun_14d.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_14d.py testing/live-stobe-queue/imm26-assert/rowtools/unblockfake_14d.py testing/live-stobe-queue/imm26-assert/rowtools/unblockscen_14d.py testing/live-stobe-queue/imm26-assert/rowtools/pywrap_u14d.sh 2>/dev/null)
[ -z "$dd" ] && chk existing-files-untouched ok || chk existing-files-untouched bad "$dd"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-14D-V2 ALL PASS $ok/$n"; else echo "SELFTEST UNBLOCK-14D-V2 ALL FAIL $ok/$n"; fi
rm -rf "$T"
