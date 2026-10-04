#!/usr/bin/env python3
"""Item 90: her words must match her action - no inferred work goal when her reply turns the order down.

Run m14 (plan row A8): "Malzin, make 2 bread." -> the model answered "Bread's a no-go, Shay. Last time I tried,
the grain silo had no power ... I can try again if you want" with action Talk, and the bug 76 inference
(stobeInferWorkGoalFromOrder) still added WORK_GOAL@Bread@2, so a goal ran while she had said no.
Now the inference also reads her reply: a reply that refuses (no-go, can't, won't, not going to, ...) and takes
nothing on ("I'll make", "on it", ...) gets no inferred goal (log `Work goal not inferred: her reply turns the
order down (item 90)`). A reply with no refusal still gets the goal (bug 76 unchanged).

Usage: item90_no_goal_when_she_refuses.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/chat_helper_functions.php",
"""function stobeInferWorkGoalFromOrder(string $playerLine, array|false $npcData, array $actions): string {
    if (!is_array($npcData) || !function_exists('npcIsInPlayerFaction') || !npcIsInPlayerFaction($npcData)) return '';
    foreach ($actions as $a) {
        if (preg_match('/^(WORK_GOAL|TASK_GOAL|TASK_CONTROL)@/i', strval($a))) return '';
    }
""",
"""function stobeInferWorkGoalFromOrder(string $playerLine, array|false $npcData, array $actions, string $reply = ''): string {
    if (!is_array($npcData) || !function_exists('npcIsInPlayerFaction') || !npcIsInPlayerFaction($npcData)) return '';
    foreach ($actions as $a) {
        if (preg_match('/^(WORK_GOAL|TASK_GOAL|TASK_CONTROL)@/i', strval($a))) return '';
    }
    if ($reply !== '' && stobeReplyRefusesOrder($reply)) {
        // Item 90: "Bread's a no-go" with no goal action: her words stand, no goal behind her back.
        if (function_exists('stobeLogInfo')) stobeLogInfo('Work goal not inferred: her reply turns the order down (item 90)', ['order'=>$playerLine, 'reply'=>$reply]);
        return '';
    }
""")

patch("lib/chat_helper_functions.php",
"""/** Item 73: her reply takes the job on ("I'll go dig it out", "on it", "right") and refuses nothing. */
function stobeReplyAgreesToErrand(string $reply): bool {""",
"""/**
 * Item 90: her reply turns an order down ("Bread's a no-go", "I can't", "not going to") and takes
 * nothing on ("I'll make them", "on it"). A refusal next to a clear yes is not a refusal.
 */
function stobeReplyRefusesOrder(string $reply): bool {
    $refuse = false;
    $agree = false;
    foreach (preg_split('/(?<=[.!?])\\s+/', strtolower(trim(str_replace(["\\u{2019}", "\\u{2018}"], "'", $reply)))) ?: [] as $sentence) {
        $sentence = trim($sentence);
        if ($sentence === '') continue;
        if (preg_match("/\\b(no[- ]go|can'?t|cannot|won'?t|will\\s+not|not\\s+going\\s+to|refuse|no\\s+way|not\\s+happening|impossible|out\\s+of\\s+the\\s+question|forget\\s+it|do\\s+it\\s+yourself)\\b/", $sentence)) $refuse = true;
        if (str_ends_with($sentence, '?')) continue;
        if (preg_match("/\\b(i'?ll\\s+(?:make|get|start|bake|cook|craft|brew|smelt|do|see\\s+to|head|work|get\\s+on)|i\\s+will\\s+(?:make|get|start|do)|on\\s+it|will\\s+do|right\\s+away|consider\\s+it\\s+done|coming\\s+up|got\\s+it|getting\\s+(?:on\\s+it|started)|let\\s+me\\s+(?:make|get|start|bake|cook))\\b/", $sentence)) $agree = true;
    }
    return $refuse && !$agree;
}

/** Item 73: her reply takes the job on ("I'll go dig it out", "on it", "right") and refuses nothing. */
function stobeReplyAgreesToErrand(string $reply): bool {""")

patch("tests/negotiation_engine_regression.php",
"""// ---------------------------------------------------------------- cleanup
""",
"""// ---------------------------------------------------------------- item 90: no inferred work goal when her reply refuses
fixtureNpc('NegTestMalzin90', ['money'=>20, 'money_observed_at'=>time()], '', 'Calm.', '100/100', 'Nameless');
$malzin90 = getNpcData('NegTestMalzin90') ?: [];
check('item 90: fixture is a squad member', npcIsInPlayerFaction($malzin90));
check('item 90: "no-go" reply -> no inferred goal', stobeInferWorkGoalFromOrder('Malzin, make 2 bread.', $malzin90, [],
    "Bread's a no-go, Shay. Last time I tried, the grain silo had no power and the whole thing stalled out - unless you've got that sorted, I can't promise anything. I can try again if you want.") === '');
check('item 90: an agreeing reply still gets the goal', stobeInferWorkGoalFromOrder('Malzin, make 2 bread.', $malzin90, [],
    "Right, I'll make them. Can't promise it'll be quick.") === 'WORK_GOAL@Bread@2');
check('item 90: no reply text -> goal as before (bug 76)', stobeInferWorkGoalFromOrder('Malzin, make 2 bread.', $malzin90, []) === 'WORK_GOAL@Bread@2');
$db->exec("DELETE FROM core_npc_master WHERE name='NegTestMalzin90'");

// ---------------------------------------------------------------- cleanup
""")

patch("processor/chat.php",
"""    $inferredGoal = stobeInferWorkGoalFromOrder(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions);""",
"""    $inferredGoal = stobeInferWorkGoalFromOrder(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        strval($responseText ?? '')); // item 90: not when her reply turns it down""")
