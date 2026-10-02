#!/usr/bin/env python3
"""Plan item 49: paying an NPC who was named after the deal was made isn't verified.

Run 12: deal recorded with "Dust Bandit"; he was then named "Weth [Dust Bandit]".
Shay paid by voice: ACTION_EXEC: GIVE_CATS actor=Shay recipient=Weth [Dust Bandit]
amount=1000, but the term stayed AWAITING_PLAYER: stobeNegCharMatches compared
"weth" (brackets stripped) with "dust bandit".
Now a name "X [Y]" also matches Y (the generic name it was given before, as in
bug 128's directive rename).

Usage: patch_r24_paid_renamed_npc.py <StobeServer tree>  (idempotent)
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

patch('lib/negotiation_engine.php',
      "    if ($a1 === $b1) return true;\n    return $norm($a) !== '' && $norm($a) === $norm($b);\n",
      """    // Item 49: named after the deal: "Weth [Dust Bandit]" is the "Dust Bandit" of the deal.
    foreach ([[$a1, $b1], [$b1, $a1]] as [$named, $generic]) {
        if (preg_match('/^.+\\[\\s*(.+?)\\s*\\]$/', $named, $bm) && $bm[1] === $generic) return true;
    }
""", 'Item 49: named after the deal', before=True)

TEST = r'''// ---------------------------------------------------------------- 12l. item 49: paid after being named
check('item 49: "Weth [Dust Bandit]" matches the deal\'s "Dust Bandit"', stobeNegCharMatches('Weth [Dust Bandit]', 'Dust Bandit') === true);
check('item 49: and the other way round', stobeNegCharMatches('Dust Bandit', 'Weth [Dust Bandit]') === true);
check('item 49: a different generic name does not match', stobeNegCharMatches('Weth [Dust Bandit]', 'Dust Bandit Bowman') === false);
check('item 49: two different named NPCs do not match', stobeNegCharMatches('Weth [Dust Bandit]', 'Yarel [Dust Bandit]') === false);

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, 'item 49: "Weth')
