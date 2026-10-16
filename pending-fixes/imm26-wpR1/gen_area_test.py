#!/usr/bin/env python3
"""Generates imm26_wpR1_area_goal_resume_regression.php (harness copied from the wpL landmark test + area-goal scenarios).
Run from C:\\KenshiModding\\pending-fixes: python3 imm26-wpR1/gen_area_test.py   (the output file is what apply.py installs; delete this generator after commit)."""
import os
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, '..', 'imm26-wpL', 'imm26_wpL_landmark_resume_regression.php'), encoding='utf-8').read().replace('\r\n', '\n')
head = src[:src.index("// 1. first start of a landmark trip")]
head = head.replace("// imm26-wpL: a trip to a LOCAL LANDMARK",
    "// imm26-wpR1 (area-goal leg of the audit gap 1; harness copied from imm26_wpL_landmark_resume_regression.php): the ACCEPTED trip created by the\n"
    "// broad-region area goal (row 24-b: kind same_route, leader npc, destination_point native_local, plus the regional_goal block written by\n"
    "// stobeTravelCapture) must resume after save+load exactly like a landmark trip (wpL, commit 0647e9d). Original wpL header follows.\n"
    "// imm26-wpL: a trip to a LOCAL LANDMARK", 1)
head = head.replace("imm26_wpL_landmark_resume_regression.php   (flock", "imm26_wpR1_area_goal_resume_regression.php   (flock")
body = r'''
/** The state the area-goal reducer leaves behind: a normal ACCEPTED same_route trip led by the NPC to a native_local endpoint, plus regional_goal. */
function ag_seed(string $actor, int $serial, array $o = []): array {
    $state = wl_seed($actor, $serial, $o + ['kind'=>'same_route']);
    $state['regional_goal'] = ['region'=>'The Hub outskirts', 'endpoint_id'=>$state['destination_point']['id'], 'endpoint_label'=>WL_LM['label'],
        'endpoint_source'=>'native_local', 'endpoint_actor_serial'=>$serial, 'endpoint_region_evidence'=>'native_region_proof',
        'trip_read_succeeded'=>true, 'trip_read_scope_hash'=>str_repeat('c', 64), 'trip_read_scope'=>['actor_id'=>$serial],
        'trip_read_actor_serial'=>$serial, 'trip_read_speaker_serial'=>TR_PLAYER_SERIAL, 'trip_read_gamets'=>$state['accepted_gamets'],
        'prior_trip_status'=>'none', 'checked_gamets'=>$state['accepted_gamets'], 'ordinary_order_validation'=>'passed', 'order_validation_gamets'=>$state['accepted_gamets']];
    if (!stobeTravelWrite($actor, TR_PLAYER, intval($o['g'] ?? 1000), $state)) throw new RuntimeException('seed write failed');
    return $state;
}

// 1. area-goal trip, save+load: pauses as interrupted_by_load, keeps its regional_goal, then resumes from the stored x/y/z (candidate_id empty)
[$A, $As] = tr_actor();
$seed = ag_seed($A, $As);
$r = tr_turn($A, $As, 1100, ['live'=>false]);
$s = $r['state'];
check('area goal load: ACCEPTED -> interrupted_by_load (not FAILED), same agreement/plan_hash, regional_goal kept', tr_phase($s) === 'interrupted_by_load' && ($s['status'] ?? '') === 'ACCEPTED'
    && ($s['agreement_id'] ?? '') === $seed['agreement_id'] && ($s['plan_hash'] ?? '') === $seed['plan_hash']
    && ($s['regional_goal']['region'] ?? '') === 'The Hub outskirts' && ($s['regional_goal']['endpoint_id'] ?? '') === $seed['destination_point']['id'], [$s['status'] ?? null, tr_phase($s)]);
check('area goal load: the area-goal state validator still accepts the paused state', stobeAreaGoalTripStateValid($s, $A, TR_PLAYER));
$r = tr_turn($A, $As, 1200, ['live'=>true]);
$w = $r['wires'][0] ?? []; $s = $r['state'];
check('area goal resume: one start wire, same agreement/plan_hash, stored x/y/z, route kind, EMPTY candidate_id (native ids die on load)', count($r['wires']) === 1
    && ($w['operation'] ?? '') === 'start' && ($w['agreement_id'] ?? '') === $seed['agreement_id'] && ($w['plan_hash'] ?? '') === $seed['plan_hash']
    && wl_xyz($w) && ($w['kind'] ?? '') === 'route' && ($w['candidate_id'] ?? 'x') === '', $r['wires']);
check('area goal resume: state requested, resume_count 1, regional_goal intact, no second agreement', tr_phase($s) === 'requested' && intval($s['execution']['resume_count'] ?? 0) === 1
    && ($s['regional_goal']['endpoint_label'] ?? '') === WL_LM['label'] && count(array_filter(tr_rows($A, $As),
        static fn($x) => ($x['agreement_id'] ?? '') !== $seed['agreement_id'] || ($x['status'] ?? '') === 'PROPOSED')) === 0);
$ev = tr_receipt($s, $A, $As, 'world-new-bbbbbbbb', 2, 'running', 'ag-ev-running');
$done = tr_receipt($s, $A, $As, 'world-new-bbbbbbbb', 2, 'completed', 'ag-ev-done', ['end_condition_verified'=>true, 'owned_work_released'=>true]);
tr_turn($A, $As, 1220, ['live'=>true, 'receipts'=>[$ev]]);
$r4 = tr_turn($A, $As, 1300, ['live'=>true, 'receipts'=>[$ev, $done]]);
check('area goal cycle: running then COMPLETED with owned_work_released', ($r4['state']['status'] ?? '') === 'COMPLETED' && ($r4['state']['execution']['owned_work_released'] ?? false) === true, $r4['state']['status'] ?? null);

// 2. out of range keeps it paused (no wire), resumes later
[$B, $Bs] = tr_actor(); ag_seed($B, $Bs);
tr_turn($B, $Bs, 1100, ['live'=>false]);
$r = tr_turn($B, $Bs, 1150, ['live'=>false]);
check('area goal transient: NPC beyond 80u stays interrupted_by_load, no wire', tr_phase($r['state']) === 'interrupted_by_load' && $r['wires'] === []);
$r = tr_turn($B, $Bs, 1160, ['live'=>true]);
check('area goal transient: resumes on the next eligible turn', count($r['wires']) === 1 && tr_phase($r['state']) === 'requested');

// 3. kill switches: landmark switch off -> honest FAILED for the area-goal trip; global switch off -> never resumes
set_setting('STOBE_TRIP_RESUME_LOCAL_ENABLED', '0');
[$D, $Ds] = tr_actor(); ag_seed($D, $Ds);
$r = tr_turn($D, $Ds, 1100, ['live'=>true]);
tr_expect_failed('area goal with STOBE_TRIP_RESUME_LOCAL_ENABLED=0', $r);
set_setting('STOBE_TRIP_RESUME_LOCAL_ENABLED', '1');
set_setting('STOBE_TRIP_RESUME_ENABLED', '0');
[$E, $Es] = tr_actor(); ag_seed($E, $Es);
tr_turn($E, $Es, 1100, ['live'=>true]);
$r = tr_turn($E, $Es, 1200, ['live'=>true]);
check('area goal with STOBE_TRIP_RESUME_ENABLED=0: no resume wire', $r['wires'] === [], $r['wires']);
reset_settings();
// TODO (successor): optional cap scenario for the area-goal trip, patterned on imm26_trip_resume_regression.php lines ~294-313 (5e resume_count).

echo "imm26_wpR1_area_goal_resume: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
'''
open(os.path.join(here, 'imm26_wpR1_area_goal_resume_regression.php'), 'w', encoding='utf-8', newline='\n').write(head + body)
print('generated')
