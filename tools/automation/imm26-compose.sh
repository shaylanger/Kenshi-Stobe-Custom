#!/usr/bin/env bash
# imm26-compose.sh (WSL, root): compose the NPC-immersion server work-package patches (program imm26, 2026-10-15).
#
#   bash tools/automation/imm26-compose.sh [--order "A B D E C1 C2"] [--tests-timeout 1800] [--step-timeout 300]
#                                          [--deadline 3000] [--no-tests] [--no-fix-eol] [--selftest]
#
# What it does (one RESULT line per step on stdout, details in $OUT/):
#   1. copy   fresh rsync copy of /root/imm26/base to /root/imm26/compose (log/ contents and __pycache__ left out)
#   2. apply  each /root/imm26/wp<X>.patch in ORDER (default A B D E C1 C2). A missing or empty patch = SKIP (that WP is still
#             in progress). Each patch is dry-run first and applied only when clean (atomic, no half applied patch); a
#             conflict prints "CONFLICT <wp> <file> <detail>" (hunk number + line) and the patch is skipped, later patches
#             still run. If the plain dry run fails, a second dry run with --ignore-whitespace is tried (CRLF/LF noise in a
#             patch); success there is applied and reported "ws-fuzzy".
#   3. eol    base files that are pure CRLF (or pure LF) and ended up mixed after patching are restored to the base style
#             (default; --no-fix-eol only reports). New files are left as the patch wrote them.
#   4. lint   php -l on every changed/new *.php file (xargs, per-file timeout)
#   5. tests  full stobe-tests on the compose tree under flock /tmp/stobe-tests.lock (tree arg: header of /usr/local/bin/stobe-tests;
#             stobe_test DB). FAIL lines are compared with the 7 expected pre-existing failures
#             (bio_unique npc_player_view relationship_stance chat_json_endpoint main_ingress social_property social_fights;
#             override with IMM26_KNOWN): NEW-FAIL = regression, KNOWN-NOW-PASSING = fixed by the composed patches.
#   6. summary line RESULT compose PASS|FAIL ...
# Never touches /var/www/html/StobeServer, ss-merge or the live DB (stobe-tests uses stobe_test only).
# Every step has a timeout and the whole run a hard deadline (watchdog kills the run, writes FAILED, exit 124).
# Status files (agent-status.ps1 format, written directly because this runs in WSL):
#   C:\KenshiTestRuns\agents\imm26-compose.status   RUNNING while working, DONE (PASS) or FAILED at the end
#   C:\KenshiTestRuns\agents\imm26-compose.result   one line: <time> | PASS|FAIL | applied/skipped/conflict | lint | eol | tests
# Exit: 0 all steps pass (skips allowed), 1 any step failed, 2 usage, 3 another compose run is active, 124 deadline.
# Env overrides (used by --selftest): IMM26_ROOT IMM26_BASE IMM26_COMPOSE IMM26_PATCHDIR IMM26_OUT IMM26_STATUS_DIR
#   IMM26_STOBE_TESTS IMM26_TESTS_LOCK IMM26_LOCK IMM26_KNOWN.
# Run it again after each WP lands: the compose tree is rebuilt from base every time.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${IMM26_ROOT:-/root/imm26}"
BASE="${IMM26_BASE:-$ROOT/base}"
COMPOSE="${IMM26_COMPOSE:-$ROOT/compose}"
PATCHDIR="${IMM26_PATCHDIR:-$ROOT}"
OUT="${IMM26_OUT:-$ROOT/compose-out}"
STATUS_DIR="${IMM26_STATUS_DIR:-/mnt/c/KenshiTestRuns/agents}"
STOBE_TESTS="${IMM26_STOBE_TESTS:-/usr/local/bin/stobe-tests}"
TESTS_LOCK="${IMM26_TESTS_LOCK:-/tmp/stobe-tests.lock}"
RUN_LOCK="${IMM26_LOCK:-/tmp/imm26-compose.lock}"
KNOWN="${IMM26_KNOWN:-bio_unique npc_player_view relationship_stance chat_json_endpoint main_ingress social_property social_fights}"
ORDER="A B D E C1 C2"
STEP_TIMEOUT=300
TESTS_TIMEOUT=1800
DEADLINE=3000
RUN_TESTS=1
FIX_EOL=1
SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --order) ORDER="$2"; shift 2;;
    --step-timeout) STEP_TIMEOUT="$2"; shift 2;;
    --tests-timeout) TESTS_TIMEOUT="$2"; shift 2;;
    --deadline) DEADLINE="$2"; shift 2;;
    --no-tests) RUN_TESTS=0; shift;;
    --no-fix-eol) FIX_EOL=0; shift;;
    --selftest) SELFTEST=1; shift;;
    -h|--help) sed -n 2,34p "$0"; exit 0;;
    *) echo "usage: imm26-compose.sh [--order \"A B D E C1 C2\"] [--step-timeout s] [--tests-timeout s] [--deadline s] [--no-tests] [--no-fix-eol] [--selftest]" >&2; exit 2;;
  esac
done

# ------------------------------------------------------------------ selftest (re-runs this script on a tiny fake tree)
if [ "$SELFTEST" = 1 ]; then
  ST="$(mktemp -d /tmp/imm26-selftest.XXXXXX)"
  trap 'rm -rf "$ST"' EXIT
  mkdir -p "$ST/base/lib" "$ST/base/log" "$ST/patches" "$ST/status"
  { echo '<?php'; for i in $(seq 1 12); do echo "function a$i() { return $i; }"; done; } > "$ST/base/lib/a.php"
  { printf '<?php\r\n'; for i in $(seq 1 12); do printf 'function b%s() { return %s; }\r\n' "$i" "$i"; done; } > "$ST/base/lib/b.php"
  cat > "$ST/fake-tests" <<'FAKE'
#!/bin/bash
# fake stobe-tests: prints the pre-existing failures (bio_unique left out = "now passing") and optionally a new one
echo "FAIL        relationship_stance_regression: x"
echo "FAIL        social_fights_regression: y"
[ "${FAKE_NEW:-0}" = 1 ] && echo "FAIL        brand_new_regression: z"
echo "suites: 5 passed, 2 FAILED, 0 known pre-existing"
[ "${FAKE_NEW:-0}" = 1 ] && exit 1
exit 1
FAKE
  chmod +x "$ST/fake-tests"
  mkp() { # mkp <name> <relpath> <sed-expr> [crlf=0|1|noise]  -> makes $ST/patches/wp<name>.patch against $ST/base
    local name="$1" rel="$2" expr="$3" mode="${4:-0}"
    rm -rf "$ST/w"; mkdir -p "$ST/w"; cp -a "$ST/base" "$ST/w/base"; cp -a "$ST/base" "$ST/w/new"
    sed -i "$expr" "$ST/w/new/$rel"
    (cd "$ST/w" && diff -uN "base/$rel" "new/$rel" | sed "s#^+++ new/#+++ wp$name/#" > "$ST/patches/wp$name.patch")
    [ "$mode" = noise ] && sed -i 's/\r$//' "$ST/patches/wp$name.patch"   # LF patch against a CRLF file
    return 0
  }
  mkp A lib/a.php 's/return 1; }/return 10; }/'
  mkp B lib/b.php 's/b9() { return 9; }\r$/b9() { return 90; }\r/'
  mkp C lib/a.php 's/return 1; }/return 99; }/'          # conflicts with A (same line)
  mkp E lib/a.php 's/a12() { return 12; }/a12() { return ; ;; }}} {/'   # syntax error -> lint FAIL
  mkp F lib/b.php 's/b3() { return 3; }\r$/b3() { return 33; }\r/' noise   # CRLF/LF noise -> ws-fuzzy + eol fix
  : > "$ST/patches/wpD.patch"                             # empty = still in progress
  # (wpG deliberately missing)
  export IMM26_BASE="$ST/base" IMM26_COMPOSE="$ST/compose" IMM26_PATCHDIR="$ST/patches" IMM26_OUT="$ST/out" \
         IMM26_STATUS_DIR="$ST/status" IMM26_STOBE_TESTS="$ST/fake-tests" IMM26_TESTS_LOCK="$ST/tests.lock" IMM26_LOCK="$ST/run.lock"
  fail=0
  crlf_pure() { [ "$(grep -c $'\r$' "$1")" = "$(grep -c '' "$1")" ]; }
  chk() { if eval "$2"; then echo "SELFTEST ok   $1"; else echo "SELFTEST FAIL $1"; fail=$((fail+1)); fi; }
  # scenario 1: A B C D G (conflict C, empty D, missing G)
  o1="$("$0" --order "A B C D G" --deadline 120 --tests-timeout 60 2>&1)"; rc1=$?
  echo "$o1" | sed 's/^/  s1| /'
  chk "s1 exit 1 (conflict)" '[ $rc1 = 1 ]'
  chk "s1 A applied" 'echo "$o1" | grep -q "^RESULT apply-A PASS"'
  chk "s1 B applied" 'echo "$o1" | grep -q "^RESULT apply-B PASS"'
  chk "s1 C conflict names file+hunk" 'echo "$o1" | grep -q "^CONFLICT C lib/a.php .*Hunk #1"'
  chk "s1 C result FAIL" 'echo "$o1" | grep -q "^RESULT apply-C FAIL"'
  chk "s1 D skipped (empty)" 'echo "$o1" | grep -q "^RESULT apply-D SKIP empty"'
  chk "s1 G skipped (missing)" 'echo "$o1" | grep -q "^RESULT apply-G SKIP missing"'
  chk "s1 a.php has A not C" 'grep -q "a1() { return 10; }" "$ST/compose/lib/a.php" && ! grep -q "return 99;" "$ST/compose/lib/a.php"'
  chk "s1 b.php still pure CRLF" 'crlf_pure "$ST/compose/lib/b.php"'
  chk "s1 base untouched" '! grep -q "a1() { return 10; }" "$ST/base/lib/a.php"'
  chk "s1 lint PASS" 'echo "$o1" | grep -q "^RESULT php-lint PASS"'
  chk "s1 tests known only" 'echo "$o1" | grep -q "^RESULT stobe-tests PASS .*new=0" && echo "$o1" | grep -q "KNOWN-NOW-PASSING bio_unique"'
  chk "s1 status FAILED + result file" 'grep -q "| FAILED |" "$ST/status/imm26-compose.status" && grep -q "| FAIL |" "$ST/status/imm26-compose.result"'
  # scenario 2: A E F, a broken php, a ws-noise patch, a new failing test
  o2="$(FAKE_NEW=1 "$0" --order "A E F" --deadline 120 --tests-timeout 60 2>&1)"; rc2=$?
  echo "$o2" | sed 's/^/  s2| /'
  chk "s2 exit 1" '[ $rc2 = 1 ]'
  chk "s2 F applied despite EOL noise" 'echo "$o2" | grep -q "^RESULT apply-F PASS .*\(ws-fuzzy\|eol-normalized\)"'
  chk "s2 eol kept" 'echo "$o2" | grep -q "^RESULT eol PASS" && crlf_pure "$ST/compose/lib/b.php" && grep -q "return 33;" "$ST/compose/lib/b.php"'
  chk "s2 lint FAIL names file" 'echo "$o2" | grep -q "^RESULT php-lint FAIL" && echo "$o2" | grep -q "LINT-ERROR lib/a.php"'
  chk "s2 new test failure" 'echo "$o2" | grep -q "NEW-FAIL brand_new_regression" && echo "$o2" | grep -q "^RESULT stobe-tests FAIL"'
  # scenario 3: all clean (A B F) -> PASS, DONE status
  o3="$("$0" --order "A B F" --deadline 120 --tests-timeout 60 2>&1)"; rc3=$?
  chk "s3 exit 0 and DONE" '[ $rc3 = 0 ] && grep -q "| DONE |" "$ST/status/imm26-compose.status" && echo "$o3" | grep -q "^RESULT compose PASS"'
  # scenario 4: hard deadline (tests step slower than the deadline)
  printf '#!/bin/bash\nsleep 30\n' > "$ST/slow-tests"; chmod +x "$ST/slow-tests"
  o4="$(IMM26_STOBE_TESTS="$ST/slow-tests" "$0" --order "A" --deadline 8 --tests-timeout 600 2>&1)"; rc4=$?
  chk "s4 deadline caps the tests step (timeout path), no hang" '[ $rc4 = 1 ] && echo "$o4" | grep -q "^RESULT stobe-tests FAIL .*\(deadline\|timeout\)"'
  [ $fail = 0 ] && { echo "RESULT imm26-compose-selftest PASS"; exit 0; }
  echo "RESULT imm26-compose-selftest FAIL failures=$fail"; exit 1
fi

# ------------------------------------------------------------------ real run
exec 9>"$RUN_LOCK"
flock -n 9 || { echo "RESULT compose FAIL another imm26-compose run is active ($RUN_LOCK)"; exit 3; }

T0=$(date +%s)
mkdir -p "$OUT" "$STATUS_DIR" 2>/dev/null
LASTLINE=""
NAME=imm26-compose
status() { # status STATE latest
  local st="$1" latest="$2"
  { echo "$NAME | $st | $(date '+%Y-%m-%d %H:%M')"
    echo "task: compose imm26 server patches ($ORDER) onto base"
    echo "latest: $latest"
    echo "outputs: $COMPOSE ; $OUT"
    echo "next: ${3:-read RESULT lines}"; } > "$STATUS_DIR/$NAME.status" 2>/dev/null
}
remaining() { echo $(( DEADLINE - ($(date +%s) - T0) )); }
res() { LASTLINE="$*"; echo "RESULT $*"; echo "RESULT $*" >> "$OUT/RESULTS.txt"; }
STATUS_FINAL=""
finish_hard() { # watchdog fired
  pkill -P $$ 2>/dev/null
  res "compose FAIL hard deadline ${DEADLINE}s exceeded"
  status FAILED "hard deadline ${DEADLINE}s exceeded; last: $LASTLINE"
  echo "$(date '+%Y-%m-%d %H:%M') | FAIL | hard deadline | - | - | -" > "$STATUS_DIR/$NAME.result" 2>/dev/null
  exit 124
}
trap finish_hard TERM
( exec 9>&-; sleep $((DEADLINE + 20)) && kill -TERM $$ 2>/dev/null ) >/dev/null 2>&1 &
WATCHDOG=$!
trap 'pkill -P $WATCHDOG 2>/dev/null; kill $WATCHDOG 2>/dev/null' EXIT

: > "$OUT/RESULTS.txt"
status RUNNING "start"

# ---- step 1: fresh copy
rm -rf "$COMPOSE"
if timeout "$STEP_TIMEOUT" rsync -a --exclude='/log/*' --exclude='__pycache__' "$BASE"/ "$COMPOSE"/ >"$OUT/copy.log" 2>&1; then
  mkdir -p "$COMPOSE/log"
  res "copy PASS $BASE -> $COMPOSE ($(du -sm "$COMPOSE" | cut -f1) MB, $(( $(date +%s) - T0 ))s)"
else
  res "copy FAIL rsync rc=$? (see $OUT/copy.log)"; status FAILED "copy failed"; echo "$(date '+%Y-%m-%d %H:%M') | FAIL | copy | - | - | -" > "$STATUS_DIR/$NAME.result"; exit 1
fi

# ---- step 2: apply
overall=0
APPLIED=""; SKIPPED=""; CONFLICTED=""
: > "$OUT/changed-files.txt"

strip_level() { # strip_level <patch>: components to strip so paths become relative to the tree root
  local p; p=$(grep -m1 '^--- ' "$1" | sed 's/^--- //; s/\t.*//')
  case "$p" in
    */base/*|base/*) local pre="${p%%base/*}"; local n; n=$(printf '%s' "${pre}base" | tr -cd '/' | wc -c); echo $((n+1));;
    *) echo 1;;
  esac
}

parse_patch_output() { # parse_patch_output <wp> <outfile>: prints CONFLICT lines, returns number of conflicts; sets FILES, FUZZ
  local wp="$1" f="$2" cur="" n=0
  : > "$OUT/apply-$wp.conflicts"
  while IFS= read -r line; do
    case "$line" in
      "patching file "*) cur="${line#patching file }";;
      "checking file "*) cur="${line#checking file }";;
      *"FAILED at "*) echo "CONFLICT $wp $cur $line" >> "$OUT/apply-$wp.conflicts"; n=$((n+1));;
      *"previously applied"*|*"Reversed"*) echo "CONFLICT $wp $cur already applied/reversed: $line" >> "$OUT/apply-$wp.conflicts"; n=$((n+1));;
      *"which already exists"*) echo "CONFLICT $wp $cur $line" >> "$OUT/apply-$wp.conflicts"; n=$((n+1));;
      *"can't find file"*|*"No such file"*) echo "CONFLICT $wp $cur $line" >> "$OUT/apply-$wp.conflicts"; n=$((n+1));;
      *"malformed patch"*|*"Only garbage"*) echo "CONFLICT $wp $cur $line" >> "$OUT/apply-$wp.conflicts"; n=$((n+1));;
    esac
  done < "$f"
  return $n
}

for X in $ORDER; do
  P="$PATCHDIR/wp$X.patch"
  if [ ! -e "$P" ]; then res "apply-$X SKIP missing ($P)"; SKIPPED="$SKIPPED $X(missing)"; continue; fi
  if [ ! -s "$P" ]; then res "apply-$X SKIP empty (WP still in progress)"; SKIPPED="$SKIPPED $X(empty)"; continue; fi
  if [ "$(remaining)" -le 5 ]; then res "apply-$X FAIL deadline"; overall=1; CONFLICTED="$CONFLICTED $X(deadline)"; continue; fi
  status RUNNING "applying $X"
  N=$(strip_level "$P")
  mode=plain; WS=""
  timeout "$STEP_TIMEOUT" patch -p"$N" -d "$COMPOSE" -N -f --no-backup-if-mismatch --dry-run < "$P" > "$OUT/apply-$X.dry" 2>&1; rc=$?
  if [ $rc -ne 0 ]; then
    parse_patch_output "$X" "$OUT/apply-$X.dry"; nplain=$?
    # second chance: whitespace noise (-l); third chance: line endings of each file section matched to the target file
    timeout "$STEP_TIMEOUT" patch -p"$N" -d "$COMPOSE" -N -f -l --no-backup-if-mismatch --dry-run < "$P" > "$OUT/apply-$X.dry2" 2>&1; rc2=$?
    if [ $rc2 -eq 0 ]; then rc=0; mode=ws-fuzzy; WS="-l"; : > "$OUT/apply-$X.conflicts"
    elif python3 -I - "$P" "$COMPOSE" "$N" > "$OUT/apply-$X.eolnorm.patch" 2>/dev/null <<'PY'
import sys, os
patch, root, strip = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = open(patch, 'rb').read().split(b'\n')
def target_style(path):
    parts = path.split('/')[strip:]
    f = os.path.join(root, *parts)
    if not os.path.isfile(f): return None
    b = open(f, 'rb').read()
    n = b.count(b'\n')
    if n == 0: return None
    cr = b.count(b'\r\n')
    return 'crlf' if cr == n else ('lf' if cr == 0 else None)
style = None; inhunk = False; out = []
for i, line in enumerate(data):
    bare = line[:-1] if line.endswith(b'\r') else line
    if bare.startswith(b'--- ') and not inhunk or (bare.startswith(b'--- ') and i + 1 < len(data) and data[i+1].startswith(b'+++ ')):
        p = bare[4:].split(b'\t')[0].decode('utf8', 'replace')
        style = target_style(p); inhunk = False
        out.append(bare); continue
    if bare.startswith(b'+++ ') and not inhunk:
        out.append(bare); continue
    if bare.startswith(b'@@'):
        inhunk = True; out.append(bare); continue
    if inhunk and line[:1] in (b' ', b'+', b'-') and style:
        out.append(bare + (b'\r' if style == 'crlf' else b'')); continue
    if bare.startswith(b'diff ') or bare.startswith(b'Index:'):
        inhunk = False
    out.append(line)
sys.stdout.buffer.write(b'\n'.join(out))
PY
    then
      timeout "$STEP_TIMEOUT" patch -p"$N" -d "$COMPOSE" -N -f --no-backup-if-mismatch --dry-run < "$OUT/apply-$X.eolnorm.patch" > "$OUT/apply-$X.dry3" 2>&1; rc3=$?
      if [ $rc3 -eq 0 ]; then rc=0; mode=eol-normalized; P="$OUT/apply-$X.eolnorm.patch"; : > "$OUT/apply-$X.conflicts"; fi
    fi
  fi
  if [ $rc -ne 0 ]; then
    [ "$rc" = 124 ] && echo "CONFLICT $X - patch dry run timed out" >> "$OUT/apply-$X.conflicts"
    cat "$OUT/apply-$X.conflicts"
    nc=$(grep -c '' "$OUT/apply-$X.conflicts")
    res "apply-$X FAIL conflicts=$nc (patch skipped, nothing applied; see $OUT/apply-$X.dry)"
    CONFLICTED="$CONFLICTED $X"; overall=1; continue
  fi
  timeout "$STEP_TIMEOUT" patch -p"$N" -d "$COMPOSE" -N -f $WS --no-backup-if-mismatch < "$P" > "$OUT/apply-$X.out" 2>&1; rc=$?
  if [ $rc -ne 0 ]; then
    res "apply-$X FAIL real apply rc=$rc after clean dry run (see $OUT/apply-$X.out); tree may be half patched"; CONFLICTED="$CONFLICTED $X(apply-rc)"; overall=1; continue
  fi
  files=$(sed -n 's/^patching file //p' "$OUT/apply-$X.out")
  echo "$files" >> "$OUT/changed-files.txt"
  nf=$(echo "$files" | grep -c .)
  fuzz=$(grep -c 'with fuzz\|offset' "$OUT/apply-$X.out")
  sfx=""; [ "$mode" != plain ] && sfx=" $mode"
  res "apply-$X PASS files=$nf strip=-p$N hunks-with-offset/fuzz=$fuzz$sfx"
  APPLIED="$APPLIED $X"
done
sort -u "$OUT/changed-files.txt" -o "$OUT/changed-files.txt"
NCHANGED=$(grep -c . "$OUT/changed-files.txt")

# ---- step 3: EOL preservation
status RUNNING "eol check"
fixed=0; mixed=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  b="$BASE/$rel"; c="$COMPOSE/$rel"
  [ -f "$b" ] && [ -f "$c" ] || continue
  bt=$(grep -c '' "$b"); bc=$(grep -c $'\r$' "$b")
  ct=$(grep -c '' "$c"); cc=$(grep -c $'\r$' "$c")
  [ "$bt" -gt 0 ] || continue
  if [ "$bc" = "$bt" ] && [ "$cc" != "$ct" ]; then
    if [ "$FIX_EOL" = 1 ]; then sed -i 's/\r$//; s/$/\r/' "$c"; fixed=$((fixed+1)); mixed="$mixed $rel(CRLF)"; else mixed="$mixed $rel(CRLF-broken)"; fi
  elif [ "$bc" = 0 ] && [ "$cc" != 0 ]; then
    if [ "$FIX_EOL" = 1 ]; then sed -i 's/\r$//' "$c"; fixed=$((fixed+1)); mixed="$mixed $rel(LF)"; else mixed="$mixed $rel(LF-broken)"; fi
  fi
done < "$OUT/changed-files.txt"
if [ -n "$mixed" ] && [ "$FIX_EOL" = 0 ]; then res "eol FAIL mixed line endings:$mixed"; overall=1
else res "eol PASS fixed=$fixed${mixed:+ ($mixed )}"; fi

# ---- step 4: php -l
status RUNNING "php -l on $NCHANGED changed files"
: > "$OUT/lint.out"; lint_fail=0; lint_n=0
while IFS= read -r rel; do
  case "$rel" in *.php) ;; *) continue;; esac
  [ -f "$COMPOSE/$rel" ] || continue
  lint_n=$((lint_n+1))
  if [ "$(remaining)" -le 5 ]; then echo "LINT-ERROR $rel deadline" >> "$OUT/lint.out"; lint_fail=$((lint_fail+1)); continue; fi
  o=$(timeout 30 php -l "$COMPOSE/$rel" </dev/null 2>&1); r=$?
  if [ $r -ne 0 ]; then echo "LINT-ERROR $rel: $(echo "$o" | head -2 | tr '\n' ' ' | cut -c1-200)" >> "$OUT/lint.out"; lint_fail=$((lint_fail+1)); fi
done < "$OUT/changed-files.txt"
if [ $lint_fail -eq 0 ]; then res "php-lint PASS files=$lint_n"
else cat "$OUT/lint.out"; res "php-lint FAIL errors=$lint_fail of $lint_n files"; overall=1; fi

# ---- step 5: stobe-tests
tests_line="not run"
if [ "$RUN_TESTS" = 1 ]; then
  rem=$(remaining); tmo=$TESTS_TIMEOUT; [ "$rem" -lt "$tmo" ] && tmo=$rem
  if [ "$tmo" -le 5 ]; then
    res "stobe-tests FAIL no time left (deadline ${DEADLINE}s)"; overall=1; tests_line="deadline"
  else
    status RUNNING "stobe-tests on compose (timeout ${tmo}s, waiting for lock $TESTS_LOCK)"
    # lock wait counts against the same budget
    timeout "$tmo" flock -w "$tmo" "$TESTS_LOCK" "$STOBE_TESTS" "$COMPOSE" > "$OUT/stobe-tests.out" 2>&1; trc=$?
    if [ $trc -eq 124 ]; then
      res "stobe-tests FAIL timeout/deadline after ${tmo}s (partial output $OUT/stobe-tests.out)"; overall=1; tests_line="timeout"
    else
      fails=$(sed -n 's/^FAIL  *\([A-Za-z0-9_.-]*\):.*/\1/p' "$OUT/stobe-tests.out")
      summary=$(grep -E '^suites: ' "$OUT/stobe-tests.out" | tail -1)
      new=0; knownp=0
      for f in $fails; do
        hit=0; for k in $KNOWN; do case "$f" in *"$k"*) hit=1;; esac; done
        if [ $hit = 1 ]; then echo "KNOWN-FAIL-PRESENT $f"; knownp=$((knownp+1)); else echo "NEW-FAIL $f"; new=$((new+1)); fi
      done
      for k in $KNOWN; do echo "$fails" | grep -q "$k" || echo "KNOWN-NOW-PASSING $k"; done
      if [ -z "$summary" ]; then
        res "stobe-tests FAIL no summary line (rc=$trc, see $OUT/stobe-tests.out)"; overall=1; tests_line="no summary"
      elif [ $new -gt 0 ]; then
        res "stobe-tests FAIL new=$new known-present=$knownp $summary"; overall=1; tests_line="new=$new"
      else
        res "stobe-tests PASS new=0 known-present=$knownp $summary"; tests_line="new=0 known=$knownp ${summary#suites: }"
      fi
    fi
  fi
else
  res "stobe-tests SKIP --no-tests"
fi

# ---- step 6: summary
el=$(( $(date +%s) - T0 ))
detail="applied:[${APPLIED# }] skipped:[${SKIPPED# }] conflicted:[${CONFLICTED# }] changed=$NCHANGED lint_err=$lint_fail ${el}s"
if [ $overall -eq 0 ]; then
  res "compose PASS $detail"
  status DONE "compose PASS $detail"
  echo "$(date '+%Y-%m-%d %H:%M') | PASS | $detail | tests: $tests_line" > "$STATUS_DIR/$NAME.result"
  exit 0
fi
res "compose FAIL $detail"
status FAILED "compose FAIL $detail" "fix conflicts in $OUT/apply-*.conflicts, then rerun"
echo "$(date '+%Y-%m-%d %H:%M') | FAIL | $detail | tests: $tests_line" > "$STATUS_DIR/$NAME.result"
exit 1
