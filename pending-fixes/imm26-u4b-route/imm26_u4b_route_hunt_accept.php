<?php
// imm26-u4b (rows 26-a/22-a/26-b/26-c): after u4a the Hunt ACCEPT grounds the target, but accept also re-resolves the persisted ROUTE
// candidate by exact id/label/coords, and native re-emits every local route row with a NEW counter id (label/coords shift) each snapshot.
// Pure: real adapter + real stobeActivityAdapter, no database. Fails before the patch (case A), passes after.
//   php tests/imm26_u4b_route_hunt_accept.php
declare(strict_types=1);
set_exception_handler(function (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), ' @', basename($e->getFile()), ':', $e->getLine(), "\n"; exit(1); });
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 500) : '') . "\n"; }
}
require_once __DIR__ . '/../lib/activity/ActivityAgreementAdapter.php';
require_once __DIR__ . '/../lib/activity/ActivityService.php';
const HUNT_SRC = '1531903-Swamp Animal Traders.mod'; const HUNT_RES = '42241-rebirth.mod';
const MINE_SRC = '1509-gamedata.base'; const MINE_RES = '1515-gamedata.base';
const PLAYER = 9001; const ACTOR = 2232299776; const W = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1';
const NOROUTE = 'No currently grounded route candidate';
const NOGROUND = 'No currently grounded suitable activity target';
function cand(string $kind, string $src, string $res, int $serial, string $id, array $over = []): array {
    return $over + ['kind'=>$kind, 'sourceId'=>$src, 'resourceId'=>$res, 'targetSerial'=>$serial, 'candidateId'=>$id, 'pathReachable'=>true, 'observedNow'=>true,
        'suitable'=>true, 'activityPermitted'=>true, 'protectedTarget'=>false, 'hostile'=>false, 'conflictingOrder'=>false,
        'x'=>1000.0, 'y'=>10.0, 'z'=>2000.0, 'agreedTargets'=>[]];
}
function route(string $id, string $label, float $x, float $y, float $z, array $over = []): array {
    return $over + ['id'=>$id, 'label'=>$label, 'actor_serial'=>ACTOR, 'kind'=>'landmark', 'source'=>'native_local', 'x'=>$x, 'y'=>$y, 'z'=>$z];
}
function req(array $cands, array $routes, array $over = [], bool $willing = true): array {
    return ['context'=>['worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'now'=>1000],
        'nativeFacts'=>$over + ['worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'npcWilling'=>$willing, 'candidates'=>$cands], 'routeCandidates'=>$routes];
}
function propose(array $cands, array $routes, array $ref, string $kind = 'Hunt'): array {
    $src = $kind === 'Mine' ? MINE_SRC : HUNT_SRC; $res = $kind === 'Mine' ? MINE_RES : HUNT_RES;
    $r = req($cands, $routes);
    return stobeActivityAdapter($r)->propose($r['context'], ['kind'=>$kind, 'sourceId'=>$src, 'resourceId'=>$res, 'quantity'=>1,
        'discoveryRef'=>$ref, 'agreedTargets'=>[], 'routeRef'=>['candidateId'=>'local:s1:1']]);
}
function accept(array $proposal, array $request, int $now = 1005) {
    $text = "Yes, let's do it.";
    $e = ['origin'=>'native_player_chat', 'worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'proposalId'=>$proposal['agreement']['id'],
        'revision'=>$proposal['revision'], 'scopeDigest'=>$proposal['scopeDigest'], 'proposalWasDisplayed'=>true, 'playerText'=>$text, 'quotedText'=>$text];
    $c = $request['context']; $c['now'] = $now;
    try { return stobeActivityAdapter($request)->accept($c, $proposal, $e); } catch (Throwable $t) { return $t->getMessage(); }
}
$goatA = cand('Hunt', HUNT_SRC, HUNT_RES, 396362304, 'activity-proposal:2232299776:76');
$R1 = route('local:s1:1', 'near Goat to the west', 1200.0, 10.0, 2100.0);
$P = propose([$goatA], [$R1], ['candidateId'=>$goatA['candidateId'], 'targetSerial'=>$goatA['targetSerial']]);
check('seed: Hunt proposed with route R1', $P['status'] === 'proposed' && $P['routeRef']['label'] === 'near Goat to the west', $P['status'] ?? null);

// Goat A wandered off; goat B is observed 100 units away. Native re-emitted the route rows with NEW ids and labels.
$goatB = cand('Hunt', HUNT_SRC, HUNT_RES, 396362999, 'activity-proposal:2232299776:81', ['x'=>1100.0, 'z'=>2050.0]);
$fresh = [route('local:s1:20103', 'near Goat to the south', 1150.0, 10.0, 2120.0),
          route('local:s1:20104', 'near Camp to the east', 9000.0, 10.0, 9000.0)];

// A. the bug
$t = accept($P, req([$goatB], $fresh));
check('A1: accept re-binds the route to the fresh row near the (re-grounded) goat and is accepted', is_array($t) && $t['record']['status'] === 'accepted', $t);
if (is_array($t)) {
    check('A2: stored record/digest/routeRef not rewritten (native consent matches the digest)',
        $t['record']['routeRef'] === $P['routeRef'] && $t['record']['scopeDigest'] === $P['scopeDigest'] && $t['envelope']['routeRef'] === $P['routeRef']);
}
// B. regression: exact same route still emitted -> accepted (exact path unchanged)
check('B1: same route row still emitted, other goat -> accepted', is_array(accept($P, req([$goatB], [$R1]))));
check('B2: same goat and same route -> accepted', is_array(accept($P, req([$goatA], [$R1]))));
// C. negatives
check('C1: no route candidates at all -> rejected', accept($P, req([$goatB], [])) === NOROUTE);
check('C2: only a route far from the stored one (other target area) -> rejected',
    accept($P, req([$goatB], [route('local:s1:9', 'near Goat to the north', 9000.0, 10.0, 9000.0)])) === NOROUTE);
check('C3: route near the stored one but far from every grounded goat -> rejected',
    accept($P, req([cand('Hunt', HUNT_SRC, HUNT_RES, 396362999, 'activity-proposal:2232299776:81', ['x'=>20000.0, 'z'=>20000.0])], $fresh)) === NOROUTE);
check('C4: fresh route of another kind -> rejected', accept($P, req([$goatB], [route('local:s1:5', 'near Goat to the south', 1150.0, 10.0, 2120.0, ['kind'=>'town'])])) === NOROUTE);
check('C5: fresh route owned by another actor -> rejected', accept($P, req([$goatB], [route('local:s1:5', 'near Goat to the south', 1150.0, 10.0, 2120.0, ['actor_serial'=>ACTOR + 1])])) === NOROUTE);
check('C6: fresh route not native_local -> rejected', accept($P, req([$goatB], [route('local:s1:5', 'near Goat to the south', 1150.0, 10.0, 2120.0, ['source'=>'catalog'])])) === NOROUTE);
check('C7: fresh route without coordinates -> rejected', accept($P, req([$goatB], [['id'=>'local:s1:5','label'=>'near Goat to the south','actor_serial'=>ACTOR,'kind'=>'landmark','source'=>'native_local']])) === NOROUTE);
check('C8: goat candidate without coordinates cannot anchor a re-bind -> rejected',
    accept($P, req([cand('Hunt', HUNT_SRC, HUNT_RES, 77, 'x:1', ['x'=>null, 'y'=>null, 'z'=>null])], $fresh)) === NOROUTE);
foreach ([['suitable',false],['protectedTarget',true],['conflictingOrder',true],['pathReachable',false],['observedNow',false]] as [$k,$v]) {
    check("C9: only goat with $k=" . json_encode($v) . ' -> rejected (target check still applies)',
        accept($P, req([cand('Hunt', HUNT_SRC, HUNT_RES, 77, 'x:2', [$k=>$v, 'x'=>1100.0])], $fresh)) === NOGROUND);
}
check('C10: other requester -> rejected', !is_array(accept($P, req([$goatB], $fresh, ['requester'=>PLAYER + 1]))));
check('C11: NPC unwilling -> rejected', !is_array(accept($P, req([$goatB], $fresh, [], false))));
check('C12: expired offer -> rejected even with a good route', !is_array(accept($P, req([$goatB], $fresh), 1000 + 1801)));
// D. propose keeps the exact route rule (a model-chosen id not in the current rows is never re-bound)
try { propose([$goatA], $fresh, ['candidateId'=>$goatA['candidateId'], 'targetSerial'=>$goatA['targetSerial']]); check('D1: propose with a route id not in the rows -> rejected', false); }
catch (Throwable $e) { check('D1: propose with a route id not in the rows -> rejected', $e->getMessage() === NOROUTE, $e->getMessage()); }
// E. Mine keeps the exact route rule at accept
$mineA = cand('Mine', MINE_SRC, MINE_RES, 4001, 'activity-proposal:2232299776:5');
$PM = propose([$mineA], [$R1], ['candidateId'=>$mineA['candidateId'], 'targetSerial'=>4001], 'Mine');
check('E1: Mine accept with the same route -> accepted', is_array(accept($PM, req([$mineA], [$R1]))));
check('E2: Mine accept with only a re-id route -> still rejected (relaxation is Hunt only)', accept($PM, req([$mineA], $fresh)) === NOROUTE);
echo "imm26_u4b_route_hunt_accept: $pass passed, $fail failed\n";
exit($fail ? 1 : 0);
