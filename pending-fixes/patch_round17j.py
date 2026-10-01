#!/usr/bin/env python3
"""Server round 17j: bugs 60, 62, 64.

60: "fetch the vodka and the mead" -> one FETCH (vodka); mead ignored. FETCH/STORE/
    DELIVER items may be a list ("Vodka, Mead" / "vodka and mead"): one goal per
    item. Action descriptions say so.
62: direct PATROL@ became Kenshi's waypoint-less PATROL (region wander). It now
    queues a managed PATROL task goal (KenshiFP 17g base loop; cancellable).
64: "loot any food off that dead bonedog" -> LOOT_TARGET@Bonedog, skipped because
    the corpse isn't in the people list. LOOT_TARGET becomes a LOOT_AREA goal when
    the player's line names a category (food/weapons/armour/medical/ammo) or the
    target can't be resolved; category -> item filter.

Usage: patch_round17j.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f"anchor count {n}: {old[:70]!r}"
    s = s.replace(old, new)

rep("'Put matching carried items into player storage, optionally at a named destination. amount 0 means all matching carried items.'",
    "'Put matching carried items into player storage, optionally at a named destination. amount 0 means all matching carried items. item may list several items separated by commas.'")
rep("'Fetch a finite quantity of matching items from player storage, optionally at a named destination.'",
    "'Fetch a finite quantity of matching items from player storage, optionally at a named destination. item may list several items separated by commas (amount applies to each).'")
rep("'Give a finite quantity of carried matching items to a named player-squad member.'",
    "'Give a finite quantity of carried matching items to a named player-squad member. item may list several items separated by commas.'")

# 60: split item lists
rep("""            } else {
                $taskResults[] = $queueOne(
                    $taskKind,$taskItem,$taskTarget,$taskDestination,$taskAmount,""",
    """            } elseif (in_array($taskKind, ['FETCH','STORE','DELIVER'], true)
                && count($taskItemList = array_values(array_filter(array_map('trim',
                    preg_split('/\\s*(?:,|&|\\band\\b)\\s*/i', strval($taskItem)) ?: []), static fn($v) => $v !== ''))) > 1) {
                foreach (array_slice($taskItemList, 0, 6) as $oneItem) {
                    $taskResults[] = $queueOne(
                        $taskKind, $oneItem, $taskTarget, $taskDestination,
                        $taskKind === 'STORE' ? $taskAmount : max(1, $taskAmount),
                        false, 0, $taskMaxCats, false
                    );
                }
            } else {
                $taskResults[] = $queueOne(
                    $taskKind,$taskItem,$taskTarget,$taskDestination,$taskAmount,""")

# 62 + 64: bridge rewrites
rep("""        if (in_array($bridgeCommand, $bridgeCommands, true)) {
            $bridgeTargetCommands = [""",
    """        if ($bridgeCommand === 'PATROL' && function_exists('stobeTaskGoalQueue')) {
            // Kenshi's PATROL order without waypoints wanders the region (bug 62).
            $patrolResult = stobeTaskGoalQueue($actor, 'PATROL', '', '', '', 0, false, 0, 0, false, $effectiveDeliveryGamets);
            if (boolval($patrolResult['ok'] ?? false)) {
                $queuedActions++;
            } else {
                stobeLogWarn('Patrol goal could not be queued', ['actor' => $actor, 'error' => strval($patrolResult['error'] ?? '')]);
                $message = trim($message . " I couldn't actually carry that action out.");
            }
            continue;
        }
        if ($bridgeCommand === 'LOOT_TARGET' && function_exists('stobeTaskGoalQueue')) {
            $lootLine = strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));
            $lootCategory = '';
            foreach ([
                'weapons' => '/\\bweapons?\\b/',
                'armour' => '/\\b(armou?r|clothing|clothes|gear)\\b/',
                'food' => '/\\b(food|meat|rations?)\\b/',
                'medical' => '/\\b(medkits?|medical|first\\s+aid|bandages?)\\b/',
                'ammo' => '/\\b(ammo|ammunition|bolts)\\b/',
            ] as $lootCat => $lootRe) {
                if (preg_match($lootRe, $lootLine) === 1) { $lootCategory = $lootCat; break; }
            }
            $lootTarget = trim($bridgeArgument);
            $lootTargetLive = $lootTarget !== '' && stobeResolveLiveParticipantSerial($lootTarget) > 0;
            if ($lootCategory !== '' || !$lootTargetLive) {
                // Category loot, or a body outside the people list (bug 64): a LOOT_AREA goal.
                $lootResult = stobeTaskGoalQueue($actor, 'LOOT_AREA', $lootCategory !== '' ? $lootCategory : 'all',
                    $lootTarget, '', 0, false, 0, 0, false, $effectiveDeliveryGamets);
                stobeLogInfo('LOOT_TARGET turned into LOOT_AREA goal', ['actor' => $actor, 'target' => $lootTarget, 'category' => $lootCategory, 'ok' => boolval($lootResult['ok'] ?? false)]);
                if (boolval($lootResult['ok'] ?? false)) {
                    $queuedActions++;
                } else {
                    $message = trim($message . " I couldn't actually carry that action out.");
                }
                continue;
            }
        }
        if (in_array($bridgeCommand, $bridgeCommands, true)) {
            $bridgeTargetCommands = [""")

f.write_text(s)
print("patched", f)
