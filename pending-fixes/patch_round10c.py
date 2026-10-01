#!/usr/bin/env python3
"""Round 10c: bug 33. "Stop! Here's 500, stop fighting" arrived ~1 s after Malzin's attack
began. Her combat flag was still stale, so the deal was recorded as SOCIAL: no STOP_ATTACK,
prompt said "This is not a fight", the deal went IMPOSSIBLE after payment (refund queued),
and she kept attacking.

The deal kind and the "is this a negotiation" check now count the NPC as fighting the
player when her combat flag says so, OR she has a fresh personal-fight registration
(<60 s), OR she started an attack on the player in the last 60 s (eventlog).

Usage: patch_round10c.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


P = "lib/negotiation_phase1.php"
patch(P,
      """    return (is_array($npcData) && stobeNpcIsInCombat($npcData)) ? 'combat' : 'social';
}""",
      """    return stobeDealNpcFightingPlayer($npcData) ? 'combat' : 'social';
}

/** Fighting the player, even before the NPC's combat flag catches up (bug 33). */
function stobeDealNpcFightingPlayer(array|false $npcData): bool {
    if (!is_array($npcData)) return false;
    if (stobeNpcIsInCombat($npcData)) return true;
    $name = normalizeParticipantNameToken(strval($npcData['name'] ?? ''));
    if ($name === '') return false;
    try {
        $fights = json_decode(strval(getConfOpt('STOBE_PERSONAL_FIGHTS', '{}')), true);
        $fight = is_array($fights) ? ($fights[strtolower($name)] ?? null) : null;
        if (is_array($fight) && time() - intval($fight['since'] ?? 0) <= 60) return true;
        $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
        $row = $GLOBALS['db']->fetchOne(
            "SELECT 1 AS hit FROM eventlog WHERE type='combat' AND localts >= $1 AND LOWER(data) LIKE LOWER($2) LIMIT 1",
            [time() - 60, $name . ': Initiated attack (talking to: ' . $player . ')%']
        );
        return is_array($row) && !empty($row['hit']);
    } catch (Throwable $e) {
        return false;
    }
}""")

patch(P,
      """    if (stobeNpcIsInCombat($npcData)) return stobeDealLooksNegotiableMessage($message);""",
      """    if (stobeDealNpcFightingPlayer($npcData)) return stobeDealLooksNegotiableMessage($message);""")

print("patch_round10c: applied")
