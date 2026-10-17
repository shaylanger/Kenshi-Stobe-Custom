#!/usr/bin/env bash
# ab2-selftest.sh: offline selftest of the pilot-2 kit (plan, turn check, lock, drift guard, mark, next-refusals, void, compare). No game, no lane, no WSL.
# Uses a temp data dir and fake row scripts; prints `SELFTEST OK (n checks)` or the first failing check.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
T="$(mktemp -d)"; TW="$(cygpath -m "$T" 2>/dev/null || echo "$T")"
trap 'rm -rf "$T"' EXIT
export AB2_DIR="$TW/ab2" KAH_RUNS_DIR="$TW/runs" AB2_ASSERT="$TW/assert" AB2_ROWS_DIR="$TW/rows" AB2_RESET_CMD="echo RESULT lane-setup fake PASS"
export AB2_FAKE_BASELINE='{"dll_mods":"AAAAAAAA","dll_re":"AAAAAAAA","bundle":"b1","saves":{"kah-imm26-i4":"1:aa"}}'
mkdir -p "$T/ab2" "$T/runs/agents" "$T/assert/rowtools" "$T/rows"
cat > "$T/assert/rowtools/fake.sh" <<'EOF'
#!/usr/bin/env bash
ROW="$1"; mkdir -p "$AB2_ROWS_DIR/$ROW"; echo "ev" > "$AB2_ROWS_DIR/$ROW/result.txt"
echo "noise line 1"; echo "EVIDENCE $ROW x"; echo "RESULT $ROW ${FAKE_WORD:-PASS} fake evidence"
EOF
cat > "$T/ab2/queue.txt" <<'EOF'
02-ax :: bash rowtools/fake.sh 02-ax {ARM}
23-b :: bash rowtools/fake.sh 23-b {ARM}
EOF
cp "$HERE/brief.md" "$T/ab2/brief.md"
N=0; FAILS=0
ok()   { N=$((N+1)); }
chk()  { N=$((N+1)); if ! eval "$2"; then echo "SELFTEST FAIL [$1]: $2"; FAILS=$((FAILS+1)); fi; }
S() { "$PY" -I "$HERE/ab2-state.py" "$@"; }

OUT="$("$PY" -I "$HERE/ab2-plan.py" --seed 5 2>&1)"; chk plan-written "[ -f '$T/ab2/plan.json' ]"
OUT2="$("$PY" -I "$HERE/ab2-plan.py" --seed 6 2>&1)"; RC=$?; chk plan-frozen "[ $RC = 3 ]"
FIRST="$("$PY" -I -c "import json;p=json.load(open('$TW/ab2/plan.json'));r=p['runs'];print(r[0]['arm'],r[0]['row'],r[1]['arm'],r[2]['arm'],r[3]['arm'],r[2]['row'])")"
set -- $FIRST; A1=$1; R1=$2; A2=$3; A3=$4; A4=$5; R2=$6
chk abba "[ '$A1' != '$A2' ] && [ '$A3' = '$A2' ] && [ '$A4' = '$A1' ]"
chk two-rows "[ '$R1' != '$R2' ]"

# ab2-next: first spawn ok, prompt filled
NX="$("$PY" -I "$HERE/ab2-next.py" 2>&1)"; chk next-ok "echo \"\$NX\" | grep -q 'agent=ab2-$A1-$R1' && echo \"\$NX\" | grep -q '\[case:bench\] \[model:$A1\] \[effort:high\]'"
chk next-prompt-filled "echo \"\$NX\" | grep -q 'You are \`ab2-$A1-$R1\`' && ! echo \"\$NX\" | grep -q '{ROW}'"
chk active-touched "[ -f '$T/ab2/ACTIVE' ]"

# wrong arm / wrong row refused, nothing ran
OUT="$(bash "$HERE/ab2-run.sh" $A2 $R1 2>&1)"; RC=$?; chk wrong-arm "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'not your turn'"
chk no-lock-left "[ ! -d '$T/ab2/RUNNING' ]"
# stale lock refuses
mkdir "$T/ab2/RUNNING"; OUT="$(bash "$HERE/ab2-run.sh" $A1 $R1 2>&1)"; RC=$?; chk lock-refuses "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'already in progress'"; rmdir "$T/ab2/RUNNING"

# run 1 (PASS)
OUT="$(bash "$HERE/ab2-run.sh" $A1 $R1 2>&1)"; RC=$?; chk run1 "[ $RC = 0 ] && echo \"\$OUT\" | grep -q 'RESULT $R1 PASS' && echo \"\$OUT\" | grep -q 'ab2-run: exit=0'"
chk run1-tail4 "[ \$(echo \"\$OUT\" | grep -c 'noise line 1') = 1 ]"
chk run1-evidence "[ -f '$T/ab2/$A1/evidence/$R1/result.txt' ] && [ -f '$T/ab2/$A1/out/$R1.out' ]"
chk run1-capture "grep -q '\"checker\":\"PASS\"' '$T/ab2/captures.jsonl'"
chk next-after-run-needs-agent-status "! $PY -I '$HERE/ab2-next.py' >/dev/null 2>&1"   # prev agent has no status file
# mark: wrong word refused, right word accepted
OUT="$(bash "$HERE/ab2-mark.sh" $A1 $R1 FAIL "RESULT $R1 PASS fake" 2>&1)"; RC=$?; chk mark-wrong "[ $RC = 3 ]"
OUT="$(bash "$HERE/ab2-mark.sh" $A1 $R1 PASS "RESULT $R1 PASS fake" 2>&1)"; RC=$?; chk mark-right "[ $RC = 0 ] && echo \"\$OUT\" | grep -q ACCEPTED"
chk csv "grep -q '^$R1,5090-i4,$A1,' '$T/ab2/$A1/verdicts.csv'"
chk no-claims "[ ! -d '$T/runs/claims' ]"
# agent status terminal -> next ok
printf 'ab2-%s-%s | RUNNING | 2026-01-01 00:00\ntask: x\n' $A1 $R1 > "$T/runs/agents/ab2-$A1-$R1.status"
chk next-blocked-running "! $PY -I '$HERE/ab2-next.py' >/dev/null 2>&1"
printf 'ab2-%s-%s | DONE | 2026-01-01 00:01\ntask: x\n' $A1 $R1 > "$T/runs/agents/ab2-$A1-$R1.status"
chk next-ok-after-done "$PY -I '$HERE/ab2-next.py' --check-only >/dev/null 2>&1"

# drift: second arm run after the row script changed -> refused; allowed with the override and recorded
echo "# changed" >> "$T/assert/rowtools/fake.sh"
OUT="$(bash "$HERE/ab2-run.sh" $A2 $R1 2>&1)"; RC=$?; chk drift-refused "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'control broken'"
chk drift-no-lock "[ ! -d '$T/ab2/RUNNING' ]"
sed -i '$d' "$T/assert/rowtools/fake.sh"   # revert -> identical hash again
# baseline drift (different DLL) refused
OUT="$(AB2_FAKE_BASELINE='{"dll_mods":"BBBBBBBB","dll_re":"AAAAAAAA","bundle":"b1","saves":{}}' bash "$HERE/ab2-run.sh" $A2 $R1 2>&1)"; RC=$?; chk baseline-refused "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'dll_mods'"
# reset failure aborts without advancing
OUT="$(AB2_RESET_CMD='echo RESULT lane-setup fake FAIL' bash "$HERE/ab2-run.sh" $A2 $R1 2>&1)"; RC=$?; chk reset-fail "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'scene reset FAILED' && [ ! -d '$T/ab2/RUNNING' ]"
# run 2 (second arm) with a SETUP-FAIL checker -> PASS mark refused, ESCALATE accepted as closed (exit 4)
OUT="$(FAKE_WORD=SETUP-FAIL bash "$HERE/ab2-run.sh" $A2 $R1 2>&1)"; RC=$?; chk run2 "[ $RC = 0 ] && echo \"\$OUT\" | grep -q 'RESULT $R1 SETUP-FAIL'"
OUT="$(bash "$HERE/ab2-mark.sh" $A2 $R1 PASS "x" 2>&1)"; RC=$?; chk mark-setupfail-pass-refused "[ $RC = 3 ]"
OUT="$(bash "$HERE/ab2-mark.sh" $A2 $R1 SETUP-FAIL "RESULT $R1 SETUP-FAIL fake" 2>&1)"; RC=$?; chk mark-setupfail-escalates "[ $RC = 4 ] && ls '$T/runs/inbox/coordinator' | grep -q pilot-escalate-$R1"
chk plan-advanced "S status | grep -q 'seq  3 .*CURRENT'"
# void the pair of row 2 seq 3, then seq 4 current
S void 3 "agent never ran" >/dev/null; chk void "S status | grep -q 'seq  3 .*VOID' && S status | grep -q 'seq  4 .*CURRENT'"
# end of plan
S void 4 "skip" >/dev/null; "$PY" -I "$HERE/ab2-next.py" >/dev/null 2>&1; chk plan-complete "[ $? = 4 ]"
# compare (no transcripts: cost off)
CMP="$("$PY" -I "$HERE/pilot-ab2-compare.py" --no-cost 2>&1)"; chk compare-table "echo \"\$CMP\" | grep -q '| $R1 |' && echo \"\$CMP\" | grep -q '## Totals'"
chk compare-selftest "$PY -I '$HERE/pilot-ab2-compare.py' --selftest | grep -q 'SELFTEST OK'"

# ---- rebaseline (ab2-rebaseline.py): archive + regenerate on the new lane state, refusals. Own data dir R (the main one above has runs).
RB() { "$PY" -I "$HERE/ab2-rebaseline.py" "$@"; }
GOODLANE='{"pid":4242,"lock_owner":"rig5090-imm26-i4","inflight":true,"held":true,"backend":"ok"}'
NEWBASE='{"dll_mods":"3FE805BF","dll_re":"3FE805BF","bundle":"b2","saves":{"kah-imm26-i4":"1:bb","kah-imm26-i4-hx0":"1:cc"}}'
export AB2_FAKE_LANE="$GOODLANE"
OUT="$(AB2_DIR="$TW/ab2" RB --check 2>&1)"; RC=$?; chk rebase-refuses-after-runs "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'state.json has runs'"
R="$TW/rb"; mkdir -p "$R"; cp "$T/ab2/queue.txt" "$T/ab2/brief.md" "$R/"
export AB2_DIR="$R"
"$PY" -I "$HERE/ab2-plan.py" --seed 7 >/dev/null 2>&1; chk rb-plan0 "[ -f '$R/plan.json' ]"
P0="$(cat "$R/plan.json")"
export AB2_FAKE_BASELINE="$NEWBASE" FAKE_WORD=DRY-RUN
OUT="$(RB --check 2>&1)"; RC=$?; chk rebase-check "[ $RC = 0 ] && echo \"\$OUT\" | grep -q 'nothing written' && echo \"\$OUT\" | grep -q 'dll_mods' && [ \"\$(cat '$R/plan.json')\" = \"\$P0\" ] && [ -z \"\$(ls '$R' | grep plan.json.)\" ]"
# refusals (each leaves plan.json untouched and no archive)
OUT="$(AB2_FAKE_LANE='{"pid":null,"lock_owner":"rig5090-imm26-i4","inflight":true,"held":true,"backend":"ok"}' RB 2>&1)"; RC=$?; chk rebase-refuse-no-game "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'lane not up'"
OUT="$(AB2_FAKE_LANE='{"pid":4242,"lock_owner":"someone","inflight":true,"held":true,"backend":"ok"}' RB 2>&1)"; RC=$?; chk rebase-refuse-lock "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'game-4.lock'"
OUT="$(AB2_FAKE_LANE='{"pid":4242,"lock_owner":"rig5090-imm26-i4","inflight":false,"held":true,"backend":"ok"}' RB 2>&1)"; RC=$?; chk rebase-refuse-inflight "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'inflight'"
OUT="$(AB2_FAKE_LANE='{"pid":4242,"lock_owner":"rig5090-imm26-i4","inflight":true,"held":false,"backend":"ok"}' RB 2>&1)"; RC=$?; chk rebase-refuse-held "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'lanes.held'"
OUT="$(AB2_FAKE_LANE='{"pid":4242,"lock_owner":"rig5090-imm26-i4","inflight":true,"held":true,"backend":"pg down"}' RB 2>&1)"; RC=$?; chk rebase-refuse-backend "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'backend not healthy'"
OUT="$(AB2_FAKE_BASELINE='{"dll_mods":"3FE805BF","dll_re":"7A5AF9EA","bundle":"b2","saves":{"kah-imm26-i4":"1:bb","kah-imm26-i4-hx0":"1:cc"}}' RB 2>&1)"; RC=$?; chk rebase-refuse-dll-copies "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'two Stobe.dll copies differ'"
OUT="$(RB --expect-dll DEADBEEF 2>&1)"; RC=$?; chk rebase-refuse-expect "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'expected prefix'"
OUT="$(AB2_FAKE_BASELINE='{"dll_mods":"3FE805BF","dll_re":"3FE805BF","bundle":null,"saves":{"kah-imm26-i4":"1:bb","kah-imm26-i4-hx0":"1:cc"}}' RB 2>&1)"; RC=$?; chk rebase-refuse-unreadable "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'baseline unreadable'"
OUT="$(FAKE_WORD=SETUP-FAIL RB 2>&1)"; RC=$?; chk rebase-refuse-dry "[ $RC = 5 ] && echo \"\$OUT\" | grep -q -- '--dry failed for 2 row'"
mkdir "$R/RUNNING"; OUT="$(RB 2>&1)"; RC=$?; chk rebase-refuse-lock-dir "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'RUNNING lock'"; rmdir "$R/RUNNING"
chk rebase-refusals-wrote-nothing "[ \"\$(cat '$R/plan.json')\" = \"\$P0\" ] && [ -z \"\$(ls '$R' | grep plan.json.)\" ]"
# the real thing
OUT="$(RB --tag nc20 --expect-dll 3FE805BF 2>&1)"; RC=$?; chk rebase-ok "[ $RC = 0 ] && echo \"\$OUT\" | grep -q 'IDENTICAL to the archived plan'"
chk rebase-archive "[ \$(ls '$R' | grep -c '^plan.json.nc20-') = 1 ] && [ \"\$(cat '$R'/plan.json.nc20-*)\" = \"\$P0\" ]"
chk rebase-new-plan "$PY -I -c \"
import json;o=json.loads(open('$R/plan.json.'+[f for f in __import__('os').listdir('$R') if f.startswith('plan.json.nc20-')][0].split('plan.json.')[1]).read());n=json.load(open('$R/plan.json'))
assert n['baseline']['dll_mods']=='3FE805BF' and n['baseline']['bundle']=='b2' and n['seed']==o['seed']==7 and n['rows']==o['rows']
assert [(r['seq'],r['arm'],r['row']) for r in n['runs']]==[(r['seq'],r['arm'],r['row']) for r in o['runs']]
assert n['rebaseline']['game_pid']==4242 and n['rebaseline']['archived_as'].startswith('plan.json.nc20-') and n['manifest'] and n['queue']\""
chk rebase-log "grep -q 'order_identical=True' '$R/rebaseline.log'"
# the new plan is usable: first run
set -- $("$PY" -I -c "import json;r=json.load(open('$TW/rb/plan.json'))['runs'][0];print(r['arm'],r['row'])"); A1=$1; R1=$2
# a run is refused for an old baseline, accepted for the new one
OUT="$(AB2_FAKE_BASELINE='{"dll_mods":"AAAAAAAA","dll_re":"AAAAAAAA","bundle":"b1","saves":{}}' "$PY" -I "$HERE/ab2-state.py" begin $A1 $R1 2>&1)"; chk rebase-old-baseline-refused "echo \"\$OUT\" | grep -q 'dll_mods'"
OUT="$("$PY" -I "$HERE/ab2-state.py" begin $A1 $R1 2>&1)"; chk rebase-new-baseline-accepted "echo \"\$OUT\" | grep -q '^CMD '"
"$PY" -I "$HERE/ab2-state.py" abort $A1 $R1 "selftest" >/dev/null 2>&1
# once state.json has runs the rebaseline refuses (begin wrote a run record)
OUT="$(RB --check 2>&1)"; RC=$?; chk rebase-refuses-after-begin "[ $RC = 5 ] && echo \"\$OUT\" | grep -q 'state.json has runs'"
rm -rf "$HERE/__pycache__"
if [ $FAILS = 0 ]; then echo "SELFTEST OK ($N checks)"; else echo "SELFTEST FAILED ($FAILS of $N)"; exit 1; fi
