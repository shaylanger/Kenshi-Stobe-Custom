#!/usr/bin/env python3
"""Item 67: a squad member agrees to a hand-over in words but sends no GIVE_ITEM.
Extends item 43's stobeInferMissingHandovers. Usage: item67_agreed_handover.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new, count=1):
    p = root / rel
    s = p.read_text(encoding='utf-8')
    if new in s:
        print(f'{rel}: already patched'); return
    n = s.count(old)
    assert n == count, f'{rel}: anchor found {n} times, expected {count}'
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'{rel}: patched')

H = 'lib/chat_helper_functions.php'
patch(H,
'''/**
 * Item 43: the player asked for several carried items in one line and her reply hands
 * over one of them (a reply carries one action): the missing GIVE_ITEM actions.
 */
function stobeInferMissingHandovers(string $playerLine, array|false $npcData, array $actions, string $reply, string $playerName): array {''',
'''/**
 * Item 67: her reply clearly agrees to hand something over ("whatever's there is yours",
 * "here you go", "take them") and doesn't refuse. A reply that is only a question is no agreement.
 */
function stobeReplyAgreesToHandover(string $reply): bool {
    $sentences = preg_split('/(?<=[.!?])\\s+/', strtolower(trim(str_replace(["\\u{2019}", "\\u{2018}"], "'", $reply)))) ?: [];
    $agree = false;
    foreach ($sentences as $sentence) {
        $sentence = trim($sentence);
        if ($sentence === '') continue;
        if (preg_match("/\\b(no|nope|won'?t|will\\s+not|not\\s+giving|not\\s+handing|mine|keep|keeping|get\\s+your\\s+own|never|refuse|forget\\s+it)\\b/", $sentence)) return false;
        if (str_ends_with($sentence, '?')) continue;
        if (preg_match("/\\b(yours|here\\s+you\\s+(?:go|are)|here\\s+(?:it\\s+is|they\\s+are)|take\\s+(?:it|them|what|whatever|all)|have\\s+(?:it|them)|help\\s+yourself|sure|fine|go\\s+ahead|of\\s+course|alright|all\\s+right)\\b/", $sentence)) $agree = true;
    }
    return $agree;
}

/**
 * Item 43: the player asked for several carried items in one line and her reply hands
 * over one of them (a reply carries one action): the missing GIVE_ITEM actions.
 * Item 67: a squad member who agreed in words but sent no GIVE_ITEM at all: the requested
 * items she carries ($squadMember null = npcIsInPlayerFaction).
 */
function stobeInferMissingHandovers(string $playerLine, array|false $npcData, array $actions, string $reply, string $playerName, ?bool $squadMember = null): array {''')
patch(H,
'''    if (count($given) === 0) return [];
    $wanted = stobeParseHandoverRequest($playerLine);
    if (count($wanted) < 2) return [];''',
'''    $wanted = stobeParseHandoverRequest($playerLine);
    if (count($given) === 0) {
        // Item 67: only a squad member who clearly agreed; others go through deals/gifts.
        if ($squadMember === null) $squadMember = function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData);
        if (!$squadMember || count($wanted) < 1 || !stobeReplyAgreesToHandover($reply)) return [];
    } elseif (count($wanted) < 2) {
        return [];
    }''')

C = 'processor/chat.php'
patch(C,
'''    $missingHandovers = stobeInferMissingHandovers(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        strval($responseText ?? ''), strval($playerName ?? ''));
    if (count($missingHandovers) > 0) {
        $responseActions = array_merge($responseActions, $missingHandovers);
        stobeLogInfo('Two-part hand-over: missing GIVE_ITEM added (item 43)', ['npc'=>$targetNpc, 'added'=>$missingHandovers]);
    }''',
'''    $missingHandovers = stobeInferMissingHandovers(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        strval($responseText ?? ''), strval($playerName ?? ''));
    if (count($missingHandovers) > 0) {
        $hadGiveItem = count(preg_grep('/^\\s*GIVE_ITEM@/i', array_map('strval', $responseActions)) ?: []) > 0;
        $responseActions = array_merge($responseActions, $missingHandovers);
        stobeLogInfo($hadGiveItem ? 'Two-part hand-over: missing GIVE_ITEM added (item 43)'
            : 'Agreed hand-over without action: GIVE_ITEM added (item 67)', ['npc'=>$targetNpc, 'added'=>$missingHandovers]);
    }''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
'''check('item 43: a one-item order -> nothing added',
    stobeInferMissingHandovers('Give me your bread.', $npc43, ['GIVE_ITEM@Shay@Bread@1'], 'Here.', 'Shay') === []);
''',
'''check('item 43: a one-item order -> nothing added',
    stobeInferMissingHandovers('Give me your bread.', $npc43, ['GIVE_ITEM@Shay@Bread@1'], 'Here.', 'Shay') === []);

// ---------------------------------------------------------------- 12h3b. item 67: a squad member agrees but sends no GIVE_ITEM
$line67 = 'Malzin, please hand me all your bread and all your dried meat, I need it for the trip.';
check('item 67: the run m1 reply (squad member agrees, no action) -> bread + dried meat added',
    stobeInferMissingHandovers($line67, $npc43, [], "Bread and dried meat - let me check what I've actually got on me. I'm not carrying much, but whatever's there is yours.", 'Shay', true)
    === ['GIVE_ITEM@Shay@Bread@2', 'GIVE_ITEM@Shay@Dried Meat@10']);
check('item 67: one item, "here you go" -> added',
    stobeInferMissingHandovers('Give me 3 dried meat.', $npc43, [], 'Here you go.', 'Shay', true) === ['GIVE_ITEM@Shay@Dried Meat@3']);
check('item 67: a pure question ("All of it?") -> nothing added',
    stobeInferMissingHandovers($line67, $npc43, [], 'All of it?', 'Shay', true) === []);
check('item 67: a refusal -> nothing added',
    stobeInferMissingHandovers($line67, $npc43, [], "Not giving you my food. Get your own.", 'Shay', true) === []);
check('item 67: "sure" but the meat stays -> nothing (a refusal word)',
    stobeInferMissingHandovers($line67, $npc43, [], 'Sure, the bread. The meat I keep.', 'Shay', true) === []);
check('item 67: a non-faction NPC agreeing in words -> nothing added (deal/gift rules)',
    stobeInferMissingHandovers($line67, $npc43, [], "Whatever's there is yours.", 'Shay', false) === []);
check('item 67: something she does not carry -> nothing added',
    stobeInferMissingHandovers('Give me your katana.', $npc43, [], 'Here you go.', 'Shay', true) === []);
''')
