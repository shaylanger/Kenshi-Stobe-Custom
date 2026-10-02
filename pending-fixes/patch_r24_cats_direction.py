#!/usr/bin/env python3
"""Plan item 44: a Cats term recorded the wrong way round.

Run 12: Shay to beaten raider Quarl: "Fifty cats and we're square, you go free."
Quarl: "Fifty... not much of a toll... Fine. Fifty cats and we're square." with
action GiveCats -> Shay, amount 50 (blocked as an unpaid gift), but deal_terms
[player GIVE_CATS 50 -> npc, STOP_ATTACK]: the ledger said Shay owed him 50.
Now, when her own action pays the player N Cats and the only Cats term is
"player pays N", that term is turned round (npc pays player).
Log: `Negotiation term fixed: her GiveCats action says she pays (item 44)`.

Usage: patch_r24_cats_direction.py <StobeServer tree>  (idempotent)
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

FUNC = r'''// ---- Item 44: a Cats term the wrong way round -------------------------------------------

/**
 * Her own action pays the player N Cats, but the only Cats term says the player pays her
 * N: the term is turned round.
 */
function stobeDealFixCatsDirection(array $terms, array $response, string $player): array {
    $action = strtolower(preg_replace('/[^a-z]/i', '', strval($response['action'] ?? '')) ?? '');
    if ($action !== 'givecats') return $terms;
    $target = strtolower(trim(strval($response['target'] ?? '')));
    if ($target === '' || ($target !== strtolower($player) && $target !== 'player')) return $terms;
    $amount = intval($response['amount'] ?? 0);
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
    stobeDealLog('warn', 'Negotiation term fixed: her GiveCats action says she pays (item 44)', ['amount'=>$amount]);
    return $terms;
}

'''
patch('lib/negotiation_phase1.php',
      "// ---- Bug 30: agreed in words, nothing recorded -------------------------------------------",
      FUNC, 'function stobeDealFixCatsDirection(')

patch('lib/negotiation_phase1.php',
      "    $terms = stobeDealFixTakeOffTerms($terms, $npcData, $playerMessage);\n",
      "    $terms = stobeDealFixCatsDirection($terms, $response, $player); // item 44\n",
      'stobeDealFixCatsDirection($terms, $response, $player); // item 44', before=False)

TEST = r'''// ---------------------------------------------------------------- 12j. item 44: her GiveCats action decides who pays
$t44 = stobeDealFixCatsDirection(
    [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>50], ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']],
    ['action'=>'GiveCats','target'=>$player,'amount'=>50], $player);
check('item 44: her GiveCats to the player turns the term round', ($t44[0]['by'] ?? '') === 'npc' && ($t44[0]['to'] ?? '') === 'player', $t44);
$t44b = stobeDealFixCatsDirection(
    [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>50]], ['action'=>'Talk','target'=>$player], $player);
check('item 44: no GiveCats action, terms unchanged', ($t44b[0]['by'] ?? '') === 'player');
$t44c = stobeDealFixCatsDirection(
    [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>300]], ['action'=>'GiveCats','target'=>$player,'amount'=>50], $player);
check('item 44: a different amount is left alone', ($t44c[0]['by'] ?? '') === 'player');

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, 'item 44: her GiveCats')
