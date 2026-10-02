#!/usr/bin/env python3
"""Plan item 50: deal reputation split in two rows by the player name's casing.

Run 12: stobe_negotiation_reputation had "shay" 42 kept / 10 broken (all history) and
"Shay" 4 kept (everything since StobeServer b6b6aa3 made the player name keep its
in-game casing). The reputation the NPCs hear about was read from "Shay" only.
Now the row key is the lower-cased player name and reads are case-insensitive.
The existing rows are merged by a one-off SQL in the run log (not here).

Usage: patch_r24_reputation_case.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, old, new, marker):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n}x: {old[:70]!r}'
    f.write_text(s.replace(old, new), encoding='utf-8')
    print('patched', rel)

patch('lib/negotiation_engine.php',
      """                 ON CONFLICT (player_name) DO UPDATE SET {$repColumn}=stobe_negotiation_reputation.{$repColumn}+1, updated_at=NOW()",""",
      """                 ON CONFLICT (player_name) DO UPDATE SET {$repColumn}=stobe_negotiation_reputation.{$repColumn}+1, updated_at=NOW()", // item 50: key is lower-case""",
      'item 50: key is lower-case')

# the INSERT's parameter list follows on the next line(s): lower-case the player there
f = root / 'lib/negotiation_engine.php'
s = f.read_text(encoding='utf-8')
i = s.index('// item 50: key is lower-case')
j = s.index('[$player]', i)
if s[j-20:j].find('strtolower') < 0 and 'strtolower($player)] /* item 50 */' not in s:
    assert j - i < 200, 'INSERT parameters not where expected'
    s = s[:j] + '[strtolower($player)] /* item 50 */' + s[j+len('[$player]'):]
    f.write_text(s, encoding='utf-8'); print('patched insert key')

patch('lib/negotiation_engine.php',
      """"SELECT player_kept, player_broken FROM stobe_negotiation_reputation WHERE player_name=$1", [$player]);""",
      """"SELECT player_kept, player_broken FROM stobe_negotiation_reputation WHERE LOWER(player_name)=LOWER($1)", [$player]); // item 50""",
      'WHERE LOWER(player_name)=LOWER($1)", [$player]); // item 50')

patch('tests/negotiation_engine_regression.php',
      """$rep = $db->fetchOne("SELECT player_kept FROM stobe_negotiation_reputation WHERE player_name=$1", [$player]);""",
      """$rep = $db->fetchOne("SELECT player_kept FROM stobe_negotiation_reputation WHERE player_name=$1", [strtolower($player)]); // item 50: lower-case key""",
      'item 50: lower-case key')
t = root / 'tests/negotiation_engine_regression.php'
s = t.read_text(encoding='utf-8')
if 'item 50: reputation' not in s:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    assert s.count(anchor) == 1
    s = s.replace(anchor, r'''// ---------------------------------------------------------------- 12m. item 50: reputation key ignores case
$db->exec("DELETE FROM stobe_negotiation_reputation WHERE LOWER(player_name)='negtestcase50'");
$db->exec("INSERT INTO stobe_negotiation_reputation (player_name, player_kept, player_broken) VALUES ('negtestcase50', 1, 5)");
check('item 50: reputation read for "NegTestCase50" finds the lower-case row', str_contains(stobeNegReputationLine('NegTestCase50'), 'breaking deals'));
$db->exec("DELETE FROM stobe_negotiation_reputation WHERE LOWER(player_name)='negtestcase50'");

''' + anchor)
    t.write_text(s, encoding='utf-8'); print('patched test 12m')
s = t.read_text(encoding='utf-8')
old = """$db->exec("DELETE FROM stobe_negotiation_reputation WHERE player_name=$1", [$player]);"""
if old in s:
    s = s.replace(old, """$db->exec("DELETE FROM stobe_negotiation_reputation WHERE LOWER(player_name)=LOWER($1)", [$player]);""")
    t.write_text(s, encoding='utf-8'); print('patched test cleanup lines')
