<?php
// Round 19 unit checks (bugs 76, 77). Run from a StobeServer tree: php pending-fixes/r19_unit.php
require __DIR__ . '/../lib/bootstrap.php';
$ok=0;$bad=0; function t($n,$c,$d=null){global $ok,$bad; if($c){$ok++;echo "PASS $n\n";}else{$bad++;echo "FAIL $n ".json_encode($d)."\n";}}
$fac = ['faction'=>'Nameless'];
$mem = function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($fac);
echo "faction member check: ".($mem?'yes':'no')."\n";
// 76
foreach ([
 ["Make 3 steel bars.", 'WORK_GOAL@Steel Bar@3'],
 ["Just try it. Make 3 steel bars and tell me if you get stuck.", 'WORK_GOAL@Steel Bar@3'],
 ["Make 2 building materials.", 'WORK_GOAL@Building Material@2'],
 ["Make 2 bread.", 'WORK_GOAL@Bread@2'],
 ["Malzin, make five rice bags", 'WORK_GOAL@Rice Bag@5'],
 ["Can you make 3 steel bars?", ''],
 ["Don't make 3 steel bars.", ''],
 ["I'll make 2 bread later", ''],
] as [$m,$exp]) { $r = stobeInferWorkGoalFromOrder($m, $fac, []); t("76 $m", $r === ($mem ? $exp : ''), $r); }
t("76 skip when goal present", stobeInferWorkGoalFromOrder("Make 2 bread.", $fac, ['WORK_GOAL@Bread@2']) === '');
// 77
$db = $GLOBALS['db'];
$db->exec("DELETE FROM stobe_task_goal_runtime WHERE actor_name='R19Npc'");
$db->exec("INSERT INTO stobe_task_goal_runtime (goal_id,actor_name,kind,item_name,created_at) VALUES "
    . "('r19-a','R19Npc','FETCH','Vodka',NOW() - INTERVAL '120 seconds'),"
    . "('r19-b','R19Npc','FETCH','mead',NOW() - INTERVAL '119 seconds'),"
    . "('r19-c','R19Npc','FETCH','Rum',NOW() - INTERVAL '30 minutes')");
$GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] = 'Actually, put them back in the chest.';
$r = stobeTaskStorePronounItems('R19Npc', 'Mead'); t("77 them -> both", $r === ['Vodka','mead'], $r);
$r = stobeTaskStorePronounItems('R19Npc', ''); t("77 empty item", $r === ['Vodka','mead'], $r);
$r = stobeTaskStorePronounItems('R19Npc', 'Hackers'); t("77 unrelated item", $r === [], $r);
$GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] = 'Put the mead back in the chest.';
$r = stobeTaskStorePronounItems('R19Npc', 'Mead'); t("77 no pronoun", $r === [], $r);
$db->exec("DELETE FROM stobe_task_goal_runtime WHERE actor_name='R19Npc'");
echo "ok=$ok bad=$bad\n";
// 73 (run after patch_r19_bug73): roster state markers
if (function_exists('stobeRosterSplitState')) {
    $GLOBALS['STOBE_ROSTER_STATES'] = [];
    t("73 split dead", stobeRosterSplitState('Sorth [Dust Bandit] (dead)') === ['Sorth [Dust Bandit]', 'dead']);
    t("73 split ko", stobeRosterSplitState(' Wendy (unconscious) ') === ['Wendy', 'unconscious']);
    t("73 split plain", stobeRosterSplitState('Malzin') === ['Malzin', '']);
    t("73 state lookup", stobeRosterState('sorth [dust bandit]') === 'dead' && stobeRosterState('Malzin') === '');
    echo "ok=$ok bad=$bad\n";
}
// 87 (run after patch_r19_bug87_follow)
if (function_exists('stobeInferFollowFromOrder')) {
    $fac = ['faction'=>'Nameless'];
    foreach ([
        ["Malzin, follow me.", 'BODYGUARD@Shay'],
        ["Malzin, guard me.", 'BODYGUARD@Shay'],
        ["Stay close to me, it's dangerous.", 'BODYGUARD@Shay'],
        ["Don't follow me.", ''],
        ["Stop following me.", ''],
        ["Nice weather.", ''],
    ] as [$m,$exp]) { $r = stobeInferFollowFromOrder($m, $fac, [], 'Shay'); t("87 $m", $r === $exp, $r); }
    t("87 skip when action present", stobeInferFollowFromOrder("Follow me.", $fac, ['BODYGUARD@Shay'], 'Shay') === '');
    t("87 non-faction", stobeInferFollowFromOrder("Follow me.", ['faction'=>'Dust Bandits'], [], 'Shay') === '');
    echo "ok=$ok bad=$bad\n";
}
// 88 (run after patch_r19_bug88_surrender_stop)
$r = normalizeActionTagToken('STOP_ATTACK@Shay', ['enabled'=>true,'disallow_stop_attack'=>true,'deal_sanctioned_give'=>true]);
t("88 deal STOP_ATTACK kept", stripos($r, 'STOP_ATTACK') === 0, $r);
$r = normalizeActionTagToken('STOP_ATTACK@Shay', ['enabled'=>true,'disallow_stop_attack'=>true]);
t("88 no deal: still dropped", $r === '', $r);
echo "ok=$ok bad=$bad\n";
// 91 (run after patch_r19_bug91_offer_caps)
if (function_exists('stobeNegOfferCap')) {
    [$c,$m,$tier] = stobeNegOfferCap('Grevik [Dust Bandit]', ['metadata'=>['money'=>9000]]);
    t("91 common bandit 9000 -> 300", $c === 300 && $tier === 'common', [$c,$tier]);
    [$c] = stobeNegOfferCap('Grevik [Dust Bandit]', ['metadata'=>['money'=>400]]);
    t("91 common bandit 400 -> 140 (35%)", $c === 140, $c);
    [$c,,$tier] = stobeNegOfferCap('Dust King', ['metadata'=>['money'=>9000]]);
    t("91 leader -> 1000", $c === 1000 && $tier === 'leader', [$c,$tier]);
    [$c,,$tier] = stobeNegOfferCap('Dezerka', ['faction'=>'Free Traders','metadata'=>['money'=>10000]]);
    t("91 trader -> 3500", $c === 3500 && $tier === 'wealthy', [$c,$tier]);
    [$c] = stobeNegOfferCap('Pax [Hungry Bandit]', ['metadata'=>['money'=>0]]);
    t("91 broke -> 0", $c === 0, $c);
    echo "ok=$ok bad=$bad\n";
}
// 90 (run after patch_r19_bug90_ceasefire)
if (function_exists('stobeDealRecentCompletedCeasefire')) {
    $db = $GLOBALS['db'];
    $db->exec("DELETE FROM stobe_social_contract WHERE npc_name='R19B90Npc'");
    t("90 none -> null", stobeDealRecentCompletedCeasefire('R19B90Npc') === null);
    $db->exec("INSERT INTO stobe_social_contract (contract_id,npc_name,player_name,status,terms,kind,updated_at) VALUES ('r19b90-a','R19B90Npc','Shay','COMPLETE','[]','combat',NOW())");
    $r = stobeDealRecentCompletedCeasefire('r19b90npc');
    t("90 recent complete found", is_array($r) && $r['contract_id'] === 'r19b90-a', $r);
    $db->exec("UPDATE stobe_social_contract SET updated_at=NOW() - INTERVAL '20 minutes' WHERE contract_id='r19b90-a'");
    t("90 old complete ignored", stobeDealRecentCompletedCeasefire('R19B90Npc') === null);
    $db->exec("DELETE FROM stobe_social_contract WHERE npc_name='R19B90Npc'");
    echo "ok=$ok bad=$bad\n";
}
