#!/usr/bin/env bash
# pilot-mark-selftest.sh: sandbox test of pilot-mark.sh (all verdict paths). Prints SELFTEST PILOT-MARK ALL PASS n/n or FAIL.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PM="$HERE/pilot-mark.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KAH_RUNS_DIR="$T/runs" KAH_PILOT_DIR="$T/runs/pilot/haiku-i4" PILOT_MODEL=haiku
mkdir -p "$KAH_RUNS_DIR/claims/99-z" "$KAH_RUNS_DIR/inbox/coordinator" "$T/ev"
echo "| IMM-05-cx | x | y | z |" > "$T/TESTS.md"; export KAH_TESTS_MD="$T/TESTS.md"
snap() { (cd "$KAH_RUNS_DIR" && find claims -print | sort | tr '\n' ' '; sha256sum "$T/TESTS.md" | cut -c1-16; ls setupfail 2>&1 | tr '\n' ' '); }
BEFORE="$(snap)"
N=0; OK=0
chk() { N=$((N+1)); if [ "$2" = "$3" ]; then OK=$((OK+1)); else echo "FAIL $1: got '$2' want '$3'"; fi; }
ev() { printf '%s\n' "$2" > "$T/ev/$1.txt"; echo "$T/ev/$1.txt"; }
pm() { bash "$PM" imm26-pilot-test "$@" --no-status >"$T/last.out" 2>&1; echo $?; }
CSV="$KAH_PILOT_DIR/verdicts.csv"; CSVW="$CSV"; command -v cygpath >/dev/null 2>&1 && CSVW="$(cygpath -m "$CSV")"

# 1 START
chk start-exit "$(pm 05-cx START)" 0
chk start-active "$([ -f "$KAH_PILOT_DIR/ACTIVE" ] && echo y)" y
# 2 PASS accepted
F=$(ev p1 $'noise\nRESULT 05-cx PASS E1 ok')
chk pass-accepted "$(pm 05-cx PASS "all good" --evidence-file "$F")" 0
chk csv-header "$(head -1 "$CSV")" "row,lane,model,start,end,wall_s,tokens,cost,operator_verdict,checker_result,agree,false_claims_n,notes"
chk csv-pass-agree "$(python3 -c "import csv;r=list(csv.DictReader(open('$CSVW')))[-1];print(r['row'],r['model'],r['operator_verdict'],r['agree'],r['wall_s']!='')")" "05-cx haiku PASS 1 True"
# 3 PASS refused on FAIL evidence
pm 16-bx START >/dev/null
F=$(ev f1 'RESULT 16-bx FAIL R1:words 3..40!189')
chk pass-refused-on-fail "$(pm 16-bx PASS "looks ok" --evidence-file "$F")" 3
chk wrong-logged "$(grep -c 'REFUSED' "$KAH_PILOT_DIR/events.log")" 1
chk csv-refused-agree0 "$(python3 -c "import csv;r=list(csv.DictReader(open('$CSVW')))[-1];print(r['agree'],r['notes'].startswith('REFUSED'))")" "0 True"
# 4 PASS refused, no RESULT line
pm 02-ax START >/dev/null
F=$(ev n1 $'some log\nno verdict here')
chk pass-refused-no-result "$(pm 02-ax PASS "ok" --evidence-file "$F")" 3
chk pass-refused-no-file "$(pm 02-cx PASS "ok" --evidence-file "$T/ev/missing.txt")" 3
# 5 FAIL accepted, then corrected FAIL on the refused row
chk fail-accepted "$(pm 16-bx FAIL "checker words" --evidence-file "$(ev f1 'RESULT 16-bx FAIL R1:words 3..40!189')")" 0
# 6 FAIL refused when the checker says PASS
pm 15-bx START >/dev/null
chk fail-refused-on-pass "$(pm 15-bx FAIL "x" --evidence-file "$(ev p2 'RESULT 15-bx PASS fine')")" 3
# 7 second wrong attempt on the same row = escalate
chk second-wrong-escalates "$(pm 15-bx FAIL "again" --evidence-file "$(ev p2 'RESULT 15-bx PASS fine')")" 4
chk escalate-msg-15bx "$(ls "$KAH_RUNS_DIR/inbox/coordinator" | grep -c 'pilot-escalate-15-bx.msg')" 1
# 8 SETUP-FAIL -> ESCALATE, inbox message text
pm 12-d START >/dev/null
chk setupfail-escalates "$(pm 12-d SETUP-FAIL "no reply of Cind" --evidence-file "$(ev s1 'RESULT 12-d SETUP-FAIL no reply')")" 4
M="$(ls "$KAH_RUNS_DIR"/inbox/coordinator/*pilot-escalate-12-d.msg | head -1)"
chk escalate-msg-prefix "$(head -c 20 "$M")" "PILOT-ESCALATE 12-d "
chk escalate-csv "$(python3 -c "import csv;r=list(csv.DictReader(open('$CSVW')))[-1];print(r['row'],r['operator_verdict'],r['agree'],r['notes'].startswith('ESCALATE'))")" "12-d SETUP-FAIL 1 True"
# 9 a closed row stays closed
chk closed-row-pass "$(pm 12-d PASS "retry" --evidence-file "$(ev p3 'RESULT 12-d PASS')")" 4
chk closed-row-start "$(pm 12-d START)" 4
# 10 explicit ESCALATE without evidence file
chk explicit-escalate "$(pm 22-b ESCALATE "weird log, unsure")" 4
# 11 odd verdict word with no RESULT line -> escalate
chk gated-escalates "$(pm 20-a GATED "declined")" 4
# 12 second FAIL of one row = escalate
pm 17-bx START >/dev/null; pm 17-bx FAIL "a" --evidence-file "$(ev q1 'RESULT 17-bx FAIL a')" >/dev/null
pm 17-bx START >/dev/null
chk second-fail-escalates "$(pm 17-bx FAIL "b" --evidence-file "$(ev q2 'RESULT 17-bx FAIL b')")" 4
# 13 last RESULT line wins, IMM- prefix, directory evidence (result.txt)
mkdir -p "$T/ev/dir"; printf 'RESULT 23-b FAIL old\nRESULT 23-b PASS new\n' > "$T/ev/dir/result.txt"
pm IMM-23-b START >/dev/null
chk dir-evidence-last-wins "$(pm IMM-23-b PASS "ok" --evidence-file "$T/ev/dir")" 0
# 14 stale evidence (older than START) refused
F=$(ev old1 'RESULT 20-d PASS old'); touch -d '2 hours ago' "$F"
pm 20-d START >/dev/null
chk stale-refused "$(pm 20-d PASS "ok" --evidence-file "$F")" 3
# 14b 00-ask: message to the coordinator, never closes
chk ask-escalates "$(pm 00-ask ESCALATE "lane is down, need launch")" 4
chk ask-twice "$(pm 00-ask ESCALATE "still down")" 4
chk ask-msgs "$(ls "$KAH_RUNS_DIR/inbox/coordinator" | grep -c 'pilot-escalate-00-ask')" 2
chk ask-text "$(head -c 22 "$(ls "$KAH_RUNS_DIR"/inbox/coordinator/*pilot-escalate-00-ask.msg | head -1)")" "PILOT-ESCALATE 00-ask "
# 15 bad usage
bash "$PM" onlyone >/dev/null 2>&1; chk usage-exit "$?" 2
chk bad-row "$(pm 'zz' PASS "x")" 2
# 16 shadow guarantees: claims, TESTS, tickets untouched
chk shadow-untouched "$(snap)" "$BEFORE"
if [ $OK -eq $N ]; then echo "SELFTEST PILOT-MARK ALL PASS $OK/$N"; exit 0; else echo "SELFTEST PILOT-MARK FAIL $OK/$N"; exit 1; fi
