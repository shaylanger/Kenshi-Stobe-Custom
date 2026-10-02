#!/usr/bin/env python3
"""Player name lowercase ("shay") in prompt lines and actions.

The PLAYER_NAME setting was entered as "shay"; the game character is "Shay". Prompts
("Word gets around: shay is known to honor deals", deal progress, breach instructions)
and action tokens (GIVE_ITEM@shay) used the setting as typed.

getSetting('PLAYER_NAME') now returns the in-game casing when the setting has no capitals
and a character with that name (any case) is known.

Usage: patch_r23_player_name_case.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
lib = root / 'lib' / 'settings.php'
s = lib.read_text(encoding='utf-8')
if 'in-game casing' not in s:
    old = """function getSetting(string $id, string $default = ''): string {
    $db = $GLOBALS["db"];
    $row = $db->fetchOne(
        "SELECT value FROM general_settings WHERE id = $1",
        [$id]
    );
    return $row ? $row['value'] : $default;
}"""
    new = """function getSetting(string $id, string $default = ''): string {
    $db = $GLOBALS["db"];
    $row = $db->fetchOne(
        "SELECT value FROM general_settings WHERE id = $1",
        [$id]
    );
    $value = $row ? $row['value'] : $default;
    if ($id === 'PLAYER_NAME' && $value !== '' && strtolower($value) === $value) {
        // Typed as "shay" in settings: use the in-game casing ("Shay") in prompts and actions.
        static $playerNameCase = [];
        if (!isset($playerNameCase[$value])) {
            $named = $db->fetchOne("SELECT name FROM core_npc_master WHERE LOWER(name) = LOWER($1) LIMIT 1", [$value]);
            $playerNameCase[$value] = is_array($named) && trim(strval($named['name'] ?? '')) !== '' ? strval($named['name']) : $value;
        }
        $value = $playerNameCase[$value];
    }
    return $value;
}"""
    assert s.count(old) == 1, 'getSetting anchor'
    s = s.replace(old, new)
    lib.write_text(s, encoding='utf-8', newline='')
    print('patched', lib)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'in-game casing' not in t:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    add = """// ---------------------------------------------------------------- 12e. player name typed lowercase in settings: in-game casing
$savedPlayerName = $db->fetchOne("SELECT value FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', $1)", [strtolower($player)]);
check('player name in-game casing from a lowercase setting', getSetting('PLAYER_NAME') === $player, getSetting('PLAYER_NAME'));
$db->exec("UPDATE general_settings SET value=$1 WHERE id='PLAYER_NAME'", [strval($savedPlayerName['value'] ?? $player)]);

"""
    assert t.count(anchor) == 1, 'test anchor'
    t = t.replace(anchor, add + anchor)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
