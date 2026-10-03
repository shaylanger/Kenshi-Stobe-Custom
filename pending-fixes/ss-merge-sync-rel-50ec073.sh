#!/bin/bash
# Sync the REL drift (live commits 307b011..50ec073: phases 6-8, runs m8-m15 scenario fixes)
# into a tree that still has the older REL versions (ss-merge).
# The patch was generated per file as `git diff <live commit equal to the tree's file> 50ec073`,
# so its context lines are the anchors: `git apply --check` refuses if any file drifted.
# Shay's latency/training-capture work (09-30/10-01) is NOT in it: ss-merge leaves that out on purpose.
# Usage: ss-merge-sync-rel-50ec073.sh <tree root>   (e.g. /root/stobe-work/ss-merge)
set -euo pipefail
ROOT="${1:?tree root}"
PATCH="$(cd "$(dirname "$0")" && pwd)/ss-merge-sync-rel-50ec073.patch"
cd "$ROOT"
git apply --check "$PATCH"
git apply "$PATCH"
for f in $(grep '^+++ b/' "$PATCH" | sed 's#^+++ b/##' | grep '\.php$'); do php -l "$f" >/dev/null; done
echo "applied $(grep -c '^diff --git' "$PATCH") file patches to $ROOT"
