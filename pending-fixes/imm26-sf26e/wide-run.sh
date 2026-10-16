#!/bin/bash
# Wide regression: every tests/imm26_*.php + activity* on the PATCHED tree, then the failures again on the PRE-PATCH files. Usage: bash wide-run.sh [compose-root]
root="${1:-/root/imm26/compose}"
cd "$root" || exit 1
files="lib/activity/ActivityChat.php lib/activity/ActivityResume.php processor/chat.php"
run() { for t in $(ls tests | grep -E '^(imm26_|activity)' | sed 's/\.php$//'); do
  STOBE_DB_NAME=stobe_test flock /tmp/stobe-tests.lock timeout 300 php tests/$t.php > /tmp/sf26e_wide_$1_$t.out 2>&1; rc=$?
  [ $rc = 0 ] || echo "$1 FAIL rc=$rc $t"; done; }
for f in $files; do cp "$f" "/tmp/sf26e_patched_$(echo $f | tr / _)"; done
echo "== patched"; run patched
for f in $files; do cp "$f.bak_before_sf26e" "$f"; done
echo "== pre-patch"; run prepatch
for f in $files; do cp "/tmp/sf26e_patched_$(echo $f | tr / _)" "$f"; done
echo done
