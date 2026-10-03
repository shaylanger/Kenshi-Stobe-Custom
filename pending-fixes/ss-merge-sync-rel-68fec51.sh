#!/bin/bash
# Sync REL 50ec073..68fec51 (run m16: storage_alias binds a re-squadded character, SR32; scenario fixes)
# into a tree that is at 50ec073 for these files (ss-merge after ss-merge-sync-rel-50ec073.sh).
# The patch is `git diff 50ec073 68fec51` from the live tree;
# so its context lines are the anchors: `git apply --check` refuses if any file drifted.
# Shay's latency/training-capture work (09-30/10-01) is NOT in it: ss-merge leaves that out on purpose.
# Usage: ss-merge-sync-rel-68fec51.sh <tree root>   (e.g. /root/stobe-work/ss-merge)
set -euo pipefail
ROOT="${1:?tree root}"
PATCH="$(cd "$(dirname "$0")" && pwd)/ss-merge-sync-rel-68fec51.patch"
cd "$ROOT"
git apply --check "$PATCH"
git apply "$PATCH"
for f in $(grep '^+++ b/' "$PATCH" | sed 's#^+++ b/##' | grep '\.php$'); do php -l "$f" >/dev/null; done
echo "applied $(grep -c '^diff --git' "$PATCH") file patches to $ROOT"
