<?php
// imm26 fix22b20d (found by 4080-i3op25):
//  22-b: a completed trip whose arrival remark was already claimed (situated_remark_claim) must not also queue a plan_report
//        directive (the second bored tick spoke a second arrival remark).
//  20-d: after a save+load the old trip is FAILED while a change waits (pending_change / pending_replacement); a bare Yes must apply
//        the waiting change (new destination), not re-offer the old trip.
// Run: STOBE_DB_NAME=stobe_test php tests/imm26_fix22b20d_regression.php   (flock /tmp/stobe-tests.lock)
require __DIR__ . '/../lib/bootstrap.php';
$db = $GLOBALS['db'];
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }

$oldPlayer = $db->fetchOne("SELECT value FROM general_settings WHERE id='PLAYER_NAME'");
register_shutdown_function(static function () use ($db, $oldPlayer): void {
    $db->exec("ROLLBACK");
    $db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
    if (is_array($oldPlayer)) $db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', $1)", [strval($oldPlayer['value'])]);
});
$db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', 'Shay')");
$GLOBALS['CACHE_CITY'] = 'The Hub';
$GLOBALS['STOBE_TRAVEL_SPEAKER'] = 'Shay';
$GLOBALS['STOBE_PLAYER_ACTOR'] = 'Shay';
$GLOBALS['CACHE_PEOPLE'] = '["Shay|hand_11111","UtFixArr|hand_77701","UtFixNoClaim|hand_77702","UtFix20d|hand_77703"]';

$db->exec('BEGIN');
$db->exec("DELETE FROM eventlog WHERE type IN ('travel_agreement','travel_alternatives','situated_remark_claim','situated_event')");
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name LIKE 'UtFix%'");
$db->exec("DELETE FROM core_npc_master WHERE name IN ('UtFix20d')");
$db->exec("INSERT INTO core_npc_master (name, metadata) VALUES ('UtFix20d', '{\"storage_id\":\"hand_77703\"}'::jsonb)");
$db->exec("DELETE FROM location_zones");
$now = time();
foreach ([['The Hub',0],['Stumble Inn',4000],['Squin',-5000],['Vain',9000]] as [$z,$x]) {
    $db->exec("INSERT INTO location_zones (zone_name, city_name, x, y, z, last_seen_ts, metadata) VALUES ($2,'',$3,0,0,$1,'{}'::jsonb)", [$now - 10, $z, $x]);
}

// ================= 22-b: arrival claimed -> no plan_report =================
function done_trip(string $actor, string $id, int $g): void {
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    stobeTravelRead($actor, 'Shay', $g);
    $s = ['status'=>'COMPLETED', 'kind'=>'same_route', 'leader'=>'npc', 'destination'=>'Squin', 'actor'=>$actor, 'speaker'=>'Shay',
        'agreement_id'=>$id, 'created_gamets'=>$g, 'execution'=>['phase'=>'completed', 'owned_work_released'=>true]];
    check("22b setup: $actor completed trip written", stobeTravelWrite($actor, 'Shay', $g, $s));
}
function dirs(string $actor): int {
    $r = $GLOBALS['db']->fetchOne("SELECT COUNT(*) AS n FROM stobe_negotiation_directive WHERE npc_name=$1 AND kind='plan_report'", [$actor]);
    return intval($r['n'] ?? 0);
}
$g = 200000;
done_trip('UtFixArr', 'trip-fixarr1', $g);
storeEvent('situated_remark_claim', time(), $g + 5, json_encode(['actor_serial'=>77701, 'event_id'=>'trip:trip-fixarr1:completed', 'kind'=>'arrival']), 'pending', '', '', false);
$n = stobeImm26PlanReportQueuePending();
check('22b: arrival already claimed -> no plan_report queued for it', dirs('UtFixArr') === 0, ['n'=>$n, 'dirs'=>dirs('UtFixArr')]);
$GLOBALS['STOBE_TRAVEL_STATE'] = [];
$live = stobeTravelRead('UtFixArr', 'Shay', $g + 10);
check('22b: the claimed trip is marked reported', !empty($live['execution']['reported']) && ($live['status'] ?? '') === 'COMPLETED', $live);
check('22b: second pass still queues nothing', stobeImm26PlanReportQueuePending() === 0 && dirs('UtFixArr') === 0);
// control: same shape of trip but the arrival remark was NOT claimed -> farewell report still queued (and a claim for another trip does not count)
done_trip('UtFixNoClaim', 'trip-fixnoclaim1', $g + 20);
storeEvent('situated_remark_claim', time(), $g + 25, json_encode(['actor_serial'=>77702, 'event_id'=>'trip:trip-someother:completed', 'kind'=>'arrival']), 'pending', '', '', false);
stobeImm26PlanReportQueuePending();
check('22b control: unclaimed completed trip still queues its plan_report', dirs('UtFixNoClaim') === 1, dirs('UtFixNoClaim'));
check('22b helper: claim lookup is exact per agreement', function_exists('stobeImm26ArrivalClaimConsumed') && stobeImm26ArrivalClaimConsumed('trip-fixarr1') && !stobeImm26ArrivalClaimConsumed('trip-fixarr') && !stobeImm26ArrivalClaimConsumed('trip-fixnoclaim1'));

// ================= 20-d: dead old trip + waiting change =================
$actor = 'UtFix20d';
$npc = ['name'=>$actor, 'race'=>'Greenlander', 'faction'=>'No Faction', 'metadata'=>['storage_id'=>'hand_77703'],
    'extended_data'=>['relationships'=>['Shay'=>['aff'=>80]]]];
$key = 'travel-v1:77703:11111:';
function turn(array $d, string $line, int $gamets): array {
    global $actor, $npc;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    $raw = json_encode($d + ['travel_kind'=>'same_route','travel_leader'=>'npc','travel_reason'=>'test']);
    $text = 'Sure.'; $actions = ['TRAVEL_LOCATION@' . ($d['travel_destination'] ?? '')];
    stobeTravelCapture($raw, $actor, $npc, 'Shay', $line, $gamets, $text, $actions);
    return [$text, $actions];
}
function kill_trip(array $state, int $g): bool {   // like commitment_native_bridge after a load: same agreement id, FAILED, ownership released
    global $actor;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    stobeTravelRead($actor, 'Shay', $g);
    return stobeTravelWrite($actor, 'Shay', $g, $state);
}
function rows(string $key): array {
    $r = $GLOBALS['db']->fetchAll("SELECT data FROM eventlog WHERE type='travel_agreement' AND LEFT(data, LENGTH($1))=$1 ORDER BY rowid", [$key]);
    return array_map(static fn($x) => json_decode(substr(strval($x['data']), strlen($key)), true), is_array($r) ? $r : []);
}
function current_row(string $key): array { $r = rows($key); return $r ? $r[count($r) - 1] : []; }

turn(['travel_decision'=>'PROPOSE','travel_destination'=>'Squin'], 'Take me to Squin.', 1000);
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>"Yes, let's go"], "Yes, let's go.", 1010);
$squin = current_row($key);
check('20d setup: Squin trip ACCEPTED', ($squin['status'] ?? '') === 'ACCEPTED' && ($squin['destination'] ?? '') === 'Squin', $squin);
$squinId = strval($squin['agreement_id'] ?? '');
turn(['travel_decision'=>'REPLACE','travel_destination'=>'Stumble Inn','travel_player_quote'=>'go to the Stumble Inn instead'], 'Actually, go to the Stumble Inn instead.', 1100);
$alt = stobeImm26AltRead($actor, 'Shay', 1100);
check('20d setup: change to Stumble Inn parked (pending_change names the Squin trip)', ($alt['pending_change']['old_agreement_id'] ?? '') === $squinId
    && ($alt['pending_change']['offer']['destination'] ?? '') === 'Stumble Inn', $alt);
// a save+load fails the old trip (commitment_native_bridge): same agreement id, status FAILED
$failed = $squin; $failed['status'] = 'FAILED'; $failed['execution'] = ['phase'=>'failed', 'reason'=>'Previous-load journey ownership could not be restored; current native observation verifies no travel work remains.', 'owned_work_released'=>true];
check('20d setup: old trip FAILED by the load', kill_trip($failed, 1200));
$nRows = count(rows($key));
$tail = stobeImm26PromptTail($actor, $npc, 'Shay', 1200);
check('20d prompt: dead old trip + pending_change -> tells the model to PROPOSE the waiting destination, not the old one',
    str_contains($tail, 'travel_decision=PROPOSE with travel_destination=Stumble Inn') && str_contains($tail, 'do NOT offer its destination again')
    && !str_contains($tail, 'current trip stays in force'), $tail);

// negatives: nothing is applied and nothing is written
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>"No, don't."], "No, don't.", 1210);
check('20d neg: negation -> waiting change not applied', count(rows($key)) === $nRows && isset(stobeImm26AltRead($actor, 'Shay', 1210)['pending_change']));
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Yes. Take me to Vain.'], 'Yes. Take me to Vain.', 1220);
check('20d neg: line names another place -> waiting change not applied', count(rows($key)) === $nRows && isset(stobeImm26AltRead($actor, 'Shay', 1220)['pending_change']));
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Yes.'], 'Yes.', 1200 + 21601);
check('20d neg: expired (> 6 game hours) -> waiting change not applied', count(rows($key)) === $nRows && isset(stobeImm26AltRead($actor, 'Shay', 1200 + 21601)['pending_change']));

// positive A: the model re-offers the OLD trip on a bare Yes -> the pending_change destination is PROPOSED instead
[$text, $actions] = turn(['travel_decision'=>'PROPOSE','travel_destination'=>'Squin','travel_player_quote'=>'Yes.'], 'Yes.', 1300);
$cur = current_row($key);
check('20d: bare Yes after the load PROPOSEs the waiting Stumble Inn (not the old Squin)', ($cur['status'] ?? '') === 'PROPOSED' && ($cur['destination'] ?? '') === 'Stumble Inn'
    && count(rows($key)) === $nRows + 1, [$cur, $text]);
check('20d: reply text names the new destination', str_contains($text, 'Stumble Inn') && !str_contains($text, 'Squin'), $text);
check('20d: pending_change cleared after it was applied', !isset(stobeImm26AltRead($actor, 'Shay', 1300)['pending_change']), stobeImm26AltRead($actor, 'Shay', 1300));
check('20d: no movement action dispatched by the proposal', !array_filter($actions, static fn($a) => str_starts_with(strval($a), 'TRAVEL_LOCATION')), $actions);

// positive B: the model answers ACCEPT (old Stumble echo) while a pending_replacement to Squin waits and the old trip is dead
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>"Yes, let's go"], "Yes, let's go.", 1400);
$stumble = current_row($key);
check('20d setup B: Stumble Inn ACCEPTED', ($stumble['status'] ?? '') === 'ACCEPTED' && ($stumble['destination'] ?? '') === 'Stumble Inn', $stumble);
$failed2 = $stumble; $failed2['status'] = 'FAILED'; $failed2['execution'] = ['phase'=>'failed', 'reason'=>'load', 'owned_work_released'=>true];
kill_trip($failed2, 1500);
stobeImm26AltWrite($actor, 'Shay', 1450, ['pending_replacement'=>['destination'=>'Squin', 'kind'=>'detour', 'leader'=>'npc', 'gamets'=>1450]]);
$tail = stobeImm26PromptTail($actor, $npc, 'Shay', 1500);
check('20d prompt B: pending_replacement tells the model what to answer on a plain yes', str_contains($tail, 'travel_decision=PROPOSE with travel_destination=Squin')
    && str_contains($tail, 'travel_kind=detour'), $tail);
$nB = count(rows($key));
[$text] = turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>'Yes.'], 'Yes.', 1510);
$cur = current_row($key);
check('20d B: ACCEPT of the dead old trip becomes a PROPOSE of the waiting Squin change', ($cur['status'] ?? '') === 'PROPOSED' && ($cur['destination'] ?? '') === 'Squin'
    && count(rows($key)) === $nB + 1, [$cur, $text]);
check('20d B: pending_replacement cleared', !isset(stobeImm26AltRead($actor, 'Shay', 1510)['pending_replacement']));
// the ordinary flow after that is untouched: a following ACCEPT of the fresh PROPOSED offer is a normal acceptance
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_kind'=>'detour','travel_player_quote'=>'Yes, go'], 'Yes, go.', 1520);
check('20d B: next Yes accepts the Squin offer normally', (current_row($key)['status'] ?? '') === 'ACCEPTED' && (current_row($key)['destination'] ?? '') === 'Squin', current_row($key));
// expired pending_replacement is neither offered in the prompt nor applied
$failed3 = current_row($key); $failed3['status'] = 'FAILED'; $failed3['execution'] = ['phase'=>'failed', 'reason'=>'load', 'owned_work_released'=>true];
kill_trip($failed3, 2000);
stobeImm26AltWrite($actor, 'Shay', 2000, ['pending_replacement'=>['destination'=>'Vain', 'kind'=>'detour', 'leader'=>'npc', 'gamets'=>2000]]);
check('20d: stale pending_replacement is not offered in the prompt', !str_contains(stobeImm26PromptTail($actor, $npc, 'Shay', 2000 + 21601), 'Vain'));
$nC = count(rows($key));
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Yes.'], 'Yes.', 2000 + 21601);
check('20d: stale pending_replacement is not applied', count(rows($key)) === $nC);

echo "imm26_fix22b20d: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
