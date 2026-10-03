#!/usr/bin/env python3
"""Item 74: a squad member agrees to "buy X from <trader>" but sends no action:
TASK_GOAL@BUY@<trader>@<item>@<qty>@@0 is added (the player's direct order is the explicit trade
authorization, as for a BuyItems action). Only when the trader is a known NPC.
Usage: item74_agreed_buy_inference.py <tree root>"""
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
r'''/**
 * Item 74: "(go) buy (me) [N] X from <trader>" to a squad member who agreed in words but sent no
 * action -> TASK_GOAL@BUY@<trader>@<item>@<N>@@0. The trader must be a known NPC ($traderKnown
 * overrides the lookup for tests).
 */
function stobeInferBuyFromAgreedRequest(string $playerLine, array|false $npcData, array $actions, string $reply, ?bool $squadMember = null, ?callable $traderKnown = null): string {
    if (!is_array($npcData)) return '';
    if ($squadMember === null) $squadMember = function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData);
    if (!$squadMember) return '';
    foreach ($actions as $a) {
        if (preg_match('/^(TASK_GOAL|WORK_GOAL|TASK_CONTROL|BUY_ITEM|BUYITEM|SELL_ITEM)@/i', trim(strval($a)))) return '';
    }
    $line = trim(function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers($playerLine) : $playerLine);
    if ($line === '' || str_contains($line, '?') || preg_match("/\b(don'?t|do\s+not|never|stop|cancel)\b/i", $line)) return '';
    if (!preg_match("/\b(?i:buy)\s+(?:me\s+|us\s+)?(?:(\d{1,4})\s+)?(?:(?:a|an|the|some)\s+)?([A-Za-z][A-Za-z' -]{1,60}?)\s+from\s+(?:the\s+)?([A-Z][A-Za-z' -]{1,60}?)(?=\s*(?:\band\b|\bfor\b|[,.!;]|$))/", $line, $m)) return '';
    $item = trim(preg_replace('/\s+/', ' ', $m[2]) ?? '');
    $trader = trim(preg_replace('/\s+/', ' ', $m[3]) ?? '');
    if ($item === '' || $trader === '' || preg_match('/^(it|them|that|this|something|stuff)$/i', $item)) return '';
    $known = $traderKnown !== null ? boolval($traderKnown($trader))
        : (function_exists('getNpcData') && is_array(getNpcData($trader)));
    if (!$known) return '';
    if (!function_exists('stobeReplyAgreesToErrand') || !stobeReplyAgreesToErrand($reply)) return '';
    $qty = ($m[1] ?? '') !== '' ? max(1, min(1000, intval($m[1]))) : 1;
    return 'TASK_GOAL@BUY@' . $trader . '@' . $item . '@' . $qty . '@@0';
}

/**
 * Bug 87: "follow me" / "guard me" to a squad member answered without a
 * movement action -> BODYGUARD@<player>.
 */''')

C = 'processor/chat.php'
patch(C,
r'''if (!$narratorMode && function_exists('stobeInferFollowFromOrder')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {''',
r'''if (!$narratorMode && function_exists('stobeInferBuyFromAgreedRequest')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $inferredBuy = stobeInferBuyFromAgreedRequest(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        strval($responseText ?? ''));
    if ($inferredBuy !== '') {
        $responseActions[] = $inferredBuy;
        stobeLogInfo('Agreed purchase without action: TASK_GOAL added (item 74)', ['npc'=>$targetNpc, 'action'=>$inferredBuy]);
    }
}
if (!$narratorMode && function_exists('stobeInferFollowFromOrder')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {''')

T = 'tests/goal_destination_regression.php'
patch(T,
r'''check('item 73: a non-faction NPC -> nothing', ''',
r'''// 74: agreed purchase without an action (run m2, 06:56:48)
$known74 = static fn(string $n): bool => $n === 'Apothecary Abia';
$line74 = 'Malzin, go buy a Standard First Aid Kit from Apothecary Abia.';
$reply74 = "Apothecary Abia, Standard First Aid Kit. I'll see what she's asking for it - assuming she's still got stock this late.";
check('item 74: the run m2 pair -> TASK_GOAL@BUY from the trader',
    stobeInferBuyFromAgreedRequest($line74, $npc73, [], $reply74, true, $known74) === 'TASK_GOAL@BUY@Apothecary Abia@Standard First Aid Kit@1@@0',
    stobeInferBuyFromAgreedRequest($line74, $npc73, [], $reply74, true, $known74));
check('item 74: a number is kept', stobeInferBuyFromAgreedRequest('Buy 2 bread from Apothecary Abia.', $npc73, [], 'Will do.', true, $known74) === 'TASK_GOAL@BUY@Apothecary Abia@bread@2@@0');
check('item 74: an unknown trader -> nothing', stobeInferBuyFromAgreedRequest('Go buy a kit from Nobody Here.', $npc73, [], "I'll go.", true, $known74) === '');
check('item 74: a refusal -> nothing', stobeInferBuyFromAgreedRequest($line74, $npc73, [], "No, I'm not wasting cats on that.", true, $known74) === '');
check('item 74: a question from the player -> nothing', stobeInferBuyFromAgreedRequest('Could you buy a kit from Apothecary Abia?', $npc73, [], "Sure.", true, $known74) === '');
check('item 74: an action already there -> nothing', stobeInferBuyFromAgreedRequest($line74, $npc73, ['TASK_GOAL@BUY@Apothecary Abia@Standard First Aid Kit@1@@0'], $reply74, true, $known74) === '');
check('item 74: a non-faction NPC -> nothing', stobeInferBuyFromAgreedRequest($line74, $npc73, [], $reply74, false, $known74) === '');
check('item 73: a non-faction NPC -> nothing', ''')
