#!/usr/bin/env python3
"""imm26-wpW: weapon guard +70 (Shay's negotiation rule, memory stobe-negotiation-rules; imm26 row 12-d).
STOBE_REL_WEAPON_MIN (70, lib/relationship_trading.php) was a dead constant: an outsider handing over an EQUIPPED weapon was
gated only by give_equipment_trust_threshold (60). Now an equipped weapon uses max(threshold, STOBE_REL_WEAPON_MIN).
Non-weapon equipped gear (60) and unpaid gifts (56) are unchanged; squad, deal-sanctioned gives and explicit barter stay exempt.
Usage (WSL): python3 apply.py <tree-root>     (idempotent; asserts anchors; installs the regression test)"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, 'lib', 'chat_helper_functions.php')
s = open(p, encoding='utf-8').read()
if 'stobeProtectedGiveRequiredAffinity' in s:
    print('already applied'); sys.exit(0)
A1 = "function stobeProtectedGiveWouldBeBlocked(string $rawTag, array $config): bool {\n"
A2 = "    $threshold = max(0, min(100, intval($config['give_equipment_trust_threshold'] ?? 60)));\n    $barter = boolval($config['explicit_barter_offer'] ?? false);\n"
A3 = "            'required_affinity' => intval($config['give_equipment_trust_threshold'] ?? 60),\n"
for a in (A1, A2, A3):
    assert s.count(a) == 1, 'anchor missing/duplicated: ' + a[:60]
helper = r'''/**
 * Weapon guard (Shay, 2026-10-03 / ticket imm26-wpW): an outsider hands over an equipped WEAPON only at
 * r >= STOBE_REL_WEAPON_MIN (70); other equipped gear keeps give_equipment_trust_threshold (60).
 */
function stobeProtectedGiveRequiredAffinity(string $argument, array $config): int {
    $threshold = max(0, min(100, intval($config['give_equipment_trust_threshold'] ?? 60)));
    $item = stobeGiveItemNameFromActionArgument($argument);
    if ($item !== '' && function_exists('stobeDealIsWeaponName') && stobeDealIsWeaponName($item)) {
        $threshold = max($threshold, defined('STOBE_REL_WEAPON_MIN') ? intval(STOBE_REL_WEAPON_MIN) : 70);
    }
    return $threshold;
}

'''
s = s.replace(A1, helper + A1)
s = s.replace(A2, "    $threshold = stobeProtectedGiveRequiredAffinity($argument, $config);\n    $barter = boolval($config['explicit_barter_offer'] ?? false);\n")
s = s.replace(A3, "            'required_affinity' => stobeProtectedGiveRequiredAffinity($argument, $config),\n")
open(p, 'w', encoding='utf-8').write(s)
shutil.copy(os.path.join(here, 'imm26_wpW_weapon_guard_regression.php'), os.path.join(root, 'tests', 'imm26_wpW_weapon_guard_regression.php'))
print('applied')
