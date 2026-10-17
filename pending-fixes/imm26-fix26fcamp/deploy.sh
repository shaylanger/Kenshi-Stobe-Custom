#!/bin/bash
# deploy.sh [--check] <site root> [<site root> ...]   (WSL; imm26 fix26fcamp)
# Backs up the 3 files, runs apply.py (anchor-asserted, idempotent), php -l, prints SHA256 of the two lib files. Refuses the live tree and ss-merge.
# Site roots: /root/imm26/compose, /tmp/stobe-imm26-5090-i5/site (5090-i5), /tmp/stobe-imm26-5090/site (5090-i3), /tmp/stobe-sfo-manual/site, a 4080 lane site (run it there via ssh/wsl).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check=0; [ "${1:-}" = --check ] && { check=1; shift; }
rc=0
for root in "$@"; do
  case "$root" in /var/www/html/*|*/ss-merge*) echo "REFUSE $root (live tree / ss-merge)"; rc=2; continue;; esac
  [ -f "$root/lib/activity/ActivityResume.php" ] || { echo "SKIP $root (no lib/activity/ActivityResume.php)"; rc=2; continue; }
  if [ $check = 1 ]; then
    t=$(mktemp -d); mkdir -p "$t/lib/activity" "$t/tests"; cp "$root/lib/activity/ActivityResume.php" "$root/lib/activity/ActivityAgreementAdapter.php" "$t/lib/activity/"
    [ -f "$root/tests/imm26_wpR1_activity_resume_regression.php" ] && cp "$root/tests/imm26_wpR1_activity_resume_regression.php" "$t/tests/"
    python3 "$HERE/apply.py" "$t" --no-tests >/dev/null 2>&1 && echo "CHECK-OK $root (anchors match)" || { echo "CHECK-FAIL $root"; rc=1; }
    rm -rf "$t"; continue
  fi
  tag=bak-pre-fix26fcamp
  tar czf "$root/../$tag-$(basename "$root").tar.gz" -C "$root" lib/activity/ActivityResume.php lib/activity/ActivityAgreementAdapter.php tests/imm26_wpR1_activity_resume_regression.php 2>/dev/null \
    || tar czf "$root/../$tag-$(basename "$root").tar.gz" -C "$root" lib/activity/ActivityResume.php lib/activity/ActivityAgreementAdapter.php
  opts=""; [ -f "$root/tests/imm26_wpR1_activity_resume_regression.php" ] || opts=--no-tests
  python3 "$HERE/apply.py" "$root" $opts || { echo "APPLY-FAIL $root"; rc=1; continue; }
  php -l "$root/lib/activity/ActivityResume.php" >/dev/null && php -l "$root/lib/activity/ActivityAgreementAdapter.php" >/dev/null || { echo "LINT-FAIL $root"; rc=1; continue; }
  echo "DEPLOYED $root $(sha256sum "$root/lib/activity/ActivityResume.php" "$root/lib/activity/ActivityAgreementAdapter.php" | cut -c1-12 | tr '\n' ' ')"
done
exit $rc
