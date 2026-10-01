#!/usr/bin/env python3
"""Server round 18c (feature 1): tasks and goals only for the player's faction.

Planner goals were already offered only to faction members, but any NPC was
offered ~20 direct orders (loot target, repair, build, operate, task, set_* job
toggles, patrol, rescue, put in bed, imprison/release, first aid) with no trust
check, so a stranger could "loot that corpse" or "operate the mine" for the player.

Now, for NPCs outside the player's faction:
- work orders are not offered and are refused at execution
  ("I don't take orders like that from you - I'm not one of yours.");
- minor requests (follow, come here, wait/hold, guard, go to a place) only run at
  trust >= MINOR_ORDER_TRUST_MIN (default = GIFT_TRUST_THRESHOLD, 56 = Fond) or
  while a deal with the player is open/agreed (a fair paid deal); otherwise refused;
- the prompt carries an ORDERS RULE saying the same.
Combat/negotiation actions (attack, help, surrender, drop weapon, items, cats) are
not affected.

Usage: patch_round18c.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f"anchor count {n}: {old[:70]!r}"
    s = s.replace(old, new)

# helper (top-level, before the serial resolver which is defined once)
rep("function stobeResolveLiveParticipantSerial(string $name, bool $allowStoredFallback = false): int {",
    r'''/** Work orders a non-faction NPC never takes from the player (feature 1). */
function stobeNonFactionWorkOrderCommands(): array {
    return ['WORK_GOAL','TASK_GOAL','TASK_CONTROL','LOOT_TARGET','REPAIR','BUILD','OPERATE_OBJECT','TASK',
        'SET_BLOCK','SET_HOLD','SET_PASSIVE','SET_JOBS','SET_RANGED','SET_TAUNT','SET_SNEAK','SET_RESOURCE','SET_MEDIC',
        'PATROL','RESCUE','PUT_IN_BED','IMPRISON','RELEASE_PRISONER','FIRST_AID'];
}

/** Minor requests a non-faction NPC takes only with trust or an agreed deal. */
function stobeNonFactionMinorOrderCommands(): array {
    return ['FOLLOW','MOVE_TO_TARGET','HOLD_POSITION','BODYGUARD','GUARD_TARGET','TRAVEL_LOCATION','MOVE_TO'];
}

function stobeNonFactionOrderTrustMin(): int {
    $gift = intval(getSettingInt('GIFT_TRUST_THRESHOLD', 56));
    return max(0, min(100, intval(getSettingInt('MINOR_ORDER_TRUST_MIN', $gift))));
}

/**
 * '' when the NPC may carry out this action for the player; otherwise an in-character
 * refusal line. Faction members and non-order actions always pass.
 */
function stobePlayerOrderGate(string $actor, array|false $npcData, string $normalizedAction): string {
    if (!is_array($npcData) || count($npcData) === 0) return '';
    if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData)) return '';
    $at = strpos($normalizedAction, '@');
    $cmd = strtoupper(trim($at === false ? $normalizedAction : substr($normalizedAction, 0, $at)));
    if (in_array($cmd, stobeNonFactionWorkOrderCommands(), true)) {
        return "I don't take orders like that from you - I'm not one of yours.";
    }
    if (!in_array($cmd, stobeNonFactionMinorOrderCommands(), true)) return '';
    $trust = function_exists('stobeNpcPlayerAffinity') ? intval(stobeNpcPlayerAffinity($npcData)) : 0;
    if ($trust >= stobeNonFactionOrderTrustMin()) return '';
    try {
        if (function_exists('stobeDealOpenForNpc') && stobeDealOpenForNpc($actor) !== null) return '';
    } catch (Throwable $e) {
    }
    return "Why would I do that for you? Make it worth my while first.";
}

function stobeResolveLiveParticipantSerial(string $name, bool $allowStoredFallback = false): int {''')

# prompt: don't offer work orders to non-members
rep("""    $actions[] = 'TravelLocation';
    $actions[] = 'MoveTo';
""",
    """    $actions[] = 'TravelLocation';
    $actions[] = 'MoveTo';
    if ($inPlayerFaction !== true) {
        // Feature 1: outsiders don't take work orders from the player.
        $nonFactionHidden = ['LootTarget','Repair','Build','OperateObject','Task','SetBlock','SetHold','SetPassive',
            'SetJobs','SetRanged','SetTaunt','SetSneak','SetResource','SetMedic','Patrol','Rescue','PutInBed',
            'Imprison','ReleasePrisoner','FirstAid'];
        $actions = array_values(array_filter($actions, static fn($a) => !in_array($a, $nonFactionHidden, true)));
    }
""")

# prompt: orders rule for non-members
rep("""        $giftThreshold = max(0, min(100, intval(getSettingInt('GIFT_TRUST_THRESHOLD', 56))));
        $actionLine .= " GIFT RULE:""",
    """        $orderTrust = function_exists('stobeNonFactionOrderTrustMin') ? stobeNonFactionOrderTrustMin() : 56;
        $actionLine .= " ORDERS RULE: You are not in the player's faction and do not work for them. Refuse work orders (making, looting, hauling, building, repairing, operating machines, patrols, jobs, healing others). Minor requests (follow, come here, wait, guard them, go somewhere) only if you trust them (affinity " . strval($orderTrust) . "+; yours is " . strval($propertyAffinity) . ") or as part of a paid deal you have agreed to; otherwise refuse in character or name your price.";
        $giftThreshold = max(0, min(100, intval(getSettingInt('GIFT_TRUST_THRESHOLD', 56))));
        $actionLine .= " GIFT RULE:""")

# execution gate in the chat action loop
rep("""            continue;
        }
        if (str_starts_with($normalizedAction, 'WORK_GOAL@')) {
            $goalParts = explode('@', $normalizedAction);""",
    """            continue;
        }
        $orderRefusal = function_exists('stobePlayerOrderGate')
            ? stobePlayerOrderGate($actor, is_array($actorData) ? $actorData : false, $normalizedAction)
            : '';
        if ($orderRefusal !== '') {
            stobeLogInfo('Order refused: NPC is not in the player faction', ['actor' => $actor, 'action' => $normalizedAction]);
            if (preg_match('/\\b(no|not|won(?:\\'|’)t|refuse|can(?:\\'|’)t|cannot|why would|price|pay)\\b/i', $message) !== 1) {
                $message = trim($message . ' ' . $orderRefusal);
            }
            continue;
        }
        if (str_starts_with($normalizedAction, 'WORK_GOAL@')) {
            $goalParts = explode('@', $normalizedAction);""")

f.write_text(s)
print("patched", f)
