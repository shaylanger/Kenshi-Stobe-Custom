#!/usr/bin/env python3
"""Item 69 (part 2): "I already handed over what I had." (no item named) while she still carries the
requested item was spoken. The none/already-gave pattern now covers "already handed over / gave you
what I had / the lot / it / them". Usage: item69b_generic_already_gave.py <tree root>"""
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

patch('lib/negotiation_phase1.php',
r'''ran\s+out|already\s+(?:handed|gave|given|passed)\s+(?:you\s+|it\s+|them\s+)?(?:all|every|everything|the\s+last))/", $s)) return '';''',
r'''ran\s+out|already\s+(?:handed|gave|given|passed)\s+(?:(?:you|it|them|over|it\s+all|them\s+all)\s+)*(?:all|every|everything|the\s+last|the\s+lot|what\s+i\s+(?:had|have|got)|it|them|(?:it|them)\s+all)\b)/", $s)) return '';''')

patch('tests/negotiation_engine_regression.php',
r'''check('item 69: a denial about something not asked for is fine', ''',
r'''check('item 69: "Again? I already handed over what I had." (run m2) is dropped while she has the meat',
    stobeDropFalseGearClaims('Again? I already handed over what I had.', ['inventory'=>'Dried Meat x4 value 40', 'equipment'=>''], $line69)['text'] === 'Again?');
check('item 69: "I already gave you it all." is false while she has it', stobeFalseEmptyClaim('I already gave you it all.', $npc69, $line69) === 'Dried Meat');
check('item 69: a denial about something not asked for is fine', ''')
