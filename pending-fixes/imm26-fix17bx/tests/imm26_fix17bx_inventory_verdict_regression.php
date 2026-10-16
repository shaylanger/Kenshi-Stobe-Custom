<?php
// imm26 fix17bx regression (offline, no DB): row 17-bx. The claims block must give the NPC an explicit inventory verdict for an item
// the conversation names: "your inventory DOES contain X" (item really in the pack) / "DOES NOT contain X" (really missing),
// read from the NPC's verified inventory, fail-closed when the inventory is unknown. FAILS on the old code (no verdict line),
// passes on the patched tree.   Run: php tests/imm26_fix17bx_inventory_verdict_regression.php
declare(strict_types=1);
$root = __DIR__ . '/..';
$n = 0;
function ok(bool $c, string $what, $detail = null): void { global $n; if (!$c) { echo 'FAIL: ' . $what . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; exit(1); } ++$n; }

// minimal stubs: the NPC's own recent replies come from eventlog through $GLOBALS['db']
if (!function_exists('stobePromptXmlEscape')) { function stobePromptXmlEscape(string $s): string { return htmlspecialchars($s, ENT_NOQUOTES | ENT_SUBSTITUTE, 'UTF-8'); } }
final class Fix17bxFakeDb { public array $rows = []; public function fetchAll($sql, $params = []) { return $this->rows; } }
$GLOBALS['db'] = new Fix17bxFakeDb();
require_once $root . '/lib/imm26_claims.php';

ok(function_exists('imm26ClaimsInventoryLines'), 'imm26ClaimsInventoryLines exists (claims block has an inventory verdict)');
function verdict(array $npc, string $msg, array $replies = []): string { return implode("\n", imm26ClaimsInventoryLines($npc, $msg, $replies)); }
function ctx(array $npc, string $msg, array $chatRows = []): string {
    $GLOBALS['db']->rows = array_map(static fn($t) => ['data' => $t], $chatRows);
    return imm26ClaimsContext('Cind', $npc, 'Shay', 0, ['player_message' => $msg]);
}

$has = ['name' => 'Cind', 'metadata' => json_encode(['inventory_items' => [
    ['name' => 'Sabreclaw', 'count' => 1, 'equipped' => false], ['name' => 'Bandages [Standard]', 'count' => 3], ['name' => 'Falling Sun Katana', 'count' => 1, 'equipped' => true]]])];
$lacks = ['name' => 'Cind', 'metadata' => json_encode(['inventory_items' => [['name' => 'Bandages', 'count' => 3], ['name' => 'Dried Fish', 'count' => 2]]])];

// the three row denials, item really in the pack
foreach (['No, I never took your Sabreclaw.', 'You are mistaken, I never touched it.', "Check your pack, I haven't had it."] as $i => $msg) {
    $replies = $i >= 1 ? ['You took my Sabreclaw.'] : [];
    $v = verdict($has, $msg, $replies);
    ok(str_contains($v, 'your inventory DOES contain Sabreclaw.') && !str_contains($v, 'DOES NOT'), "has: denial #$i gets DOES contain Sabreclaw", $v);
    ok(str_contains($v, 'misplaced it yourself') && str_contains($v, 'Do not say you saw'), "has: admit-mistake rule and no-fabrication rule #$i", $v);
}
// same three denials, item really missing
foreach (['No, I never took your Sabreclaw.', 'You are mistaken, I never touched it.', "Check your pack, I haven't had it."] as $i => $msg) {
    $replies = $i >= 1 ? ['You took my Sabreclaw.'] : [];
    $v = verdict($lacks, $msg, $replies);
    ok(str_contains($v, 'your inventory DOES NOT contain Sabreclaw.') && !str_contains($v, 'DOES contain'), "lacks: denial #$i gets DOES NOT contain Sabreclaw", $v);
    ok(str_contains($v, 'do not retract') && str_contains($v, 'Do not say you saw'), "lacks: hold-position rule and no-fabrication rule #$i", $v);
}
// a plain question, lower case item matched against the pack; quality tag and worn gear handled
ok(str_contains(verdict($has, 'Do you have any bandages on you?'), 'DOES contain Bandages.'), 'question: bandages (quality tag stripped)');
ok(str_contains(verdict($has, 'Did you take my katana?'), 'DOES contain Falling Sun Katana.'), 'worn katana counts (head word match)');
ok(str_contains(verdict($lacks, 'Do you have the Falling Sun Katana?'), 'DOES NOT contain Falling Sun Katana.'), 'asked item the pack lacks');
// text-list fallback when there is no structured list
$text = ['name' => 'Cind', 'inventory' => 'Sabreclaw x1 value 900, Bandages x3 value 20', 'equipment' => 'Wooden Sandals [Shoddy] x1 value 45'];
ok(str_contains(verdict($text, 'You took my Sabreclaw!'), 'DOES contain Sabreclaw.'), 'text inventory fallback');
ok(str_contains(verdict($text, 'Where are my sandals, did you take them?'), 'DOES contain Wooden Sandals.'), 'text equipment fallback');

// fail-closed and no noise
ok(verdict(['name' => 'Cind'], 'You took my Sabreclaw.') === '', 'unknown inventory -> no verdict');
ok(verdict($has, 'Nice weather today, is it not?') === '', 'no item/ownership topic -> no verdict');
ok(verdict($has, 'What a lovely Sabreclaw design.') === '', 'item mentioned without ownership/challenge topic -> no verdict');
ok(verdict($lacks, 'You took my money.') === '', 'money is not an inventory item -> no DOES NOT line');
ok(verdict($lacks, 'Did you take it to the Holy Nation?') === '', 'faction word is not an item');
ok(verdict($has, "Check your pack, I haven't had it.") === '', 'bare challenge with no item anywhere -> no verdict');

// full block: the claims block carries the verdict for the seeded accusation (NPC accused, item in her own pack)
$block = ctx($has, "Check your pack, I haven't had it.", ['Cind: You took my Sabreclaw.']);
ok(str_contains($block, '<claims_and_corrections>') && str_contains($block, 'your inventory DOES contain Sabreclaw.'), 'block: DOES contain Sabreclaw from the NPC\'s own accusation', $block);
ok(str_contains($block, 'correcting or challenging you'), 'block: the challenge rule is still there');
$block2 = ctx($lacks, 'No, I never took your Sabreclaw.', ['Cind: You took my Sabreclaw.']);
ok(str_contains($block2, 'your inventory DOES NOT contain Sabreclaw.') && str_contains($block2, 'do not retract'), 'block: DOES NOT contain when missing', $block2);
ok(!str_contains(ctx($has, 'Hello there.', []), 'Inventory check'), 'block: no verdict for a greeting');
ok(ctx(['name' => 'Cind'], 'Hello there.', []) === '', 'block: nothing at all for a greeting');

echo "imm26_fix17bx_inventory_verdict_regression: $n checks passed\n";
