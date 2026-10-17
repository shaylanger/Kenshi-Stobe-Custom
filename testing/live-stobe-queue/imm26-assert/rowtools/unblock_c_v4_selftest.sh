#!/usr/bin/env bash
# unblock_c_v4_selftest.sh (imm26-fix15bx05cx3, derived from unblock_c_v3_selftest.sh by imm26-sfU): OFFLINE self-test of unblockdefs_c_v4.sh / unblockcheck_c_v2.py (15-bx v2 scene).  No game, ssh or DB: lanes are simulated by KAH_ROW_DRY
# (gr_default_fake), the verdict logic by synthetic evidence dirs and a logging stub for assert_witness.py.  The v1 files are only READ.
# Prints `SELFTEST unblockCv4-<name> PASS|FAIL` and `SELFTEST UNBLOCK-C-V4 ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_c_v4_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); command -v cygpath >/dev/null && T=$(cygpath -m "$T"); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log"
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX_PRELOADED UC_LOADED HX15_AWAY HX_ASSERT_DIR
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblockCv4-$1 PASS ${3:-}"; else echo "SELFTEST unblockCv4-$1 FAIL ${3:-}"; fi; }
U="${UC_U:-$ST_HERE/unblockdefs_c_v4.sh}"; C="$ST_HERE/unblockcheck_c_v2.py"

# ---- 1. syntax / registration
bash -n "$U" && chk bash-n ok || chk bash-n bad
"$PYB" -m py_compile "$C" && chk py-compile ok || chk py-compile bad
"$PYB" "$C" --has 15-bx && ! "$PYB" "$C" --has 20-a && ! "$PYB" "$C" --has 10-b && chk checker-has-only-15bx ok || chk checker-has-only-15bx bad
r=$(bash "$U" 20-a 4080-i4 2>/dev/null); echo "$r" | grep -q '^RESULT 20-a SETUP-FAIL not a v2 row' && chk runner-refuses-other-rows ok || chk runner-refuses-other-rows bad "$r"
HX_ASSERT_DIR="" "$PYB" -c "
import importlib.util, os, sys
sys.argv=['x']
spec=importlib.util.spec_from_file_location('u', r'$(command -v cygpath >/dev/null && cygpath -m "$C" || echo "$C")'); m=importlib.util.module_from_spec(spec); os.environ.pop('HX_ASSERT_DIR', None); spec.loader.exec_module(m)
sys.exit(0 if os.environ.get('HX_ASSERT_DIR','').replace(chr(92),'/').endswith('/imm26-assert/v2') else 1)" && chk checker-defaults-to-v2-asserters ok || chk checker-defaults-to-v2-asserters bad

# ---- 2. checker (assert_witness replaced by a logging stub; hxcheck.py builds the command line)
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_witness.py"
export HX_ASSERT_DIR="$T/stubs"
mk15() {  # mk15 <dir> [xdist] [pdist] [sleeper] [fighters] [starter] [away yes|no] [after_fight state] [sample state]
  local d="$1" xd="${2:-300}" pd="${3:-10}" sd="${4:-60}" fi="${5:-Vren,Dalla,Hungry}" st="${6:-Vren}" aw="${7:-yes}" saf="${8:-SLEEP_ON_FLOOR}" ssa="${9:-SLEEP_ON_FLOOR}" l
  rm -rf "$d"; mkdir -p "$d"; echo "$d" > "$d/bundle_dir.txt"
  for l in X1 X2 X3; do mkdir -p "$d/$l"; echo "Cind [Hungry Bandit]|$xd" > "$d/$l/distance.txt"; echo "x" > "$d/$l/prompt.txt"; done
  for l in P1 P2 P3; do mkdir -p "$d/$l"; echo "Cind [Hungry Bandit]|$pd" > "$d/$l/distance.txt"; done
  mkdir -p "$d/S1"; echo "Drifter One|$sd" > "$d/S1/distance.txt"
  [ "$aw" = yes ] && echo "12:00:00 away=far Cind [Hungry Bandit] -> -53200 957 4893" > "$d/away.txt"
  if [ "$saf" != NONE ]; then
    printf '%s\n' "ordered|\"unconscious\":false \"first_order\":\"SLEEP_ON_FLOOR\" " "after_fight|\"unconscious\":false \"first_order\":\"$saf\" " "sample|\"unconscious\":false \"first_order\":\"$ssa\" " > "$d/S1/sleep_state.txt"
  fi
  echo "$fi" > "$d/fighters.txt"; echo "$st" > "$d/starter.txt"
}
c15() { "$PYB" "$C" 15-bx "$1" 2>/dev/null | head -1; }
mk15 "$T/e15a"; rm -f "$STUB_LOG"; r=$(STUB_KIND=PASS c15 "$T/e15a")
case "$r" in "RESULT 15-bx PASS"*"S1 sleep"*) chk good-scene-pass ok;; *) chk good-scene-pass bad "$r";; esac
tr "\\\\" "/" < "$STUB_LOG" | grep -q -- "--out $T/e15a/X1 $T/e15a/X2 $T/e15a/X3 --inrange $T/e15a/P1 $T/e15a/P2 $T/e15a/P3 --asleep $T/e15a/S1 --fighters Vren,Dalla,Hungry --starter Vren" && chk assert-argv-unchanged ok || chk assert-argv-unchanged bad "$(cat "$STUB_LOG" 2>/dev/null | head -2)"
mk15 "$T/e15b" 300 10 60 "Vren,Dalla,Hungry" Vren yes; r=$(STUB_KIND=FAIL c15 "$T/e15b"); case "$r" in "RESULT 15-bx FAIL"*) chk behaviour-fail-passes-through ok;; *) chk behaviour-fail-passes-through bad "$r";; esac
# S1 sleep-state controls (new in v2)
mk15 "$T/e15c" 300 10 60 "Vren,Dalla,Hungry" Vren yes SLEEP_ON_FLOOR NULL_TASK; r=$(c15 "$T/e15c"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"S1 was not asleep"*sample*) chk s1-awake-at-sample-setupfail ok;; *) chk s1-awake-at-sample-setupfail bad "$r";; esac
mk15 "$T/e15d" 300 10 60 "Vren,Dalla,Hungry" Vren yes NULL_TASK SLEEP_ON_FLOOR; r=$(c15 "$T/e15d"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"S1 was not asleep"*after_fight*) chk s1-woken-by-fight-setupfail ok;; *) chk s1-woken-by-fight-setupfail bad "$r";; esac
mk15 "$T/e15e" 300 10 60 "Vren,Dalla,Hungry" Vren yes NONE; r=$(c15 "$T/e15e"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"sleep_state.txt missing"*) chk s1-state-not-recorded-setupfail ok;; *) chk s1-state-not-recorded-setupfail bad "$r";; esac
mk15 "$T/e15f"; "$PYB" - "$T/e15f/S1/sleep_state.txt" <<'EOF'
import sys
p = sys.argv[1]
open(p, 'w').write('ordered|"unconscious":false "first_order":"SLEEP_ON_FLOOR" \nsample|"unconscious":true "first_order":"none" \n')
EOF
r=$(c15 "$T/e15f"); case "$r" in "RESULT 15-bx SETUP-FAIL"*'"after_fight" not recorded'*) chk s1-missing-after-fight-tag-setupfail ok;; *) chk s1-missing-after-fight-tag-setupfail bad "$r";; esac
mk15 "$T/e15g" 300 10 60 "Vren,Dalla,Hungry" Vren yes NULL_TASK NULL_TASK; "$PYB" - "$T/e15g/S1/sleep_state.txt" <<'EOF'
import sys
p = sys.argv[1]
open(p, 'w').write('ordered|"unconscious":false "first_order":"SLEEP_ON_FLOOR" \nafter_fight|"unconscious":true "first_order":"none" \nsample|"unconscious":true "first_order":"none" \n')
EOF
r=$(STUB_KIND=PASS c15 "$T/e15g"); case "$r" in "RESULT 15-bx PASS"*) chk s1-unconscious-counts-as-ko ok;; *) chk s1-unconscious-counts-as-ko bad "$r";; esac
mk15 "$T/e15h" 300 10 60 "Vren,Dalla,Hungry" Vren no; r=$(c15 "$T/e15h"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"away.txt missing"*) chk x-not-sent-away-setupfail ok;; *) chk x-not-sent-away-setupfail bad "$r";; esac
# every v1 scene control still holds
mk15 "$T/e15i" 300 10 60 "Malzin,Vren,Dalla" Vren; r=$(c15 "$T/e15i"); case "$r" in "RESULT 15-bx SETUP-FAIL"*Malzin*) chk v1-malzin-in-roster-setupfail ok;; *) chk v1-malzin-in-roster-setupfail bad "$r";; esac
mk15 "$T/e15j" 218; r=$(c15 "$T/e15j"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"X1 distance"*) chk v1-x-too-close-setupfail ok;; *) chk v1-x-too-close-setupfail bad "$r";; esac
mk15 "$T/e15k" 300 10 5267; r=$(c15 "$T/e15k"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"S1 distance"*) chk v1-sleeper-far-setupfail ok;; *) chk v1-sleeper-far-setupfail bad "$r";; esac
mk15 "$T/e15l" 300 31; r=$(c15 "$T/e15l"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"P1 distance"*) chk v1-p-far-setupfail ok;; *) chk v1-p-far-setupfail bad "$r";; esac
mk15 "$T/e15m" 300 10 60 "Vren,Dalla" "Ukil"; r=$(c15 "$T/e15m"); case "$r" in "RESULT 15-bx SETUP-FAIL"*Ukil*) chk v1-foreign-starter-setupfail ok;; *) chk v1-foreign-starter-setupfail bad "$r";; esac
mk15 "$T/e15n" 300 10 60 Vren Vren; r=$(c15 "$T/e15n"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"<2 names"*) chk v1-one-fighter-setupfail ok;; *) chk v1-one-fighter-setupfail bad "$r";; esac
mk15 "$T/e15o"; rm -rf "$T/e15o/P2"; r=$(c15 "$T/e15o"); case "$r" in "RESULT 15-bx SETUP-FAIL"*"missing"*P2*) chk v1-missing-bundle-setupfail ok;; *) chk v1-missing-bundle-setupfail bad "$r";; esac
unset HX_ASSERT_DIR

# ---- 3. runner as a separate process (dry): the new step order
dry() { ( export KAH_ROW_DRY=1 KAH_ROW_FAKE_LOG="$T/fake-$1$2.log"; : > "$T/fake-$1$2.log"; bash "$U" "$@" 2>/dev/null ); }
r=$(dry 15-bx 4080-i4 --away far); echo "$r" | grep -q '^RESULT 15-bx DRY-RUN' && [ "$(echo "$r" | grep -c '^RESULT')" = 1 ] && chk dry-one-result-line ok || chk dry-one-result-line bad "$r"
L="$T/fake-15-bx4080-i4.log"
awayln=$(grep -n "stobe-auto teleport 'Cind \[Hungry Bandit\]' -53200 957 4893" "$L" | head -1 | cut -d: -f1)
spawnln=$(grep -n 'stobe-auto spawn' "$L" | head -1 | cut -d: -f1)
fightln=$(grep -n 'stobe-auto fight' "$L" | head -1 | cut -d: -f1)
[ -n "$awayln" ] && [ -n "$spawnln" ] && [ "$awayln" -lt "$spawnln" ] && [ "$awayln" -lt "$fightln" ] && chk x-sent-to-HX_FAR-before-spawn-and-fight ok "line $awayln < $spawnln < $fightln" || chk x-sent-to-HX_FAR-before-spawn-and-fight bad "away=$awayln spawn=$spawnln fight=$fightln"
sed -n "$((awayln-1)),$((awayln+1))p" "$L" | grep -q "teleport Shay 'Cind \[Hungry Bandit\]'" && chk shay-follows-x-to-far ok || chk shay-follows-x-to-far bad
[ "$(grep -c "stobe-auto teleport 'Cind \[Hungry Bandit\]' -53200 957 4893" "$L")" = 1 ] && chk away-only-in-out-phase ok || chk away-only-in-out-phase bad "count=$(grep -c "stobe-auto teleport 'Cind \[Hungry Bandit\]' -53200 957 4893" "$L")"
awk -v a="$awayln" 'NR>a && /stobe-auto spawn/ {f=1} END{exit !f}' "$L" && chk spawns-after-away ok || chk spawns-after-away bad
# X is brought to spot+320 for the samples only (unchanged v1 step), after the fight
xln=$(grep -n "stobe-auto teleport 'Cind \[Hungry Bandit\]' -47680 1500 2960" "$L" | head -1 | cut -d: -f1)
[ -n "$xln" ] && [ "$xln" -gt "$fightln" ] && chk x-to-spot+320-only-after-fight ok || chk x-to-spot+320-only-after-fight bad "x=$xln fight=$fightln"
EV15="$KAH_ROWS_BASE/imm26-4080-i4/rows/15-bx"
[ -s "$EV15/away.txt" ] && grep -q 'away=far' "$EV15/away.txt" && chk away-txt-recorded ok || chk away-txt-recorded bad
[ "$(wc -l < "$EV15/S1/sleep_state.txt")" = 3 ] && grep -q '^ordered|' "$EV15/S1/sleep_state.txt" && grep -q '^after_fight|' "$EV15/S1/sleep_state.txt" && grep -q '^sample|' "$EV15/S1/sleep_state.txt" && chk sleep-state-three-tags ok || chk sleep-state-three-tags bad "$(cat "$EV15/S1/sleep_state.txt" 2>/dev/null | head -3)"
[ "$(grep -c 'stobe_say' "$L")" = 7 ] && chk seven-samples-unchanged ok || chk seven-samples-unchanged bad "say count $(grep -c 'stobe_say' "$L")"
grep -q "delete from eventlog where type in ('combat','combat_start','combat_end')" "$L" && grep -q 'stobe-auto teleport Malzin' "$L" && [ "$(grep -c 'stobe-auto fight' "$L")" -ge 2 ] && ! grep -q 'fight Malzin' "$L" && chk v1-scene-steps-kept ok || chk v1-scene-steps-kept bad
# --away near : spot+320 instead of the far spot
r=$(dry 15-bx 4080-i4 --away near); L2="$T/fake-15-bx4080-i4.log"
echo "$r" | grep -q '^RESULT 15-bx DRY-RUN' && grep -q 'away=near' "$EV15/away.txt" && grep -n "stobe-auto teleport 'Cind \[Hungry Bandit\]' -47680 1500 2960" "$L2" | head -1 | cut -d: -f1 | awk -v s="$(grep -n 'stobe-auto spawn' "$L2" | head -1 | cut -d: -f1)" '{exit !($1 < s)}' && chk away-near-option ok || chk away-near-option bad "$(cat "$EV15/away.txt" 2>/dev/null)"
r=$(bash "$U" 15-bx nolane 2>/dev/null); [ "$(echo "$r" | wc -l)" = 1 ] && echo "$r" | grep -q 'SETUP-FAIL' && chk unknown-lane-setupfail ok || chk unknown-lane-setupfail bad "$r"
r=$(UC_LOADED=1 bash "$U" -c 'print(40+2)' 2>&1); [ "$r" = 42 ] && chk shim-passes-python ok || chk shim-passes-python bad "$r"
mkdir -p "$T/e15s"; r=$(UC_LOADED=1 bash "$U" /x/rowtools/rowcheck.py 15-bx "$T/e15s" 2>/dev/null | head -1); case "$r" in "RESULT 15-bx SETUP-FAIL"*) chk shim-routes-15bx-to-v2-checker ok;; *) chk shim-routes-15bx-to-v2-checker bad "$r";; esac

# ---- 4. library mode + v1 / operator files untouched
r=$(bash -c ". '$A/go-row.sh'; . '$ST_HERE/hxdefs.sh'; . '$U'; echo \$(declare -f rd_15bx | grep -c 'ub15_scene \"\$HX_SAVE\" away') \$(declare -f ub15_scene | grep -c HX15_AWAY)" 2>&1 | tail -1)
[ "${r%% *}" = 1 ] && [ "${r##* }" -ge 1 ] 2>/dev/null && chk library-mode-redefines-rd_15bx ok || chk library-mode-redefines-rd_15bx bad "$r"
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_c.py testing/live-stobe-queue/imm26-assert/rowtools/rowdefs.sh testing/live-stobe-queue/imm26-assert/imm26_lib.py testing/live-stobe-queue/imm26-assert/assert_principle.py 2>/dev/null && chk v1-files-untouched ok || chk v1-files-untouched bad "modified"

# ---- 5. ub15_say (sfU2): cancelled reply -> one repeat, second cancellation -> named SETUP-FAIL; plain no-reply -> no repeat
cat > "$T/say_t.sh" <<'EOS'
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$U"
KAH_ROW_DRY=; HXD="$T/hxd"; EV="$T/ev"; UB_NPC=Cind; mkdir -p "$HXD" "$EV"; calls=0; places=0
hxd_sample() { calls=$((calls+1)); mkdir -p "$HXD/$1"; if [ "$MODE" != plain ]; then echo '24097|chat|Cind: x (talking to: Shay)|cancelled' > "$HXD/$1/events.txt"; else echo '1|chat|y|' > "$HXD/$1/events.txt"; fi
  if [ "$MODE" = okretry ] && [ $calls = 2 ]; then return 0; fi; RL_REASON="no reply of Cind within 150s in $1"; return 3; }
pl() { places=$((places+1)); mkdir -p "$HXD/$1"; return 0; }
ub15_say P1 "q" pl; rc=$?; echo "rc=$rc calls=$calls places=$places reason=$RL_REASON retry=$(ls "$EV/retry" 2>/dev/null | paste -sd, -)"
EOS
for MODE in cancelled plain okretry; do export MODE A ST_HERE U T; echo "$MODE: $(bash "$T/say_t.sh" 2>&1 | tail -1)"; done > "$T/say.out"
grep -q '^cancelled: rc=3 calls=2 places=1 .*first try AND the retry.*P1-cancelled.txt' "$T/say.out" && chk say-cancelled-retries-once-then-names-it ok || chk say-cancelled-retries-once-then-names-it bad "$(grep ^cancelled "$T/say.out")"
grep -q '^plain: rc=3 calls=1 places=0 ' "$T/say.out" && chk say-plain-noreply-no-retry ok || chk say-plain-noreply-no-retry bad "$(grep ^plain "$T/say.out")"
grep -q '^okretry: rc=0 calls=2 places=1 ' "$T/say.out" && chk say-ok-no-retry ok || chk say-ok-no-retry bad "$(grep ^okretry "$T/say.out")"

# ---- 6. v3 (imm26-fix15bx05cx): ko instead of sleep, KO gate, ko re-issue before the sample, social_rumor purge, rename poll, renamed starter
L3="$T/fake-15-bx4080-i4.log"
if grep -q "stobe-auto ko '#[0-9]*/[0-9]*' 900" "$L3" && ! grep -q "stobe-auto sleep" "$L3"; then chk v3-ko-900-replaces-sleep ok; else chk v3-ko-900-replaces-sleep bad "$(grep -c 'stobe-auto sleep' "$L3") sleep lines"; fi
k1=$(grep -n "stobe-auto ko '#[0-9]*/[0-9]*' 900" "$L3" | head -1 | cut -d: -f1); k2=$(grep -n "stobe-auto ko '#[0-9]*/[0-9]*' 120" "$L3" | head -1 | cut -d: -f1); lastst=$(grep -n 'stobe_state' "$L3" | tail -1 | cut -d: -f1)
[ -n "$k1" ] && [ -n "$k2" ] && [ "$k2" -gt "$k1" ] && [ "$k2" -lt "$lastst" ] && chk v3-ko-120-reissued-before-sample ok "$k1 < $k2 < $lastst" || chk v3-ko-120-reissued-before-sample bad "k1=$k1 k2=$k2 laststate=$lastst"
grep -q "update social_rumor set status='retired' where status='active'" "$L3" && [ "$(grep -c "update social_rumor" "$L3")" = 2 ] && chk v3-social-rumor-retired-both-loads ok || chk v3-social-rumor-retired-both-loads bad "count=$(grep -c 'update social_rumor' "$L3")"
cat > "$T/v3_t.sh" <<'EOS'
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$U"
export KAH_ROW_FAKE=1; unset KAH_ROW_DRY; HXD="$T/hxd3"; EV="$T/ev3"; mkdir -p "$HXD" "$EV"; UB_NPC=Cind; REACHED=no
hxd_begin() { :; }; rd_need_npc() { :; }; ub15_scene() { :; }; hxd_rowid() { echo 0; }; lt_h() { cat >/dev/null; }
ub_spawn() { UB_ID="#9/9"; }
ub15_sleep_state() { mkdir -p "$HXD/S1"; echo "$1|$STATE" >> "$HXD/S1/sleep_state.txt"; }
# fix15bxorder: the OUT-phase pair is now spawned FIRST (call 1 = ok, X1-X3 sampled with mocks), then S1 + ko + gate; call 2 (IN phase, after the S1 sample) stops the run
PAIRN=0; ub15_pair() { PAIRN=$((PAIRN+1)); UB_FN=A,B; UB_STARTER=A; UB_ID1="#9/1"; [ $PAIRN -ge 2 ] || return 0; REACHED=yes; RL_REASON="stop-after-gate"; return 3; }
ub15_place_x() { :; }; ub15_say() { :; }; hxd_dist() { :; }; ub15_place_s() { :; }; hxd_sample() { :; }; hxd_trim() { :; }
STATE='"unconscious":false "first_order":"SLEEP_ON_FLOOR"'
PAIRN=0; rd_15bx; echo "gate-false rc=$? reached=$REACHED reason=$RL_REASON pairs=$PAIRN"
REACHED=no; PAIRN=0; STATE='"unconscious": true "first_order":"none"'; rm -f "$HXD/S1/sleep_state.txt"
rd_15bx; echo "gate-true rc=$? reached=$REACHED reason=$RL_REASON pairs=$PAIRN"
EOS
export A ST_HERE U T; bash "$T/v3_t.sh" > "$T/v3_t.out" 2>&1
grep -q '^gate-false rc=3 reached=no reason=S1 not KO right after the ko order.*needs: recipe pairs=1' "$T/v3_t.out" && chk v3-awake-s1-fails-fast-before-pair ok || chk v3-awake-s1-fails-fast-before-pair bad "$(grep ^gate-false "$T/v3_t.out")"
grep -q '^gate-true rc=3 reached=yes reason=stop-after-gate pairs=2' "$T/v3_t.out" && chk v3-ko-s1-passes-gate-to-pair ok || chk v3-ko-s1-passes-gate-to-pair bad "$(grep ^gate-true "$T/v3_t.out")"
# ---- 6b. fix15bxorder: X1-X3 are sampled before S1 exists / is KO'd (X's prompt must not show an unconscious body: "I came in after <S1> was down" = EYEWITNESS)
say3=$(grep -n 'stobe_say' "$L3" | sed -n 3p | cut -d: -f1); say4=$(grep -n 'stobe_say' "$L3" | sed -n 4p | cut -d: -f1); kofirst=$(grep -n "stobe-auto ko " "$L3" | head -1 | cut -d: -f1)
[ -n "$say3" ] && [ -n "$kofirst" ] && [ "$kofirst" -gt "$say3" ] && chk v4c-no-ko-before-x-samples ok "x3 say line $say3 < first ko line $kofirst" || chk v4c-no-ko-before-x-samples bad "say3=$say3 ko=$kofirst"
[ -n "$say4" ] && [ "$kofirst" -lt "$say4" ] && chk v4c-s1-ko-before-s1-sample ok "ko $kofirst < s1 say $say4" || chk v4c-s1-ko-before-s1-sample bad "ko=$kofirst say4=$say4"
dsp=$(grep -n 'Shay dist 25' "$L3" | head -1 | cut -d: -f1); [ -n "$dsp" ] && [ "$dsp" -gt "$say3" ] && [ "$dsp" -lt "$kofirst" ] && chk v4c-s1-placed-after-x-samples-before-ko ok "x3 say $say3 < s1 teleport-to-Shay $dsp < ko $kofirst" || chk v4c-s1-placed-after-x-samples-before-ko bad "s1tp=$dsp say3=$say3 ko=$kofirst"
# no unconscious Nearby entry in an X prompt: clean prompt passes; the real v3 shapes ("Action: unconscious", "doing:unconscious", roster "(unconscious)") are SETUP-FAIL
mk15 "$T/e15u" 300 10 60 "Vren,Dalla,Hungry" Vren yes; r=$(HX_ASSERT_DIR="$T/stubs" c15 "$T/e15u"); case "$r" in "RESULT 15-bx PASS"*) chk v4c-clean-x-prompt-passes ok;; *) chk v4c-clean-x-prompt-passes bad "$r";; esac
si=0; for shape in "- Nyt [Hungry Bandit] (Male Shek): Faction: Drifters [Neutral] | Action: unconscious | Appearance: x" "Nyt [Hungry Bandit] (male) | doing:unconscious (knocked out, cannot talk) | condition:-" "[infonpc] Shay: nearby NPC roster (2): Cind [Hungry Bandit], Nyt [Hungry Bandit] (unconscious)"; do
  mk15 "$T/e15v" 300 10 60 "Vren,Dalla,Hungry" Vren yes; printf 'ok line
%s
' "$shape" > "$T/e15v/X2/prompt.txt"; r=$(c15 "$T/e15v"); si=$((si+1))
  case "$r" in "RESULT 15-bx SETUP-FAIL"*"X2 prompt shows an unconscious"*) chk "v4c-unconscious-in-x-prompt-setupfail-$si" ok;; *) chk "v4c-unconscious-in-x-prompt-setupfail-$si" bad "$r";; esac
done
# the AVAILABLE ACTION catalogue mentions "unconscious" in every prompt: must not trip the guard
mk15 "$T/e15w" 300 10 60 "Vren,Dalla,Hungry" Vren yes; printf 'AVAILABLE ACTION: CutHorns (Works only on dead, knocked-out, unconscious, imprisoned, or carried Shek)
- Only say that someone is knocked out when the people list shows it. unconscious
' > "$T/e15w/X1/prompt.txt"; r=$(HX_ASSERT_DIR="$T/stubs" c15 "$T/e15w"); case "$r" in "RESULT 15-bx PASS"*) chk v4c-action-catalogue-not-flagged ok;; *) chk v4c-action-catalogue-not-flagged bad "$r";; esac
# ---- 7. v4 (imm26-fix15bx05cx3)
# 7a default away is near ; explicit far still works
r=$(dry 15-bx 4080-i4); LD="$T/fake-15-bx4080-i4.log"
echo "$r" | grep -q '^RESULT 15-bx DRY-RUN' && grep -q 'away=near' "$EV15/away.txt" && ! grep -q "teleport 'Cind \[Hungry Bandit\]' -53200 957 4893" "$LD" && chk v4-default-away-near ok || chk v4-default-away-near bad "$(cat "$EV15/away.txt" 2>/dev/null)"
# 7b both fighters get their own names (setname) before the fight order
sn1=$(grep -n "stobe-auto setname '#9/[0-9]*' 'Garrick'" "$LD" | head -1 | cut -d: -f1); sn2=$(grep -n "stobe-auto setname '#9/[0-9]*' 'Odrun'" "$LD" | head -1 | cut -d: -f1); fi1=$(grep -n 'stobe-auto fight' "$LD" | head -1 | cut -d: -f1)
[ -n "$sn1" ] && [ -n "$sn2" ] && [ -n "$fi1" ] && [ "$sn1" -lt "$fi1" ] && [ "$sn2" -lt "$fi1" ] && chk v4-setname-both-before-fight ok "$sn1,$sn2 < $fi1" || chk v4-setname-both-before-fight bad "sn=$sn1,$sn2 fight=$fi1"
r=$(dry 15-bx 4080-i4 --names "Aldo Brek"); grep -q "setname '#9/[0-9]*' 'Aldo'" "$LD" && grep -q "setname '#9/[0-9]*' 'Brek'" "$LD" && chk v4-names-option ok || chk v4-names-option bad
head -1 "$EV15/fighters.txt" 2>/dev/null | grep -q "^Aldo,Brek" && chk v4-fighters-file-has-assigned-names ok || chk v4-fighters-file-has-assigned-names bad "$(cat "$EV15/fighters.txt" 2>/dev/null)"
# 7c ub15_pair with mocks: SQL filter on the fighters' names ; ambient rows ignored ; failure diagnosis
cat > "$T/v4_p.sh" <<'EOS'
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$U"
export KAH_ROW_FAKE=1; unset KAH_ROW_DRY; HXD="$T/hxd5"; EV="$T/ev5"; mkdir -p "$HXD" "$EV"; UB_NPC=Cind
ub_spawn() { UB_ID="#9/$((++sp))"; UB_SHORT=Hungry; }
hxd_rowid() { echo 100; }; hxd_fight() { echo "fight $1 $2" >> "$EV/fight.txt"; }; hxd_sleep() { :; }
ub_name() { case "$1" in "#9/1") echo "${N1:-Garrick [HNO]}";; *) echo "${N2:-Odrun [DB]}";; esac; }
lt_h() { cat >/dev/null; echo "Garrick [HNO] #9/1 pos=1,2,3"; }
lt_sql() { echo "$1" >> "$T/sql.log"
  case "$1" in
    "select count(*)"*) echo 31;;
    *"like 'Garrick:%'"*) [ "$MODE" = none ] && return 0; echo "Odrun: Initiated attack (talking to: Garrick [HNO])"; echo "Garrick: Initiated attack (talking to: Odrun)";;
    *) echo "Grink: Initiated attack (talking to: Rhuk [Dust Bandit])";;
  esac; }
for MODE in ours none heldnot; do sp=0; rm -f "$T/sql.log" "$EV/phases.txt" "$EV/pair_diag.txt"; UB_STARTER=; RL_REASON=
  if [ "$MODE" = heldnot ]; then N1="Hungry Bandit [HNO]"; N2="Hungry Bandit [DB]"; HX15_RENAME_N=1; else unset N1 N2; fi
  ub15_pair; echo "$MODE rc=$? fn=$UB_FN starter=$UB_STARTER diag=$([ -s "$EV/pair_diag.txt" ] && echo yes || echo no) reason=$(echo "$RL_REASON" | cut -c1-420)"; done
EOS
export A ST_HERE U T; bash "$T/v4_p.sh" > "$T/v4_p.out" 2>&1
grep -q '^ours rc=0 fn=Garrick,Odrun starter=Odrun diag=no' "$T/v4_p.out" && chk v4-starter-from-own-names-not-ambient ok || chk v4-starter-from-own-names-not-ambient bad "$(grep ^ours "$T/v4_p.out")"
grep -q "data like 'Garrick:%' or data like 'Odrun:%'" "$T/sql.log" && chk v4-sql-filters-on-fighter-names ok || chk v4-sql-filters-on-fighter-names bad "$(head -c 300 "$T/sql.log")"
grep -q '^none rc=3 fn=Garrick,Odrun starter= diag=yes reason=no .Initiated attack. row by one of the fighters (Garrick,Odrun) within 30 s.*Initiated-attack rows after the mark: 31, by our pair: 0.*pair_diag.txt' "$T/v4_p.out" && chk v4-no-own-row-setupfail-with-diagnosis ok || chk v4-no-own-row-setupfail-with-diagnosis bad "$(grep ^none "$T/v4_p.out")"
grep -q '^heldnot rc=0 fn=Garrick,Odrun,Hungry starter=Odrun' "$T/v4_p.out" && chk v4-setname-not-held-falls-back-to-spawn-name ok || chk v4-setname-not-held-falls-back-to-spawn-name bad "$(grep ^heldnot "$T/v4_p.out")"
# 7d save: lane default exists, missing save = loud SETUP-FAIL before any load
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$PYB\" '$ST_HERE/hxfake_cx4.py' \"\$@\"; }; export -f lt_fake; export KAH_ROW_FAKE=1; exec bash '$U' \"\$@\"" _ "$@" 2>/dev/null; }
export FAKE_SCEN="$T/scen.json"; export FAKE_STATE="$T/state.json"
"$PYB" "$ST_HERE/hxscen_cx4.py" savemissing > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"
o=$(cli 15-bx 5090-i3 --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | grep -q '^RESULT 15-bx SETUP-FAIL SAVE-MISSING base save .kah-imm26-5090-ready. does not exist' && [ $rc = 2 ] && ! grep -q 'stobe-auto load' "$KAH_ROW_FAKE_LOG" && chk v4-missing-save-fails-loudly ok || chk v4-missing-save-fails-loudly bad "rc=$rc $o"
"$PYB" "$ST_HERE/hxscen_cx4.py" base > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"
o=$(cli 15-bx 5090-i3 --allow-retry selftest); grep -q "stobe-auto load kah-imm26-5090-ready" "$KAH_ROW_FAKE_LOG" && ! grep -q hxA "$KAH_ROW_FAKE_LOG" && chk v4-i3-default-save-is-ready ok || chk v4-i3-default-save-is-ready bad "$(echo "$o" | head -2)"
"$PYB" "$ST_HERE/hxscen_cx4.py" savemissing > "$FAKE_SCEN"; o2=$(cli 15-bx 5090-i3 --save kah-imm26-5090-hxA --allow-retry selftest)
echo "$o2" | grep -q 'SAVE-MISSING base save .kah-imm26-5090-hxA.' && chk v4-explicit-missing-save-fails ok || chk v4-explicit-missing-save-fails bad "$o2"
unset FAKE_SCEN FAKE_STATE

# ---- 8. fix15bxv5: ub15_place_p pins F1 (HOLD_POSITION) so a MOVING fighter cannot run off between the teleport and the distance read (op25: P3 17.4 u > 15)
cat > "$T/pin_t.sh" <<'EOS'
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$U"
export KAH_ROW_FAKE=1; unset KAH_ROW_DRY; HXD="$T/hxd8"; EV="$T/ev8"; rm -rf "$HXD" "$EV"; mkdir -p "$HXD" "$EV"; UB_NPC="Cind [Hungry Bandit]"; UB_ID1="#9/1"
S8="$T/s8"; rm -rf "$S8"; mkdir -p "$S8"; echo 1000 > "$S8/f1x"; echo 1000 > "$S8/px"; echo 0 > "$S8/pinned"; : > "$S8/calls"
# moving-fighter fixture: F1 runs 20 u the moment P is teleported next to it unless it was pinned (HOLD_POSITION); MODE=stuck: the teleport never lands within range
lt_h() { local l f1x px d
  while IFS= read -r l; do
    case "$l" in
      *"order '#9/1' HOLD_POSITION keep"*) echo 1 > "$S8/pinned"; echo "pin" >> "$S8/calls"; echo "ordered";;
      *"where '#9/1'"*) f1x=$(cat "$S8/f1x"); echo "Garrick #9/1 [HNO] pos=$f1x,0,0";;
      *"where 'Cind"*) px=$(cat "$S8/px"); echo "Cind [Hungry Bandit] #1/2 [x] pos=$px,0,0";;
      *"teleport 'Cind [Hungry Bandit]' '#9/1' dist "*) d=${l##*dist }; d=${d%% *}; f1x=$(cat "$S8/f1x"); echo "tp" >> "$S8/calls"
        if [ "${MODE:-}" = stuck ]; then echo $((f1x+40)) > "$S8/px"; else echo $((f1x+d)) > "$S8/px"; fi
        [ "$(cat "$S8/pinned")" = 1 ] || echo $((f1x-20)) > "$S8/f1x";;
    esac
  done; }
for MODE in moving stuck; do echo 1000 > "$S8/f1x"; echo 1000 > "$S8/px"; echo 0 > "$S8/pinned"; : > "$S8/calls"; RL_REASON=
  ub15_place_p P1; echo "$MODE rc=$? calls=$(paste -sd, "$S8/calls") dist=$(cat "$HXD/P1/distance.txt" | tr '\n' ' ') reason=$(echo "$RL_REASON" | cut -c1-120)"; done
EOS
export A ST_HERE U T; bash "$T/pin_t.sh" > "$T/pin_t.out" 2>&1
grep -q '^moving rc=0 calls=pin,tp ' "$T/pin_t.out" && grep -q '^moving rc=0 .*dist=Cind .Hungry Bandit.|10.0' "$T/pin_t.out" && chk v5-moving-fighter-pinned-p-within-15 ok || chk v5-moving-fighter-pinned-p-within-15 bad "$(grep ^moving "$T/pin_t.out" | head -1)"
grep -q '^stuck rc=3 .*reason=P could not be placed within 15 u of the fight at P1' "$T/pin_t.out" && [ "$(grep '^stuck' "$T/pin_t.out" | grep -o 'tp' | wc -l)" = 3 ] && chk v5-distance-guard-still-setupfails ok || chk v5-distance-guard-still-setupfails bad "$(grep ^stuck "$T/pin_t.out" | head -1)"
grep -q 'HOLD_POSITION keep' "$T/ev8/pin.txt" 2>/dev/null; [ -s "$T/ev8/pin.txt" ] && chk v5-pin-evidence-file ok || chk v5-pin-evidence-file bad
# the dry run issues the pin before the first P placement
grep -q "stobe-auto order '#9/[0-9]*' HOLD_POSITION keep" "$L3" && chk v5-dry-run-issues-pin ok || chk v5-dry-run-issues-pin bad "no HOLD_POSITION in the dry fake log"

rm -rf "$T"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-C-V4 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-C-V4 ALL FAIL $ok/$n"; exit 1; fi
