<?php
// imm26-wpR1: Hunt / Mine / ClearGroup (camp zone) activities and pending offers survive a save/load (new native epoch = new world_id).
// Offline: real ActivityStore + real adapter on TEMP tables in stobe_test (nothing persists). Run:
//   STOBE_DB_NAME=stobe_test php tests/imm26_wpR1_activity_resume_regression.php   (flock /tmp/stobe-tests.lock)
// Fails BEFORE the patch (lib/activity/ActivityResume.php missing), passes after.
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 700) : '') . "\n"; }
}
if (!is_file(__DIR__ . '/../lib/activity/ActivityResume.php')) {
    echo "FAIL activity resume is not installed (lib/activity/ActivityResume.php missing): an accepted activity is orphaned by a save/load\n";
    echo "imm26_wpR1_activity_resume: 0 passed, 1 failed\n"; exit(1);
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/activity/ActivityStore.php';
require_once __DIR__ . '/../lib/activity/ActivityResume.php';
$db = $GLOBALS['db'];

// temp copies of the activity tables (schema.sql), dropped with the connection
foreach (['stobe_activity_outbox', 'stobe_activity_record'] as $t) $db->exec("DROP TABLE IF EXISTS pg_temp.$t");
$db->exec("CREATE TEMP TABLE stobe_activity_record (id text PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, requester bigint NOT NULL, revision integer NOT NULL, record jsonb NOT NULL)");
$db->exec("CREATE UNIQUE INDEX stobe_activity_one_active_actor ON stobe_activity_record(world_id,actor) WHERE record->>'status' IN ('proposed','accepted')");
$db->exec("CREATE TEMP TABLE stobe_activity_outbox (sequence bigserial PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, agreement_id text NOT NULL REFERENCES stobe_activity_record(id), revision integer NOT NULL, envelope jsonb NOT NULL, acknowledged boolean NOT NULL DEFAULT false, UNIQUE(agreement_id,revision))");
$store = new \Stobe\Activity\ActivityStore($db);

const HUNT_SRC = '1531903-Swamp Animal Traders.mod'; const HUNT_RES = '42241-rebirth.mod';
const MINE_SRC = '1509-gamedata.base';               const MINE_RES = '1515-gamedata.base';
const PLAYER = 9001;
const W1 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1'; const W2 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2'; const W3 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3';
$GLOBALS['NEXT_ACTOR'] = 100;
function new_actor(): int { return ++$GLOBALS['NEXT_ACTOR']; }

function cand(string $kind, string $src, string $res, int $serial, string $id, array $targets = [], ?array $camp = null): array {
    $c = ['kind'=>$kind, 'sourceId'=>$src, 'resourceId'=>$res, 'targetSerial'=>$serial, 'candidateId'=>$id, 'pathReachable'=>true, 'observedNow'=>true,
          'suitable'=>true, 'activityPermitted'=>true, 'protectedTarget'=>false, 'hostile'=>false, 'conflictingOrder'=>false,
          'x'=>1000.0, 'y'=>10.0, 'z'=>2000.0, 'agreedTargets'=>$targets];
    if ($camp) $c['campZone'] = $camp;
    return $c;
}
function facts(string $world, int $actor, array $cands): array { return ['worldId'=>$world, 'actor'=>$actor, 'requester'=>PLAYER, 'candidates'=>$cands]; }
function route(int $actor, string $id, string $label, float $x, float $y, float $z, string $kind = 'landmark'): array {
    return ['id'=>$id, 'label'=>$label, 'actor_serial'=>$actor, 'kind'=>$kind, 'source'=>'native_local', 'x'=>$x, 'y'=>$y, 'z'=>$z];
}
function ctx(string $world, int $actor, int $now): array { return ['worldId'=>$world, 'actor'=>$actor, 'requester'=>PLAYER, 'now'=>$now]; }
function req(string $world, int $actor, int $now, array $cands, array $routes, bool $willing = true): array {
    $f = facts($world, $actor, $cands); $f['npcWilling'] = $willing;
    return ['context'=>ctx($world, $actor, $now), 'nativeFacts'=>$f, 'routeCandidates'=>$routes];
}
/** Propose (and optionally accept) an activity in epoch $world through the real adapter and store, exactly as the chat pipeline does. */
function make_job(\Stobe\Activity\ActivityStore $store, string $world, int $actor, int $now, string $kind, bool $accept, array $o = []): array {
    $src = $o['src'] ?? ($kind === 'Mine' ? MINE_SRC : HUNT_SRC); $res = $kind === 'ClearGroup' ? '' : ($o['res'] ?? ($kind === 'Mine' ? MINE_RES : HUNT_RES));
    $targets = $o['targets'] ?? []; $camp = $o['camp'] ?? null;
    $cand = cand($kind, $src, $res, $o['serial'] ?? 5001, $o['cid'] ?? 'activity-proposal:1:1', $targets, $camp);
    $rt = [route($actor, $o['rid'] ?? 'local:s1:1', 'higher ground to the east', 4000.0, 20.0, 6000.0)];
    $request = req($world, $actor, $now, [$cand], $rt);
    $adapter = stobeActivityAdapter($request);
    $intent = ['kind'=>$kind, 'sourceId'=>$src, 'resourceId'=>$res, 'quantity'=>$kind === 'ClearGroup' ? 0 : 3,
        'discoveryRef'=>['candidateId'=>$cand['candidateId'], 'targetSerial'=>$cand['targetSerial']], 'agreedTargets'=>$targets,
        'routeRef'=>['candidateId'=>$rt[0]['id']]];
    if ($camp) $intent['campZoneRef'] = $camp;
    $proposal = $adapter->propose($request['context'], $intent);
    $store->transaction(static function() use ($store, $proposal): void { $store->propose($proposal); });
    if (!$accept) return $proposal;
    $evidence = ['origin'=>'native_player_chat', 'worldId'=>$world, 'actor'=>$actor, 'requester'=>PLAYER, 'proposalId'=>$proposal['agreement']['id'],
        'revision'=>$proposal['revision'], 'scopeDigest'=>$proposal['scopeDigest'], 'proposalWasDisplayed'=>true, 'playerText'=>'yes', 'quotedText'=>'yes'];
    $transition = $adapter->accept(ctx($world, $actor, $now + 5), $proposal, $evidence);
    return $store->transaction(static fn() => $store->commit($transition, bin2hex(random_bytes(16))));
}
function row(string $id): ?array {
    $r = $GLOBALS['db']->fetchOne('SELECT world_id, record FROM stobe_activity_record WHERE id=$1', [$id]);
    return $r ? ['world'=>$r['world_id']] + json_decode($r['record'], true) : null;
}
function outbox(string $world): array {
    $r = $GLOBALS['db']->fetchAll('SELECT sequence, agreement_id, revision, envelope FROM stobe_activity_outbox WHERE world_id=$1 ORDER BY sequence', [$world]);
    return array_map(static fn($x) => ['id'=>$x['agreement_id'], 'revision'=>(int)$x['revision']] + json_decode($x['envelope'], true), is_array($r) ? $r : []);
}
function sweep(\Stobe\Activity\ActivityStore $store, string $world, int $now): array {
    $ended = [];
    $store->transaction(static function() use ($store, $world, $now, &$ended): void { stobeActivityResumeSweep($store, ['worldId'=>$world, 'now'=>$now], $ended); });
    return $ended;
}
function chat(\Stobe\Activity\ActivityStore $store, array $request, array &$ended = []): ?array {
    return $store->transaction(static function() use ($store, $request, &$ended): ?array { return stobeActivityResumeForChat($store, $request, $ended); });
}
function set_env(array $kv): void { foreach (['STOBE_ACTIVITY_RESUME_ENABLED', 'STOBE_ACTIVITY_RESUME_MAX_COUNT', 'STOBE_ACTIVITY_RESUME_MAX_AGE_GAMETS', 'STOBE_ACTIVITY_RESUME_ROUTE_RADIUS'] as $k) putenv($k); foreach ($kv as $k => $v) putenv("$k=$v"); }
set_env([]);
/** The digest and identity of a resumed record are valid in the new epoch: the real cancel path accepts it. */
function cancel_ok(array $record, string $world, int $actor, int $now): bool {
    $adapter = stobeActivityAdapter(req($world, $actor, $now, [], []));
    $evidence = ['origin'=>'native_player_chat', 'worldId'=>$world, 'actor'=>$actor, 'requester'=>PLAYER, 'proposalId'=>$record['agreement']['id'],
        'revision'=>$record['revision'], 'scopeDigest'=>$record['scopeDigest'], 'proposalWasDisplayed'=>true, 'playerText'=>'cancel', 'quotedText'=>'cancel'];
    try { $t = $adapter->cancel(ctx($world, $actor, $now), $record, $evidence); return $t['record']['status'] === 'cancelled'; }
    catch (Throwable $e) { return false; }
}

// ======================================================================================================================
// 1. accepted Hunt survives an epoch change: sweep marks it pending, the next chat turn re-grants it under a NEW id in W2
// ======================================================================================================================
$A = new_actor();
$job = make_job($store, W1, $A, 1000, 'Hunt', true);
check('seed: accepted in W1, grant in the W1 outbox', $job['status'] === 'accepted' && count(outbox(W1)) === 1 && outbox(W1)[0]['operation'] === 'grant', $job['status']);
check('seed: before the sweep the new epoch sees nothing (the bug: orphaned record)', $store->active(W2) === [] && row($job['agreement']['id'])['world'] === W1);
$ended = sweep($store, W2, 1100);
$r0 = row($job['agreement']['id']);
check('sweep: still accepted, marked resume.state=pending (not ended, not re-granted blind)', $r0['status'] === 'accepted' && ($r0['resume']['state'] ?? '') === 'pending'
    && $ended === [] && outbox(W2) === [], $r0['resume'] ?? null);
$ended = sweep($store, W2, 1105);
check('sweep: idempotent on the next poll (revision unchanged)', row($job['agreement']['id'])['revision'] === $r0['revision']);
$req = req(W2, $A, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:7')], [route($A, 'local:s2:44', 'a rise to the east', 4010.0, 20.0, 6005.0)]);
$ended = [];
$new = chat($store, $req, $ended);
check('chat: resumed record active in W2', is_array($new) && $new['status'] === 'accepted' && $new['agreement']['worldId'] === W2
    && $new['routeRef']['worldId'] === W2 && $new['routeRef']['candidateId'] === 'local:s2:44' && $new['discoveryRef']['candidateId'] === 'activity-proposal:9:7', $new['agreement'] ?? null);
check('chat: continuation id differs from the old id (the DLL revokes old ids for good); terms identical', $new['agreement']['id'] !== $job['agreement']['id']
    && $new['agreement']['kind'] === 'Hunt' && $new['agreement']['sourceId'] === HUNT_SRC && $new['agreement']['resourceId'] === HUNT_RES
    && $new['agreement']['quantity'] === 3 && $new['agreement']['expiresAt'] === $job['agreement']['expiresAt'] && $new['acceptedAt'] === $job['acceptedAt']);
$ob = outbox(W2);
check('outbox: exactly one fresh grant for the new id under W2 with the new digest/revision/route', count($ob) === 1 && $ob[0]['operation'] === 'grant'
    && $ob[0]['id'] === $new['agreement']['id'] && $ob[0]['agreement']['worldId'] === W2 && $ob[0]['scopeDigest'] === $new['scopeDigest']
    && $ob[0]['revision'] === 2 && $ob[0]['routeRef']['candidateId'] === 'local:s2:44' && $ob[0]['protocol'] === 'stobe.activity.v2', $ob);
$old = row($job['agreement']['id']);
check('old record: superseded (chain kept), no longer active anywhere', $old['status'] === 'superseded' && ($old['resume']['continuedAs'] ?? '') === $new['agreement']['id']
    && $store->staleActive(W2, $A, PLAYER) === [] && count($store->active(W2)) === 1);
check('resumed record: resume block (count 1, of=old id) and a valid digest/identity for the real cancel path', ($new['resume']['count'] ?? 0) === 1
    && ($new['resume']['of'] ?? '') === $job['agreement']['id'] && cancel_ok($new, W2, $A, 1200));
// the second chat turn finds the record in W2 directly: nothing is re-granted
check('chat: nothing stale remains, so a later turn does not re-grant', chat($store, $req) === null && count(outbox(W2)) === 1);

// ======================================================================================================================
// 2. pending offer: a PROPOSED offer is moved to the new epoch (same id), nothing is granted
// ======================================================================================================================
$B = new_actor();
$prop = make_job($store, W1, $B, 1000, 'Mine', false);
sweep($store, W2, 1100);
$req = req(W2, $B, 1110, [cand('Mine', MINE_SRC, MINE_RES, 5001, 'activity-proposal:9:8')], [route($B, 'local:s2:50', 'a ridge', 4001.0, 20.0, 6001.0)]);
$moved = chat($store, $req);
$rb = row($prop['agreement']['id']);
check('proposal: same agreement id now bound to W2 (DB world_id, agreement, route) and still proposed', is_array($moved) && $moved['agreement']['id'] === $prop['agreement']['id']
    && $rb['world'] === W2 && $moved['status'] === 'proposed' && $moved['agreement']['worldId'] === W2 && $moved['revision'] === $prop['revision'] + 1, [$rb['world'], $moved['status'] ?? null]);
check('proposal: re-grounded refs are the fresh ones and no grant was written for it (only job 1 has an outbox row)', $moved['discoveryRef']['candidateId'] === 'activity-proposal:9:8'
    && count(array_filter(outbox(W2), static fn($x) => $x['id'] === $prop['agreement']['id'])) === 0);
check('proposal: deadline unchanged and chat record lookup (world+actor+requester) finds it', $moved['proposalExpiresAt'] === $prop['proposalExpiresAt']
    && $db->fetchOne("SELECT id FROM stobe_activity_record WHERE world_id=$1 AND actor=$2 AND requester=$3 AND record->>'status' IN ('proposed','accepted')", [W2, $B, PLAYER])['id'] === $prop['agreement']['id']);

// ======================================================================================================================
// 3. ClearGroup with a camp zone: scope (fixed targets + zone) must be re-observed exactly
// ======================================================================================================================
$camp = ['candidateId'=>'v1:' . str_repeat('a', 48), 'scopeDigest'=>str_repeat('b', 64)];
$C = new_actor();
$cg = make_job($store, W1, $C, 1000, 'ClearGroup', true, ['src'=>'camp-threats', 'targets'=>[303, 404], 'camp'=>$camp, 'serial'=>303]);
sweep($store, W2, 1100);
$wrong = req(W2, $C, 1110, [cand('ClearGroup', 'camp-threats', '', 303, 'activity-proposal:9:9', [303, 405], $camp)], [route($C, 'local:s2:60', 'camp gate', 4000.0, 20.0, 6000.0)]);
check('camp: a changed fixed-target set is NOT resumed (stays pending, nothing granted)', chat($store, $wrong) === null && row($cg['agreement']['id'])['status'] === 'accepted');
$otherZone = req(W2, $C, 1112, [cand('ClearGroup', 'camp-threats', '', 303, 'activity-proposal:9:9', [303, 404], ['candidateId'=>'v1:' . str_repeat('c', 48), 'scopeDigest'=>str_repeat('b', 64)])], [route($C, 'local:s2:60', 'camp gate', 4000.0, 20.0, 6000.0)]);
check('camp: a different camp zone is NOT resumed', chat($store, $otherZone) === null);
$right = req(W2, $C, 1115, [cand('ClearGroup', 'camp-threats', '', 303, 'activity-proposal:9:9', [303, 404], $camp)], [route($C, 'local:s2:60', 'camp gate', 4000.0, 20.0, 6000.0)]);
$cn = chat($store, $right);
$obC = array_values(array_filter(outbox(W2), static fn($x) => $x['id'] === ($cn['agreement']['id'] ?? '')));
check('camp: same targets + zone resume; zone, targets and scopeVersion 3 ride in the new grant', is_array($cn) && $cn['agreement']['campZone'] === $camp
    && $cn['agreement']['agreedTargets'] === [303, 404] && $cn['agreement']['scopeVersion'] === 3 && count($obC) === 1
    && $obC[0]['agreement']['campZone'] === $camp && $obC[0]['agreement']['agreedTargets'] === [303, 404], $obC);

// ======================================================================================================================
// 4. transient: target / route not observed now keeps the job pending; it resumes on a later turn; far route is refused
// ======================================================================================================================
$D = new_actor();
$dj = make_job($store, W1, $D, 1000, 'Hunt', true);
sweep($store, W2, 1100);
check('transient: no candidates in view -> pending, no grant', chat($store, req(W2, $D, 1110, [], [route($D, 'local:s2:70', 'x', 4000.0, 20.0, 6000.0)])) === null && row($dj['agreement']['id'])['status'] === 'accepted');
check('transient: target in view but the nearest route point is beyond the radius -> pending', chat($store, req(W2, $D, 1112,
    [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:10')], [route($D, 'local:s2:71', 'far away', 90000.0, 20.0, 90000.0)])) === null);
check('transient: another source (different animal template) is not accepted', chat($store, req(W2, $D, 1113,
    [cand('Hunt', 'other-animal.mod', HUNT_RES, 5001, 'activity-proposal:9:11')], [route($D, 'local:s2:72', 'near', 4000.0, 20.0, 6000.0)])) === null);
$dn = chat($store, req(W2, $D, 1120, [cand('Hunt', HUNT_SRC, HUNT_RES, 5099, 'activity-proposal:9:12')], [route($D, 'local:s2:73', 'a different rise', 4100.0, 20.0, 6050.0)]));
check('transient: later turn with another animal of the same source and a nearby route point resumes it', is_array($dn) && $dn['discoveryRef']['targetSerial'] === 5099
    && $dn['routeRef']['candidateId'] === 'local:s2:73' && ($dn['resume']['count'] ?? 0) === 1);
check('route: when the old waypoint is gone the point nearest the fresh source stands in (beyond-radius old route)', (function () use ($store) {
    $E = new_actor(); $j = make_job($store, W1, $E, 1000, 'Hunt', true); sweep($store, W2, 1100);
    $far = route($E, 'local:s2:80', 'new camp spot', 1010.0, 10.0, 2010.0);               // near the fresh source (1000,10,2000), far from the old route (4000,20,6000)
    set_env(['STOBE_ACTIVITY_RESUME_ROUTE_RADIUS' => '100']);
    $n = chat($store, req(W2, $E, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:13')], [$far]));
    set_env([]);
    return is_array($n) && $n['routeRef']['candidateId'] === 'local:s2:80';
})());

// ======================================================================================================================
// 5. never revived: terminal records stay terminal, with or without facts
// ======================================================================================================================
$F = new_actor();
$done = make_job($store, W1, $F, 1000, 'Hunt', true);
foreach (['completed', 'failed', 'cancelled', 'expired', 'superseded'] as $i => $terminal) {
    $rec = row($done['agreement']['id']); unset($rec['world']); $rec['status'] = $terminal; $rec['revision']++;
    $db->exec('UPDATE stobe_activity_record SET revision=$1, record=$2::jsonb WHERE id=$3', [$rec['revision'], json_encode($rec), $done['agreement']['id']]);
    $before = count(outbox(W2));
    $e1 = sweep($store, W2, 1100);
    $c1 = chat($store, req(W2, $F, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:20')], [route($F, 'local:s2:90', 'a', 4000.0, 20.0, 6000.0)]));
    check("terminal $terminal: not swept, not resumed, no grant", $e1 === [] && $c1 === null && count(outbox(W2)) === $before && row($done['agreement']['id'])['status'] === $terminal);
}

// ======================================================================================================================
// 6. cap, expiry, rollback, age: each ends cleanly (no 'accepted' forever); only a really agreed job gets a history row
// ======================================================================================================================
// 6a cap: count already at the cap -> failed / interrupted_by_load
$G = new_actor(); $gj = make_job($store, W1, $G, 1000, 'Hunt', true);
$rec = row($gj['agreement']['id']); unset($rec['world']); $rec['resume'] = ['count' => 3, 'interruptedAt' => 1000, 'state' => 'pending', 'fromWorld' => W1];
$db->exec('UPDATE stobe_activity_record SET record=$1::jsonb WHERE id=$2', [json_encode($rec), $gj['agreement']['id']]);
$ended = [];
$res = chat($store, req(W2, $G, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:30')], [route($G, 'local:s2:91', 'a', 4000.0, 20.0, 6000.0)]), $ended);
$rg = row($gj['agreement']['id']);
check('cap: resume count at the cap -> ended failed / interrupted_by_load, not resumed, history row requested', $res === null && $rg['status'] === 'failed'
    && ($rg['failureReason'] ?? '') === 'interrupted_by_load' && count($ended) === 1 && $ended[0]['status'] === 'failed' && ($rg['resume']['why'] ?? '') === 'resume_count', $rg['resume'] ?? null);
check('cap: the outcome text for the NPC mentions the interruption', str_contains(strval(stobeActivityOutcomeText($rg)), 'save and load'), stobeActivityOutcomeText($rg));
// 6b below the raised cap it still resumes
set_env(['STOBE_ACTIVITY_RESUME_MAX_COUNT' => '5']);
$G2 = new_actor(); $g2 = make_job($store, W1, $G2, 1000, 'Hunt', true);
$rec = row($g2['agreement']['id']); unset($rec['world']); $rec['resume'] = ['count' => 3, 'interruptedAt' => 1000, 'state' => 'pending', 'fromWorld' => W1];
$db->exec('UPDATE stobe_activity_record SET record=$1::jsonb WHERE id=$2', [json_encode($rec), $g2['agreement']['id']]);
$n2 = chat($store, req(W2, $G2, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:31')], [route($G2, 'local:s2:92', 'a', 4000.0, 20.0, 6000.0)]));
check('cap: STOBE_ACTIVITY_RESUME_MAX_COUNT=5 lets count 3 resume (count becomes 4)', is_array($n2) && $n2['resume']['count'] === 4, $n2['resume'] ?? null);
set_env([]);
// 6c expiry of an accepted job (deadline = accept time + 21600)
$H = new_actor(); $hj = make_job($store, W1, $H, 1000, 'Hunt', true);
$ended = sweep($store, W2, $hj['agreement']['expiresAt'] + 5);
$rh = row($hj['agreement']['id']);
check('expiry: accepted job past its deadline -> expired / expired, history row requested', $rh['status'] === 'expired' && ($rh['failureReason'] ?? '') === 'expired' && count($ended) === 1);
// 6d an unanswered offer past its proposal deadline: expired quietly (no history row for a job nobody agreed to)
$I = new_actor(); $ij = make_job($store, W1, $I, 1000, 'Hunt', false);
$ended = sweep($store, W2, $ij['proposalExpiresAt'] + 1);
check('expiry: offer past proposalExpiresAt -> expired, no history row', row($ij['agreement']['id'])['status'] === 'expired' && $ended === []);
// 6e loading an EARLIER timeline: the job was never agreed there
$J = new_actor(); $jj = make_job($store, W1, $J, 5000, 'Hunt', true);
$ended = sweep($store, W2, 4000);
check('rollback: now < record time -> cancelled quietly (timeline_rollback), no history, not resumed', row($jj['agreement']['id'])['status'] === 'cancelled' && $ended === []
    && (row($jj['agreement']['id'])['resume']['why'] ?? '') === 'timeline_rollback');
// 6f too long since the load
$K = new_actor(); $kj = make_job($store, W1, $K, 1000, 'Hunt', true);
sweep($store, W2, 1100);
$ended = sweep($store, W3, 1100 + 7201);
check('age: still pending 7200+ game seconds after the load -> failed / interrupted_by_load', row($kj['agreement']['id'])['status'] === 'failed' && (row($kj['agreement']['id'])['resume']['why'] ?? '') === 'too_old'
    && count(array_filter($ended, static fn(array $e): bool => $e['agreement']['id'] === $kj['agreement']['id'])) === 1);
// 6g legacy protocol v1 record cannot be re-grounded -> ended, not orphaned
$L = new_actor(); $lj = make_job($store, W1, $L, 1000, 'Hunt', true);
$rec = row($lj['agreement']['id']); unset($rec['world']); $rec['protocol'] = 'stobe.activity.v1'; unset($rec['routeRef']);
$db->exec('UPDATE stobe_activity_record SET record=$1::jsonb WHERE id=$2', [json_encode($rec), $lj['agreement']['id']]);
$ended = sweep($store, W2, 1100);
check('legacy v1 record: ended failed (no routeRef to re-ground)', row($lj['agreement']['id'])['status'] === 'failed' && count($ended) === 1);

// ======================================================================================================================
// 7. kill switch STOBE_ACTIVITY_RESUME_ENABLED=0: today's behaviour exactly (record untouched, nothing granted)
// ======================================================================================================================
set_env(['STOBE_ACTIVITY_RESUME_ENABLED' => '0']);
$M = new_actor(); $mj = make_job($store, W1, $M, 1000, 'Hunt', true); $obBefore = count(outbox(W2));
$e = sweep($store, W2, 1100);
$rm = chat($store, req(W2, $M, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:40')], [route($M, 'local:s2:95', 'a', 4000.0, 20.0, 6000.0)]));
check('kill switch off: sweep and chat do nothing; record stays as it was; no grant', $e === [] && $rm === null && count(outbox(W2)) === $obBefore
    && row($mj['agreement']['id'])['status'] === 'accepted' && !isset(row($mj['agreement']['id'])['resume']) && row($mj['agreement']['id'])['world'] === W1);
check('kill switch off: getSetting-style values parse (0/false/off all disable)', (function () {
    foreach (['0', 'false', 'off', 'no'] as $v) { set_env(['STOBE_ACTIVITY_RESUME_ENABLED' => $v]); if (stobeActivityResumeEnabled()) return false; }
    set_env([]); return stobeActivityResumeEnabled();
})());
set_env([]);
$rm = chat($store, req(W2, $M, 1120, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:41')], [route($M, 'local:s2:96', 'a', 4000.0, 20.0, 6000.0)]));
check('kill switch back on: the same orphan now resumes', is_array($rm) && $rm['agreement']['worldId'] === W2);

// ======================================================================================================================
// 8. conflicts: a new activity already running in this epoch wins; duplicates collapse; second load resumes again with the chain intact
// ======================================================================================================================
$N = new_actor(); $nj = make_job($store, W1, $N, 1000, 'Hunt', true);
$newer = make_job($store, W2, $N, 1050, 'Mine', true, ['cid' => 'activity-proposal:5:5', 'rid' => 'local:s2:97']);
sweep($store, W2, 1100);
check('conflict: a new accepted activity in W2 supersedes the stale one (no double job, no unique-index crash)', row($nj['agreement']['id'])['status'] === 'superseded'
    && row($newer['agreement']['id'])['status'] === 'accepted' && count($store->staleActive(W2, $N, PLAYER)) === 0);
$O = new_actor();
$o1 = make_job($store, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1', $O, 900, 'Hunt', true);
$o2 = make_job($store, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2', $O, 1000, 'Mine', true);
sweep($store, W2, 1100);
check('duplicates: two stale records of one actor collapse to the newest', row($o1['agreement']['id'])['status'] === 'superseded' && row($o2['agreement']['id'])['status'] === 'accepted'
    && (row($o2['agreement']['id'])['resume']['state'] ?? '') === 'pending');
// second load of a resumed job: W2 -> W3
$P = new_actor(); $pj = make_job($store, W1, $P, 1000, 'Hunt', true); sweep($store, W2, 1100);
$p2 = chat($store, req(W2, $P, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:50')], [route($P, 'local:s2:98', 'a', 4000.0, 20.0, 6000.0)]));
sweep($store, W3, 1300);
$p3 = chat($store, req(W3, $P, 1310, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:12:3')], [route($P, 'local:s3:1', 'a', 4000.0, 20.0, 6000.0)]));
check('second load: resumes again, count 2, chain points at the original id, grant in the W3 outbox', is_array($p3) && $p3['resume']['count'] === 2
    && $p3['resume']['of'] === $pj['agreement']['id'] && $p3['agreement']['id'] !== $p2['agreement']['id'] && count(array_filter(outbox(W3), static fn($x) => $x['id'] === $p3['agreement']['id'])) === 1);

// ======================================================================================================================
// 9. wiring (the endpoint and the chat begin call the new code at the right place)
// ======================================================================================================================
$act = file_get_contents(__DIR__ . '/../activity.php'); $chat = file_get_contents(__DIR__ . '/../lib/activity/ActivityChat.php');
check('wiring: activity.php sweeps older epochs before the active() loop and records history for ended jobs', strpos($act, 'stobeActivityResumeSweep') !== false
    && strpos($act, 'stobeActivityResumeSweep') < strpos($act, "foreach (\$store->active(") && strpos($act, 'foreach ($resumeEnded as') !== false);
check('wiring: ActivityChat resumes (inside a transaction) before the offer is put in the prompt', strpos($chat, 'stobeActivityResumeForChat') !== false
    && strpos($chat, 'stobeActivityResumeForChat') < strpos($chat, 'stobeActivityAppendDynamicTail($messages'));

echo "imm26_wpR1_activity_resume: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
