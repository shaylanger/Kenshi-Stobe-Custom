#!/usr/bin/env python3
"""Round 8b: bug 2. The low-trust "don't hand over worn gear" rule ignored agreed deals, so a
paid-for hat (Malzin 09-29, Slant J4) was stripped from the reply and the deal term went
IMPOSSIBLE (action_blocked_by_policy). Apply the same deal exemptions as the unpaid-gift rule.

Usage: patch_round8b.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/chat_helper_functions.php"
t = p.read_text(encoding="utf-8")
old = """    if ($command !== 'GIVE_ITEM' || boolval($config['in_player_faction'] ?? false)) {
        return false;
    }
    $argument = trim(substr($value, $at + 1));
    $giveTarget = stobeGiveItemTargetFromActionArgument($argument);"""
new = """    if ($command !== 'GIVE_ITEM' || boolval($config['in_player_faction'] ?? false)) {
        return false;
    }
    // Part of an agreed deal: a paid-for item is not a gift, even if it's worn.
    if (boolval($config['deal_sanctioned_give'] ?? false)) {
        return false;
    }
    $dealNpc = strval($config['npc_name'] ?? '');
    if ($dealNpc !== '' && function_exists('stobeNegNpcHasDealContext') && stobeNegNpcHasDealContext($dealNpc)) {
        return false;
    }
    $argument = trim(substr($value, $at + 1));
    $giveTarget = stobeGiveItemTargetFromActionArgument($argument);"""
assert t.count(old) == 1, "anchor"
p.write_text(t.replace(old, new), encoding="utf-8")
print("patch_round8b: applied")
