#!/usr/bin/env python3
"""Item 73: a squad member agrees to "fetch/get/bring X from <container>" but sends no action:
TASK_GOAL@FETCH@<container>@<item>@<qty>@@0 is added (empty destination = bring it back to the
walk-back target). Usage: item73_agreed_fetch_inference.py <tree root>"""
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
 * Bug 87: "follow me" / "guard me" to a squad member answered without a
 * movement action -> BODYGUARD@<player>.
 */''',
r'''/** Item 73: her reply takes the job on ("I'll go dig it out", "on it", "right") and refuses nothing. */
function stobeReplyAgreesToErrand(string $reply): bool {
    $agree = false;
    foreach (preg_split('/(?<=[.!?])\s+/', strtolower(trim(str_replace(["\u{2019}", "\u{2018}"], "'", $reply)))) ?: [] as $sentence) {
        $sentence = trim($sentence);
        if ($sentence === '') continue;
        if (preg_match("/\b(no|nope|won'?t|will\s+not|can'?t|cannot|not\s+going|refuse|get\s+it\s+yourself|do\s+it\s+yourself|later|busy)\b/", $sentence)) return false;
        if (str_ends_with($sentence, '?')) continue;
        if (preg_match("/\b(i'?ll|i\s+will|let\s+me|i'?m\s+on\s+it|on\s+it|on\s+my\s+way|right\s+away|will\s+do|got\s+it|sure|fine|right|alright|all\s+right|okay|ok|be\s+right\s+back|going\s+(?:now|to\s+get|to\s+fetch))\b/", $sentence)) $agree = true;
    }
    return $agree;
}

/**
 * Item 73: "fetch/get/bring (me) [N] X from (the) <container>" to a squad member who agreed in
 * words but sent no goal action -> TASK_GOAL@FETCH@<Container>@<item>@<N>@@0 ('' destination =
 * she brings it to the walk-back target). Only when the source is a container name.
 */
function stobeInferFetchFromAgreedRequest(string $playerLine, array|false $npcData, array $actions, string $reply, ?bool $squadMember = null): string {
    if (!is_array($npcData)) return '';
    if ($squadMember === null) $squadMember = function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData);
    if (!$squadMember) return '';
    foreach ($actions as $a) {
        if (preg_match('/^(TASK_GOAL|WORK_GOAL|TASK_CONTROL|GIVE_ITEM|LOOT_TARGET|TAKE_ITEM)@/i', trim(strval($a)))) return '';
    }
    $line = trim(function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers($playerLine) : $playerLine);
    if ($line === '' || preg_match("/\b(don'?t|do\s+not|never|stop|cancel)\b/i", $line)) return '';
    if (!preg_match("/\b(?:fetch|get|grab|bring|fetch\s+me|get\s+me|bring\s+me|grab\s+me)\s+(?:me\s+)?(?:(\d{1,4})\s+)?(?:(?:the|some|a|an|all\s+the|all|my|our)\s+)?([a-z][a-z' -]{1,40}?)\s+(?:from|out\s+of)\s+(?:the\s+|our\s+|my\s+)?([a-z][a-z' -]{2,60}?)(?=\s*(?:\band\b|[,.!?;]|$))/i", $line, $m)) return '';
    $item = trim(preg_replace('/\s+/', ' ', $m[2]) ?? '');
    $container = ucwords(strtolower(trim(preg_replace('/\s+/', ' ', $m[3]) ?? '')));
    if ($item === '' || preg_match('/^(it|them|that|this|those|these|something|stuff)$/i', $item)) return '';
    if (!function_exists('stobeGoalNameIsContainer') || !stobeGoalNameIsContainer($container)) return '';
    if (!stobeReplyAgreesToErrand($reply)) return '';
    $qty = ($m[1] ?? '') !== '' ? max(1, min(1000, intval($m[1]))) : 1;
    return 'TASK_GOAL@FETCH@' . $container . '@' . $item . '@' . $qty . '@@0';
}

/**
 * Bug 87: "follow me" / "guard me" to a squad member answered without a
 * movement action -> BODYGUARD@<player>.
 */''')

C = 'processor/chat.php'
patch(C,
r'''if (!$narratorMode && function_exists('stobeInferFollowFromOrder')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {''',
r'''if (!$narratorMode && function_exists('stobeInferFetchFromAgreedRequest')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $inferredFetch = stobeInferFetchFromAgreedRequest(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        strval($responseText ?? ''));
    if ($inferredFetch !== '') {
        $responseActions[] = $inferredFetch;
        stobeLogInfo('Agreed fetch without action: TASK_GOAL added (item 73)', ['npc'=>$targetNpc, 'action'=>$inferredFetch]);
    }
}
if (!$narratorMode && function_exists('stobeInferFollowFromOrder')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {''')

T = 'tests/goal_destination_regression.php'
patch(T,
r'''check('item 68: a container as destination is never a base lookup -> here', $here(stobeWorkGoalResolveDestination('General Camp Storage Chest')));''',
r'''check('item 68: a container as destination is never a base lookup -> here', $here(stobeWorkGoalResolveDestination('General Camp Storage Chest')));
// 73: agreed fetch without an action (run m2, 06:32:03)
$npc73 = ['inventory'=>'', 'equipment'=>''];
$line73 = 'Malzin, fetch the mead from the general camp storage chest and bring it to me.';
$reply73 = "Mead from the storage chest. Right - I'll go dig it out, assuming nobody's already drunk it.";
check('item 73: the run m2 pair -> TASK_GOAL@FETCH from the chest, back to the player',
    stobeInferFetchFromAgreedRequest($line73, $npc73, [], $reply73, true) === 'TASK_GOAL@FETCH@General Camp Storage Chest@mead@1@@0',
    stobeInferFetchFromAgreedRequest($line73, $npc73, [], $reply73, true));
check('item 73: a number is kept', stobeInferFetchFromAgreedRequest('Get me 3 bread from the storage box.', $npc73, [], 'On it.', true) === 'TASK_GOAL@FETCH@Storage Box@bread@3@@0');
check('item 73: a refusal -> nothing', stobeInferFetchFromAgreedRequest($line73, $npc73, [], "No. Get it yourself.", true) === '');
check('item 73: only a question -> nothing', stobeInferFetchFromAgreedRequest($line73, $npc73, [], 'The mead?', true) === '');
check('item 73: an existing TASK_GOAL -> nothing', stobeInferFetchFromAgreedRequest($line73, $npc73, ['TASK_GOAL@FETCH@General Camp Storage Chest@mead@1@@0'], $reply73, true) === '');
check('item 73: not a container (a town) -> nothing', stobeInferFetchFromAgreedRequest('Fetch the mead from Squin.', $npc73, [], "I'll go.", true) === '');
check('item 73: a non-faction NPC -> nothing', stobeInferFetchFromAgreedRequest($line73, $npc73, [], $reply73, false) === '');''')
