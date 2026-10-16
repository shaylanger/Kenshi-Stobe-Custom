<?php
// imm26-inv22b2 / row 22-b (4080-i3 live run 3): a COMPLETED native trip receipt is ingested by the bored-turn reconcile
// (processor/bored.php:182-190 -> stobeCommitmentReconcileNative) only when the request resolves the speaker to the NPC row that
// carries the native snapshot. The DLL names the speaker "Cind [Hungry Bandit]" (profile= and people=, ChatBox.cpp:5752-5754/5833-5844);
// the 22-b recipe tick (rowtools/sfr22b_bored_g.sh, from unblockdefs_a.sh i4_bored) sent the BARE name "Cind". getNpcData() is an exact
// name lookup (data_functions.php:7786-7810, no bracket-prefix match), so the bare name hits a stale placeholder row ("Cind",
// metadata {"storage_id":"hand_2017700224"}, no travel_lifecycle) and the reconcile returns at stobeCommitmentNativeSnapshot (commitment_native_bridge.php:7-9).
// Lane-shaped data: request_id/plan_hash/world/generation/receipt fields copied from the 4080-i3 lane DB (Cind [Hungry Bandit], receipt
// trip-74b4cbd97f4d525d4955d7239c8f55bf, task order:2529907200:19, world travel-66e5..., generation 8).
// Run (WSL, scratch tree with this file in tests/): flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test php tests/imm26_inv22b2_bored_profile_regression.php
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/situated_dialogue.php';
$db = $GLOBALS['db'];
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 700) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }

const P_NAME = 'Shay'; const P_SERIAL = 971557632;
const FULL = 'UtI22b2 [Hungry Bandit]'; const BARE = 'UtI22b2'; const SERIAL = 2529907201; const STUB_SERIAL = 2017700225;
$oldPlayer = $db->fetchOne("SELECT value FROM general_settings WHERE id='PLAYER_NAME'");
function cleanup(): void {
    $d = $GLOBALS['db'];
    $d->exec("DELETE FROM core_npc_master WHERE name IN ($1,$2)", [FULL, BARE]);
    $d->exec("DELETE FROM eventlog WHERE type IN ('travel_agreement','travel_alternatives','travel_order_owner')");
    $d->exec("DELETE FROM eventlog WHERE type='situated_event' AND data LIKE 'situated-v1:" . SERIAL . ":%'");
    $d->exec("DELETE FROM eventlog WHERE type='situated_remark_claim' AND data LIKE '%\"actor_serial\":" . SERIAL . "%'");
    $d->exec("DELETE FROM eventlog WHERE type IN ('inputtext','inputtext_s','situated_remark_claim') AND localts >= " . (time() - 300));
}
register_shutdown_function(static function () use ($db, $oldPlayer): void {
    cleanup();
    $db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
    if (is_array($oldPlayer)) $db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', $1)", [strval($oldPlayer['value'])]);
});
$db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', 'Shay')");
$GLOBALS['STOBE_TRAVEL_SPEAKER'] = P_NAME; $GLOBALS['STOBE_PLAYER_ACTOR'] = P_NAME;
$_SERVER['HTTP_X_STOBE_PLAYTHROUGH'] = 'rcpt-22b2';
const WORLD = 'travel-66e5cd8f2882304fb33cb5b02404b35a'; const GEN = 8;
const DEST = ['x'=>-62461, 'y'=>324.745, 'z'=>16346.8, 'label'=>'Squin', 'source'=>'visited_location'];

/** Seed the pre-arrival world: both NPC rows, the ACCEPTED/requested agreement (as the lane DB held it after OWNED_TRAVEL start). */
function seed(): array {
    cleanup();
    $g = 277500;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    $people = [P_NAME . '|hand_' . P_SERIAL, FULL . '|hand_' . SERIAL];
    $GLOBALS['CACHE_PEOPLE'] = json_encode($people);
    stobeTravelRead(FULL, P_NAME, $g); // prime the request-local cache (writers require it)
    $hash = stobeTravelPlanHash(FULL, P_NAME, 'same_route', 'npc', DEST);
    $state = ['status'=>'ACCEPTED', 'kind'=>'same_route', 'leader'=>'npc', 'destination'=>'Squin', 'destination_point'=>DEST,
        'plan_hash'=>$hash, 'actor'=>FULL, 'speaker'=>P_NAME, 'origin'=>'player', 'proposed_by'=>P_NAME,
        'agreement_id'=>'trip-74b4cbd97f4d525d4955d7239c8f55bf', 'created_gamets'=>276514, 'proposed_gamets'=>276514, 'accepted_gamets'=>276883,
        'accepted_by'=>[FULL, P_NAME], 'acceptance_quote'=>"I'm fine. Yes, let's go.", 'expires_gamets'=>363283,
        'execution'=>['phase'=>'requested', 'changed_gamets'=>276883, 'request_id'=>'dd58d174b23c123ad3a4f0569545ddbc4a5cda7fd38236bc61c58388c4f243a8',
            'requested_action'=>'TRAVEL_LOCATION@Squin', 'dispatch_world_id'=>WORLD, 'session_generation'=>GEN, 'plan_hash'=>$hash,
            'actor_serial'=>SERIAL, 'speaker_serial'=>P_SERIAL]];
    if (!stobeTravelWrite(FULL, P_NAME, 276883, $state)) throw new RuntimeException('agreement seed failed');
    $receipt = ['phase'=>'completed', 'reason'=>'measured_route_arrival', 'task_id'=>'order:' . SERIAL . ':19', 'world_id'=>WORLD,
        'plan_hash'=>$hash, 'request_id'=>$state['execution']['request_id'], 'evidence_id'=>WORLD . ':43', 'actor_serial'=>SERIAL,
        'agreement_id'=>$state['agreement_id'], 'speaker_serial'=>P_SERIAL, 'ownership_scope'=>'native_order', 'dispatch_outcome'=>'accepted',
        'session_generation'=>GEN, 'controller_released'=>true, 'owned_work_released'=>true, 'not_started_verified'=>false, 'end_condition_verified'=>true,
        'participation'=>['mode'=>'travel_accompaniment', 'task_id'=>'order:' . SERIAL . ':19', 'world_id'=>WORLD, 'qualified'=>true, 'actor_name'=>FULL,
            'last_gamets'=>277452, 'actor_serial'=>SERIAL, 'agreement_id'=>$state['agreement_id'], 'first_gamets'=>277251, 'partner_name'=>P_NAME,
            'actor_distance'=>172.282, 'max_separation'=>14.1726, 'partner_serial'=>P_SERIAL, 'schema_version'=>1, 'terminal_gamets'=>277452,
            'actor_storage_id'=>'hand_' . SERIAL, 'progress_samples'=>0, 'endpoint_progress'=>120.324, 'qualified_samples'=>66,
            'partner_storage_id'=>'hand_' . P_SERIAL, 'partner_distance'=>179.106, 'conscious_alive_all'=>true]];
    $snap = ['receipts'=>[$receipt], 'world_id'=>WORLD, 'actor_serial'=>SERIAL, 'observed_unix'=>time(), 'observed_gamets'=>277500,
        'session_generation'=>GEN, 'absence_evidence_id'=>WORLD . ':absence:59', 'absence_observed_unix'=>time(), 'absence_observed_gamets'=>277501,
        'scoped_travel_absent_verified'=>true];
    $meta = ['storage_id'=>'hand_' . SERIAL, 'travel_lifecycle_context_receipt'=>'rcpt-22b2', 'travel_lifecycle'=>$snap];
    $GLOBALS['db']->exec("INSERT INTO core_npc_master (name, original_name, race, faction, metadata) VALUES ($1, 'Hungry Bandit', 'Hive Soldier Drone', 'Traders Guild', $2::jsonb)", [FULL, json_encode($meta)]);
    // The stale placeholder the recipe's bare-name ticks created on the lane (core_npc_master id 3213): other serial, no native snapshot.
    $GLOBALS['db']->exec("INSERT INTO core_npc_master (name, original_name, metadata, gamets_last_updated) VALUES ($1, $1, $2::jsonb, 0)", [BARE, json_encode(['storage_id'=>'hand_' . STUB_SERIAL])]);
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    return [$g, $state];
}
function agreement(int $g): ?array { $GLOBALS['STOBE_TRAVEL_STATE'] = []; return stobeTravelRead(FULL, P_NAME, $g); }
function arrival_rows(): int {
    $r = $GLOBALS['db']->fetchOne("SELECT COUNT(*) AS n FROM eventlog WHERE type='situated_event' AND data LIKE 'situated-v1:" . SERIAL . ":%'");
    return intval($r['n'] ?? 0);
}
/** processor/bored.php speaker resolution (lines 49-87) + reconcile (182-190) + the normal-turn situated claim (225-235), for a targeted optional request. */
function bored_tick(string $profile, array $people, int $g): array {
    $GLOBALS['CACHE_PEOPLE'] = json_encode($people);
    $_GET['profile'] = $profile;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    $speakerNpc = ''; $speakerData = false;
    foreach ([normalizeParticipantNameToken($profile)] as $candidate) {
        $data = getNpcData($candidate);
        if (!$data) { storeNpcProfile($candidate, []); $data = getNpcData($candidate); }
        if (!$data) continue;
        $speakerNpc = $candidate; $speakerData = $data; break;
    }
    stobeCommitmentReconcileNative($speakerNpc, P_NAME, $speakerData, $g);
    $meta = ['gamets'=>$g, 'stream_gamets'=>$g, 'eligible_bored_turn'=>true, 'social_optional_speech_allowed'=>true];
    $claim = stobeSituatedClaimRemark($speakerNpc, P_NAME, $g, is_array($speakerData) ? $speakerData : [], $meta);
    return ['speaker'=>$speakerNpc, 'row_storage'=>strval((is_array($speakerData) ? normalizeCoreNpcMetadata($speakerData['metadata'] ?? [])['storage_id'] ?? '' : '')), 'claim'=>$claim];
}

// 0. The bored.php wiring this test replays is still what the source does (guards the replica).
$src = str_replace("\r\n", "\n", strval(file_get_contents(__DIR__ . '/../processor/bored.php')));
check('bored.php resolves the speaker with an exact-name getNpcData($candidateName)', substr_count($src, '$candidateData = getNpcData($candidateName);') >= 1);
check('bored.php reconciles with the resolved $speakerData', strpos($src, 'stobeCommitmentReconcileNative($speakerNpc, $playerName, $speakerData, intval($gamets))') !== false);
check('bored.php claims the situated remark with the resolved $speakerData', strpos($src, 'stobeSituatedClaimRemark($speakerNpc, $playerName, intval($gamets), $speakerData, $optionalMeta)') !== false);

$G = 277511; // the live-gamets tick of the lane run (tick1 stamp)
$dll = [P_NAME . '|hand_' . P_SERIAL, FULL . '|hand_' . SERIAL];            // DLL form: ChatBox.cpp:5833-5844 (npc->getName() + serial)
$old = [BARE . '|hand_' . SERIAL, P_NAME . '|hand_' . P_SERIAL];             // recipe form of tick1_log: profile=Cind people=Cind|2529907200,Shay|971557632

// 1. Control: the stored row for the full name carries the native snapshot; the bare name resolves to the stub without it.
[$g0, $seed] = seed();
$full = getNpcData(FULL); $bare = getNpcData(BARE);
check('control: getNpcData(full) returns the row with travel_lifecycle', is_array($full) && is_array(normalizeCoreNpcMetadata($full['metadata'] ?? [])['travel_lifecycle'] ?? null));
check('control: getNpcData(bare) returns the placeholder (other serial, no travel_lifecycle) - no bracket-prefix match',
    is_array($bare) && (normalizeCoreNpcMetadata($bare['metadata'] ?? [])['storage_id'] ?? '') === 'hand_' . STUB_SERIAL && !isset(normalizeCoreNpcMetadata($bare['metadata'] ?? [])['travel_lifecycle']));
check('control: agreement is ACCEPTED/requested with no task bound', ($seed['status'] ?? '') === 'ACCEPTED' && ($seed['execution']['phase'] ?? '') === 'requested' && empty($seed['execution']['task_id']));

// 2. The recipe's old tick (bare profile): nothing is ingested - this is the 22-b live-run-3 result (agreement stays ACCEPTED/requested, no arrival event).
$r2 = bored_tick(BARE, $old, $G);
$s2 = agreement($G);
check('old recipe tick (bare name) resolved the placeholder row', $r2['row_storage'] === 'hand_' . STUB_SERIAL, $r2);
check('old recipe tick: agreement stays ACCEPTED/requested (22-b run 3 symptom)', ($s2['status'] ?? '') === 'ACCEPTED' && ($s2['execution']['phase'] ?? '') === 'requested' && empty($s2['execution']['task_id']), $s2['execution'] ?? null);
check('old recipe tick: no situated arrival event, nothing claimable', arrival_rows() === 0 && $r2['claim'] === null, [arrival_rows(), $r2['claim']]);

// 3. The DLL-form tick (full profile name + serial people): the same receipt is bound, the trip COMPLETES, the arrival event exists and is claimed.
[$g0, $seed] = seed();
$r3 = bored_tick(FULL, $dll, $G);
$s3 = agreement($G);
check('DLL-form tick resolved the NPC row with the native snapshot', $r3['row_storage'] === 'hand_' . SERIAL, $r3);
check('DLL-form tick: receipt bound (task_id from the completed receipt)', ($s3['execution']['task_id'] ?? '') === 'order:' . SERIAL . ':19' && ($s3['execution']['world_id'] ?? '') === WORLD, $s3['execution'] ?? null);
check('DLL-form tick: agreement COMPLETED, phase completed, owned work released', ($s3['status'] ?? '') === 'COMPLETED' && ($s3['execution']['phase'] ?? '') === 'completed'
    && ($s3['execution']['owned_work_released'] ?? false) === true, [$s3['status'] ?? null, $s3['execution'] ?? null]);
check('DLL-form tick: one situated arrival event for the player, claimed on the same bored turn',
    arrival_rows() === 1 && is_array($r3['claim']) && ($r3['claim']['kind'] ?? '') === 'arrival' && intval($r3['claim']['requester_serial'] ?? 0) === P_SERIAL, [arrival_rows(), $r3['claim']]);
check('DLL-form tick: the arrival fact names the destination', is_array($r3['claim']) && str_contains(strval($r3['claim']['fact'] ?? ''), 'Squin'), $r3['claim'] ?? null);

// 4. A second DLL-form tick right after does not repeat the remark (spacing / used-event rule) and does not re-ingest.
$r4 = bored_tick(FULL, $dll, $G + 30);
check('DLL-form second tick: no second claim of the same arrival', $r4['claim'] === null && arrival_rows() === 1, [$r4['claim'], arrival_rows()]);

// 5. DLL form but a stale snapshot (older than 120 gamets or 120 s) still refuses to ingest (guards the freshness rule stays).
[$g0, $seed] = seed();
$r5 = bored_tick(FULL, $dll, $G + 400);
$s5 = agreement($G + 400);
check('stale snapshot (gamets beyond the 120 window) is not ingested', ($s5['status'] ?? '') === 'ACCEPTED' && empty($s5['execution']['task_id']) && arrival_rows() === 0, $s5['execution'] ?? null);

echo "imm26_inv22b2_bored_profile: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
