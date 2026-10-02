#!/usr/bin/env python3
"""Plan item 44, part 3: the deal on the table decides who pays when the player's line doesn't.

Run 12 haggle with a beaten raider who offered to pay (npc GIVE_CATS 300 on the table):
"Alright, 350 and you go free." -> ACCEPT recorded as player GIVE_CATS 350 (Shay owes
him), kind=surrender. Neither part 1 (her GiveCats action) nor part 2 ("you give me N")
caught it.
Now: if the open deal's only Cats term is paid by the NPC, the new terms' only Cats term
says the player pays, and the player's line has no "I('ll) pay/give/hand", "pay you",
"give you" or "from me", that term is turned round.
Log: `Negotiation term fixed: the deal on the table has her paying (item 44)`.

Usage: patch_r24_cats_direction_table.py <StobeServer tree>  (idempotent; after parts 1-2)
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

FUNC = r'''/** Item 44: the open deal has the NPC paying and the player's line doesn't say the player pays. */
function stobeDealFixCatsDirectionFromTable(array $terms, ?array $open, string $playerMessage): array {
    if ($open === null) return $terms;
    $m = strtolower($playerMessage);
    if (preg_match("/\b(?:i'?ll|i will|i can|i)\s+(?:pay|give|hand)\b|\bpay you\b|\bgive you\b|\bfrom me\b/", $m)) return $terms;
    $openTerms = json_decode(strval($open['terms'] ?? '[]'), true);
    $openCats = array_values(array_filter(is_array($openTerms) ? $openTerms : [], static fn($t) => is_array($t) && strtoupper(strval($t['kind'] ?? '')) === 'GIVE_CATS'));
    if (count($openCats) !== 1 || ($openCats[0]['by'] ?? '') !== 'npc') return $terms;
    $cats = [];
    foreach ($terms as $i => $t) {
        if (is_array($t) && strtoupper(strval($t['kind'] ?? '')) === 'GIVE_CATS') $cats[] = $i;
    }
    if (count($cats) !== 1 || ($terms[$cats[0]]['by'] ?? '') !== 'player') return $terms;
    $terms[$cats[0]]['by'] = 'npc';
    $terms[$cats[0]]['to'] = 'player';
    stobeDealLog('warn', 'Negotiation term fixed: the deal on the table has her paying (item 44)', ['amount'=>intval($terms[$cats[0]]['amount'] ?? 0)]);
    return $terms;
}

'''
patch('lib/negotiation_phase1.php',
      "// ---- Item 45: a 0-Cats term voids the deal",
      FUNC, 'function stobeDealFixCatsDirectionFromTable(')
patch('lib/negotiation_phase1.php',
      "    $terms = stobeDealFixCatsDirectionFromWords($terms, $playerMessage); // item 44\n",
      "    $terms = stobeDealFixCatsDirectionFromTable($terms, $open, $playerMessage); // item 44\n",
      'stobeDealFixCatsDirectionFromTable($terms, $open, $playerMessage); // item 44', before=False)

TEST = r'''$open44 = ['terms'=>json_encode([['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>300], ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']])];
$t44f = stobeDealFixCatsDirectionFromTable([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>350], ['kind'=>'SPARE','by'=>'player','target'=>'npc']], $open44, 'Alright, 350 and you go free.');
check('item 44: "350 and you go free" with her paying on the table: she pays', ($t44f[0]['by'] ?? '') === 'npc', $t44f);
$t44g = stobeDealFixCatsDirectionFromTable([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>350]], $open44, "Fine, I'll pay you 350 instead.");
check('item 44: "I\'ll pay you 350" stays the player paying', ($t44g[0]['by'] ?? '') === 'player');
check('item 44: no deal on the table, unchanged', (stobeDealFixCatsDirectionFromTable([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>350]], null, '350.')[0]['by'] ?? '') === 'player');

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, 'with her paying on the table')
