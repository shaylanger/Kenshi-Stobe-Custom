<?php
// Item 106 (STOBE 18, m16 next): Shay's "Stop fighting and I'll pay you 200 cats right now" got the model's terms
// [GIVE_CATS player->npc 200, STOP_ATTACK npc, SPARE by npc target player]. SPARE can only be the player's ("I spare
// you"), so deterministic validation rejected the WHOLE deal (`wrong_performer`) and nothing was recorded.
// Fix: before validation, a term on the wrong side is repaired when its meaning is clear and dropped otherwise:
//   SPARE/PROTECT by the NPC ("she spares/protects the player") = her ceasefire -> STOP_ATTACK by npc (once);
//   STOP_ATTACK/SAFE_PASSAGE by the player toward the NPC = the player's restraint -> SPARE by player (once);
//   any other wrong-side term is dropped. Each repair is logged; the rest of the deal stands.
// Usage: php item106_fix_wrong_performer.php <tree root>
$root = rtrim($argv[1] ?? '', '/');
function p106(string $path, array $edits): void {
    $s = file_get_contents($path);
    if ($s === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($s, 'Item 106')) { fwrite(STDERR, "$path already has item 106\n"); exit(1); }
    foreach ($edits as [$a, $b]) {
        if (substr_count($s, $a) !== 1) { fwrite(STDERR, "anchor missing/not unique in $path: " . substr($a, 0, 90) . "\n"); exit(1); }
        $s = str_replace($a, $b, $s);
    }
    file_put_contents($path, $s); echo "patched $path\n";
}
p106("$root/lib/negotiation_phase1.php", [
["    \$terms = stobeDealFixTargetField(\$terms); // item 46\n",
 "    \$terms = stobeDealFixTargetField(\$terms); // item 46\n    \$terms = stobeDealFixWrongPerformer(\$terms, \$npc); // Item 106\n"],
["function stobeDealFixTargetField(array \$terms): array {", <<<'B'
/** Item 106: a term on the side that can't perform it is repaired when its meaning is clear, else dropped. */
function stobeDealFixWrongPerformer(array $terms, string $npc = ''): array {
    if (!function_exists('stobeNegTermPerformer')) return $terms;
    $has = static function (array $ts, string $kind, string $by): bool {
        foreach ($ts as $t) if (is_array($t) && ($t['kind'] ?? '') === $kind && ($t['by'] ?? '') === $by) return true;
        return false;
    };
    $out = [];
    foreach ($terms as $t) {
        if (!is_array($t)) { $out[] = $t; continue; }
        $kind = strval($t['kind'] ?? ''); $by = strval($t['by'] ?? '');
        $performer = stobeNegTermPerformer($kind);
        if ($performer === '' || $performer === $by || !in_array($by, ['npc', 'player'], true)) { $out[] = $t; continue; }
        $fixed = null;
        if ($by === 'npc' && in_array($kind, ['SPARE', 'PROTECT'], true)) {
            $fixed = ['kind' => 'STOP_ATTACK', 'by' => 'npc', 'target' => 'player'];   // her "sparing" him = her ceasefire
        } elseif ($by === 'player' && in_array($kind, ['STOP_ATTACK', 'SAFE_PASSAGE'], true)) {
            $fixed = ['kind' => 'SPARE', 'by' => 'player', 'target' => 'npc'];         // his ceasefire = sparing her
        }
        $merged = array_merge($terms, $out);
        if ($fixed !== null && !$has($merged, $fixed['kind'], $fixed['by'])) $out[] = $fixed;
        if (function_exists('stobeDealLog')) stobeDealLog('info', 'Negotiation term on the wrong side repaired (item 106)',
            ['npc' => $npc, 'term' => $kind . ' by ' . $by, 'now' => $fixed !== null ? $fixed['kind'] . ' by ' . $fixed['by'] : 'dropped']);
    }
    // a repaired term may now duplicate one the deal already had
    $seen = []; $final = [];
    foreach ($out as $t) {
        $key = is_array($t) && in_array($t['kind'] ?? '', ['STOP_ATTACK', 'SPARE'], true) ? ($t['kind'] . '|' . ($t['by'] ?? '')) : null;
        if ($key !== null) { if (isset($seen[$key])) continue; $seen[$key] = true; }
        $final[] = $t;
    }
    return $final;
}

function stobeDealFixTargetField(array $terms): array {
B],
]);
p106("$root/tests/negotiation_engine_regression.php", [
["// ---------------------------------------------------------------- cleanup", <<<'B'
// ---------------------------------------------------------------- Item 106: a term on the wrong side doesn't sink the deal
$fixed = stobeDealFixWrongPerformer([
    ['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200],
    ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'],
    ['kind'=>'SPARE','by'=>'npc','target'=>'player'],
], 'NegTestBandit');
check('item 106: SPARE by npc folds into her STOP_ATTACK (m16 18)', count($fixed) === 2
    && stobeDealValidate(['parties'=>['npc'=>'NegTestBandit','player'=>$player], 'terms'=>$fixed])['ok'] === true, $fixed);
$fixed2 = stobeDealFixWrongPerformer([['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>50], ['kind'=>'STOP_ATTACK','by'=>'player','target'=>'npc']], 'NegTestBandit');
check('item 106: STOP_ATTACK by player becomes SPARE by player', ($fixed2[1]['kind'] ?? '') === 'SPARE' && ($fixed2[1]['by'] ?? '') === 'player', $fixed2);
$fixed3 = stobeDealFixWrongPerformer([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>50], ['kind'=>'LOAN_ITEM','by'=>'player','to'=>'npc','item'=>'Katana']], 'NegTestBandit');
check('item 106: an unclear wrong-side term is dropped, the rest stands', count($fixed3) === 1 && ($fixed3[0]['kind'] ?? '') === 'GIVE_CATS', $fixed3);

// ---------------------------------------------------------------- cleanup
B],
]);
