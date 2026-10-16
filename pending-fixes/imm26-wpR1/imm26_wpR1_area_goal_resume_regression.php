<?php
// imm26-wpR1 (area-goal leg of the audit gap 1; harness copied from imm26_wpL_landmark_resume_regression.php): the ACCEPTED trip created by the
// broad-region area goal (row 24-b: kind same_route, leader npc, destination_point native_local, plus the regional_goal block written by
// stobeTravelCapture) must resume after save+load exactly like a landmark trip (wpL, commit 0647e9d). Original wpL header follows.
// imm26-wpL: a trip to a LOCAL LANDMARK (source=native_local, e.g. "higher ground to the east") must resume after save+load from its stored
// x/y/z (Shay 2026-10-15, trip-continues-after-load). The resumed OWNED_TRAVEL start carries candidate_id="" (native candidate ids die on load);
// the first start of a landmark trip still carries the candidate id. Harness copied from imm26_trip_resume_regression.php.
// Run: STOBE_DB_NAME=stobe_test php tests/imm26_trip_resume_regression.php   (flock /tmp/stobe-tests.lock)
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/area_goal_integration.php';
$db = $GLOBALS['db'];
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 700) : '') . "\n"; }
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
$_SERVER['HTTP_X_STOBE_PLAYTHROUGH'] = 'rcpt-tr';
const TR_PLAYER = 'Shay';
const TR_PLAYER_SERIAL = 11111;

$db->exec('BEGIN');
$db->exec("DELETE FROM eventlog WHERE type IN ('travel_agreement','travel_alternatives','travel_order_owner')");
function set_setting(string $id, string $value): void {
    $GLOBALS['db']->exec("DELETE FROM general_settings WHERE id=$1", [$id]);
    $GLOBALS['db']->exec("INSERT INTO general_settings (id, value) VALUES ($1, $2)", [$id, $value]);
}
function reset_settings(): void {
    set_setting('STOBE_TRIP_RESUME_ENABLED', '1');
    set_setting('STOBE_TRIP_RESUME_MAX_AGE_GAMETS', '7200');
    set_setting('STOBE_TRIP_RESUME_MAX_COUNT', '3');
}
reset_settings();

$GLOBALS['TR_NEXT'] = 0;
/** One fresh NPC per scenario: own serial, own agreement. */
function tr_actor(): array {
    $i = ++$GLOBALS['TR_NEXT'];
    $name = 'UtTrip' . $i; $serial = 33000 + $i;
    $GLOBALS['db']->exec("DELETE FROM core_npc_master WHERE name=$1", [$name]);
    $GLOBALS['db']->exec("INSERT INTO core_npc_master (name, metadata) VALUES ($1, $2::jsonb)", [$name, json_encode(['storage_id'=>'hand_' . $serial])]);
    return [$name, $serial];
}
function tr_people(array $actors, bool $playerLive = true): void {
    $p = $playerLive ? [TR_PLAYER . '|hand_' . TR_PLAYER_SERIAL] : [];
    foreach ($actors as $a) $p[] = $a[0] . '|hand_' . $a[1];
    $GLOBALS['CACHE_PEOPLE'] = json_encode($p);
}
const TR_DEST = ['source'=>'visited_location', 'label'=>'Squin', 'x'=>-62461.0, 'y'=>324.755, 'z'=>16346.8];

/** Write the accepted + running trip exactly as the pre-save session left it. */
function tr_seed(string $actor, int $serial, array $o = []): array {
    $g = $o['g'] ?? 1000;
    $kind = $o['kind'] ?? 'guide'; $leader = $o['leader'] ?? 'npc';
    $point = $o['point'] ?? TR_DEST;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    $GLOBALS['STOBE_TRAVEL_GAMETS'] = $g;
    tr_people([[$actor, $serial]]);
    stobeTravelRead($actor, TR_PLAYER, $g);            // prime the request-local cache (writers require it)
    $hash = stobeTravelPlanHash($actor, TR_PLAYER, $kind, $leader, $point);
    $state = ['status'=>'ACCEPTED', 'kind'=>$kind, 'leader'=>$leader,
        'destination'=>$point['label'], 'destination_point'=>$point + (($point['source'] ?? '') === 'native_local' ? ['id'=>'cand_1', 'actor_serial'=>$serial] : []),
        'plan_hash'=>$hash, 'actor'=>$actor, 'speaker'=>TR_PLAYER, 'origin'=>'player', 'proposed_by'=>TR_PLAYER,
        'agreement_id'=>'trip-' . bin2hex(random_bytes(8)) . 'aaaaaaaa', 'created_gamets'=>$g - 50, 'accepted_gamets'=>$g - 40,
        'accepted_by'=>[$actor, TR_PLAYER], 'acceptance_quote'=>"Yes, let's go.", 'expires_gamets'=>$o['expires'] ?? ($g - 40 + 86400),
        'execution'=>['phase'=>'running', 'changed_gamets'=>$g - 30, 'request_id'=>'req-old-' . bin2hex(random_bytes(4)),
            'dispatch_world_id'=>'world-old-aaaaaaaa', 'world_id'=>'world-old-aaaaaaaa', 'session_generation'=>1,
            'task_id'=>'task-old-1', 'actor_serial'=>$serial, 'speaker_serial'=>TR_PLAYER_SERIAL, 'plan_hash'=>$hash,
            'evidence_id'=>'ev-old-1', 'requested_action'=>$leader === 'player' ? 'FOLLOW@Shay' : 'TRAVEL_LOCATION@' . $point['label'],
            'owned_work_released'=>false]];
    foreach (($o['exec'] ?? []) as $k => $v) { if ($v === null) unset($state['execution'][$k]); else $state['execution'][$k] = $v; }
    if (!stobeTravelWrite($actor, TR_PLAYER, $g, $state)) throw new RuntimeException('seed write failed');
    return $state;
}

/** NPC row as the plugin request would carry it after a load: native snapshot bound to the current receipt. */
function tr_npc(string $actor, int $serial, int $g, array $o = []): array {
    $snap = ['actor_serial'=>$serial, 'world_id'=>$o['world'] ?? 'world-new-bbbbbbbb', 'session_generation'=>$o['gen'] ?? 2,
        'observed_gamets'=>$g, 'observed_unix'=>time(), 'receipts'=>$o['receipts'] ?? [],
        'scoped_travel_absent_verified'=>$o['absent'] ?? true];
    if ($snap['scoped_travel_absent_verified']) {
        $snap += ['absence_evidence_id'=>$snap['world_id'] . ':abs-' . $g, 'absence_observed_gamets'=>$g, 'absence_observed_unix'=>time()];
    }
    $meta = ['storage_id'=>'hand_' . $serial, 'travel_lifecycle_context_receipt'=>'rcpt-tr', 'travel_lifecycle'=>$snap];
    if (isset($o['char_state'])) $meta['character_state'] = $o['char_state'];
    if (!empty($o['combat'])) {
        $meta += ['native_ai_context_receipt'=>'rcpt-tr', 'native_ai_context_gamets'=>$g,
            'native_ai'=>['version'=>1, 'observed'=>true, 'actor_serial'=>$serial, 'observed_unix'=>time(), 'game_ts'=>$g,
                'combat'=>['observed'=>true, 'in_combat'=>true]]];
    }
    return ['name'=>$actor, 'race'=>'Greenlander', 'faction'=>'No Faction', 'hunger'=>'', 'blood'=>'', 'metadata'=>$meta,
        'extended_data'=>['relationships'=>[TR_PLAYER=>['aff'=>$o['aff'] ?? 60]]]];
}

/** One plugin request after a load: reconcile (the prompt/bored paths do this first), then the response path emits wires.
 *  $o: world gen absent combat char_state aff receipts, live=false (NPC not within 80u), bored=true (no player chat gamets), actions, text */
function tr_turn(string $actor, int $serial, int $g, array $o = []): array {
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    $GLOBALS['STOBE_TRAVEL_GAMETS'] = $g;
    if (!empty($o['bored'])) { unset($_POST['gamets'], $_GET['gamets']); } else { $_POST['gamets'] = $g; }
    tr_people(($o['live'] ?? true) ? [[$actor, $serial]] : []);
    $npc = tr_npc($actor, $serial, $g, $o);
    stobeCommitmentReconcileNative($actor, TR_PLAYER, $npc, $g);
    $captured = '';
    ob_start(static function (string $chunk) use (&$captured): string { $captured .= $chunk; return ''; }, 1);
    try {
        streamResponse($actor, 'ScriptQueue', $o['text'] ?? 'Here we are.', $npc, $o['actions'] ?? [],
            !empty($o['bored']) ? 'chat' : '', '', !empty($o['bored']) ? $g : 0);
    } finally { ob_end_clean(); }
    $wires = [];
    foreach (preg_split('/\r?\n/', $captured) as $line) {
        if (preg_match('/^[^|]*\|ActionQueue\|OWNED_TRAVEL@(\{.*\})$/', $line, $m)) {
            $j = json_decode($m[1], true);
            if (is_array($j)) $wires[] = $j;
        }
    }
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    return ['wires'=>$wires, 'out'=>$captured, 'state'=>stobeTravelRead($actor, TR_PLAYER, $g)];
}
function tr_same_xyz(?array $p): bool {
    return is_array($p) && abs(floatval($p['x'] ?? NAN) - TR_DEST['x']) < 0.0005 && abs(floatval($p['y'] ?? NAN) - TR_DEST['y']) < 0.0005
        && abs(floatval($p['z'] ?? NAN) - TR_DEST['z']) < 0.0005;
}
function tr_phase(?array $s): string { return strval($s['execution']['phase'] ?? ''); }
function tr_rows(string $actor, int $serial): array {
    $key = 'travel-v1:' . $serial . ':' . TR_PLAYER_SERIAL . ':';
    $r = $GLOBALS['db']->fetchAll("SELECT data FROM eventlog WHERE type='travel_agreement' AND LEFT(data, LENGTH($1))=$1 ORDER BY rowid", [$key]);
    return array_map(static fn($x) => json_decode(substr(strval($x['data']), strlen($key)), true), is_array($r) ? $r : []);
}
function tr_receipt(array $st, string $actor, int $serial, string $world, int $gen, string $phase, string $ev, array $extra = []): array {
    return $extra + ['world_id'=>$world, 'actor_serial'=>$serial, 'speaker_serial'=>TR_PLAYER_SERIAL, 'session_generation'=>$gen,
        'agreement_id'=>$st['agreement_id'], 'request_id'=>$st['execution']['request_id'], 'plan_hash'=>$st['plan_hash'],
        'task_id'=>'task-new-2', 'dispatch_outcome'=>'accepted', 'ownership_scope'=>'native_order', 'phase'=>$phase, 'evidence_id'=>$ev];
}
/** Terminal outcome: honest FAILED (never interrupted, no wire, native work marked released). */
function tr_expect_failed(string $name, array $r): void {
    $s = $r['state'];
    check("$name: FAILED with an honest reason, not interrupted", ($s['status'] ?? '') === 'FAILED' && tr_phase($s) === 'failed'
        && trim(strval($s['execution']['reason'] ?? '')) !== '', [$s['status'] ?? null, tr_phase($s), $s['execution']['reason'] ?? null]);
    check("$name: no OWNED_TRAVEL wire", $r['wires'] === [], $r['wires']);
}


const WL_LM = ['source'=>'native_local', 'label'=>'higher ground to the east', 'x'=>-52810.9, 'y'=>412.5, 'z'=>16101.25];
/** Seed a landmark trip with the point as the offer stored it (id + actor_serial are part of the plan hash). */
function wl_seed(string $actor, int $serial, array $o = []): array {
    $pt = array_replace(WL_LM + ['id'=>'local:sess1:' . $serial . ':7', 'actor_serial'=>$serial], $o['point'] ?? []);
    unset($o['point']);
    return tr_seed($actor, $serial, ['point'=>$pt] + $o);
}
function wl_xyz(array $w): bool { return abs(floatval($w['x'] ?? 0) - WL_LM['x']) < 0.01 && abs(floatval($w['y'] ?? 0) - WL_LM['y']) < 0.01 && abs(floatval($w['z'] ?? 0) - WL_LM['z']) < 0.01; }


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
