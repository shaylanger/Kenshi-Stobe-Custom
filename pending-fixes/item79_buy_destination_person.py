#!/usr/bin/env python3
"""Item 79: TASK_GOAL@BUY@Apothecary Abia@Standard First Aid Kit@1@Apothecary Abia@5000 was rejected
with destination_not_known: the trader's name as destination was looked up as a base. A destination
equal to the target is dropped (any kind), and any known NPC name (core_npc_master) as destination
counts as a person (no base lookup). Usage: item79_buy_destination_person.py <tree root>"""
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
r'''function stobeTaskGoalNormalizeTargetDestination(string $kind, string $target, string $destination): array
{
    if (!in_array(strtoupper($kind), ['FETCH','DELIVER'], true)) return [$target, $destination];''',
r'''function stobeTaskGoalNormalizeTargetDestination(string $kind, string $target, string $destination): array
{
    // Item 79: the target repeated as destination ("BUY@Apothecary Abia@...@Apothecary Abia") is no destination.
    if (trim($target) !== '' && strcasecmp(trim($target), trim($destination)) === 0) return [$target, ''];
    if (!in_array(strtoupper($kind), ['FETCH','DELIVER'], true)) return [$target, $destination];''')
patch(W,
r'''    if (function_exists('stobeResolveLiveParticipantSerial') && function_exists('normalizeParticipantNameToken')
        && stobeResolveLiveParticipantSerial(normalizeParticipantNameToken($requested), false) > 0) return 'person';''',
r'''    if (function_exists('stobeResolveLiveParticipantSerial') && function_exists('normalizeParticipantNameToken')
        && stobeResolveLiveParticipantSerial(normalizeParticipantNameToken($requested), false) > 0) return 'person';
    try { // item 79: any known NPC (also out of sight) is a person, not a base
        $known = $GLOBALS['db']->fetchOne("SELECT 1 AS x FROM core_npc_master WHERE LOWER(name)=LOWER($1) LIMIT 1", [trim($requested)]);
        if (is_array($known)) return 'person';
    } catch (Throwable $e) {
    }''')

H = 'lib/chat_helper_functions.php'
patch(H,
r'''                if ($fixedTarget !== strval($taskTarget)) {
                    stobeLogInfo('Task goal target/destination swapped (item 68)', ['actor'=>$actor, 'target'=>$fixedTarget, 'destination'=>$fixedDestination]);
                    $taskTarget = $fixedTarget; $taskDestination = $fixedDestination;
                }''',
r'''                if ($fixedTarget !== strval($taskTarget) || $fixedDestination !== strval($taskDestination)) {
                    stobeLogInfo('Task goal target/destination normalized (items 68/79)', ['actor'=>$actor, 'target'=>$fixedTarget, 'destination'=>$fixedDestination]);
                    $taskTarget = $fixedTarget; $taskDestination = $fixedDestination;
                }''')

T = 'tests/goal_destination_regression.php'
patch(T,
r'''check('item 73: a non-faction NPC -> nothing', ''',
r'''// 79: run m4 TASK_GOAL@BUY@Apothecary Abia@Standard First Aid Kit@1@Apothecary Abia@5000
check('item 79: destination equal to the target is dropped (BUY)',
    stobeTaskGoalNormalizeTargetDestination('BUY', 'Apothecary Abia', 'Apothecary Abia') === ['Apothecary Abia', '']);
$db->exec("DELETE FROM core_npc_master WHERE name='GdTest Trader79'");
$db->exec("INSERT INTO core_npc_master (name, metadata, created_at, updated_at) VALUES ('GdTest Trader79', '{}'::jsonb, NOW(), NOW())");
check('item 79: a known NPC out of sight as destination is a person -> here, no base lookup',
    stobeGoalDestinationFallback('GdTest Trader79') === 'person' && $here(stobeWorkGoalResolveDestination('GdTest Trader79')));
$db->exec("DELETE FROM core_npc_master WHERE name='GdTest Trader79'");
check('item 73: a non-faction NPC -> nothing', ''')
