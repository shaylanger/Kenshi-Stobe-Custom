#!/usr/bin/env python3
# C49 (m22 batch D): the deal was made with "Dalx 2 [Dust Bandit]" (already auto-named), then the wrapper renamed him
# "Weth [Dust Bandit]". Player GIVE_CATS to "Weth [Dust Bandit]" never verified: stobeNegRecipientMatches only accepted
# a rename when the deal's NPC name was the bare template ("Dust Bandit"), not an earlier "<name> [template]".
# Fix: compare templates (bracket part, or the whole name) on both sides, and accept the recipient when his live
# serial (people list) or his stored serial is the deal's serial.
# usage: m22-c49b.py <tree root> test|fix
import pathlib, sys
root = pathlib.Path(sys.argv[1]); mode = sys.argv[2]
def patch(rel, old, new):
    p = root / rel; s = p.read_text(); assert s.count(old) == 1, (rel, s.count(old)); p.write_text(s.replace(old, new, 1))
if mode == 'test':
    patch('tests/negotiation_engine_regression.php',
"check('item 49: attacks/actor matching stays exact', stobeNegCharMatches('Yarel [Dust Bandit]', 'Dust Bandit') === false);\n",
"check('item 49: attacks/actor matching stays exact', stobeNegCharMatches('Yarel [Dust Bandit]', 'Dust Bandit') === false);\n"
"check('C49b: deal made with an earlier auto-name, paid after a second rename', stobeNegRecipientMatches('Weth49 [Dust Bandit]', 'Dalx49 2 [Dust Bandit]', 4949) === true);\n"
"check('C49b: earlier auto-name, another serial does not', stobeNegRecipientMatches('Weth49 [Dust Bandit]', 'Dalx49 2 [Dust Bandit]', 4950) === false);\n"
"check('C49b: other template with the same serial does not', stobeNegRecipientMatches('Weth49 [Dust Bandit]', 'Dalx49 2 [Hungry Bandit]', 4949) === false);\n"
"$GLOBALS['CACHE_PEOPLE'] = json_encode(['Shay|hand_1', 'Weth49b [Dust Bandit]|hand_4951']);\n"
"check('C49b: no stored row yet, live people-list serial counts', stobeNegRecipientMatches('Weth49b [Dust Bandit]', 'Dalx49 2 [Dust Bandit]', 4951) === true);\n"
"unset($GLOBALS['CACHE_PEOPLE']);\n")
else:
    patch('lib/negotiation_engine.php',
"""    if ($serial <= 0 || !preg_match('/^.+\[\s*(.+?)\s*\]$/', trim($recipient), $bm)) return false;
    if (strcasecmp($bm[1], trim($npc)) !== 0) return false;
    $row = $GLOBALS['db']->fetchOne(
        "SELECT metadata->>'storage_id' AS sid FROM core_npc_master WHERE LOWER(name)=LOWER($1) LIMIT 1", [trim($recipient)]);
    return is_array($row) && strval($row['sid'] ?? '') === 'hand_' . $serial;""",
"""    if ($serial <= 0 || !preg_match('/^.+\[\s*(.+?)\s*\]$/', trim($recipient), $bm)) return false;
    // C49b: the deal may carry an earlier auto-name ("Dalx 2 [Dust Bandit]"): compare templates.
    $npcTemplate = preg_match('/^.+\[\s*(.+?)\s*\]$/', trim($npc), $nm) ? $nm[1] : trim($npc);
    if (strcasecmp($bm[1], $npcTemplate) !== 0) return false;
    if (function_exists('stobeResolveLiveParticipantSerial') && stobeResolveLiveParticipantSerial(trim($recipient)) === $serial) return true;
    $row = $GLOBALS['db']->fetchOne(
        "SELECT metadata->>'storage_id' AS sid FROM core_npc_master WHERE LOWER(name)=LOWER($1) LIMIT 1", [trim($recipient)]);
    return is_array($row) && strval($row['sid'] ?? '') === 'hand_' . $serial;""")
