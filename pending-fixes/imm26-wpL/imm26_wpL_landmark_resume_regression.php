<?php
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

// 1. first start of a landmark trip (no load yet): the wire still carries the native candidate id (unchanged behaviour)
[$A, $As] = tr_actor();
$seedA = wl_seed($A, $As, ['exec'=>['phase'=>'accepted', 'request_id'=>null, 'dispatch_world_id'=>null, 'world_id'=>null, 'task_id'=>null, 'session_generation'=>0, 'owned_work_released'=>true]]);
check('seed: landmark plan_hash is a real hash', preg_match('/^[0-9a-f]{64}$/', strval($seedA['plan_hash'])) === 1, $seedA['plan_hash']);
$r = tr_turn($A, $As, 1010, ['live'=>true, 'actions'=>['TRAVEL_LOCATION@higher ground to the east']]);
$w = $r['wires'][0] ?? [];
check('first start: one OWNED_TRAVEL wire with the native candidate id and stored x/y/z', count($r['wires']) === 1
    && ($w['candidate_id'] ?? null) === 'local:sess1:' . $As . ':7' && wl_xyz($w), $r['wires']);

// 2. ACCEPTED landmark trip, then save+load: pauses as interrupted_by_load (not FAILED), then resumes from the stored coordinates
[$B, $Bs] = tr_actor();
$seed = wl_seed($B, $Bs);
$r = tr_turn($B, $Bs, 1100, ['live'=>false]);
$s = $r['state'];
check('landmark load: phase interrupted_by_load, ACCEPTED, same agreement/plan_hash/destination',
    tr_phase($s) === 'interrupted_by_load' && ($s['status'] ?? '') === 'ACCEPTED' && ($s['agreement_id'] ?? '') === $seed['agreement_id']
    && ($s['plan_hash'] ?? '') === $seed['plan_hash'] && ($s['destination'] ?? '') === 'higher ground to the east', [$s['status'] ?? null, tr_phase($s)]);
check('landmark load: stored point (source native_local + x/y/z) kept', ($s['destination_point']['source'] ?? '') === 'native_local' && wl_xyz($s['destination_point'] ?? []), $s['destination_point'] ?? null);
$r = tr_turn($B, $Bs, 1200, ['live'=>true]);
$w = $r['wires'][0] ?? []; $s = $r['state'];
check('landmark resume: exactly one start wire, same agreement_id + plan_hash, stored x/y/z, route kind', count($r['wires']) === 1 && ($w['operation'] ?? '') === 'start'
    && ($w['agreement_id'] ?? '') === $seed['agreement_id'] && ($w['plan_hash'] ?? '') === $seed['plan_hash'] && wl_xyz($w) && ($w['kind'] ?? '') === 'route'
    && ($w['label'] ?? '') === 'higher ground to the east', $r['wires']);
check('landmark resume: NEW request_id/world/generation and candidate_id is empty (native ids die on load)', ($w['request_id'] ?? '') !== '' && ($w['request_id'] ?? '') !== $seed['execution']['request_id']
    && ($w['world_id'] ?? '') === 'world-new-bbbbbbbb' && intval($w['session_generation'] ?? 0) === 2 && ($w['candidate_id'] ?? 'x') === '', $w);
check('landmark resume: state requested, ACCEPTED, resume_count 1', tr_phase($s) === 'requested' && ($s['status'] ?? '') === 'ACCEPTED'
    && intval($s['execution']['resume_count'] ?? 0) === 1 && ($s['agreement_id'] ?? '') === $seed['agreement_id'], $s['execution'] ?? null);
$r2 = tr_turn($B, $Bs, 1210, ['live'=>true]);
check('landmark resume: not injected twice while the start is pending', $r2['wires'] === [] && tr_phase($r2['state']) === 'requested');
$ev = tr_receipt($s, $B, $Bs, 'world-new-bbbbbbbb', 2, 'running', 'wl-ev-running');
$r3 = tr_turn($B, $Bs, 1220, ['live'=>true, 'receipts'=>[$ev]]);
$done = tr_receipt($s, $B, $Bs, 'world-new-bbbbbbbb', 2, 'completed', 'wl-ev-done', ['end_condition_verified'=>true, 'owned_work_released'=>true]);
$r4 = tr_turn($B, $Bs, 1300, ['live'=>true, 'receipts'=>[$ev, $done]]);
check('landmark cycle: running, then COMPLETED with owned_work_released', tr_phase($r3['state']) === 'running' && ($r4['state']['status'] ?? '') === 'COMPLETED'
    && ($r4['state']['execution']['owned_work_released'] ?? false) === true, [tr_phase($r3['state']), $r4['state']['status'] ?? null]);
check('landmark resume: no other agreement id / PROPOSED row in the log', count(array_filter(tr_rows($B, $Bs),
    static fn($x) => ($x['agreement_id'] ?? '') !== $seed['agreement_id'] || ($x['status'] ?? '') === 'PROPOSED')) === 0);

// 3. second load of the same landmark trip also resumes with candidate_id ''
[$C, $Cs] = tr_actor(); wl_seed($C, $Cs);
tr_turn($C, $Cs, 1100, ['world'=>'world-load-1-cccccccc', 'gen'=>2, 'live'=>true]);
$r = tr_turn($C, $Cs, 1300, ['world'=>'world-load-2-cccccccc', 'gen'=>3, 'live'=>true]);
$w = $r['wires'][0] ?? [];
check('landmark: a second load resumes again (resume_count 2, candidate_id empty)', count($r['wires']) === 1 && ($w['candidate_id'] ?? 'x') === '' && wl_xyz($w)
    && intval($r['state']['execution']['resume_count'] ?? 0) === 2, [$r['wires'], $r['state']['execution']['resume_count'] ?? null]);

// 4. transient: out of range keeps it interrupted, then resumes
[$D, $Ds] = tr_actor(); wl_seed($D, $Ds);
tr_turn($D, $Ds, 1100, ['live'=>false]);
$r = tr_turn($D, $Ds, 1150, ['live'=>false]);
check('landmark transient (not within 80u): stays interrupted_by_load, no wire', tr_phase($r['state']) === 'interrupted_by_load' && $r['wires'] === []);
$r = tr_turn($D, $Ds, 1160, ['live'=>true]);
check('landmark transient: resumes on the next eligible turn', count($r['wires']) === 1 && tr_phase($r['state']) === 'requested');

// 5. no usable stored destination -> honest FAILED, no wire
[$E, $Es] = tr_actor();
wl_seed($E, $Es);
$GLOBALS['STOBE_TRAVEL_STATE'] = []; $stE = stobeTravelRead($E, TR_PLAYER, 1000);
unset($stE['destination_point']['x']);                                   // coordinates lost
check('seed: coordinates-less landmark state written', stobeTravelWrite($E, TR_PLAYER, 1000, $stE));
$r = tr_turn($E, $Es, 1100, ['live'=>true]);
tr_expect_failed('landmark without stored coordinates', $r);
[$E2, $E2s] = tr_actor();
wl_seed($E2, $E2s);
$GLOBALS['STOBE_TRAVEL_STATE'] = []; $stE2 = stobeTravelRead($E2, TR_PLAYER, 1000);
$stE2['destination_point']['id'] = '';                                   // candidate identity lost: plan hash no longer matches
stobeTravelWrite($E2, TR_PLAYER, 1000, $stE2);
$r = tr_turn($E2, $E2s, 1100, ['live'=>true]);
tr_expect_failed('landmark without its candidate id (plan hash mismatch)', $r);
[$E3, $E3s] = tr_actor();
wl_seed($E3, $E3s, ['point'=>['actor_serial'=>$E3s + 500]]);              // point bound to another actor serial
$r = tr_turn($E3, $E3s, 1100, ['live'=>true]);
tr_expect_failed('landmark bound to a different actor serial', $r);
[$E4, $E4s] = tr_actor();
wl_seed($E4, $E4s, ['expires'=>1100 + 300]);
$r = tr_turn($E4, $E4s, 1100, ['live'=>false]);
check('landmark almost expired at the load -> honest FAILED, no resume', ($r['state']['status'] ?? '') === 'FAILED' && tr_phase($r['state']) === 'failed' && $r['wires'] === []);

// 6. kill switch STOBE_TRIP_RESUME_LOCAL_ENABLED=0 restores today's behaviour for landmarks only
set_setting('STOBE_TRIP_RESUME_LOCAL_ENABLED', '0');
[$F, $Fs] = tr_actor(); wl_seed($F, $Fs);
$r = tr_turn($F, $Fs, 1100, ['live'=>true]);
tr_expect_failed('local resume disabled by setting', $r);
[$F2, $F2s] = tr_actor(); tr_seed($F2, $F2s);
tr_turn($F2, $F2s, 1100, ['live'=>false]);
$r = tr_turn($F2, $F2s, 1200, ['live'=>true]);
check('local resume disabled: a visited_location trip still resumes', count($r['wires']) === 1 && tr_phase($r['state']) === 'requested');
set_setting('STOBE_TRIP_RESUME_LOCAL_ENABLED', '1');

// 7. visited_location trips unchanged (stored zone, candidate_id empty, same plan hash)
[$G, $Gs] = tr_actor(); $seedG = tr_seed($G, $Gs);
tr_turn($G, $Gs, 1100, ['live'=>false]);
$r = tr_turn($G, $Gs, 1200, ['live'=>true]);
$w = $r['wires'][0] ?? [];
check('visited_location unchanged: one wire, same plan_hash, stored x/y/z, empty candidate_id', count($r['wires']) === 1
    && ($w['plan_hash'] ?? '') === $seedG['plan_hash'] && tr_same_xyz($w) && ($w['candidate_id'] ?? 'x') === '', $r['wires']);

echo "imm26_wpL_landmark_resume: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
