<?php
// imm26 trip resume (row 19-a option B, Shay 2026-10-15): a trip saved mid-way and loaded must CONTINUE with the same agreement id.
// WP-B offline tests, written FIRST against the design (C:\KenshiTestRuns\agents\out\imm26-trip-resume-design\latest.md):
//   after a load native proves the scoped trip order is gone (scoped_travel_absent_verified) -> the agreement enters
//   execution.phase=interrupted_by_load (status stays ACCEPTED, agreement_id/destination/plan_hash kept) instead of FAILED;
//   the first plugin response (player chat OR bored/director) with the NPC live, calm and in range injects the already agreed
//   TRAVEL_LOCATION/FOLLOW action once; the existing chain (note request -> WrapDispatch -> native start wire) then re-issues
//   OWNED_TRAVEL start with a NEW request_id/world_id/session_generation but the SAME plan_hash + x/y/z.
// Entry points used (all existing public functions): stobeCommitmentReconcileNative (called per turn by the prompt/bored paths),
// streamResponse (the response path that emits the ActionQueue wire), stobeTravelCapture (player END), settings via general_settings.
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

// =====================================================================================================
// 0. Harness controls (must pass on today's code): the ordinary start -> bind -> running -> completed chain, no load involved
// =====================================================================================================
[$Z, $Zs] = tr_actor();
$seedZ = tr_seed($Z, $Zs, ['exec'=>['phase'=>'accepted', 'request_id'=>null, 'dispatch_world_id'=>null, 'world_id'=>null, 'task_id'=>null, 'session_generation'=>0, 'owned_work_released'=>true]]);
$rz = tr_turn($Z, $Zs, 1010, ['world'=>'world-new-bbbbbbbb', 'gen'=>2, 'live'=>true, 'actions'=>['TRAVEL_LOCATION@Squin']]);
$wz = $rz['wires'][0] ?? [];
check('control: an agreed TRAVEL_LOCATION action emits one OWNED_TRAVEL start wire (wire parser + chain work)', count($rz['wires']) === 1
    && ($wz['operation'] ?? '') === 'start' && ($wz['agreement_id'] ?? '') === $seedZ['agreement_id'] && ($wz['plan_hash'] ?? '') === $seedZ['plan_hash'] && tr_same_xyz($wz), $rz['wires']);
check('control: the state is requested with that request_id and world', tr_phase($rz['state']) === 'requested'
    && ($rz['state']['execution']['request_id'] ?? '') === ($wz['request_id'] ?? '?') && ($rz['state']['execution']['dispatch_world_id'] ?? '') === 'world-new-bbbbbbbb', $rz['state']['execution'] ?? null);
$evz = tr_receipt($rz['state'], $Z, $Zs, 'world-new-bbbbbbbb', 2, 'running', 'ctl-ev-running');
$doz = tr_receipt($rz['state'], $Z, $Zs, 'world-new-bbbbbbbb', 2, 'completed', 'ctl-ev-done', ['end_condition_verified'=>true, 'owned_work_released'=>true]);
$rz2 = tr_turn($Z, $Zs, 1020, ['world'=>'world-new-bbbbbbbb', 'gen'=>2, 'live'=>true, 'receipts'=>[$evz]]);
check('control: receipt binds the task, trip running', tr_phase($rz2['state']) === 'running' && ($rz2['state']['execution']['task_id'] ?? '') === 'task-new-2', $rz2['state']['execution'] ?? null);
$rz3 = tr_turn($Z, $Zs, 1030, ['world'=>'world-new-bbbbbbbb', 'gen'=>2, 'live'=>true, 'receipts'=>[$evz, $doz]]);
check('control: completed receipt -> COMPLETED, owned_work_released true', ($rz3['state']['status'] ?? '') === 'COMPLETED' && ($rz3['state']['execution']['owned_work_released'] ?? false) === true, $rz3['state']['execution'] ?? null);

[$Z2, $Z2s] = tr_actor();
tr_seed($Z2, $Z2s, ['exec'=>['phase'=>'accepted', 'request_id'=>null, 'dispatch_world_id'=>null, 'world_id'=>null, 'task_id'=>null, 'session_generation'=>0, 'owned_work_released'=>true]]);
$rz4 = tr_turn($Z2, $Z2s, 1010, ['world'=>'world-new-bbbbbbbb', 'gen'=>2, 'live'=>true, 'bored'=>true, 'actions'=>['TRAVEL_LOCATION@Squin']]);
check('control: the bored/director response path (no player chat gamets) emits the start wire too', count($rz4['wires']) === 1 && tr_phase($rz4['state']) === 'requested', [$rz4['wires'], tr_phase($rz4['state'])]);

// =====================================================================================================
// 1. Entering interrupted_by_load (calm load, NPC still live: the 19-a happy path), keeps the agreement
// =====================================================================================================
[$A, $As] = tr_actor();
$seed = tr_seed($A, $As);
$rowsBefore = count(tr_rows($A, $As));
// First post-load request, but the NPC is not in the 80u people list yet: the state is entered, nothing is injected.
$r = tr_turn($A, $As, 1100, ['live'=>false]);
$s = $r['state'];
check('enter: load with verified absence -> phase interrupted_by_load (not FAILED)', tr_phase($s) === 'interrupted_by_load' && ($s['status'] ?? '') === 'ACCEPTED', [$s['status'] ?? null, tr_phase($s)]);
check('enter: same agreement_id, destination, plan_hash, expiry kept', ($s['agreement_id'] ?? '') === $seed['agreement_id'] && ($s['destination'] ?? '') === 'Squin'
    && ($s['plan_hash'] ?? '') === $seed['plan_hash'] && intval($s['expires_gamets'] ?? 0) === intval($seed['expires_gamets']), $s);
check('enter: stored destination point (x/y/z) kept', tr_same_xyz($s['destination_point'] ?? null), $s['destination_point'] ?? null);
check('enter: native ownership retired (nothing left to clean up)', ($s['execution']['owned_work_released'] ?? false) === true
    && empty($s['execution']['task_id']) && empty($s['execution']['dispatch_world_id']) && !stobeCommitmentCleanupPending($s), $s['execution'] ?? null);
check('enter: interrupted_gamets recorded', intval($s['execution']['interrupted_gamets'] ?? 0) === 1100, $s['execution']['interrupted_gamets'] ?? null);
check('enter: no wire while she is out of range (stays interrupted, retried on a later turn)', $r['wires'] === [], $r['wires']);
// Idempotent: a second turn in the same state adds no rows and keeps interrupted_gamets.
$rowsAfterEnter = count(tr_rows($A, $As));
$r = tr_turn($A, $As, 1110, ['live'=>false]);
check('enter: idempotent (no new row, interrupted_gamets unchanged, still ACCEPTED)', count(tr_rows($A, $As)) === $rowsAfterEnter
    && intval($r['state']['execution']['interrupted_gamets'] ?? 0) === 1100 && ($r['state']['status'] ?? '') === 'ACCEPTED', [count(tr_rows($A, $As)), $rowsAfterEnter, $r['state']['execution'] ?? null]);
check('enter: the log only ever holds this one agreement id', count(array_unique(array_map(static fn($x) => $x['agreement_id'] ?? '', tr_rows($A, $As)))) === 1);

// =====================================================================================================
// 2. Injection exactly once: new request/world/generation, same plan_hash + x/y/z; then bind -> running -> completed
// =====================================================================================================
$r = tr_turn($A, $As, 1200, ['live'=>true]);   // she walked into range / chat started: first eligible turn
$s = $r['state']; $w = $r['wires'][0] ?? [];
check('inject: exactly one OWNED_TRAVEL start wire on the first eligible turn', count($r['wires']) === 1 && ($w['operation'] ?? '') === 'start', $r['wires']);
check('inject: wire carries the SAME agreement_id and plan_hash', ($w['agreement_id'] ?? '') === $seed['agreement_id'] && ($w['plan_hash'] ?? '') === $seed['plan_hash'], $w);
check('inject: wire has a NEW request_id', ($w['request_id'] ?? '') !== '' && ($w['request_id'] ?? '') !== $seed['execution']['request_id'], $w['request_id'] ?? null);
check('inject: wire has the NEW world_id and session_generation', ($w['world_id'] ?? '') === 'world-new-bbbbbbbb' && intval($w['session_generation'] ?? 0) === 2, $w);
check('inject: wire x/y/z equal the stored destination', tr_same_xyz($w), $w);
check('inject: route kind (NPC leads), label is the destination', ($w['kind'] ?? '') === 'route' && ($w['label'] ?? '') === 'Squin', $w);
check('inject: persisted state is requested with the same agreement id, ACCEPTED', tr_phase($s) === 'requested' && ($s['status'] ?? '') === 'ACCEPTED'
    && ($s['agreement_id'] ?? '') === $seed['agreement_id'] && ($s['execution']['request_id'] ?? '') === ($w['request_id'] ?? '?')
    && ($s['execution']['dispatch_world_id'] ?? '') === 'world-new-bbbbbbbb', $s['execution'] ?? null);
check('inject: no other agreement id and no PROPOSED row ever written', count(array_filter(tr_rows($A, $As),
    static fn($x) => ($x['agreement_id'] ?? '') !== $seed['agreement_id'] || ($x['status'] ?? '') === 'PROPOSED')) === 0);
// Exactly once: the next turn (state requested, same world) must not inject again.
$r2 = tr_turn($A, $As, 1210, ['live'=>true]);
check('inject: not injected a second time while the start is pending', $r2['wires'] === [] && tr_phase($r2['state']) === 'requested', [$r2['wires'], tr_phase($r2['state'])]);
// Native receipts: bind -> running
$req = $r['state'];
$ev = tr_receipt($req, $A, $As, 'world-new-bbbbbbbb', 2, 'running', 'new-ev-running');
$r3 = tr_turn($A, $As, 1220, ['live'=>true, 'receipts'=>[$ev]]);
check('cycle: receipt binds the new task and the trip is running again (same agreement id)', tr_phase($r3['state']) === 'running'
    && ($r3['state']['execution']['task_id'] ?? '') === 'task-new-2' && ($r3['state']['agreement_id'] ?? '') === $seed['agreement_id'] && ($r3['state']['status'] ?? '') === 'ACCEPTED', $r3['state']['execution'] ?? null);
check('cycle: still one wire in total (no re-injection once running)', $r3['wires'] === [], $r3['wires']);
$done = tr_receipt($req, $A, $As, 'world-new-bbbbbbbb', 2, 'completed', 'new-ev-completed', ['end_condition_verified'=>true, 'owned_work_released'=>true]);
$r4 = tr_turn($A, $As, 1300, ['live'=>true, 'receipts'=>[$ev, $done]]);
check('cycle: arrival at the destination -> COMPLETED with owned_work_released true (row 19-d)', ($r4['state']['status'] ?? '') === 'COMPLETED'
    && tr_phase($r4['state']) === 'completed' && ($r4['state']['execution']['owned_work_released'] ?? false) === true, $r4['state']['execution'] ?? null);

// =====================================================================================================
// 3. Unverified absence keeps today's behaviour (fighting / moving at load), later re-evaluated
// =====================================================================================================
[$B, $Bs] = tr_actor();
$seedB = tr_seed($B, $Bs);
$r = tr_turn($B, $Bs, 1100, ['absent'=>false, 'live'=>true]);
check('unverified: absence not verified -> not interrupted, not FAILED, still the old running record', ($r['state']['status'] ?? '') === 'ACCEPTED'
    && tr_phase($r['state']) === 'running' && ($r['state']['execution']['load_changed'] ?? false) === true
    && ($r['state']['execution']['cleanup'] ?? '') === 'unverified_after_load' && $r['wires'] === [], $r['state']['execution'] ?? null);
$r = tr_turn($B, $Bs, 1150, ['absent'=>true, 'live'=>false]);
check('unverified: a later verified snapshot re-evaluates and enters interrupted_by_load', tr_phase($r['state']) === 'interrupted_by_load'
    && ($r['state']['agreement_id'] ?? '') === $seedB['agreement_id'], tr_phase($r['state']));

// =====================================================================================================
// 4. Transient misses: stay interrupted_by_load, no injection, no new agreement (NC2 and friends)
// =====================================================================================================
foreach ([
    'fighting after load (NC2)'      => ['combat'=>true],
    'knocked out'                    => ['char_state'=>'unconscious'],
    'not within 80u (NC2)'           => ['live'=>false],
] as $label => $opt) {
    [$C, $Cs] = tr_actor();
    $seedC = tr_seed($C, $Cs);
    tr_turn($C, $Cs, 1100, ['live'=>false]);                     // enter interrupted, out of range
    $r = tr_turn($C, $Cs, 1150, $opt);
    check("transient ($label): stays interrupted_by_load, ACCEPTED, same agreement id", tr_phase($r['state']) === 'interrupted_by_load'
        && ($r['state']['status'] ?? '') === 'ACCEPTED' && ($r['state']['agreement_id'] ?? '') === $seedC['agreement_id'], [$r['state']['status'] ?? null, tr_phase($r['state'])]);
    check("transient ($label): no OWNED_TRAVEL, no new agreement id, no PROPOSED row", $r['wires'] === [] && count(array_filter(tr_rows($C, $Cs),
        static fn($x) => ($x['agreement_id'] ?? '') !== $seedC['agreement_id'] || ($x['status'] ?? '') === 'PROPOSED')) === 0, $r['wires']);
    // and the very next calm turn in range resumes it (the player's reaffirmation is not required)
    $r = tr_turn($C, $Cs, 1160, ['live'=>true]);
    check("transient ($label): resumes on the next eligible turn", count($r['wires']) === 1 && tr_phase($r['state']) === 'requested', [count($r['wires']), tr_phase($r['state'])]);
}

// =====================================================================================================
// 5. Terminal outcomes: honest FAILED through the existing writer, nothing injected
// =====================================================================================================
// 5a too old (age since interrupted_gamets > STOBE_TRIP_RESUME_MAX_AGE_GAMETS), 5b agreement expired
[$D, $Ds] = tr_actor(); tr_seed($D, $Ds); tr_turn($D, $Ds, 1100, ['live'=>false]);
$r = tr_turn($D, $Ds, 1100 + 7201, ['live'=>true]);
tr_expect_failed('too old (> 7200 game seconds after the load)', $r);
[$D2, $D2s] = tr_actor(); tr_seed($D2, $D2s); tr_turn($D2, $D2s, 1100, ['live'=>false]);
$r = tr_turn($D2, $D2s, 1100 + 7000, ['live'=>true]);
check('age: still inside the window at 7000 -> resumes', count($r['wires']) === 1 && tr_phase($r['state']) === 'requested', [count($r['wires']), tr_phase($r['state'])]);
[$E, $Es] = tr_actor(); tr_seed($E, $Es, ['expires'=>2100]); tr_turn($E, $Es, 1100, ['live'=>false]);
$r = tr_turn($E, $Es, 2200, ['live'=>true]);
tr_expect_failed('agreement expired while interrupted', $r);
[$E2, $E2s] = tr_actor(); tr_seed($E2, $E2s, ['expires'=>1100 + 300]);
$r = tr_turn($E2, $E2s, 1100, ['live'=>false]);
check('expiry: almost expired at the load -> no resume (honest FAILED as today)', ($r['state']['status'] ?? '') === 'FAILED' && tr_phase($r['state']) === 'failed', [$r['state']['status'] ?? null, tr_phase($r['state'])]);
// 5c policy refusal at resume time (trust dropped below the travel minimum), 5d dead
[$F, $Fs] = tr_actor(); tr_seed($F, $Fs); tr_turn($F, $Fs, 1100, ['live'=>false]);
$r = tr_turn($F, $Fs, 1200, ['live'=>true, 'aff'=>-20]);
tr_expect_failed('policy refusal (affinity below the travel minimum)', $r);
[$G, $Gs] = tr_actor(); tr_seed($G, $Gs); tr_turn($G, $Gs, 1100, ['live'=>false]);
$r = tr_turn($G, $Gs, 1200, ['live'=>true, 'char_state'=>'dead']);
tr_expect_failed('NPC dead', $r);
// 5e resume_count at the max: three loads resume, the fourth is an honest FAILED; MAX_COUNT=1 allows only one
[$H, $Hs] = tr_actor(); $seedH = tr_seed($H, $Hs);
$ok = true; $g = 1000; $last = null;
for ($load = 1; $load <= 3; $load++) {
    $g += 100;
    $r = tr_turn($H, $Hs, $g, ['world'=>"world-load-$load-cccccccc", 'gen'=>$load + 1, 'live'=>true]);
    $ok = $ok && count($r['wires']) === 1 && tr_phase($r['state']) === 'requested' && ($r['state']['agreement_id'] ?? '') === $seedH['agreement_id'];
    $last = $r;
}
check('count: three consecutive loads each resume the SAME agreement (one wire each)', $ok, [$last['wires'] ?? null, tr_phase($last['state'] ?? null)]);
$g += 100;
$r = tr_turn($H, $Hs, $g, ['world'=>'world-load-4-cccccccc', 'gen'=>5, 'live'=>true]);
tr_expect_failed('resume_count at the max (fourth load)', $r);
set_setting('STOBE_TRIP_RESUME_MAX_COUNT', '1');
[$H2, $H2s] = tr_actor(); tr_seed($H2, $H2s);
$r = tr_turn($H2, $H2s, 1100, ['world'=>'world-load-1-dddddddd', 'gen'=>2, 'live'=>true]);
$ok1 = count($r['wires']) === 1;
$r = tr_turn($H2, $H2s, 1200, ['world'=>'world-load-2-dddddddd', 'gen'=>3, 'live'=>true]);
check('count: STOBE_TRIP_RESUME_MAX_COUNT=1 -> first load resumes', $ok1);
tr_expect_failed('count: MAX_COUNT=1 second load', $r);
reset_settings();
// 5f native_local destinations now resume from their stored x/y/z (imm26-wpL: tests/imm26_wpL_landmark_resume_regression.php)
// 5g a meeting (duel/truce) is not a resumable walk
[$I2, $I2s] = tr_actor(); tr_seed($I2, $I2s, ['kind'=>'duel_meeting']);
$r = tr_turn($I2, $I2s, 1100, ['live'=>true]);
tr_expect_failed('duel_meeting kind', $r);
// 5h settings off -> today's FAILED behaviour, not interrupted, no wire
set_setting('STOBE_TRIP_RESUME_ENABLED', '0');
[$J, $Js] = tr_actor(); $seedJ = tr_seed($J, $Js);
$r = tr_turn($J, $Js, 1100, ['live'=>true]);
check('settings off: load with verified absence still ends FAILED (today\'s behaviour)', ($r['state']['status'] ?? '') === 'FAILED' && tr_phase($r['state']) === 'failed'
    && ($r['state']['execution']['cleanup'] ?? '') === 'verified_absent_after_load' && ($r['state']['execution']['owned_work_released'] ?? false) === true && $r['wires'] === [], $r['state']['execution'] ?? null);
reset_settings();

// =====================================================================================================
// 6. Player END while interrupted: ENDED + cancelled, nothing pending to clean up, nothing injected
// =====================================================================================================
[$K, $Ks] = tr_actor(); $seedK = tr_seed($K, $Ks); tr_turn($K, $Ks, 1100, ['live'=>false]);
$GLOBALS['STOBE_TRAVEL_STATE'] = []; $GLOBALS['STOBE_TRAVEL_GAMETS'] = 1150; $_POST['gamets'] = 1150;
tr_people([[$K, $Ks]]);
$npcK = tr_npc($K, $Ks, 1150);
stobeCommitmentReconcileNative($K, TR_PLAYER, $npcK, 1150);
$text = 'Alright, never mind.'; $actions = [];
stobeTravelCapture(json_encode(['travel_decision'=>'END', 'travel_kind'=>'guide', 'travel_leader'=>'npc', 'travel_destination'=>'Squin',
    'travel_player_quote'=>'Forget the trip.', 'travel_reason'=>'withdrawn', 'travel_busy_reason'=>'none', 'travel_alternative_id'=>'']),
    $K, $npcK, TR_PLAYER, 'Forget the trip.', 1150, $text, $actions);
$sk = stobeTravelRead($K, TR_PLAYER, 1150);
check('end: player END while interrupted -> ENDED, cancelled, no cleanup pending', ($sk['status'] ?? '') === 'ENDED' && tr_phase($sk) === 'cancelled'
    && ($sk['execution']['owned_work_released'] ?? false) === true && !stobeCommitmentCleanupPending($sk)
    && ($sk['agreement_id'] ?? '') === $seedK['agreement_id'], $sk['execution'] ?? null);
check('end: no release wire is queued', stobeCommitmentDrainReleaseWires($K) === []);
$r = tr_turn($K, $Ks, 1160, ['live'=>true]);
check('end: nothing is injected after END', $r['wires'] === [] && ($r['state']['status'] ?? '') === 'ENDED', [$r['wires'], $r['state']['status'] ?? null]);

// =====================================================================================================
// 7. Leader = player trips resume with FOLLOW; the bored/director response path resumes too
// =====================================================================================================
[$L, $Ls] = tr_actor(); $seedL = tr_seed($L, $Ls, ['leader'=>'player', 'kind'=>'same_route']);
$rL = tr_turn($L, $Ls, 1100, ['live'=>false]);
check('enter: area-goal state validator accepts ACCEPTED + interrupted_by_load', function_exists('stobeAreaGoalTripStateValid')
    && tr_phase($rL['state']) === 'interrupted_by_load' && stobeAreaGoalTripStateValid($rL['state'], $L, TR_PLAYER), $rL['state']['execution'] ?? null);
$r = tr_turn($L, $Ls, 1200, ['live'=>true]);
$w = $r['wires'][0] ?? [];
check('follow: leader=player trip resumes once as a follow start (same plan_hash/x/y/z)', count($r['wires']) === 1 && ($w['kind'] ?? '') === 'follow'
    && ($w['plan_hash'] ?? '') === $seedL['plan_hash'] && tr_same_xyz($w) && ($w['agreement_id'] ?? '') === $seedL['agreement_id'], $r['wires']);
[$M, $Ms] = tr_actor(); $seedM = tr_seed($M, $Ms);
tr_turn($M, $Ms, 1100, ['live'=>false, 'bored'=>true]);
$r = tr_turn($M, $Ms, 1200, ['live'=>true, 'bored'=>true, 'text'=>'*stretches* Shall we get going?']);
$w = $r['wires'][0] ?? [];
check('bored/director: the first bored response resumes the trip without the player speaking', count($r['wires']) === 1
    && ($w['agreement_id'] ?? '') === $seedM['agreement_id'] && ($w['plan_hash'] ?? '') === $seedM['plan_hash'] && tr_phase($r['state']) === 'requested', [$r['wires'], tr_phase($r['state'])]);

// =====================================================================================================
// 8. Negative control NC: an agreement that never existed (older save) is not invented
// =====================================================================================================
[$N, $Ns] = tr_actor();
$GLOBALS['STOBE_TRAVEL_STATE'] = []; $GLOBALS['STOBE_TRAVEL_GAMETS'] = 1100;
$r = tr_turn($N, $Ns, 1100, ['live'=>true]);
check('NC: no agreement -> no row, no interrupted state, no OWNED_TRAVEL', $r['state'] === null && $r['wires'] === [] && tr_rows($N, $Ns) === [], [$r['state'], $r['wires']]);
// NC: a COMPLETED / ENDED trip never resumes
[$O, $Os] = tr_actor(); $seedO = tr_seed($O, $Os);
$GLOBALS['STOBE_TRAVEL_STATE'] = []; stobeTravelRead($O, TR_PLAYER, 1100);
$ended = tr_turn($O, $Os, 1090, ['world'=>'world-old-aaaaaaaa', 'gen'=>1, 'live'=>true]);  // same world: nothing changes
check('NC: same world and generation (no load) leaves a running trip alone', tr_phase($ended['state']) === 'running' && $ended['wires'] === [], tr_phase($ended['state']));

echo "imm26_trip_resume: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
