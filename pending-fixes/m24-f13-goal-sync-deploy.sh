#!/bin/bash
# m24 fixer 13 deploy (WSL root): goal status-file sync fix (m24-f13-goal-sync.py) to both trees, .new + mv; commit + push live.
# Also deletes the resurrected stale goal wg-5490d01b (BLOCKED Junkbow, Avarek) from the live DB.
set -euo pipefail
P=/mnt/c/KenshiModding/pending-fixes
FILES="lib/work_goal_functions.php lib/task_goal_functions.php tests/ended_goal_history_regression.php"
for T in /var/www/html/StobeServer /root/stobe-work/ss-merge; do
  W=$(mktemp -d); for f in $FILES; do mkdir -p "$W/$(dirname $f)"; cp -p "$T/$f" "$W/$f"; done
  python3 $P/m24-f13-goal-sync.py "$W"
  for f in $FILES; do php -l "$W/$f" >/dev/null; done
  for f in $FILES; do cat "$W/$f" > "$T/$f.new"; chown --reference="$T/$f" "$T/$f.new"; chmod --reference="$T/$f" "$T/$f.new"; mv "$T/$f.new" "$T/$f"; done
  rm -rf "$W"; echo "deployed $T"
done
(cd /tmp && sudo -u postgres psql -q -d stobe -c "DELETE FROM stobe_work_goal WHERE goal_id='wg-5490d01b95fee9ff4f0cc41c'")
cd /var/www/html/StobeServer
git add $FILES
git -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -q -m "fix(goals): status-file sync no longer resurrects rolled-back goals or refreshes unchanged ones (16-fullbase)

Batch G: loading kah-fullbase rolled back and deleted the earlier run's BLOCKED Junkbow goal, but
Stobe's status file still listed it; the next prompt's sync re-inserted it with updated_at=NOW(),
and every sync also bumped updated_at on unchanged rows. The prompt said 'BLOCKED Junkbow, ended
0 min ago, no crafting bench' and Avarek refused the order (no WORK_GOAL, step 63).
Now an ended goal missing from the DB is not inserted, and an unchanged row keeps its age (work and
task goals). Status file paths can be overridden by env (tests).
Regression: tests/ended_goal_history_regression.php (4 checks fail without the fix).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q origin HEAD:stobe; git log --oneline -2
