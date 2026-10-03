#!/usr/bin/env python3
"""Items 66 + 68: goal destinations the base table can't resolve.
66: "Home"/"base"/"camp"/"outpost" (or the area she is in) with no stored base -> work right here.
68: a destination that is a person ("Shay", "me", a live participant) -> no base lookup: she
    brings it back to the walk-back target (the selected squad member, bug 75).
Plus: a task goal that fails on an unknown destination says so, like work goals.
Usage: item66_68_goal_destinations.py <tree root>"""
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

W = 'lib/work_goal_functions.php'
patch(W,
'''    if (function_exists('stobeResolveTravelLocationFromVisitedZones')) {
        $zone = stobeResolveTravelLocationFromVisitedZones($requested);
        if (is_array($zone)) {
            return [
                'name' => trim(strval($zone['label'] ?? $requested)),
                'x' => floatval($zone['x'] ?? 0),
                'y' => floatval($zone['y'] ?? 0),
                'z' => floatval($zone['z'] ?? 0),
            ];
        }
    }
    return false;
}''',
'''    if (function_exists('stobeResolveTravelLocationFromVisitedZones')) {
        $zone = stobeResolveTravelLocationFromVisitedZones($requested);
        if (is_array($zone)) {
            return [
                'name' => trim(strval($zone['label'] ?? $requested)),
                'x' => floatval($zone['x'] ?? 0),
                'y' => floatval($zone['y'] ?? 0),
                'z' => floatval($zone['z'] ?? 0),
            ];
        }
    }
    $fallback = stobeGoalDestinationFallback($requested);
    if ($fallback !== '') {
        if (function_exists('stobeLogInfo')) {
            stobeLogInfo('Goal destination not a known place: using the current location (items 66/68)', ['requested' => $requested, 'why' => $fallback]);
        }
        return ['name' => '', 'x' => null, 'y' => null, 'z' => null, 'fallback' => $fallback];
    }
    return false;
}

/**
 * Items 66/68: why an unresolved destination still means "here" ('' when it doesn't):
 * 'person' (the player, "me", a live participant: she brings it back to the walk-back target),
 * 'home_word' ("home", "base", "camp", "outpost": the player's base when none is stored),
 * 'current_area' (the area the game last reported).
 */
function stobeGoalDestinationFallback(string $requested): string
{
    $req = strtolower(trim(preg_replace('/\\s+/', ' ', $requested) ?? ''));
    $req = trim(preg_replace('/^(?:to|at|in|back\\s+to)\\s+/', '', $req) ?? $req);
    if ($req === '') return '';
    if (preg_match('/^(?:me|myself|us|player|the\\s+player|you|yourself|here|there)$/', $req)) return 'person';
    $player = function_exists('getSetting') ? strtolower(trim(strval(getSetting('PLAYER_NAME', '')))) : '';
    if ($player !== '' && $req === $player) return 'person';
    if (function_exists('stobeResolveLiveParticipantSerial') && function_exists('normalizeParticipantNameToken')
        && stobeResolveLiveParticipantSerial(normalizeParticipantNameToken($requested), false) > 0) return 'person';
    if (preg_match("/^(?:(?:my|our|your|the|shay'?s|player'?s)\\s+)?(?:home|base|home\\s+base|camp|outpost|town|hq|headquarters|settlement|compound)$/", $req)) return 'home_word';
    try {
        $row = $GLOBALS['db']->fetchOne(
            "SELECT location FROM eventlog WHERE location <> '' AND localts >= $1 ORDER BY rowid DESC LIMIT 1",
            [time() - 900]
        );
        $loc = strtolower(trim(strval(is_array($row) ? ($row['location'] ?? '') : '')));
        if ($loc !== '' && strlen($req) >= 3 && (str_contains($loc, $req) || str_contains($req, $loc))) return 'current_area';
    } catch (Throwable $e) {
    }
    return '';
}''')

H = 'lib/chat_helper_functions.php'
patch(H,
'''            $allOk = count($taskResults) > 0;
            foreach ($taskResults as $taskResult) {
                if (!boolval($taskResult['ok'] ?? false)) {
                    $allOk = false;''',
'''            $allOk = count($taskResults) > 0;
            $taskDestUnknown = false;
            foreach ($taskResults as $taskResult) {
                if (!boolval($taskResult['ok'] ?? false)) {
                    $allOk = false;
                    if (strval($taskResult['error'] ?? '') === 'destination_not_known') $taskDestUnknown = true;''')
patch(H,
'''            if (!$allOk) {
                $message = trim($message . ' I could not start all of that task right now.');
            }''',
'''            if (!$allOk && $taskDestUnknown && trim($taskDestination) !== '') {
                // Item 68: say why, like work goals do.
                $message = trim($message . ' I cannot do that because I do not know how to reach ' . trim($taskDestination) . '.');
            } elseif (!$allOk) {
                $message = trim($message . ' I could not start all of that task right now.');
            }''')

T = 'tests/goal_destination_regression.php'
p = root / T
if p.exists():
    print(f'{T}: exists')
else:
    p.write_text(r'''<?php
// Items 66/68: goal destinations without a stored base. Run ONLY against a test database:
//   STOBE_DB_NAME=stobe_test php tests/goal_destination_regression.php
require __DIR__ . '/../lib/bootstrap.php';

$db = $GLOBALS['db'];
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }

stobeWorkGoalEnsureSchema();
$oldPlayer = $db->fetchOne("SELECT value FROM general_settings WHERE id='PLAYER_NAME'");
register_shutdown_function(static function () use ($db, $oldPlayer): void {
    $db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
    if (is_array($oldPlayer)) $db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', $1)", [strval($oldPlayer['value'])]);
    $db->exec("DELETE FROM eventlog WHERE data='GdTest area'");
    $db->exec("DELETE FROM player_base_locations WHERE base_id='gdtest-fortress'");
    $db->exec("DELETE FROM player_bases WHERE base_id='gdtest-fortress'");
});
$db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', 'GdTestPlayer')");
$db->exec("DELETE FROM player_base_locations WHERE LOWER(base_name) IN ('home','gdtest fortress')");
$GLOBALS['CACHE_PEOPLE'] = '["GdTestPlayer|hand_11111","GdTestMate|hand_22222"]';
$here = static fn($r): bool => is_array($r) && strval($r['name'] ?? 'x') === '' && array_key_exists('x', $r) && $r['x'] === null;

// 66: "Home" with no stored base (the run m1 case) and other base words
check('item 66: "Home" without a stored base -> here', $here(stobeWorkGoalResolveDestination('Home')), stobeWorkGoalResolveDestination('Home'));
check('item 66: "our base" -> here', $here(stobeWorkGoalResolveDestination('our base')));
check('item 66: "the outpost" -> here', $here(stobeWorkGoalResolveDestination('the outpost')));
check('item 66: an unknown faraway town still fails', stobeWorkGoalResolveDestination('Gdtest Nowhere City') === false);
// 66: a stored base still wins
$db->exec("INSERT INTO player_bases (base_id, name) VALUES ('gdtest-fortress', 'GdTest Fortress') ON CONFLICT DO NOTHING");
$db->exec("INSERT INTO player_base_locations (base_id, base_name, x, y, z) VALUES ('gdtest-fortress', 'GdTest Fortress', 10, 20, 30)");
$f = stobeWorkGoalResolveDestination('GdTest Fortress');
check('item 66: a stored base resolves to its position', is_array($f) && floatval($f['x']) === 10.0, $f);
$db->exec("DELETE FROM player_base_locations WHERE base_name='GdTest Fortress'");
$db->exec("DELETE FROM player_bases WHERE base_id='gdtest-fortress'");
// 66: the area the game last reported
$db->exec("INSERT INTO eventlog (type, ts, gamets, data, sess, localts, people, location) VALUES ('info',$1,1000,'GdTest area','pending',$1,'','Gdtestshire, Border Zone')", [time()]);
check('item 66: the current area -> here', $here(stobeWorkGoalResolveDestination('Gdtestshire')));
$db->exec("DELETE FROM eventlog WHERE data='GdTest area'");

// 68: a person as destination (the run m1 TASK_GOAL@FETCH@...@Shay case)
check('item 68: the player name -> here (bring it back)', $here(stobeWorkGoalResolveDestination('GdTestPlayer')));
check('item 68: "me" -> here', $here(stobeWorkGoalResolveDestination('me')));
check('item 68: a live participant -> here', $here(stobeWorkGoalResolveDestination('GdTestMate')));
check('item 68: fallback reason is person', stobeGoalDestinationFallback('GdTestPlayer') === 'person');

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
''', encoding='utf-8')
    print(f'{T}: created')
