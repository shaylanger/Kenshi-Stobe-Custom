#!/usr/bin/env python3
"""Item 69: she says she has none / nothing left of an item the player asked for while her
inventory holds it ("I already handed you all five strips... nothing left in my pack but dry bread"
with Dried Meat x5). That sentence is dropped like an item-41 gear claim (same hook: streamed and
full replies), and for a squad member it counts as agreeing to the hand-over (item 67 adds the
GIVE_ITEM). Only items named in the player's line are checked.
Usage: item69_false_empty_claim.py <tree root>"""
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
'''function stobeFalseGearClaim(string $sentence, array|false $npcData, string $playerMessage = ''): string {
    if (!is_array($npcData) || !function_exists('stobeNegInventoryDisplayNames')) return '';''',
'''function stobeFalseGearClaim(string $sentence, array|false $npcData, string $playerMessage = ''): string {
    if (!is_array($npcData) || !function_exists('stobeNegInventoryDisplayNames')) return '';
    $empty = function_exists('stobeFalseEmptyClaim') ? stobeFalseEmptyClaim($sentence, $npcData, $playerMessage) : '';
    if ($empty !== '') return $empty; // item 69''')
patch(P,
'''/** Drops item-41 sentences from a whole reply: ['text'=>..., 'dropped'=>[sentence, ...]]. */''',
'''/**
 * Item 69: a sentence saying she has none / nothing left / already handed over all of an item the
 * player's line asks for, while her inventory holds it: that item's display name, or ''.
 * A denial naming no requested item ("nothing left in my pack but dry bread") counts for them all.
 * Hits are remembered for this request (item 67 treats them as agreeing to hand it over).
 */
function stobeFalseEmptyClaim(string $sentence, array|false $npcData, string $playerMessage = ''): string {
    if (!is_array($npcData) || trim($playerMessage) === '' || !function_exists('stobeParseHandoverRequest')
        || !function_exists('stobeNegInventoryCounts') || !function_exists('stobeNegItemMatchesTerm')) return '';
    $s = strtolower(str_replace(["\\u{2019}", "\\u{2018}"], "'", $sentence));
    if (!preg_match("/\\b(?:nothing\\s+(?:left|more)|none\\s+left|no\\s+more|(?:all|clean)\\s+out\\s+of|(?:i'?m|i\\s+am)\\s+out\\s+of|all\\s+gone|(?:don'?t|do\\s+not)\\s+have\\s+any|(?:haven'?t|have\\s+not)\\s+got\\s+any|not\\s+carrying\\s+any|ran\\s+out|already\\s+(?:handed|gave|given|passed)\\s+(?:you\\s+|it\\s+|them\\s+)?(?:all|every|everything|the\\s+last))/", $s)) return '';
    $wanted = stobeParseHandoverRequest($playerMessage);
    if (count($wanted) === 0) return '';
    $counts = stobeNegInventoryCounts(strval($npcData['inventory'] ?? ''));
    $display = function_exists('stobeItemListDisplayNames') ? stobeItemListDisplayNames(strval($npcData['inventory'] ?? '')) : [];
    $held = [];
    $namedAny = false;
    foreach ($wanted as $w) {
        $part = $w['part'];
        $head = strval(array_slice(preg_split('/\\s+/', rtrim($part, 's')) ?: [''], -1)[0]);
        $named = $head !== '' && strlen($head) >= 3 && preg_match('/\\b' . preg_quote($head, '/') . '/', $s) === 1;
        if ($named) $namedAny = true;
        foreach ($counts as $name => $qty) {
            if ($qty < 1) continue;
            if (stobeNegItemMatchesTerm($name, $part) || stobeNegItemMatchesTerm($name, rtrim($part, 's'))) {
                $held[] = ['name'=>$display[$name] ?? ucwords($name), 'named'=>$named];
                break;
            }
        }
    }
    if (!$namedAny) {
        // About another item she names ("No more bread."), unless it's the exception ("nothing left but bread").
        foreach (array_keys($counts) as $name) {
            $oh = strval(array_slice(preg_split('/\\s+/', strval($name)) ?: [''], -1)[0]);
            if (strlen($oh) < 3 || !preg_match('/\\b' . preg_quote($oh, '/') . '/', $s)) continue;
            if (!preg_match('/\\b(?:but|except|besides|other\\s+than|apart\\s+from)\\s+(?:[a-z\\'-]+\\s+){0,3}' . preg_quote($oh, '/') . '/', $s)) return '';
        }
    }
    foreach ($held as $h) {
        if ($h['named'] || !$namedAny) {
            $GLOBALS['STOBE_FALSE_EMPTY_CLAIM_ITEMS'][] = $h['name'];
            return $h['name'];
        }
    }
    return '';
}

/** Drops item-41 sentences from a whole reply: ['text'=>..., 'dropped'=>[sentence, ...]]. */''')

H = 'lib/chat_helper_functions.php'
patch(H,
'''        if (!$squadMember || count($wanted) < 1 || !stobeReplyAgreesToHandover($reply)) return [];''',
'''        // Item 69: "nothing left" while she carries it (sentence dropped) = she meant to hand it over.
        $falseEmpty = !empty($GLOBALS['STOBE_FALSE_EMPTY_CLAIM_ITEMS']);
        foreach (preg_split('/(?<=[.!?])\\s+/', trim($reply)) ?: [] as $replySentence) {
            if (!$falseEmpty && function_exists('stobeFalseEmptyClaim') && stobeFalseEmptyClaim($replySentence, $npcData, $playerLine) !== '') $falseEmpty = true;
        }
        if (!$squadMember || count($wanted) < 1 || (!$falseEmpty && !stobeReplyAgreesToHandover($reply))) return [];''')
patch(H,
'''        $refused = false;
        foreach ($sentences as $sentence) {
            if ($head !== '' && str_contains($sentence, $head)''',
'''        $refused = false;
        foreach ($sentences as $sentence) {
            if (function_exists('stobeFalseEmptyClaim') && stobeFalseEmptyClaim($sentence, $npcData, $playerLine) !== '') continue; // item 69
            if ($head !== '' && str_contains($sentence, $head)''')

patch(H,
r'''        $p = trim(preg_replace("/\b(please|now|too|as well|then)\b/", '', $raw) ?? $raw);''',
r'''        $p = trim(preg_replace("/\b(please|now|too|as well|then|again|for me)\b/", '', $raw) ?? $raw); // item 69: "again"''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
'''// ---------------------------------------------------------------- 12h4. item 48: knocked out or dead NPCs don't negotiate''',
'''// ---------------------------------------------------------------- 12h3c. item 69: "nothing left" while she carries it
$npc69 = ['inventory'=>'Dried Meat x5 value 40, Bread x1 value 10', 'equipment'=>''];
$line69 = 'Malzin, give me all your dried meat again.';
$reply69 = "I already handed you all five strips, remember? There's nothing left in my pack but dry bread.";
$fix69 = stobeDropFalseGearClaims($reply69, $npc69, $line69);
check('item 69: the run m1 denial sentences are dropped', count($fix69['dropped']) === 2, $fix69);
check('item 69: "no dried meat left" while she has 5 is false', stobeFalseEmptyClaim('No more dried meat, sorry.', $npc69, $line69) === 'Dried Meat');
check('item 69: a denial about something not asked for is fine', stobeFalseEmptyClaim('No more bread.', $npc69, $line69) === '');
check('item 69: true when she really has none', stobeFalseEmptyClaim("There's nothing left.", ['inventory'=>'Bread x1 value 10'], $line69) === '');
check('item 69: no check without a hand-over request', stobeFalseEmptyClaim("There's nothing left.", $npc69, 'How are you?') === '');
unset($GLOBALS['STOBE_FALSE_EMPTY_CLAIM_ITEMS']);
check('item 69: for a squad member the false denial still hands the items over (item 67 path)',
    stobeInferMissingHandovers($line69, $npc69, [], $reply69, 'Shay', true) === ['GIVE_ITEM@Shay@Dried Meat@5'],
    stobeInferMissingHandovers($line69, $npc69, [], $reply69, 'Shay', true));
check('item 69: a non-faction NPC: nothing added', stobeInferMissingHandovers($line69, $npc69, [], $reply69, 'Shay', false) === []);
unset($GLOBALS['STOBE_FALSE_EMPTY_CLAIM_ITEMS']);

// ---------------------------------------------------------------- 12h4. item 48: knocked out or dead NPCs don't negotiate''')
