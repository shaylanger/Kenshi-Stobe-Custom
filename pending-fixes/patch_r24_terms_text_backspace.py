#!/usr/bin/env python3
"""Plan item 52: a backspace character where "\\b" was meant in the terms-text parser.

Found in run 12 while checking a patch: lib/negotiation_phase1.php (since the
2026-09-30 checkpoint f4b4d7e) has two guards `!preg_match('/\\d+\\s*cats?<BS>/i', ...)`
with a literal 0x08 byte, so they never match. A summary like "npc gives 50 cats now"
then became GIVE_ITEM "50 cats now" instead of being left to the Cats rules.
Now the byte is the word boundary it was meant to be.

Usage: patch_r24_terms_text_backspace.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
f = root / 'lib/negotiation_phase1.php'
b = f.read_bytes()
bad = b"cats?\x08/i"
n = b.count(bad)
if n == 0:
    print('already patched', f)
else:
    assert n == 2, f'expected 2, found {n}'
    f.write_bytes(b.replace(bad, b"cats?\\b/i"))
    print('patched', f)

t = root / 'tests/negotiation_engine_regression.php'
s = t.read_text(encoding='utf-8')
if 'item 52:' not in s:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    assert s.count(anchor) == 1
    s = s.replace(anchor, r'''// ---------------------------------------------------------------- 12o. item 52: "gives 50 cats now" is not an item
foreach (['npc gives 50 cats up front', 'npc returns 50 cats'] as $x52) {
    $t52 = stobeDealParseTermsText($x52);
    $items52 = array_filter(is_array($t52) ? $t52 : [], static fn($t) => in_array($t['kind'] ?? '', ['GIVE_ITEM','RETURN_ITEM'], true));
    check('item 52: "' . $x52 . '" is not an item term', count($items52) === 0, $t52);
}

''' + anchor)
    t.write_text(s, encoding='utf-8'); print('patched tests')
