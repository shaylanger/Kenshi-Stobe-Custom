#!/bin/bash
# m24 fixer 13 deploy (WSL root): fixer 12's REL patch (m24-f12-rel.py) to both trees, .new + mv.
# Aborts if rel-b55/rel-m18 is running. Commits (one per fix) + pushes the live tree.
set -euo pipefail
pgrep -f "rel-b55.sh|rel-m18.sh" >/dev/null && { echo "ABORT: rel-b55/rel-m18 running"; exit 1; }
P=/mnt/c/KenshiModding/pending-fixes
I=tests/social_relationship/ingame
FILES="lib/social_property.php tests/social_property_regression.php $I/REL-p3-06-ko-loot-witnessed.txt $I/rel-m18.sh $I/rel-b55.sh"
for T in /var/www/html/StobeServer /root/stobe-work/ss-merge; do
  W=$(mktemp -d); for f in $FILES; do mkdir -p "$W/$(dirname $f)"; cp -p "$T/$f" "$W/$f"; done
  python3 $P/m24-f12-rel.py "$W"
  php -l "$W/lib/social_property.php" >/dev/null; php -l "$W/tests/social_property_regression.php" >/dev/null
  bash -n "$W/$I/rel-m18.sh"; bash -n "$W/$I/rel-b55.sh"
  for f in $FILES; do cat "$W/$f" > "$T/$f.new"; chown --reference="$T/$f" "$T/$f.new"; chmod --reference="$T/$f" "$T/$f.new"; mv "$T/$f.new" "$T/$f"; done
  rm -rf "$W"; echo "deployed $T"
done
cd /var/www/html/StobeServer
C() { git -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -q -m "$1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"; }
git add lib/social_property.php tests/social_property_regression.php
C "fix(rel): theft-caught window defaults to 900 game s (SR13/SR14)

The owner's own alarm (Stobe theft dialog EV_THIEF_CAUGHT_STEALING_FROM_ME) reached the server
464 game s after the stolen pickup in m22 batch F; the 300 s default matched nothing (hunt_open),
so the give-back scored as a gift instead of property_returned.
Regression: tests/social_property_regression.php (fails with 300)."
git add $I/REL-p3-06-ko-loot-witnessed.txt
C "test(rel): SR09 witness follows Malzin 2 s before the take so her senses are fresh

Teleported while paused, Rel Wren was 3 m away with sees_actor=false (stale senses, m22 F)."
git add $I/rel-m18.sh
C "test(rel): SR06 verdict says PASS/FAIL (Rel Vorn -> Shay aggression in >= 2 combat incidents)"
git add $I/rel-b55.sh
C "test(rel): B55 wild ignores theft_caught squad lines; bleed uses a deep non-bleeding arm wound

wild: Shay/Malzin witnessing the bandits' burglary is not the squad joining the fight.
bleed: chest 100 + blood 30 % bled Rel Vex out before waking (m22 F); now ~-70 % right arm,
bleed 0, blood watchdog while KO, SETUP FAIL if the wound is off."
git push -q origin HEAD:stobe; git log --oneline -5; git status --short | head -5
