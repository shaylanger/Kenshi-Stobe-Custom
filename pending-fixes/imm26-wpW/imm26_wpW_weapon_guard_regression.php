<?php
// imm26 wpW (row 12-d): an outsider hands over an EQUIPPED weapon only at r >= 70 (STOBE_REL_WEAPON_MIN); other equipped
// gear stays at 60, unpaid gifts at 56. Fails on the old code (weapon at 60-69 was allowed).
// Run: STOBE_DB_NAME=stobe_test php tests/imm26_wpW_weapon_guard_regression.php
require __DIR__ . '/../lib/bootstrap.php';
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
$base = stobeBuildActionConfigForNpc('chat', false);
$base['player_name'] = 'Shay';
$base['allowlist'] = [];
$base['give_equipment_trust_threshold'] = 60;
$base['gift_trust_threshold'] = 56;
$base['protected_equipment_text'] = 'falling sun, dustcoat, hemp trousers';
$cfg = fn(array $o) => array_merge($base, $o);
$n = fn(string $tag, array $c) => normalizeActionTagToken($tag, $c);
$W = 'GIVE_ITEM@Shay@Falling Sun@1';
$A = 'GIVE_ITEM@Shay@Dustcoat@1';
check('W0: constant is 70', defined('STOBE_REL_WEAPON_MIN') && STOBE_REL_WEAPON_MIN === 70);
check('W1: equipped weapon blocked at 60', $n($W, $cfg(['player_affinity'=>60])) === '');
check('W2: equipped weapon blocked at 69', $n($W, $cfg(['player_affinity'=>69])) === '');
check('W3: equipped weapon allowed at 70', $n($W, $cfg(['player_affinity'=>70])) !== '', $n($W, $cfg(['player_affinity'=>70])));
check('W4: equipped armour still allowed at 60', $n($A, $cfg(['player_affinity'=>60])) !== '');
check('W5: equipped armour blocked at 59', $n($A, $cfg(['player_affinity'=>59])) === '');
check('W6: squadmate weapon exempt', $n($W, $cfg(['player_affinity'=>0, 'in_player_faction'=>true])) !== '');
check('W7: deal-sanctioned weapon exempt', $n($W, $cfg(['player_affinity'=>0, 'deal_sanctioned_give'=>true])) !== '');
check('W8: explicit barter weapon exempt', $n($W, $cfg(['player_affinity'=>65, 'explicit_barter_offer'=>true])) !== '');
check('W9: unequipped weapon still follows the gift gate (56)', $n('GIVE_ITEM@Shay@Katana@1', $cfg(['player_affinity'=>60])) !== '');
check('W10: lowered configured threshold cannot weaken the weapon guard', $n($W, $cfg(['player_affinity'=>50, 'give_equipment_trust_threshold'=>40])) === '');
check('W11: required affinity helper', stobeProtectedGiveRequiredAffinity('Shay@Falling Sun@1', $base) === 70
    && stobeProtectedGiveRequiredAffinity('Shay@Dustcoat@1', $base) === 60
    && stobeProtectedGiveRequiredAffinity('Shay@Falling Sun@1', array_merge($base, ['give_equipment_trust_threshold'=>85])) === 85);
echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
