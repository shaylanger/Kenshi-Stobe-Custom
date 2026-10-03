#!/usr/bin/env python3
"""Item 41 regression checks in tests/negotiation_engine_regression.php (after the bug 39 block).

Usage: patch_r26_41_tests.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'tests/negotiation_engine_regression.php'
s = f.read_text(encoding='utf-8')
if 'item 41:' in s:
    print('already patched', f)
    sys.exit(0)
anchor = "// ---------------------------------------------------------------- 12i. item 45"
assert s.count(anchor) == 1, 'anchor'
block = r'''// ---------------------------------------------------------------- 12h2. item 41: a false claim about her gear
$npc41 = ['equipment'=>'Black Cloth Shirt [Shoddy] x1 value 202, Iron Hat [Shoddy] x1 value 526, Chisa Katana [Ancient] x1 value 2789, Wooden Sandals [Shoddy] x1 value 45'];
check('item 41: "you\'ve got my blade" while she wears the katana is false',
    stobeFalseGearClaim("You've got my larder and my blade both, and I'm still standing here empty-handed.", $npc41, 'Now give me all your dried meat.') === 'Chisa Katana');
check('item 41: "you took my hat" while she wears it is false',
    stobeFalseGearClaim('You took my hat.', $npc41) === 'Iron Hat');
check('item 41: "my katana is yours" while she wears it is false',
    stobeFalseGearClaim('My katana is yours now.', $npc41) === 'Chisa Katana');
check('item 41: the player asked for the katana this turn: not checked',
    stobeFalseGearClaim("There. You've got my katana.", $npc41, 'Give me your katana.') === '');
check('item 41: an item she no longer wears is fine',
    stobeFalseGearClaim("You've got my boots.", $npc41) === '');
check('item 41: idioms are fine',
    stobeFalseGearClaim("You have my word. You've got my back.", $npc41) === '');
$fix41 = stobeDropFalseGearClaims("You've got my larder and my blade both, and I'm still standing here empty-handed. So what's the test for?", $npc41, '');
check('item 41: the false sentence is dropped, the rest kept',
    $fix41['text'] === "So what's the test for?" && count($fix41['dropped']) === 1, $fix41);
check('item 41: a reply that is only the false claim becomes "Hm."',
    stobeDropFalseGearClaims('You took my hat.', $npc41)['text'] === 'Hm.');
check('item 41: a clean reply is unchanged',
    stobeDropFalseGearClaims('Fine. The hat stays on.', $npc41)['dropped'] === []);

'''
s = s.replace(anchor, block + anchor)
f.write_text(s, encoding='utf-8')
print('patched', f)
