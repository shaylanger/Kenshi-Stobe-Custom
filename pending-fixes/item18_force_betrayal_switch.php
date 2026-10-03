<?php
// STOBE 18 (section 2 -> automatable): a test-only switch that makes the NPC betray a paid deal.
// general_settings NEG_TEST_FORCE_BETRAYAL (bool, default false). When true, any deal where the player pays and the
// NPC could betray (hostile kind, or NPC terms after the player's) is planned as a betrayal regardless of the
// personality/affinity gates and the dice; the plan's reason says `test_switch` and a warning is logged, so a run
// with the switch left on can't be mistaken for normal behaviour. The betrayal itself (re-attack directive,
// BREACHED_NPC, `intentional_betrayal` evidence, reputation/relationship effects) runs through the normal path.
// Usage: php item18_force_betrayal_switch.php <tree root>
$root = rtrim($argv[1] ?? '', '/');
function p18(string $path, array $edits): void {
    $s = file_get_contents($path);
    if ($s === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($s, 'STOBE 18')) { fwrite(STDERR, "$path already has the switch\n"); exit(1); }
    foreach ($edits as [$a, $b]) {
        if (substr_count($s, $a) !== 1) { fwrite(STDERR, "anchor missing in $path: " . substr($a, 0, 80) . "\n"); exit(1); }
        $s = str_replace($a, $b, $s);
    }
    file_put_contents($path, $s); echo "patched $path\n";
}
p18("$root/lib/negotiation_engine.php", [[<<<'A'
    $playerPays = count(array_filter($state, static fn($t) => ($t['by'] ?? '') === 'player')) > 0;
    if (!$playerPays) return [];
    $npc = strval($deal['npc_name']);
A, <<<'B'
    $playerPays = count(array_filter($state, static fn($t) => ($t['by'] ?? '') === 'player')) > 0;
    if (!$playerPays) return [];
    $npc = strval($deal['npc_name']);
    // STOBE 18 test switch (general_settings NEG_TEST_FORCE_BETRAYAL, off by default): betray every eligible paid deal.
    $forceSwitch = false;
    try { $forceSwitch = getSettingBool('NEG_TEST_FORCE_BETRAYAL', false); } catch (Throwable $e) { $forceSwitch = false; }
    if ($forceSwitch && ($hasAfterTerms || stobeNegDealKindIsHostile($deal))) {
        stobeLogWarn('Negotiation: betrayal forced by test switch NEG_TEST_FORCE_BETRAYAL (turn it off after the test)', ['contract_id'=>strval($deal['contract_id'] ?? ''), 'npc'=>$npc]);
        return ['considered'=>true, 'planned'=>true, 'chance'=>1.0, 'roll'=>0.0, 'reason'=>'test_switch NEG_TEST_FORCE_BETRAYAL'];
    }
B]]);
p18("$root/tests/negotiation_engine_regression.php", [[<<<'A'
putenv('STOBE_NEG_TEST_FORCE_BETRAYAL');
$db->exec("DELETE FROM stobe_negotiation_directive");
A, <<<'B'
putenv('STOBE_NEG_TEST_FORCE_BETRAYAL');
$db->exec("DELETE FROM stobe_negotiation_directive");
// STOBE 18: the general_settings test switch forces a betrayal even for an honest, neutral NPC; off = no betrayal.
$db->exec("DELETE FROM general_settings WHERE id='NEG_TEST_FORCE_BETRAYAL'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('NEG_TEST_FORCE_BETRAYAL', 'true')");
$id = makeDeal('NegTestTrader', [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>40], ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']]);
stobeNegBeginPerformance($id, ['STOP_ATTACK@' . $player], $player, 1000, '');
$b = stobeNegDecode(stobeNegFetchDeal($id)['betrayal']);
check('STOBE 18: test switch forces the betrayal (honest NPC)', !empty($b['planned']) && str_contains(strval($b['reason'] ?? ''), 'test_switch'), $b);
$db->exec("UPDATE stobe_social_contract SET performance_started_unix = performance_started_unix - 25 WHERE contract_id=$1", [$id]);
stobeLine("ACTION_EXEC: GIVE_CATS actor=$player recipient=NegTestTrader amount=40", time());
stobeNegTick();
check('STOBE 18: forced betrayal -> BREACHED_NPC', status($id) === 'BREACHED_NPC', status($id));
$db->exec("UPDATE general_settings SET value='false' WHERE id='NEG_TEST_FORCE_BETRAYAL'");
$id = makeDeal('NegTestTrader', [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>41], ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']]);
stobeNegBeginPerformance($id, ['STOP_ATTACK@' . $player], $player, 1000, '');
$b = stobeNegDecode(stobeNegFetchDeal($id)['betrayal']);
check('STOBE 18: switch off -> honest NPC does not betray', empty($b['planned']), $b);
$db->exec("DELETE FROM general_settings WHERE id='NEG_TEST_FORCE_BETRAYAL'");
$db->exec("DELETE FROM stobe_negotiation_directive");
B]]);
