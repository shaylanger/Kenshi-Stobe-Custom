#!/usr/bin/env python3
"""Bug 98 (part 2, server): judge "losing?" by live health from the fight.

Stobe (round 21) sends "took a major hit (health N%)" major_damage events
while a fighter's health drops. The stored NPC row is stale during a fight,
so use the lower of the stored ratio and the newest live N from the last 90 s.

Usage: patch_r21_bug98b_server_live_health.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_engine.php'
text = path.read_text(encoding='utf-8')
if 'stobeNegLiveHealthRatio' in text:
    print('already patched')
    sys.exit(0)

helper_anchor = "/** Bug 98: does the stored row carry real health numbers? */\n"
helper = """/** Bug 98: newest live health from the fight ("took a major hit (health N%)"), or null. */
function stobeNegLiveHealthRatio(string $name, int $sinceUnix): ?float {
    try {
        $row = $GLOBALS['db']->fetchOne(
            "SELECT data FROM eventlog WHERE type='major_damage' AND localts >= $1 AND data LIKE $2 ORDER BY localts DESC LIMIT 1",
            [$sinceUnix, $name . ': took a major hit (health %']
        );
        if (is_array($row) && preg_match('/\\(health (\\d+)%\\)/', strval($row['data'] ?? ''), $m)) {
            return max(0.0, min(1.0, intval($m[1]) / 100.0));
        }
    } catch (Throwable $e) {
    }
    return null;
}

"""
use_old = """            if (!stobeNegHasHealthData($row)) { // bug 98: no numbers -> judge by major hits
                $ratio = max(0.1, 1.0 - 0.35 * stobeNegMajorHitsOn($name, $now - 90));
            }
"""
use_new = use_old + """            $live = stobeNegLiveHealthRatio($name, $now - 90); // bug 98: stored health is stale mid-fight
            // The event being handled isn't in the event log yet: read its own "(health N%)".
            if (count($names) === 1 && preg_match('/\\(health (\\d+)%\\)/', $eventData, $hm)) {
                $eventLive = max(0.0, min(1.0, intval($hm[1]) / 100.0));
                if ($live === null || $eventLive < $live) $live = $eventLive;
            }
            if ($live !== null && $live < $ratio) $ratio = $live;
"""
# "Initiated attack" only comes when a fighter picks a target (start of the
# fight, full health); also check the NPC who just took a hit.
names_old = """        if (preg_match('/^(.+?):\\s*Initiated attack\\s*\\(talking to:\\s*(.+?)\\)/', trim($eventData), $m)) {
            $names = [normalizeParticipantNameToken($m[1]), normalizeParticipantNameToken($m[2])];
        }
"""
names_new = names_old.rstrip('\n') + """ elseif (preg_match('/^(.+?):\\s*took a major hit/', trim($eventData), $m)) {
            $names = [normalizeParticipantNameToken($m[1])]; // bug 98: re-check as health drops
        }
"""
assert text.count(names_old) == 1, 'names anchor'
text = text.replace(names_old, names_new)
assert text.count(helper_anchor) == 1, 'helper anchor'
assert text.count(use_old) == 1, 'use anchor'
text = text.replace(helper_anchor, helper + helper_anchor).replace(use_old, use_new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
