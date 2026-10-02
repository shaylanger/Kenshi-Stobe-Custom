#!/usr/bin/env python3
"""Plan item 44, part 2: the player's words decide who pays, too.

Run 12, after part 1: "Quarl, let's settle it: you give me 50 cats and I let you go."
Quarl: "Fine. You take the fifty, I walk." terms [player GIVE_CATS 50 -> npc, SPARE]
with action Talk -> "one_sided_terms", nothing recorded. The model keeps writing the
Cats term the wrong way round.
Now, when the player's line says the NPC pays them N ("you give/pay/hand me N",
"pay me N", "give me N cats") and the only Cats term is "player pays N", it is turned
round. Log: `Negotiation term fixed: the player said she pays (item 44)`.

Usage: patch_r24_cats_direction_words.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, anchor, new, marker, before=True):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(anchor)
    assert n == 1, f'{rel}: anchor found {n}x: {anchor[:60]!r}'
    s = s.replace(anchor, new + anchor if before else anchor + new)
    f.write_text(s, encoding='utf-8')
    print('patched', rel)

FUNC = r'''/** Item 44: the player said the NPC pays them N Cats, but the only Cats term says the player pays N. */
function stobeDealFixCatsDirectionFromWords(array $terms, string $playerMessage): array {
    $m = strtolower($playerMessage);
    if (!preg_match('/\b(?:you\s+(?:give|pay|hand)\s+me|pay\s+me|give\s+me|hand\s+(?:me\s+)?over)\s+(\d{1,7})\b/', $m, $mm)) return $terms;
    $amount = intval($mm[1]);
    if ($amount < 1) return $terms;
    $cats = [];
    foreach ($terms as $i => $t) {
        if (is_array($t) && strtoupper(strval($t['kind'] ?? '')) === 'GIVE_CATS') $cats[] = $i;
    }
    if (count($cats) !== 1) return $terms;
    $i = $cats[0];
    if (($terms[$i]['by'] ?? '') !== 'player' || intval($terms[$i]['amount'] ?? 0) !== $amount) return $terms;
    $terms[$i]['by'] = 'npc';
    $terms[$i]['to'] = 'player';
    stobeDealLog('warn', 'Negotiation term fixed: the player said she pays (item 44)', ['amount'=>$amount]);
    return $terms;
}

'''
patch('lib/negotiation_phase1.php',
      "// ---- Item 45: a 0-Cats term voids the deal",
      FUNC, 'function stobeDealFixCatsDirectionFromWords(')

patch('lib/negotiation_phase1.php',
      "    $terms = stobeDealFixCatsDirection($terms, $response, $player); // item 44\n",
      "    $terms = stobeDealFixCatsDirectionFromWords($terms, $playerMessage); // item 44\n",
      'stobeDealFixCatsDirectionFromWords($terms, $playerMessage); // item 44', before=False)

TEST = r'''$t44d = stobeDealFixCatsDirectionFromWords(
    [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>50], ['kind'=>'SPARE','by'=>'player','target'=>'npc']],
    "Quarl, let's settle it: you give me 50 cats and I let you go.");
check('item 44: "you give me 50 cats" turns the term round', ($t44d[0]['by'] ?? '') === 'npc' && ($t44d[0]['to'] ?? '') === 'player', $t44d);
$t44e = stobeDealFixCatsDirectionFromWords(
    [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>50]], "I'll give you 50 cats for your hat.");
check('item 44: "I\'ll give you 50" is left alone', ($t44e[0]['by'] ?? '') === 'player');

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, 'you give me 50 cats" turns')
