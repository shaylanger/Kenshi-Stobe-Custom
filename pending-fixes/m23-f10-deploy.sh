#!/bin/bash
# m23 fixer 10 deploy (WSL root): rollback relationships column fix + rel-b55 accident setup, both trees, .new + mv.
# Aborts if rel-b55/rel-m18 is running. Commits + pushes the live tree.
set -euo pipefail
pgrep -f "rel-b55.sh|rel-m18.sh" >/dev/null && { echo "ABORT: rel-b55/rel-m18 running"; exit 1; }
P=/mnt/c/KenshiModding/pending-fixes
FILES="lib/playthrough_rollback.php tests/relationship_rollback_regression.php tests/social_relationship/ingame/rel-b55.sh"
for T in /var/www/html/StobeServer /root/stobe-work/ss-merge; do
  W=$(mktemp -d); for f in $FILES; do mkdir -p "$W/$(dirname $f)"; cp -p "$T/$f" "$W/$f"; done
  python3 $P/m23-rel-rollback-column.py "$W"
  python3 $P/m23-rel-b55-accident.py "$W/tests/social_relationship/ingame/rel-b55.sh"
  mv "$W/tests/social_relationship/ingame/rel-b55.sh.new" "$W/tests/social_relationship/ingame/rel-b55.sh"
  php -l "$W/lib/playthrough_rollback.php" >/dev/null; php -l "$W/tests/relationship_rollback_regression.php" >/dev/null
  bash -n "$W/tests/social_relationship/ingame/rel-b55.sh"
  for f in $FILES; do cat "$W/$f" > "$T/$f.new"; chown --reference="$T/$f" "$T/$f.new"; chmod --reference="$T/$f" "$T/$f.new"; mv "$T/$f.new" "$T/$f"; done
  rm -rf "$W"; echo "deployed $T"
done
cd /var/www/html/StobeServer
git add lib/playthrough_rollback.php tests/relationship_rollback_regression.php
git -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -q -m "fix(rel): loading an older save restores/clears the relationships column too

The rollback restored or cleared only extended_data.relationships, but every persist writes the
core_npc.relationships column too and stobeGetNpcRelationshipMap falls back to / merges it, so a
cleared grudge read back after the load (rel-b55 fade: stale Rel Fenn -> Shay -15, m23).
Regression: tests/relationship_rollback_regression.php (3 checks fail without the fix).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git add tests/social_relationship/ingame/rel-b55.sh
git -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -q -m "test(rel): B55 accident waits for Stobe's first post-load event sweep, wakes Malzin with protect

The hit landed before Stobe's first NPC world event sweep (45 s after the load), so Malzin was first
seen already KO and no knockout was reported; she then stayed KO (head -30.6) through the injury block.
Setup failures are now SETUP FAIL lines (m23 batch E).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q origin HEAD:stobe; git log --oneline -3
