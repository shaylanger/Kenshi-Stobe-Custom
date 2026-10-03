#!/usr/bin/env python3
"""Item 69 (part 3): still spoken while she carried the meat: "You already took the last of it -
three strips, and I had none to spare after." / "You've had the last of it twice over now." The
denial pattern adds "(took|had|got|ate|have) the last of it/them", "none to spare", "nothing to spare".
Usage: item69c_last_of_it.py <tree root>"""
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
r'''    if (!preg_match("/\b(?:nothing\s+(?:left|more)|none\s+left|''',
r'''    if (!preg_match("/\b(?:(?:took|taken|had|got|ate|eaten|have|'ve\s+had)\s+(?:the\s+)?last\s+of\s+(?:it|them|my\s+[a-z ]+)|(?:none|nothing|no\s+more)\s+to\s+spare|nothing\s+(?:left|more)|none\s+left|''')

patch('tests/negotiation_engine_regression.php',
r'''check('item 69: a denial about something not asked for is fine', ''',
r'''check('item 69: "You already took the last of it - three strips, and I had none to spare after." (run m3) is false while she has it',
    stobeFalseEmptyClaim('You already took the last of it - three strips, and I had none to spare after.', $npc69, $line69) === 'Dried Meat');
check('item 69: "You\'ve had the last of it twice over now." (run m3) is false while she has it',
    stobeFalseEmptyClaim("You've had the last of it twice over now.", $npc69, $line69) === 'Dried Meat');
check('item 69: a denial about something not asked for is fine', ''')
