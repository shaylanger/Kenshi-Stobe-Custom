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
