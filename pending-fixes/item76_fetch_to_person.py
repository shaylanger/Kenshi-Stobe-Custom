#!/usr/bin/env python3
"""Item 76 (server): "fetch the mead ... and bring it to me" ended with Malzin keeping the mead.
A FETCH whose destination is a person keeps that person's name as the destination label (no
coordinates), so KenshiFP hands the fetched items over when her walk-back arrives. Item 73's
inferred fetch carries "me" when the line says "(bring|give|hand) it to me" / "bring me".
Plain "fetch X" keeps no destination. Usage: item76_fetch_to_person.py <tree root>"""
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
r'''/** Item 68: a storage container / box name ("General Camp Storage Chest", "the barrel"). */''',
r'''/** Item 76: the person a "person" destination names: "me"/"player" = the player, else the name. */
function stobeGoalPersonName(string $requested): string
{
    $req = trim(preg_replace('/^(?:to|at|back\s+to)\s+/i', '', trim($requested)) ?? $requested);
    if (preg_match('/^(?:me|myself|us|player|the\s+player)$/i', $req)) {
        return function_exists('getSetting') ? trim(strval(getSetting('PLAYER_NAME', ''))) : '';
    }
    if (preg_match('/^(?:you|yourself|here|there)$/i', $req)) return '';
    return function_exists('normalizeParticipantNameToken') ? normalizeParticipantNameToken($req) : $req;
}

/** Item 68: a storage container / box name ("General Camp Storage Chest", "the barrel"). */''')

TG = 'lib/task_goal_functions.php'
patch(TG,
r'''    $destName = trim(strval($resolved['name'] ?? ''));
    $x = $resolved['x'] ?? null; $y = $resolved['y'] ?? null; $z = $resolved['z'] ?? null;

    $goalId = stobeWorkGoalId();''',
r'''    $destName = trim(strval($resolved['name'] ?? ''));
    $x = $resolved['x'] ?? null; $y = $resolved['y'] ?? null; $z = $resolved['z'] ?? null;
    if ($kind === 'FETCH' && strval($resolved['fallback'] ?? '') === 'person' && function_exists('stobeGoalPersonName')) {
        // Item 76: bring it to that person: a label only (no coordinates); KenshiFP hands it over on the walk-back.
        $destName = stobeGoalPersonName($destination);
    }

    $goalId = stobeWorkGoalId();''')

H = 'lib/chat_helper_functions.php'
patch(H,
r'''    $qty = ($m[1] ?? '') !== '' ? max(1, min(1000, intval($m[1]))) : 1;
    return 'TASK_GOAL@FETCH@' . $container . '@' . $item . '@' . $qty . '@@0';''',
r'''    $qty = ($m[1] ?? '') !== '' ? max(1, min(1000, intval($m[1]))) : 1;
    // Item 76: "bring/give/hand it to me", "bring me ..." = hand it to the player on return.
    $toMe = preg_match("/\b(?:bring|give|hand|pass|take)\s+(?:it|them|that|those|the\s+[a-z' -]{1,40}?)?\s*(?:back\s+)?to\s+me\b|\b(?:bring|fetch|get|grab)\s+me\b/i", $line) === 1;
    return 'TASK_GOAL@FETCH@' . $container . '@' . $item . '@' . $qty . '@' . ($toMe ? 'me' : '') . '@0';''')

T = 'tests/goal_destination_regression.php'
patch(T,
r'''check('item 73: the run m2 pair -> TASK_GOAL@FETCH from the chest, back to the player',
    stobeInferFetchFromAgreedRequest($line73, $npc73, [], $reply73, true) === 'TASK_GOAL@FETCH@General Camp Storage Chest@mead@1@@0',''',
r'''check('item 73/76: the run m2 pair -> TASK_GOAL@FETCH from the chest, handed to the player ("to me")',
    stobeInferFetchFromAgreedRequest($line73, $npc73, [], $reply73, true) === 'TASK_GOAL@FETCH@General Camp Storage Chest@mead@1@me@0',''')
patch(T,
r'''check('item 73: a number is kept', stobeInferFetchFromAgreedRequest('Get me 3 bread from the storage box.', $npc73, [], 'On it.', true) === 'TASK_GOAL@FETCH@Storage Box@bread@3@@0');''',
r'''check('item 73: a number is kept ("get me" = to the player)', stobeInferFetchFromAgreedRequest('Get me 3 bread from the storage box.', $npc73, [], 'On it.', true) === 'TASK_GOAL@FETCH@Storage Box@bread@3@me@0');
check('item 76: plain "fetch X from the chest" keeps no destination', stobeInferFetchFromAgreedRequest('Fetch the mead from the storage chest.', $npc73, [], 'On it.', true) === 'TASK_GOAL@FETCH@Storage Chest@mead@1@@0');
check('item 76: "me" as person destination is the player', stobeGoalPersonName('me') === 'GdTestPlayer' && stobeGoalPersonName('to GdTestMate') === 'GdTestMate');''')
