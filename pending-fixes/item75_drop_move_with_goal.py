#!/usr/bin/env python3
"""Item 75 (server): next to the inferred TASK_GOAL@BUY (item 74) the model's own
MOVE_TO@Apothecary Abia failed to resolve and was spoken as
"ROLEPLAY_ACTION@Could not identify that destination.". When items 73/74 add a goal, a
MOVE_TO / MOVE_TO_TARGET / TRAVEL_LOCATION toward that goal's trader or container is dropped
(the goal walks there itself). Usage: item75_drop_move_with_goal.py <tree root>"""
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

H = 'lib/chat_helper_functions.php'
patch(H,
r'''/**
 * Item 74: "(go) buy (me) [N] X from <trader>" to a squad member who agreed in words but sent no''',
r'''/**
 * Item 75: an inferred goal (TASK_GOAL@KIND@<place>@...) walks to its trader/container itself:
 * a MOVE_TO / MOVE_TO_TARGET / TRAVEL_LOCATION toward that place is dropped. Returns the actions.
 */
function stobeDropMovesCoveredByGoal(array $actions, string $goalAction): array {
    $parts = explode('@', $goalAction);
    $place = strtolower(trim(strval($parts[2] ?? '')));
    if ($place === '') return $actions;
    $bare = static fn(string $s): string => strtolower(trim(preg_replace('/\s*\[[^\]]*\]\s*/', ' ', $s) ?? $s));
    return array_values(array_filter($actions, static function ($a) use ($place, $bare): bool {
        if (!preg_match('/^\s*(MOVE_TO|MOVE_TO_TARGET|TRAVEL_LOCATION)@(.*)$/i', strval($a), $m)) return true;
        $target = $bare(strval($m[2]));
        return !($target !== '' && ($target === $bare($place) || str_contains($target, $bare($place)) || str_contains($bare($place), $target)));
    }));
}

/**
 * Item 74: "(go) buy (me) [N] X from <trader>" to a squad member who agreed in words but sent no''')

C = 'processor/chat.php'
patch(C,
r'''        $responseActions[] = $inferredBuy;
        stobeLogInfo('Agreed purchase without action: TASK_GOAL added (item 74)', ['npc'=>$targetNpc, 'action'=>$inferredBuy]);''',
r'''        $responseActions = stobeDropMovesCoveredByGoal($responseActions, $inferredBuy); // item 75
        $responseActions[] = $inferredBuy;
        stobeLogInfo('Agreed purchase without action: TASK_GOAL added (item 74)', ['npc'=>$targetNpc, 'action'=>$inferredBuy]);''')
patch(C,
r'''        $responseActions[] = $inferredFetch;
        stobeLogInfo('Agreed fetch without action: TASK_GOAL added (item 73)', ['npc'=>$targetNpc, 'action'=>$inferredFetch]);''',
r'''        $responseActions = stobeDropMovesCoveredByGoal($responseActions, $inferredFetch); // item 75
        $responseActions[] = $inferredFetch;
        stobeLogInfo('Agreed fetch without action: TASK_GOAL added (item 73)', ['npc'=>$targetNpc, 'action'=>$inferredFetch]);''')

T = 'tests/goal_destination_regression.php'
patch(T,
r'''check('item 73: a non-faction NPC -> nothing', ''',
r'''// 75: the model's MOVE_TO toward the goal's trader is dropped (run m2: "Could not identify that destination")
check('item 75: MOVE_TO@Apothecary Abia is dropped next to the inferred BUY goal',
    stobeDropMovesCoveredByGoal(['MOVE_TO@Apothecary Abia', 'EQUIP_ITEM@Hat'], 'TASK_GOAL@BUY@Apothecary Abia@Standard First Aid Kit@1@@0') === ['EQUIP_ITEM@Hat']);
check('item 75: a move elsewhere stays',
    stobeDropMovesCoveredByGoal(['MOVE_TO@Squin'], 'TASK_GOAL@BUY@Apothecary Abia@Kit@1@@0') === ['MOVE_TO@Squin']);
check('item 73: a non-faction NPC -> nothing', ''')
