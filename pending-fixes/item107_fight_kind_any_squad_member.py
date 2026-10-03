#!/usr/bin/env python3
"""Item 107: a deal struck while an NPC fights ANY player-side character is a combat deal.

stobeDealNpcFightingPlayer() fell back to an eventlog check for
"<npc>: Initiated attack (talking to: <PLAYER_NAME>)", so on a save whose squad isn't the
persona (Full-Base: Beaks/Avarek) a raider fighting Beaks gave a `social` deal (1 game-day
deadline): an unpaid pay-later never became BREACHED_PLAYER. The prompt block also chose the
kind from the combat flag alone. Now: any player-side target counts, and the prompt uses the
same check.

Usage: item107_fight_kind_any_squad_member.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new, count=1):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == count, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/negotiation_phase1.php",
"""        $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
        $row = $GLOBALS['db']->fetchOne(
            "SELECT 1 AS hit FROM eventlog WHERE type='combat' AND localts >= $1 AND LOWER(data) LIKE LOWER($2) LIMIT 1",
            [time() - 60, $name . ': Initiated attack (talking to: ' . $player . ')%']
        );
        return is_array($row) && !empty($row['hit']);
""",
"""        $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
        // Item 107: any player-side target counts (a squad without the persona, e.g. Beaks).
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT data FROM eventlog WHERE type='combat' AND localts >= $1 AND LOWER(data) LIKE LOWER($2) ORDER BY localts DESC LIMIT 10",
            [time() - 60, $name . ': Initiated attack (talking to: %']
        );
        foreach (is_array($rows) ? $rows : [] as $r) {
            if (!preg_match('/\\(talking to:\\s*(.+?)\\)/', strval($r['data'] ?? ''), $m)) continue;
            $target = normalizeParticipantNameToken($m[1]);
            if (strcasecmp($target, $player) === 0) return true;
            if (function_exists('stobeNegIsPlayerSide') && stobeNegIsPlayerSide($target, $player)) return true;
        }
        return false;
""")

patch("lib/negotiation_phase1.php",
"""    $kind = $open !== null ? strval($open['kind'] ?? 'combat') : ((stobeNpcIsInCombat($npcData)) ? 'combat' : 'social');""",
"""    $kind = $open !== null ? strval($open['kind'] ?? 'combat') : (stobeDealNpcFightingPlayer($npcData) ? 'combat' : 'social'); // item 107""")

patch("tests/negotiation_engine_regression.php",
"""// ---------------------------------------------------------------- cleanup
""",
"""// ---------------------------------------------------------------- Item 107: a fight with any squad member makes a combat deal
fixtureNpc('NegTestBeaks107', ['money'=>800, 'money_observed_at'=>time()], '', '', '100/100', 'Nameless');
fixtureNpc('NegTestRaider107', ['money'=>50, 'money_observed_at'=>time()], '', 'A raider.');
$raider107 = getNpcData('NegTestRaider107');
check('item 107: no fight seen -> social', stobeDealKindFor($raider107) === 'social', stobeDealKindFor($raider107));
$db->exec("INSERT INTO eventlog (type, ts, gamets, data, sess, localts, people, location) VALUES ('combat',$1,1000,$2,'pending',$1,'','')",
    [time(), 'NegTestRaider107: Initiated attack (talking to: NegTestBeaks107)']);
check('item 107: raider attacking a non-persona squad member -> combat deal', stobeDealKindFor($raider107) === 'combat', stobeDealKindFor($raider107));
$db->exec("DELETE FROM eventlog WHERE data LIKE '%NegTestRaider107%'");
$db->exec("INSERT INTO eventlog (type, ts, gamets, data, sess, localts, people, location) VALUES ('combat',$1,1000,$2,'pending',$1,'','')",
    [time(), 'NegTestRaider107: Initiated attack (talking to: NegTestTrader)']);
check('item 107: attacking an outsider is not a fight with the player', stobeDealKindFor($raider107) === 'social', stobeDealKindFor($raider107));
$db->exec("DELETE FROM eventlog WHERE data LIKE '%NegTestRaider107%'");
foreach (['NegTestBeaks107', 'NegTestRaider107'] as $n) { $db->exec("DELETE FROM core_npc_master WHERE name=$1", [$n]); $db->exec("DELETE FROM core_npc WHERE name=$1", [$n]); }

// ---------------------------------------------------------------- cleanup
""")
