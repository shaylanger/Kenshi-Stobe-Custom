<?php
// Items 102-104 (Shay, 2026-10-03, "build it"): relationship-shaped trading on the server.
//   102 weapon-stow guard at r >= 70 (DROP_WEAPON and stow-to-pack too), 103 willingness lines, 104 deal prices
//   + the pricing endpoint for Stobe.dll's shop-window hook.
// Installs lib/relationship_trading.php and relationship_pricing.php (new files, from pending-fixes), patches
// lib/negotiation_phase1.php and processor/chat.php (anchored), adds tests/relationship_trading_regression.php.
// Usage: php item102_104_relationship_trading.php <tree root>
$root = rtrim($argv[1] ?? '', '/');
$here = __DIR__;
foreach ([['relationship_trading.php', 'lib/relationship_trading.php'], ['relationship_pricing_endpoint.php', 'relationship_pricing.php'],
          ['relationship_trading_regression.php', 'tests/relationship_trading_regression.php']] as [$from, $to]) {
    if (file_exists("$root/$to")) { fwrite(STDERR, "$to exists already\n"); exit(1); }
    copy("$here/$from", "$root/$to") or exit(1);
    echo "added $to\n";
}
function p102(string $path, array $edits): void {
    $s = file_get_contents($path);
    if ($s === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($s, 'Item 102')) { fwrite(STDERR, "$path already has item 102\n"); exit(1); }
    foreach ($edits as [$a, $b]) {
        if (substr_count($s, $a) !== 1) { fwrite(STDERR, "anchor missing/not unique in $path: " . substr($a, 0, 90) . "\n"); exit(1); }
        $s = str_replace($a, $b, $s);
    }
    file_put_contents($path, $s); echo "patched $path\n";
}
p102("$root/lib/negotiation_phase1.php", [
["<?php\n\n/**\n * Deal ledger.", "<?php\n\nrequire_once __DIR__ . '/relationship_trading.php'; // Item 102-104: relationship-shaped trading\n\n/**\n * Deal ledger."],
[<<<'A'
/** The NPC's affinity toward the player, or 0 if they have no relationship. */
function stobeDealNpcTrust(array|false $npcData, string $player): int {
    if (!is_array($npcData) || !function_exists('stobeGetNpcRelationshipMap')) return 0;
A, <<<'B'
/** The NPC's affinity toward the player, or 0 if they have no relationship. */
function stobeDealNpcTrust(array|false $npcData, string $player): int {
    if (function_exists('stobeRelValue')) return stobeRelValue($npcData, $player); // Item 102: character, else persona
    if (!is_array($npcData) || !function_exists('stobeGetNpcRelationshipMap')) return 0;
B],
["    \$minTrust = function_exists('getSettingInt') ? getSettingInt('NEG_WEAPON_TRUST_MIN', 56) : 56;",
 "    \$minTrust = function_exists('getSettingInt') ? getSettingInt('NEG_WEAPON_TRUST_MIN', 70) : 70; // Item 102: Shay's +70"],
[<<<'A'
        if (preg_match('/^UNEQUIP_ITEM@(.+)$/i', $a, $m)) $item = $m[1];
        elseif (preg_match('/^GIVE_ITEM@[^@]*@([^@]+)/i', $a, $m)) $item = $m[1];
A, <<<'B'
        if (preg_match('/^UNEQUIP_ITEM@(.+)$/i', $a, $m)) $item = $m[1];
        elseif (preg_match('/^GIVE_ITEM@[^@]*@([^@]+)/i', $a, $m)) $item = $m[1];
        // Item 102: dropping it, or stowing it into the pack/inventory, leaves her defenceless just the same.
        elseif (preg_match('/^DROP_WEAPON\b/i', $a)) { $removed[] = $a; continue; }
        elseif (preg_match('/^(?:SHEATHE_?WEAPON|HOLSTER_?WEAPON)@.*\b(pack|backpack|bag|inventory|stow)\b/i', $a)) { $removed[] = $a; continue; }
        elseif (preg_match('/^DROP_ITEM@(.+)$/i', $a, $m)) $item = $m[1];
B],
[<<<'A'
    $deal = [
        'parties'=>['npc'=>$npc,'player'=>$player],
A, <<<'B'
    // Items 103/104: relationship willingness lines and prices (squad exempt; hostile deals keep their own rules).
    if (function_exists('stobeRelTradeGate') && in_array($decision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
        $gate = stobeRelTradeGate($npc, $npcData, $player, $kind, $terms);
        if (empty($gate['ok'])) return $gate;
        $terms = $gate['terms'];
        if (!empty($gate['priced']) && $decision === 'ACCEPT') {
            $decision = 'COUNTER'; // she asks her price instead of accepting a cheaper one
            stobeDealLog('info', 'Negotiation: accept at the wrong price recorded as a counter at her price (item 104)', ['npc'=>$npc, 'r'=>$gate['r'] ?? 0]);
        }
    }
    $deal = [
        'parties'=>['npc'=>$npc,'player'=>$player],
B],
]);
p102("$root/processor/chat.php", [
["                if (strval(\$dealResult['error'] ?? '') === 'weapon_not_negotiable') {\n                    // Bug 32: whatever she said, her weapon isn't part of the deal.",
 "                if (in_array(strval(\$dealResult['error'] ?? ''), ['weapon_not_negotiable', 'relationship_no_trade', 'relationship_no_pay_later',\n                    'relationship_no_free_gift', 'relationship_no_free_favour'], true)) { // Item 102/103\n                    // Bug 32: whatever she said, her weapon isn't part of the deal. Items 103: a refused deal line in character."],
["    if (count(\$weaponActionsRemoved) > 0) {\n        stobeLogWarn('Weapon hand-over blocked (not surrendering, not trusted)', [",
 "    if (count(\$weaponActionsRemoved) > 0) {\n        // Item 102: refuse in character (her words may have agreed); nothing streamed yet = replace the line.\n        if (empty(\$alreadyStreamed)) \$responseText = 'No. My weapon stays with me.';\n        stobeLogWarn('Weapon hand-over blocked (not surrendering, not trusted)', ["],
]);
