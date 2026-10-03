#!/usr/bin/env python3
"""Item 82 (server): "go buy a Standard First Aid Kit from Apothecary Abia and bring it to me": the
kit stayed with Malzin. Like item 76 for FETCH: a BUY whose destination is a person keeps the name as
a label, and item 74's inferred buy sends "me" for "bring/give it to me" / "buy me".
Usage: item82_buy_to_person.py <tree root>"""
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

patch('lib/task_goal_functions.php',
r'''    if ($kind === 'FETCH' && strval($resolved['fallback'] ?? '') === 'person' && function_exists('stobeGoalPersonName')) {''',
r'''    if (in_array($kind, ['FETCH','BUY'], true) && strval($resolved['fallback'] ?? '') === 'person' && function_exists('stobeGoalPersonName')) { // items 76/82''')

patch('lib/chat_helper_functions.php',
r'''    $qty = ($m[1] ?? '') !== '' ? max(1, min(1000, intval($m[1]))) : 1;
    return 'TASK_GOAL@BUY@' . $trader . '@' . $item . '@' . $qty . '@@0';''',
r'''    $qty = ($m[1] ?? '') !== '' ? max(1, min(1000, intval($m[1]))) : 1;
    // Item 82: "bring/give it to me", "buy me ..." = hand it to the player on return.
    $toMe = preg_match("/\b(?:bring|give|hand|pass|take)\s+(?:it|them|that|those|the\s+[a-z' -]{1,40}?)?\s*(?:back\s+)?to\s+me\b|\bbuy\s+me\b/i", $line) === 1;
    return 'TASK_GOAL@BUY@' . $trader . '@' . $item . '@' . $qty . '@' . ($toMe ? 'me' : '') . '@0';''')

patch('tests/goal_destination_regression.php',
r'''check('item 74: a number is kept', ''',
r'''check('item 82: "... and bring it to me" -> the bought kit goes to the player',
    stobeInferBuyFromAgreedRequest('Malzin, go buy a Standard First Aid Kit from Apothecary Abia and bring it to me.', $npc73, [], "I'll go and get it.", true, $known74)
    === 'TASK_GOAL@BUY@Apothecary Abia@Standard First Aid Kit@1@me@0');
check('item 74: a number is kept', ''')
