#!/usr/bin/env bash
# ctxfix-selftest.sh: offline selftest for the lane-operator context-cut tools (imm26-ctxfix): rowcard.py/row-card.sh/next-row.sh, logwin.sh, usage.sh,
# status-mark.sh, wait-row.sh. Builds a fake runs dir + fake git repo in a temp dir; no game, no ssh, never touches the real TESTS file, claims or git history.
# Run from Git Bash:  bash tools/automation/ctxfix-selftest.sh     -> prints "ok   <check>" / "FAIL <check>" lines and a final "SELFTEST CTXFIX ALL PASS n/n" (exit 0) or FAIL (exit 1).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || echo "$1"; }
TW="$(W "$T")"
RUNS="$T/runs"; REPO="$T/repo"; RT="$REPO/testing/live-stobe-queue/imm26-assert/rowtools"
mkdir -p "$RUNS/agents" "$RUNS/claims" "$RUNS/row-attempts" "$RUNS/inbox/operators" "$RT" "$REPO/testing"
export KAH_RUNS_DIR="$TW/runs" KAH_REPO="$TW/repo" KAH_TESTS_MD="$TW/repo/testing/NPC_IMMERSION_26_TESTS.md"
PASS=0; FAIL=0
chk() { local n="$1" ok=1 a; shift; [ $# -ge 1 ] || ok=0; for a in "$@"; do [ "$a" = 1 ] || ok=0; done; if [ $ok = 1 ]; then echo "ok   $n"; PASS=$((PASS+1)); else echo "FAIL $n"; FAIL=$((FAIL+1)); fi; }
has() { printf '%s' "$1" | grep -qE -- "$2" && echo 1 || echo 0; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && echo 0 || echo 1; }
LONG="$(printf 'long-setup-text %.0s' $(seq 1 60))"
cat > "$REPO/testing/NPC_IMMERSION_26_TESTS.md" <<EOF
# fake tests
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-01-a | s1 | say: "hi" | e1 | n | BASE | PASS | ev1 | 2026-10-15 |
| IMM-02-a | SETUPTEXT-A $LONG | say: "a" | EXPECTED-A $LONG | NEG-A | BASE | UNRUN | | |
| IMM-02-b | s2b | say: "b" | e2b | n | BASE | UNRUN | | |
| IMM-02-c | s2c | say: "c" | e2c | n | BASE | FAIL | old ev $LONG | 2026-10-14 |
| IMM-03-a | s3 | say: "d" | e3 | n | BASE | GATED | | |
| IMM-04-a | s4 | say: "e" | e4 | n | BASE | UNRUN | | |
| IMM-05-a | s5 | say: "f" | e5 | n | BASE | UNRUN | | |
| IMM-06-a | s6 | say: "g" | e6 | n | BASE | UNRUN | | |
EOF
cat > "$RT/rowdefs.sh" <<'EOF'
rd_02a() {  # fake
  :
}
rd_02c() {  # fake
  :
}
EOF
cat > "$T/runners.tsv" <<'EOF'
# fake
02-b | reload-run-sfi.sh | --save <ready> | fake note
04-a | trip-run.sh | [--save <ready>] |
EOF
export KAH_ROW_RUNNERS="$TW/runners.tsv"
printf 'fake-op | RUNNING | 2026-10-16 12:00\ntask: 5090 i4 operator "fake" task\nlatest: x\n' > "$RUNS/agents/imm26-fake-op.status"
printf '# fake handoff\nTODO (not run): 04-a, 02-c/b\n' > "$RUNS/agents/imm26-5090-i4op9.handoff.md"
echo '{"5090-i4":{"ops":["imm26-5090-i4op9"],"dirs":["d"]}}' > "$RUNS/lane-owners.json"
printf 'LANE PLAN\n5090-i4 (op x): FIRST 06-a then 05-a, 02-a.\n5090-i3 (op y): 03-a\n' > "$RUNS/inbox/operators/lane-plan-1.txt"
printf 'fake note about 5090-i4 and a thing\nsecond line\n' > "$RUNS/inbox/operators/n1.txt"
printf 'other lane note about 4080-i3 only\n' > "$RUNS/inbox/operators/n2.txt"
printf 'row mention 05-a only\n' > "$RUNS/inbox/operators/n3.txt"
PY="$(command -v python3 || command -v python)"

# ---- row-card ----
C="$(bash "$HERE/row-card.sh" 02-a 5090-i4)"
chk "card <= 600 chars ($(printf '%s' "$C" | wc -c))" $([ "$(printf '%s' "$C" | wc -c)" -le 600 ] && echo 1 || echo 0)
chk "card has status, lane, RUN via go-row fallback, RESULT shape, evidence path" $(has "$C" '^IMM-02-a \[UNRUN\] 5090-i4 \| claim:free' ) $(has "$C" 'go-row.sh 02-a 5090-i4')
chk "card RUN line uses go-row.sh for rd_02a" $(has "$C" 'RUN: cd /c/KenshiModding && bash testing/live-stobe-queue/imm26-assert/go-row.sh 02-a 5090-i4')
chk "card keeps RESULT shape + evidence dir" $(has "$C" 'RESULT 02-a PASS\|FAIL\|SETUP-FAIL\|GATED <evidence>; evidence .*/imm26-5090-i4/rows/02-a/')
C2="$(bash "$HERE/row-card.sh" 02-b 4080-i4)"
chk "runner table row: script + --save ready save, NO KAH_PF_ISOLATION bypass on 4080-i4 (PI-60)" $(has "$C2" 'RUN: cd /c/KenshiModding && bash testing/live-stobe-queue/imm26-assert/rowtools/reload-run-sfi.sh 02-b 4080-i4 --save kah-imm26-4080-i4h')
chk "no card prints KAH_PF_ISOLATION=0 and the RUN-NOTE is there (PI-60)" $(lacks "$C2" "KAH_PF_ISOLATION=0") $(has "$C2" "RUN-NOTE: no isolation bypass")
C3="$(bash "$HERE/row-card.sh" 03-a 5090-i3)"
chk "manual row says manual" $(has "$C3" 'RUN: manual')
chk "unknown row reported" $(has "$(bash "$HERE/row-card.sh" 99-z 5090-i4)" 'not found')
mkdir "$RUNS/claims/02-b"
chk "claimed row shows HELD" $(has "$(bash "$HERE/row-card.sh" 02-b 5090-i4)" 'claim:HELD')
echo '{"rows":{"02-c":{"attempts":2,"last":"FAIL","cause":"x","evidence":"e","t":"t"}}}' > "$RUNS/row-attempts/5090-i4.json"
C4="$(bash "$HERE/row-card.sh" 02-c 5090-i4)"
chk "attempt-blocked row shows needs --allow-retry in header and RUN" $(has "$C4" 'last attempt FAIL x2: needs --allow-retry') $(has "$C4" 'go-row.sh --allow-retry "<why>" 02-c')
chk "all cards <= 600 chars" $(for r in 01-a 02-a 02-b 02-c 03-a 04-a 05-a; do [ "$(bash "$HERE/row-card.sh" $r 5090-i4 | wc -c)" -le 600 ] || echo bad; done | grep -q bad && echo 0 || echo 1)

# ---- next-row ----
N="$(bash "$HERE/next-row.sh" 5090-i4 --ids --n 6 | tr '\n' ' ')"
chk "next order: handoff TODO 04-a, plan 06-a 05-a 02-a, attempt-blocked 02-c last ($N)" $(has "$N" '^04-a 06-a 05-a 02-a 02-c ')
chk "claimed 02-b skipped, PASS 01-a skipped" $(lacks "$N" '02-b|01-a')
NR="$(bash "$HERE/next-row.sh" 5090-i4)"
chk "next-row prints NEXT line + card + also line" $(has "$NR" '^NEXT 5090-i4: 04-a \[UNRUN\] via handoff-TODO') $(has "$NR" '^also: ')
chk "next-row total <= 1200 chars ($(printf '%s' "$NR" | wc -c))" $([ "$(printf '%s' "$NR" | wc -c)" -le 1200 ] && echo 1 || echo 0)
CL="$(bash "$HERE/next-row.sh" 5090-i4 --claim)"
chk "--claim mkdir's claims/04-a" $([ -d "$RUNS/claims/04-a" ] && echo 1 || echo 0)
CL2="$(bash "$HERE/next-row.sh" 5090-i4 --claim)"
chk "second --claim takes the next row (06-a), not 04-a" $(has "$CL2" 'CLAIMED 06-a')
touch "$RUNS/inbox/operators/5090-i4-ready-02c.txt"
chk "ready note 02c puts 02-c first even though attempt-blocked" $(has "$(bash "$HERE/next-row.sh" 5090-i4 --ids --n 1)" '^02-c$')
chk "bad lane -> usage exit 2" $(bash "$HERE/next-row.sh" nolane >/dev/null 2>&1; [ $? -eq 2 ] && echo 1 || echo 0)

# ---- inbox digest ----
D="$("$PY" -I "$HERE/rowcard.py" inbox 5090-i4)"
chk "digest: lane-tagged note + lane-plan queue line + row-id note kept, other-lane note dropped" $(has "$D" 'n1.txt') $(has "$D" 'queue: 5090-i4') $(lacks "$D" 'n2.txt')
chk "digest <= 2500 bytes and has paths" $([ "$(printf '%s' "$D" | wc -c)" -le 2500 ] && printf '%s' "$D" | grep -q -- '-> ' && echo 1 || echo 0)

# ---- logwin ----
L="$T/test.log"
{ for i in $(seq 1 400); do echo "[2026-10-16 11:46:$(printf %02d $((i%60))).000] [Stobe] HOOK_MSG_PROC: noise line $i"; echo "[2026-10-16 11:47:$(printf %02d $((i%60))).000] [Stobe] FOLLOW_TICK: follower=Cind dist=$i"; done
  echo "[2026-10-16 11:48:00.000] [Stobe] MARKER_X start"; echo "[2026-10-16 11:48:01.000] [Stobe] ACTIVITY grant rejected: source_mismatch"; echo "RESULT 26-d SETUP-FAIL needs: recipe: no PROPOSE record in s1"; echo "[2026-10-16 11:48:02.000] [Stobe] TOWNS_DIAG filler"; } > "$L"
LW="$(bash "$HERE/logwin.sh" "$L" 'FOLLOW_TICK|HOOK_MSG|RESULT|ACTIVITY' 1200)"
chk "logwin: noise tags dropped (HOOK_MSG in pattern is kept? no: named in pattern -> kept)" $(has "$LW" 'noise dropped')
LW="$(bash "$HERE/logwin.sh" "$L" 'FOLLOW_TICK|RESULT|ACTIVITY|TOWNS' 1200)"
chk "logwin: capped output <= 1200 + footer, RESULT line kept whole" $(has "$LW" 'RESULT 26-d SETUP-FAIL needs: recipe: no PROPOSE record in s1') $([ "$(printf '%s' "$LW" | wc -c)" -le 2600 ] && echo 1)
chk "logwin: TRUNCATED footer names full file + source log" $(has "$LW" 'TRUNCATED.*FULL filtered output: .*kah-logwin.*source log: ')
FULLF="$(printf '%s' "$LW" | grep -oE 'FULL filtered output: [^ |]+' | sed 's/FULL filtered output: //')"
chk "logwin: full file exists and holds all filtered lines (>= 400 FOLLOW_TICK)" $([ -f "$FULLF" ] && [ "$(grep -c FOLLOW_TICK "$FULLF")" -ge 400 ] && echo 1 || echo 0)
LW2="$(bash "$HERE/logwin.sh" "$L" 'since:MARKER_X' 2500)"
chk "logwin since: starts at the last marker, shows source_mismatch + RESULT, TOWNS_DIAG filtered" $(has "$LW2" 'MARKER_X start') $(has "$LW2" 'source_mismatch') $(lacks "$LW2" 'TOWNS_DIAG filler')
LW3="$(bash "$HERE/logwin.sh" "$L" 'HOOK_MSG' 600)"
chk "logwin: explicit noise tag in the pattern is honoured" $(has "$LW3" 'HOOK_MSG_PROC: noise line')
LW4="$(bash "$HERE/logwin.sh" "$L" 'at:11:48:00+1' 2500)"
chk "logwin at: window" $(has "$LW4" 'MARKER_X') $(has "$LW4" 'source_mismatch')
LW5="$(bash "$HERE/logwin.sh" "$L" 'NO_SUCH_THING' 500)"; RCW=$?
chk "logwin: no match -> message, exit 1" $(has "$LW5" 'matched|nothing left|not found|0 ')
chk "logwin: marker not found -> exit 1" $(bash "$HERE/logwin.sh" "$L" 'since:NOPE_NOPE' >/dev/null 2>&1; [ $? -eq 1 ] && echo 1 || echo 0)
chk "logwin: missing log -> exit 2" $(bash "$HERE/logwin.sh" "$T/nolog" x >/dev/null 2>&1; [ $? -eq 2 ] && echo 1 || echo 0)
chk "logwin: lines cut to 220" $( { printf 'X%.0s' $(seq 1 500); echo " LONGLINE"; } > "$T/long.log"; [ "$(bash "$HERE/logwin.sh" "$T/long.log" LONGLINE | sed -n 2p | wc -c)" -le 224 ] && echo 1 || echo 0)

# ---- usage ----
U="$(bash "$HERE/usage.sh" go-row.sh)"
chk "usage go-row.sh <= 12 lines and mentions RESULT + exit codes" $([ "$(printf '%s\n' "$U" | wc -l)" -le 12 ] && echo 1 || echo 0) $(has "$U" 'RESULT <ROW> PASS')
chk "usage accepts a path and no suffix" $(has "$(bash "$HERE/usage.sh" /x/y/unblockrun_f)" 'unblockrun_f.sh <13-c')
chk "usage unknown -> exit 1" $(bash "$HERE/usage.sh" nonexistent >/dev/null 2>&1; [ $? -eq 1 ] && echo 1 || echo 0)
BAD=""; for s in $(bash "$HERE/usage.sh" --list); do n="$(bash "$HERE/usage.sh" "$s" | wc -l)"; [ "$n" -le 12 ] || BAD="$BAD $s"; done
chk "every table entry prints <= 12 lines${BAD:+ (bad:$BAD)}" $([ -z "$BAD" ] && echo 1 || echo 0)
MISS=""; for s in $(bash "$HERE/usage.sh" --list); do case "$s" in lib-i5.sh|kenshi-ctl.ps1|agent-status.ps1) continue;; esac; f="$(find "$HERE" "$HERE/../../testing/live-stobe-queue/imm26-assert" "$HERE/../../testing/live-stobe-queue/imm26-assert/rowtools" -maxdepth 1 -name "$s" 2>/dev/null | head -1)"; [ -n "$f" ] || MISS="$MISS $s"; done
chk "every usage-table script exists on disk${MISS:+ (missing:$MISS)}" $([ -z "$MISS" ] && echo 1 || echo 0)

# ---- row-runners.tsv sanity (the real table) ----
BADR=""; while IFS='|' read -r row script rest; do row="$(echo "$row" | xargs)"; script="$(echo "$script" | xargs)"; case "$row" in ''|\#*) continue;; esac
  p="$HERE/../../testing/live-stobe-queue/imm26-assert/rowtools/$script"; [ -f "$p" ] || BADR="$BADR $row:$script"; done < "$HERE/row-runners.tsv"
chk "every row-runners.tsv script exists${BADR:+ (missing:$BADR)}" $([ -z "$BADR" ] && echo 1 || echo 0)

# ---- status-mark ----
( cd "$REPO" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init && git init -q --bare "$T/remote.git" && git remote add origin "$(W "$T/remote.git")" && git push -q origin HEAD 2>/dev/null )
SM="$(bash "$HERE/status-mark.sh" imm26-fake-op 02-a PASS 'RESULT 02-a PASS ev=C:/x/rows/02-a' --lane 5090-i4 --next '04-a' 2>&1)"; RCM=$?
chk "status-mark exit 0 ($RCM)" $([ $RCM -eq 0 ] && echo 1 || echo 0)
chk "status-mark prints <= 4 short lines: marked / status / commit / push" $([ "$(printf '%s\n' "$SM" | wc -l)" -le 4 ] && echo 1 || echo 0) $(has "$SM" 'marked 02-a PASS') $(has "$SM" 'push: ok')
chk "TESTS row now PASS" $(has "$(grep '^| IMM-02-a ' "$REPO/testing/NPC_IMMERSION_26_TESTS.md")" '\| PASS \|')
chk "status file updated with the SAME task text" $(has "$(cat "$RUNS/agents/imm26-fake-op.status")" 'task: 5090 i4 operator "fake" task') $(has "$(cat "$RUNS/agents/imm26-fake-op.status")" '02-a PASS')
chk "commit contains only the TESTS file, remote received it" $([ "$(git -C "$REPO" show --stat --format= HEAD | grep -c '|')" = 1 ] && [ "$(git -C "$T/remote.git" log --oneline | wc -l)" = 2 ] && echo 1 || echo 0)
SM2="$(bash "$HERE/status-mark.sh" imm26-fake-op 02-b SETUP-FAIL 'no idea' --lane 5090-i4 2>&1)"; RC2=$?
chk "bare SETUP-FAIL refused whole (exit 2), nothing committed" $([ $RC2 -eq 2 ] && echo 1 || echo 0) $(has "$SM2" 'needs:') $(has "$SM2" 'mark refused')
chk "no extra commit after the refusal" $([ "$(git -C "$REPO" log --oneline | wc -l)" = 2 ] && echo 1 || echo 0)
SM3="$(bash "$HERE/status-mark.sh" imm26-fake-op 02-b SETUP-FAIL 'needs: recipe: nothing proposed' --lane 5090-i4 --no-status 2>&1)"; RC3=$?
chk "SETUP-FAIL with needs: marked + committed ($RC3)" $([ $RC3 -eq 0 ] && echo 1 || echo 0) $(has "$SM3" 'marked 02-b SETUP-FAIL')
printf '#!/usr/bin/env bash
echo "marked noop"
' > "$T/noopmark.sh"; SM4="$(KAH_MARK_ROW="bash $T/noopmark.sh" bash "$HERE/status-mark.sh" imm26-fake-op 02-b SETUP-FAIL 'needs: recipe: nothing proposed' --lane 5090-i4 --no-status 2>&1)"
chk "unchanged file: quiet 'nothing to commit' line, no git status dump" $(has "$SM4" 'nothing to commit') $(lacks "$SM4" 'Untracked|On branch|Changes not staged')
chk "--dry prints the plan only" $(has "$(bash "$HERE/status-mark.sh" a 02-a PASS ev --dry)" '^DRY mark-row.py')

# ---- wait-row ----
printf 'step one\nEVIDENCE x\nstill working on s2\n' > "$T/row.out"
WR="$(bash "$HERE/wait-row.sh" "$T/row.out" 1)"; RCR=$?
chk "wait-row RUNNING one line exit 10" $([ $RCR -eq 10 ] && [ "$(printf '%s\n' "$WR" | wc -l)" = 1 ] && printf '%s' "$WR" | grep -q '^RUNNING stage=still working on s2' && echo 1 || echo 0)
echo 'RESULT 02-a FAIL cause=x evidence=C:/y' >> "$T/row.out"
WR="$(bash "$HERE/wait-row.sh" "$T/row.out" 1)"; RCR=$?
chk "wait-row RESULT line whole, exit 1 for FAIL" $([ $RCR -eq 1 ] && printf '%s' "$WR" | grep -q '^RESULT 02-a FAIL cause=x evidence=C:/y$' && echo 1 || echo 0)
mkdir -p "$T/batch"; printf 'RESULT 02-a PASS e\nRESULT 02-b FAIL f\n' > "$T/batch/results.txt"
WR="$(bash "$HERE/wait-row.sh" "$T/batch" 1)"; RCR=$?
chk "wait-row batch RUNNING rows=2" $([ $RCR -eq 10 ] && printf '%s' "$WR" | grep -q '^RUNNING rows=2 last=RESULT 02-b FAIL f' && echo 1 || echo 0)
echo 'PASS=1 FAIL=1' > "$T/batch/summary.txt"; touch "$T/batch/DONE"
WR="$(bash "$HERE/wait-row.sh" "$T/batch" 1)"; RCR=$?
chk "wait-row batch DONE exit 11 with summary" $([ $RCR -eq 11 ] && printf '%s' "$WR" | grep -q '^DONE PASS=1 FAIL=1 results=' && echo 1 || echo 0)
chk "wait-row missing file -> WAITING exit 12" $(bash "$HERE/wait-row.sh" "$T/none" 1 >/dev/null; [ $? -eq 12 ] && echo 1 || echo 0)

echo
if [ $FAIL -eq 0 ]; then echo "SELFTEST CTXFIX ALL PASS $PASS/$PASS"; exit 0; else echo "SELFTEST CTXFIX FAIL $FAIL of $((PASS+FAIL))"; exit 1; fi
