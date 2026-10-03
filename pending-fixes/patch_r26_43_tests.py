#!/usr/bin/env python3
"""Item 43 regression checks in tests/negotiation_engine_regression.php (after the item 41 block).

Usage: patch_r26_43_tests.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'tests/negotiation_engine_regression.php'
s = f.read_text(encoding='utf-8')
if 'item 43:' in s:
    print('already patched', f)
    sys.exit(0)
anchor = "// ---------------------------------------------------------------- 12i. item 45"
assert s.count(anchor) == 1, 'anchor'
block = r'''// ---------------------------------------------------------------- 12h3. item 43: a two-part hand-over
$npc43 = ['inventory'=>'Bread x2 value 10, Dried Meat x10 value 40, Ration Pack x1 value 60', 'equipment'=>''];
check('item 43: "all your bread and all your dried meat", bread given -> dried meat added',
    stobeInferMissingHandovers('Give me all your bread and all your dried meat.', $npc43, ['GIVE_ITEM@Shay@Bread@2'], 'You took my food.', 'Shay')
    === ['GIVE_ITEM@Shay@Dried Meat@10']);
check('item 43: "both breads", meat given -> 2 bread added',
    stobeInferMissingHandovers('Malzin, put your katana back on, and give me all your dried meat and both breads.', $npc43,
        ['GIVE_ITEM@Shay@Dried Meat@10'], 'All of it, then.', 'Shay') === ['GIVE_ITEM@Shay@Bread@2']);
check('item 43: three items, one given -> two added',
    stobeInferMissingHandovers('Hand over your bread, 5 dried meat and the ration pack.', $npc43, ['GIVE_ITEM@Shay@Bread@1'], 'Fine.', 'Shay')
    === ['GIVE_ITEM@Shay@Dried Meat@5', 'GIVE_ITEM@Shay@Ration Pack@1']);
check('item 43: she keeps one ("the meat stays") -> nothing added',
    stobeInferMissingHandovers('Give me all your bread and all your dried meat.', $npc43, ['GIVE_ITEM@Shay@Bread@2'], 'Bread, fine. The meat stays with me.', 'Shay') === []);
check('item 43: no hand-over at all (a refusal) -> nothing added',
    stobeInferMissingHandovers('Give me all your bread and all your dried meat.', $npc43, [], 'No.', 'Shay') === []);
check('item 43: both already given -> nothing added',
    stobeInferMissingHandovers('Give me all your bread and all your dried meat.', $npc43, ['GIVE_ITEM@Shay@Bread@2', 'GIVE_ITEM@Shay@Dried Meat@10'], 'Here.', 'Shay') === []);
check('item 43: something she does not carry -> nothing added',
    stobeInferMissingHandovers('Give me your bread and your katana.', $npc43, ['GIVE_ITEM@Shay@Bread@1'], 'Here.', 'Shay') === []);
check('item 43: a one-item order -> nothing added',
    stobeInferMissingHandovers('Give me your bread.', $npc43, ['GIVE_ITEM@Shay@Bread@1'], 'Here.', 'Shay') === []);

'''
s = s.replace(anchor, block + anchor)
f.write_text(s, encoding='utf-8')
print('patched', f)
