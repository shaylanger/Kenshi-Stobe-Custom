#!/usr/bin/env python3
"""Plan item 45: a 0-Cats term voids a whole deal.

Run 12: beaten raider Quarl accepted "You give me 50 cats, and I let you go" with terms
[player GIVE_CATS 0, npc GIVE_CATS 50, SPARE] -> "Negotiation rejected by deterministic
validation: invalid_cats", nothing recorded although both sides agreed.
Now Cats terms with amount 0 are dropped before validation when other terms remain.
Log: `Negotiation term dropped: 0 Cats (item 45)`.

Usage: patch_r24_zero_cats_term.py <StobeServer tree>  (idempotent)
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

FUNC = r'''// ---- Item 45: a 0-Cats term voids the deal ---------------------------------------------

/** Drops GIVE_CATS terms of 0 Cats when other terms remain. */
function stobeDealDropZeroCatsTerms(array $terms): array {
    $kept = array_values(array_filter($terms, static fn($t) => !(is_array($t)
        && strtoupper(strval($t['kind'] ?? '')) === 'GIVE_CATS'
        && is_numeric($t['amount'] ?? null) && intval($t['amount']) === 0)));
    if (count($kept) === count($terms) || count($kept) === 0) return $terms;
    stobeDealLog('info', 'Negotiation term dropped: 0 Cats (item 45)', ['dropped'=>count($terms) - count($kept)]);
    return $kept;
}

'''
patch('lib/negotiation_phase1.php',
      "// ---- Bug 30: agreed in words, nothing recorded -------------------------------------------",
      FUNC, 'stobeDealDropZeroCatsTerms(array')

patch('lib/negotiation_phase1.php',
      "    $terms = stobeDealFixTakeOffTerms($terms, $npcData, $playerMessage);\n",
      "    $terms = stobeDealDropZeroCatsTerms($terms); // item 45\n",
      'stobeDealDropZeroCatsTerms($terms); // item 45', before=False)

TEST = r'''// ---------------------------------------------------------------- 12i. item 45: a 0-Cats term doesn't void the deal
$t45 = stobeDealDropZeroCatsTerms([
    ['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>0],
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>50],
    ['kind'=>'SPARE','by'=>'player','target'=>'npc'],
]);
check('item 45: 0-Cats term dropped, the rest kept', count($t45) === 2 && ($t45[0]['by'] ?? '') === 'npc', $t45);
check('item 45: the deal then validates', stobeDealValidate(['parties'=>['npc'=>'a','player'=>'b'],'terms'=>$t45])['ok'] === true);
check('item 45: a lone 0-Cats term is left for validation to refuse',
    count(stobeDealDropZeroCatsTerms([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>0]])) === 1);

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, 'item 45: 0-Cats')
