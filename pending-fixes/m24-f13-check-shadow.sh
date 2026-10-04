#!/bin/bash
# m24 fixer 13 (WSL root): --check-shadow counted the test_setup affinity seed rows (rules_version test_setup, applied by
# design) as applied effects -> false "FAIL: affinity effects were applied" (p2-04b/p3-05b/p3-06/p5-03). Exclude them.
set -euo pipefail
F=tools/social_relationship_inspect.php
OLD="    'applied' => (int)(\$q('SELECT count(*) AS n FROM social_effect WHERE applied')[0]['n'] ?? 0),"
NEW="    // M24_F13: test_setup seed rows (relationship setup for a test, applied by design) are not effects of play
    'applied' => (int)(\$q(\"SELECT count(*) AS n FROM social_effect WHERE applied AND rules_version <> 'test_setup'\")[0]['n'] ?? 0),
    'test_setup' => (int)(\$q(\"SELECT count(*) AS n FROM social_effect WHERE applied AND rules_version = 'test_setup'\")[0]['n'] ?? 0),"
for T in /var/www/html/StobeServer /root/stobe-work/ss-merge; do
  W=$(mktemp); cp "$T/$F" "$W"
  OLD="$OLD" NEW="$NEW" python3 -c 'import os,sys; p=sys.argv[1]; s=open(p).read(); o=os.environ["OLD"]; assert s.count(o)==1, "anchor"; open(p,"w").write(s.replace(o,os.environ["NEW"]))' "$W"
  php -l "$W" >/dev/null
  cat "$W" > "$T/$F.new"; chown --reference="$T/$F" "$T/$F.new"; chmod --reference="$T/$F" "$T/$F.new"; mv "$T/$F.new" "$T/$F"; rm -f "$W"; echo "deployed $T"
done
cd /var/www/html/StobeServer
(cd /tmp && sudo -u www-data php /var/www/html/StobeServer/$F --check-shadow 2>&1 | grep -E '"(applied|test_setup|check_shadow)"')
git add $F
git -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -q -m "test(rel): --check-shadow ignores test_setup seed rows (false 'affinity effects were applied')

The only applied social_effect rows were the four test_setup lifesaving seeds (Rel Rook -> Shay,
rules_version test_setup, applied by design); the shadow check counted the whole table, so every
shadow block (p2-04b/p3-05b/p3-06/p5-03) reported FAIL. Counted separately now.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q origin HEAD:stobe; git log --oneline -1
