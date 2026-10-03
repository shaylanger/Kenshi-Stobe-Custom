#!/usr/bin/env python3
"""Item 68 (part 2): the LLM swapped FETCH target/destination
(TASK_GOAL@FETCH@Shay@mead@1@General Camp Storage Chest@0). A person as target with a container
as destination is swapped; a container/storage name as destination is never a base lookup (here).
Usage: item68b_fetch_arg_swap.py <tree root>"""
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
'''    if (preg_match('/^(?:me|myself|us|player|the\\s+player|you|yourself|here|there)$/', $req)) return 'person';''',
'''    if (preg_match('/^(?:me|myself|us|player|the\\s+player|you|yourself|here|there)$/', $req)) return 'person';
    if (stobeGoalNameIsContainer($req)) return 'container'; // item 68: a chest/storage is no place to travel to''')
patch(W,
'''/**
 * Items 66/68: why an unresolved destination still means "here"''',
'''/** Item 68: a storage container / box name ("General Camp Storage Chest", "the barrel"). */
function stobeGoalNameIsContainer(string $name): bool
{
    return preg_match('/\\b(?:storage|chest|chests|box|boxes|crate|crates|barrel|barrels|container|stash|shelf|shelves|rack|cabinet|locker|cupboard|warehouse|silo|trunk|sack)\\b/i', $name) === 1;
}

/**
 * Item 68: FETCH/DELIVER with the person and the container swapped
 * (target "Shay", destination "General Camp Storage Chest"): [target, destination] put right.
 */
function stobeTaskGoalNormalizeTargetDestination(string $kind, string $target, string $destination): array
{
    if (!in_array(strtoupper($kind), ['FETCH','DELIVER'], true)) return [$target, $destination];
    if (trim($target) === '' || trim($destination) === '') return [$target, $destination];
    if (stobeGoalDestinationFallback($target) === 'person' && stobeGoalNameIsContainer($destination)
        && !stobeGoalNameIsContainer($target)) {
        return [$destination, $target];
    }
    return [$target, $destination];
}

/**
 * Items 66/68: why an unresolved destination still means "here"''')

H = 'lib/chat_helper_functions.php'
patch(H,
'''            $taskKind = strtoupper(trim(strval($taskKind)));
            $taskAmount = max(0, min(1000, intval($taskAmountRaw)));''',
'''            $taskKind = strtoupper(trim(strval($taskKind)));
            if (function_exists('stobeTaskGoalNormalizeTargetDestination')) { // item 68: person/container swapped
                [$fixedTarget, $fixedDestination] = stobeTaskGoalNormalizeTargetDestination($taskKind, strval($taskTarget), strval($taskDestination));
                if ($fixedTarget !== strval($taskTarget)) {
                    stobeLogInfo('Task goal target/destination swapped (item 68)', ['actor'=>$actor, 'target'=>$fixedTarget, 'destination'=>$fixedDestination]);
                    $taskTarget = $fixedTarget; $taskDestination = $fixedDestination;
                }
            }
            $taskAmount = max(0, min(1000, intval($taskAmountRaw)));''')

T = 'tests/goal_destination_regression.php'
patch(T,
'''check('item 68: fallback reason is person', stobeGoalDestinationFallback('GdTestPlayer') === 'person');''',
'''check('item 68: fallback reason is person', stobeGoalDestinationFallback('GdTestPlayer') === 'person');
// 68 part 2: the run m1 swap TASK_GOAL@FETCH@Shay@mead@1@General Camp Storage Chest@0
check('item 68: FETCH target=player, destination=chest -> swapped',
    stobeTaskGoalNormalizeTargetDestination('FETCH', 'GdTestPlayer', 'General Camp Storage Chest') === ['General Camp Storage Chest', 'GdTestPlayer']);
check('item 68: the right order stays', stobeTaskGoalNormalizeTargetDestination('FETCH', 'General Camp Storage Chest', 'GdTestPlayer') === ['General Camp Storage Chest', 'GdTestPlayer']);
check('item 68: other kinds untouched', stobeTaskGoalNormalizeTargetDestination('GUARD', 'GdTestPlayer', 'Storage Chest') === ['GdTestPlayer', 'Storage Chest']);
check('item 68: a container as destination is never a base lookup -> here', $here(stobeWorkGoalResolveDestination('General Camp Storage Chest')));''')
