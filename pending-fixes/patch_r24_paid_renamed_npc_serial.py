#!/usr/bin/env python3
"""Plan item 49, part 2: the rename match must be pinned to the deal's serial.

Part 1 (patch_r24_paid_renamed_npc.py) let "X [Y]" match Y in stobeNegCharMatches.
Run 12 showed that is too broad: Shay's 1000 Cats to "Weth [Dust Bandit]" also
completed an old "Dust Bandit" deal (another NPC, Ulvik), and gang-mate "Yarel [Dust
Bandit]"'s attack was logged against Weth's deal as attack_resumed.
Now stobeNegCharMatches is back to exact/stripped matching; the player-payment checks
(stobeNegCatsExecuted / stobeNegItemExecuted for the player's terms) accept "X [Y]"
for a deal with Y only when X's stored serial is the deal's serial.

Usage: patch_r24_paid_renamed_npc_serial.py <StobeServer tree>  (idempotent; after part 1)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
f = root / 'lib/negotiation_engine.php'
s = f.read_text(encoding='utf-8')
if 'function stobeNegRecipientMatches(' in s:
    print('already patched', f)
else:
    def sub(old, new):
        global s
        n = s.count(old)
        assert n == 1, f'anchor found {n}x: {old[:70]!r}'
        s = s.replace(old, new)
    # undo part 1
    sub("""    // Item 49: named after the deal: "Weth [Dust Bandit]" is the "Dust Bandit" of the deal.
    foreach ([[$a1, $b1], [$b1, $a1]] as [$named, $generic]) {
        if (preg_match('/^.+\\[\\s*(.+?)\\s*\\]$/', $named, $bm) && $bm[1] === $generic) return true;
    }
""", "")
    sub("/** Cats moved from $from to $to per the game's GIVE_CATS execution records. */\n",
        """/**
 * Item 49: the recipient in a game record is the deal's NPC: same name, or the name he
 * was given after the deal ("Weth [Dust Bandit]" for "Dust Bandit") when that name's
 * stored serial is the deal's serial.
 */
function stobeNegRecipientMatches(string $recipient, string $npc, int $serial = 0): bool {
    if (stobeNegCharMatches($recipient, $npc)) return true;
    if ($serial <= 0 || !preg_match('/^.+\\[\\s*(.+?)\\s*\\]$/', trim($recipient), $bm)) return false;
    if (strcasecmp($bm[1], trim($npc)) !== 0) return false;
    $row = $GLOBALS['db']->fetchOne(
        "SELECT metadata->>'storage_id' AS sid FROM core_npc_master WHERE LOWER(name)=LOWER($1) LIMIT 1", [trim($recipient)]);
    return is_array($row) && strval($row['sid'] ?? '') === 'hand_' . $serial;
}

/** Cats moved from $from to $to per the game's GIVE_CATS execution records. */
""")
    sub("function stobeNegCatsExecuted(string $from, string $to, int $sinceUnix): array {",
        "function stobeNegCatsExecuted(string $from, string $to, int $sinceUnix, int $toSerial = 0): array {")
    sub("""        if (preg_match('/^actor=(.+?) recipient=(.+?) amount=(\\d+)/', $r['body'], $m)
            && stobeNegCharMatches($m[1], $from) && stobeNegCharMatches($m[2], $to)) {""",
        """        if (preg_match('/^actor=(.+?) recipient=(.+?) amount=(\\d+)/', $r['body'], $m)
            && stobeNegCharMatches($m[1], $from) && stobeNegRecipientMatches($m[2], $to, $toSerial)) {""")
    sub("function stobeNegItemExecuted(string $from, string $to, string $item, int $sinceUnix): array {",
        "function stobeNegItemExecuted(string $from, string $to, string $item, int $sinceUnix, int $toSerial = 0): array {")
    sub("""            && stobeNegCharMatches($m[1], $from) && stobeNegCharMatches($m[2], $to)
            && stobeNegItemMatchesTerm($m[4], $item)) {""",
        """            && stobeNegCharMatches($m[1], $from) && stobeNegRecipientMatches($m[2], $to, $toSerial)
            && stobeNegItemMatchesTerm($m[4], $item)) {""")
    sub("        $exec = stobeNegCatsExecuted($player, $npc, $start - 3);",
        "        $exec = stobeNegCatsExecuted($player, $npc, $start - 3, intval($serial)); // item 49")
    sub("        $exec = stobeNegItemExecuted($player, $npc, $item, $start - 3);",
        "        $exec = stobeNegItemExecuted($player, $npc, $item, $start - 3, intval($serial)); // item 49")
    f.write_text(s, encoding='utf-8')
    print('patched', f)

t = root / 'tests/negotiation_engine_regression.php'
s = t.read_text(encoding='utf-8')
if 'stobeNegRecipientMatches(' not in s:
    old_start = "// ---------------------------------------------------------------- 12l. item 49: paid after being named\n"
    old_end = "// ---------------------------------------------------------------- 13. toggles"
    i = s.index(old_start); j = s.index(old_end)
    s = s[:i] + r'''// ---------------------------------------------------------------- 12l. item 49: paid after being named
fixtureNpc('Weth49 [Dust Bandit]', ['money'=>10, 'storage_id'=>'hand_4949'], 'Bread x1 value 10', '', '100/100');
check('item 49: named after the deal, same serial: his payment counts', stobeNegRecipientMatches('Weth49 [Dust Bandit]', 'Dust Bandit', 4949) === true);
check('item 49: another serial (a gang-mate or an old deal) does not', stobeNegRecipientMatches('Weth49 [Dust Bandit]', 'Dust Bandit', 4950) === false);
check('item 49: no serial, no rename match', stobeNegRecipientMatches('Weth49 [Dust Bandit]', 'Dust Bandit', 0) === false);
check('item 49: attacks/actor matching stays exact', stobeNegCharMatches('Yarel [Dust Bandit]', 'Dust Bandit') === false);
$db->exec("DELETE FROM core_npc_master WHERE name='Weth49 [Dust Bandit]'");

''' + s[j:]
    t.write_text(s, encoding='utf-8'); print('patched', t)
