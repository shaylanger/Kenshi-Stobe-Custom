#!/usr/bin/env python3
"""Item 71: surrender offers never fired: "is he fighting the player?" only read combat rows whose
text holds his current name. (a) a "took a major hit from <player side>" counts as a fight with the
player; (b) combat rows logged under his pre-naming generic name ("Dust Bandit" for
"Torek [Dust Bandit]") count when that side's serial in the row's people list is his.
Usage: item71_surrender_fight_detection.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text(encoding='utf-8')
    if new in s:
        print(f'{rel}: already patched'); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n} times'
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'{rel}: patched')

E = 'lib/negotiation_engine.php'
patch(E,
'''function stobeNegNpcDied(string $npc, int $sinceUnix): bool {''',
'''/**
 * Item 71: fight events involving this NPC since $sinceUnix, as [ts, attacker, target]:
 * combat rows under his name (defences included); combat rows under his pre-naming generic
 * name ("Dust Bandit" for "Torek [Dust Bandit]") when that side's serial in the row's people
 * list is his; and "took a major hit from X" (X attacked him).
 */
function stobeNegFightEventsForNpc(string $name, array|false $npcData, int $sinceUnix): array {
    $events = stobeNegCombatEvents($sinceUnix, $name, true);
    $serial = function_exists('stobeNegNpcHandSerial') ? stobeNegNpcHandSerial($name, $npcData) : '';
    $serials = [];
    if ($serial !== '') {
        $serials[] = $serial;
        $signed = intval($serial) - 4294967296;
        if ($signed < 0) $serials[] = strval($signed);
    }
    $sideSerial = static function (string $people, int $index): string {
        $list = json_decode($people, true);
        if (!is_array($list) || !isset($list[$index])) return '';
        return preg_match('/\\|hand_(-?\\d+)\\s*$/', strval($list[$index]), $m) ? $m[1] : '';
    };
    $generic = preg_match('/\\[([^\\]]+)\\]\\s*$/', $name, $gm) ? trim($gm[1]) : '';
    if ($generic !== '' && count($serials) > 0) {
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT localts, data, people FROM eventlog WHERE type='combat' AND localts >= $1 AND data LIKE $2 ORDER BY localts DESC LIMIT 400",
            [$sinceUnix, '%' . $generic . '%']
        );
        foreach (is_array($rows) ? $rows : [] as $row) {
            if (!preg_match('/^(.+?):\\s*(?:Initiated attack|Defending against)\\s*\\(talking to:\\s*(.+?)\\)\\s*$/', trim(strval($row['data'] ?? '')), $m)) continue;
            $attacker = normalizeParticipantNameToken($m[1]);
            $target = normalizeParticipantNameToken($m[2]);
            $people = strval($row['people'] ?? '');
            if (strcasecmp($attacker, $generic) === 0 && in_array($sideSerial($people, 0), $serials, true)) $attacker = $name;
            elseif (strcasecmp($target, $generic) === 0 && in_array($sideSerial($people, 1), $serials, true)) $target = $name;
            else continue;
            $events[] = ['ts'=>intval($row['localts']), 'attacker'=>$attacker, 'target'=>$target];
        }
    }
    $hitNames = [$name];
    if ($generic !== '' && count($serials) > 0) $hitNames[] = $generic;
    foreach ($hitNames as $hitName) {
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT localts, data, people FROM eventlog WHERE type='major_damage' AND localts >= $1 AND data LIKE $2 ORDER BY localts DESC LIMIT 100",
            [$sinceUnix, $hitName . ': took a major hit from %']
        );
        foreach (is_array($rows) ? $rows : [] as $row) {
            if ($hitName !== $name && !in_array($sideSerial(strval($row['people'] ?? ''), 0), $serials, true)) continue;
            if (!preg_match('/:\\s*took a major hit from\\s+(.+?)(?:\\s+using\\s+.+)?\\s*$/', trim(strval($row['data'] ?? '')), $m)) continue;
            $events[] = ['ts'=>intval($row['localts']), 'attacker'=>normalizeParticipantNameToken($m[1]), 'target'=>$name];
        }
    }
    return $events;
}

function stobeNegNpcDied(string $npc, int $sinceUnix): bool {''')
patch(E,
'''            $events = stobeNegCombatEvents($now - 90, $name, true);
            $hostileToPlayer = false;''',
'''            $events = stobeNegFightEventsForNpc($name, $data, $now - 90); // item 71
            $hostileToPlayer = false;''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
'''// ---------------------------------------------------------------- 12h5. deal-offer cap tiers''',
'''// ---------------------------------------------------------------- 12h4b. item 71: the fight with the player is seen
// Run m1: Shay attacked "Dust Bandit" (named "Torek [Dust Bandit]" after); he never swung back
// under his new name, so hostile_to_player stayed false and no surrender offer came.
$db->exec("DELETE FROM eventlog WHERE data LIKE '%NegTest71%' OR people LIKE '%hand_4100000071%' OR people LIKE '%hand_4100000072%'");
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name LIKE '%NegTest71%'");
$ev71 = static function (string $type, string $data, string $people) use ($db): void {
    $db->exec("INSERT INTO eventlog (type, ts, gamets, data, sess, localts, people, location) VALUES ($1,$2,1000,$3,'pending',$2,$4,'')",
        [$type, time() - 5, $data, $people]);
};
$readyAll71 = static function () use ($db): void {
    $db->exec("UPDATE stobe_negotiation_directive SET created_unix = created_unix - 5000 WHERE kind IN ('surrender','assist')");
};
// (a) only "took a major hit from <player>" under his new name
fixtureNpc('Torek71 [NegTest71 Bandit]', ['money'=>50,'money_observed_at'=>time(),'is_in_combat'=>true,'storage_id'=>'hand_4100000071'], 'Bread x1', 'A timid coward.', '100/100');
$ev71('major_damage', "Torek71 [NegTest71 Bandit]: took a major hit from $player using Machete", "[\\"Torek71 [NegTest71 Bandit]|hand_4100000071\\",\\"$player|hand_1\\"]");
$readyAll71();
stobeNegConsiderInitiatives('major_damage', 'Torek71 [NegTest71 Bandit]: took a major hit (health 25%)', "[\\"Torek71 [NegTest71 Bandit]|hand_4100000071\\",\\"$player|hand_1\\"]", 1000);
$d71a = $db->fetchOne("SELECT kind FROM stobe_negotiation_directive WHERE npc_name='Torek71 [NegTest71 Bandit]' ORDER BY id DESC LIMIT 1");
check('item 71: "took a major hit from <player>" is a fight with the player -> surrender offer', ($d71a['kind'] ?? '') === 'surrender', $d71a);
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name LIKE '%NegTest71%'");
$db->exec("DELETE FROM eventlog WHERE data LIKE '%NegTest71%'");
// (b) the fight logged under his generic name, his serial
fixtureNpc('Varn71 [NegTest71 Bandit]', ['money'=>50,'money_observed_at'=>time(),'is_in_combat'=>true,'storage_id'=>'hand_4100000072'], 'Bread x1', 'A timid coward.', '100/100');
$ev71('combat', "$player: Initiated attack (talking to: NegTest71 Bandit)", "[\\"$player|hand_1\\",\\"NegTest71 Bandit|hand_4100000072\\"]");
$ev71('combat', "NegTest71 Bandit: Initiated attack (talking to: $player)", "[\\"NegTest71 Bandit|hand_4100000072\\",\\"$player|hand_1\\"]");
$readyAll71();
stobeNegConsiderInitiatives('major_damage', 'Varn71 [NegTest71 Bandit]: took a major hit (health 25%)', "[\\"Varn71 [NegTest71 Bandit]|hand_4100000072\\",\\"$player|hand_1\\"]", 1000);
$d71b = $db->fetchOne("SELECT kind FROM stobe_negotiation_directive WHERE npc_name='Varn71 [NegTest71 Bandit]' ORDER BY id DESC LIMIT 1");
check('item 71: a fight logged under his pre-naming generic name (same serial) counts', ($d71b['kind'] ?? '') === 'surrender', $d71b);
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name LIKE '%NegTest71%'");
$db->exec("DELETE FROM eventlog WHERE data LIKE '%NegTest71%'");
// another bandit with the same generic name (other serial) fighting the player: not his fight
$ev71('combat', "$player: Initiated attack (talking to: NegTest71 Bandit)", "[\\"$player|hand_1\\",\\"NegTest71 Bandit|hand_4100000099\\"]");
$ev71('combat', "NegTest71 Bandit: Initiated attack (talking to: $player)", "[\\"NegTest71 Bandit|hand_4100000099\\",\\"$player|hand_1\\"]");
$f71 = stobeNegFightEventsForNpc('Varn71 [NegTest71 Bandit]', getNpcData('Varn71 [NegTest71 Bandit]'), time() - 90);
check('item 71: a same-named bandit with another serial is not his fight', count(array_filter($f71, static fn($e) => $e['attacker'] === 'Varn71 [NegTest71 Bandit]' || $e['target'] === 'Varn71 [NegTest71 Bandit]')) === 0, $f71);
$db->exec("DELETE FROM eventlog WHERE data LIKE '%NegTest71%'");
foreach (['Torek71 [NegTest71 Bandit]', 'Varn71 [NegTest71 Bandit]'] as $n71) {
    $db->exec("DELETE FROM core_npc_master WHERE name=$1", [$n71]);
    $db->exec("DELETE FROM core_npc WHERE name=$1", [$n71]);
}

// ---------------------------------------------------------------- 12h5. deal-offer cap tiers''')
