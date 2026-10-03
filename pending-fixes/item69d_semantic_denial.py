#!/usr/bin/env python3
"""Item 69 (part 4, semantic): for a squad member (her hand-over of a requested item she carries is
added/kept by item 67/69), every sentence denying having/carrying/being able to give it, or claiming
it was all given already, is dropped, generic or item-named ("I can't give what I don't carry").
Other NPCs keep the narrower item-69 patterns. Usage: item69d_semantic_denial.py <tree root>"""
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

P = 'lib/negotiation_phase1.php'
patch(P,
r'''function stobeFalseEmptyClaim(string $sentence, array|false $npcData, string $playerMessage = ''): string {
    if (!is_array($npcData) || trim($playerMessage) === '' || !function_exists('stobeParseHandoverRequest')
        || !function_exists('stobeNegInventoryCounts') || !function_exists('stobeNegItemMatchesTerm')) return '';
    $s = strtolower(str_replace(["\u{2019}", "\u{2018}"], "'", $sentence));
    if (!preg_match(''',
r'''/** Item 69 (semantic): a sentence denying she has / carries / can give something, or saying it's all given already. */
function stobeSentenceDeniesHaving(string $s): bool {
    return preg_match("/\b(?:(?:can'?t|cannot|can\s+not|couldn'?t|won'?t\s+be\s+able\s+to)\s+(?:give|hand|spare|share|offer)|(?:don'?t|do\s+not|doesn'?t|didn'?t)\s+(?:have|carry|got|own)|what\s+i\s+(?:don'?t|do\s+not)\s+(?:have|carry)|(?:haven'?t|have\s+not|hasn'?t)\s+(?:got|any)|not\s+(?:carrying|holding)|nothing\s+(?:left|more|to\s+give|on\s+me)|none\s+(?:left|on\s+me)|no\s+more|to\s+spare|(?:all|clean)\s+out|ran\s+out|all\s+gone|empty[- ]handed|already\s+(?:gave|given|handed|took|taken|passed|had)|(?:took|taken|had|got|ate|eaten)\s+(?:(?:it|them)\s+)?(?:all|everything|the\s+lot)|last\s+of\s+(?:it|them|my))\b/", $s) === 1;
}

function stobeFalseEmptyClaim(string $sentence, array|false $npcData, string $playerMessage = '', ?bool $squadMember = null): string {
    if (!is_array($npcData) || trim($playerMessage) === '' || !function_exists('stobeParseHandoverRequest')
        || !function_exists('stobeNegInventoryCounts') || !function_exists('stobeNegItemMatchesTerm')) return '';
    $s = strtolower(str_replace(["\u{2019}", "\u{2018}"], "'", $sentence));
    if ($squadMember === null) $squadMember = function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData);
    if ($squadMember && stobeSentenceDeniesHaving($s)) {
        // item 69 (semantic): her hand-over goes through (item 67), so any denial is false
    } elseif (!preg_match(''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
r'''check('item 69: a denial about something not asked for is fine', ''',
r'''// item 69 (semantic): every m1-m3 denial sentence from a squad member carrying the requested meat
$npc69s = ['inventory'=>'Dried Meat x3 value 40, Bread x1 value 10', 'equipment'=>''];
foreach ([
    'I already handed you all five strips, remember?',
    "There's nothing left in my pack but dry bread.",
    'Again? I already handed over what I had.',
    'You already took the last of it - three strips, and I had none to spare after.',
    "You've had the last of it twice over now.",
    "If the hunger's still gnawing, say so plain and I'll find you something, but I can't give what I don't carry.",
    "I don't have any meat left.",
    "I'm not carrying any more.",
] as $s69) {
    check('item 69 (semantic, squad member): "' . $s69 . '" is dropped', stobeFalseEmptyClaim($s69, $npc69s, $line69, true) === 'Dried Meat', $s69);
}
check('item 69 (semantic): an ordinary sentence stays', stobeFalseEmptyClaim("Here, take them. Eat slowly.", $npc69s, $line69, true) === '');
check('item 69 (semantic): a denial about another item she names stays', stobeFalseEmptyClaim('No more bread for you though.', $npc69s, $line69, true) === '');
check('item 69 (semantic): a non-faction NPC keeps the narrow patterns', stobeFalseEmptyClaim("I can't give what I don't carry.", $npc69s, $line69, false) === '');
check('item 69: a denial about something not asked for is fine', ''')
