#!/bin/bash
# Runs the suites on the pre-patch files (restored from *.bak_before_sf26e), then on the patched files. Usage: bash before-after.sh [compose-root]
here="$(cd "$(dirname "$0")" && pwd)"
root="${1:-/root/imm26/compose}"
cd "$root" || exit 1
files="lib/activity/ActivityChat.php lib/activity/ActivityResume.php processor/chat.php"
for f in $files; do php -l "$f" | grep -v "^No syntax" ; cp "$f" "/tmp/sf26e_patched_$(echo $f | tr / _)"; done
for f in $files; do cp "$f.bak_before_sf26e" "$f"; done
bash "$here/run-tests.sh" "$root" > /tmp/sf26e_before.txt 2>&1; echo "before rc=$?"
for f in $files; do cp "/tmp/sf26e_patched_$(echo $f | tr / _)" "$f"; done
bash "$here/run-tests.sh" "$root" > /tmp/sf26e_after.txt 2>&1; echo "after rc=$?"
grep -h "passed\|RC-FAIL\|(missing)" /tmp/sf26e_before.txt > /tmp/sf26e_b.txt
grep -h "passed\|RC-FAIL\|(missing)" /tmp/sf26e_after.txt > /tmp/sf26e_a.txt
echo "=== BEFORE"; cat /tmp/sf26e_b.txt; echo "=== AFTER"; cat /tmp/sf26e_a.txt
