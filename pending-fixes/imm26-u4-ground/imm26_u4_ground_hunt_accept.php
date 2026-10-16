<?php
// imm26-u4 (rows 26-a/22-a/26-b/26-c): ACCEPT of a Hunt offer must still ground when the proposed animal is no longer emitted under the
// same candidate id/serial (animals wander, flee, die; native reuses a candidate id only while that exact animal is emitted).
// Pure: real adapter + real stobeActivityAdapter, no database. Fails before the patch (case A), passes after.
//   php tests/imm26_u4_ground_hunt_accept.php
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
function cand(string $kind, string $src, string $res, int $serial, string $id, array $over = []): array {
    return $over + ['kind'=>$kind, 'sourceId'=>$src, 'resourceId'=>$res, 'targetSerial'=>$serial, 'candidateId'=>$id, 'pathReachable'=>true, 'observedNow'=>true,
        'suitable'=>true, 'activityPermitted'=>true, 'protectedTarget'=>false, 'hostile'=>false, 'conflictingOrder'=>false,
        'x'=>1000.0, 'y'=>10.0, 'z'=>2000.0, 'agreedTargets'=>[]];
}
$ROUTES = [['id'=>'local:s1:1', 'label'=>'near Goat to the west', 'actor_serial'=>ACTOR, 'kind'=>'landmark', 'source'=>'native_local', 'x'=>4000.0, 'y'=>20.0, 'z'=>6000.0]];
function req(array $cands, array $over = [], bool $willing = true): array {
    global $ROUTES;
    return ['context'=>['worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'now'=>1000],
        'nativeFacts'=>$over + ['worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'npcWilling'=>$willing, 'candidates'=>$cands], 'routeCandidates'=>$ROUTES];
}
function propose(array $cands, array $ref, string $kind = 'Hunt'): array {
    $src = $kind === 'Mine' ? MINE_SRC : HUNT_SRC; $res = $kind === 'Mine' ? MINE_RES : HUNT_RES;
    $r = req($cands);
    return stobeActivityAdapter($r)->propose($r['context'], ['kind'=>$kind, 'sourceId'=>$src, 'resourceId'=>$res, 'quantity'=>1,
        'discoveryRef'=>$ref, 'agreedTargets'=>[], 'routeRef'=>['candidateId'=>'local:s1:1']]);
}
/** @return array|string accepted transition or the rejection message */
function accept(array $proposal, array $request, int $now = 1005) {
    $e = ['origin'=>'native_player_chat', 'worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'proposalId'=>$proposal['agreement']['id'],
        'revision'=>$proposal['revision'], 'scopeDigest'=>$proposal['scopeDigest'], 'proposalWasDisplayed'=>true, 'playerText'=>"Yes, let's do it.", 'quotedText'=>"Yes, let's do it."];
    $c = $request['context']; $c['now'] = $now;
    try { return stobeActivityAdapter($request)->accept($c, $proposal, $e); } catch (Throwable $t) { return $t->getMessage(); }
}
const NOGROUND = 'No currently grounded suitable activity target';
$goatA = cand('Hunt', HUNT_SRC, HUNT_RES, 396362304, 'activity-proposal:2232299776:76');
$P = propose([$goatA], ['candidateId'=>$goatA['candidateId'], 'targetSerial'=>$goatA['targetSerial']]);
check('seed: Hunt proposed', $P['status'] === 'proposed' && $P['discoveryRef']['targetSerial'] === 396362304, $P['status'] ?? null);

// A. the bug: goat A is gone, another goat B is observed under a new id/serial
$goatB = cand('Hunt', HUNT_SRC, HUNT_RES, 396362999, 'activity-proposal:2232299776:81');
$t = accept($P, req([$goatB]));
check('A: accept grounds on another suitable goat of the same kind/source/resource', is_array($t) && $t['record']['status'] === 'accepted', $t);
if (is_array($t)) {
    check('A: record is not rebound (discoveryRef and digest unchanged, native consent/report match the digest)',
        $t['record']['discoveryRef'] === $P['discoveryRef'] && $t['record']['scopeDigest'] === $P['scopeDigest'], $t['record']['discoveryRef']);
    check('A: grant envelope carries the stored scope and a grant op', $t['envelope']['operation'] === 'grant' && $t['envelope']['scopeDigest'] === $P['scopeDigest']);
}
// B. regression: the same goat re-emitted (same id and serial) still grounds; also with unrelated goats ahead of it
$t = accept($P, req([$goatB, $goatA]));
check('B: same goat still emitted -> accepted', is_array($t) && $t['record']['status'] === 'accepted', $t);
// C. negatives: every safety check still applies to the fallback candidate
check('C1: nothing observed -> still rejected', accept($P, req([])) === NOGROUND);
check('C2: only a candidate of ANOTHER source (other animal) -> rejected', accept($P, req([cand('Hunt', 'other.mod', HUNT_RES, 5, 'x:1')])) === NOGROUND);
check('C3: only a candidate of another resource -> rejected', accept($P, req([cand('Hunt', HUNT_SRC, 'other-res', 5, 'x:2')])) === NOGROUND);
check('C4: only a candidate of another kind (Mine) -> rejected', accept($P, req([cand('Mine', HUNT_SRC, HUNT_RES, 5, 'x:3')])) === NOGROUND);
foreach ([['suitable',false],['activityPermitted',false],['protectedTarget',true],['conflictingOrder',true],['pathReachable',false],['observedNow',false]] as [$k,$v]) {
    check("C5: fallback candidate with $k=" . json_encode($v) . ' -> rejected', accept($P, req([cand('Hunt', HUNT_SRC, HUNT_RES, 77, 'x:4', [$k=>$v])])) === NOGROUND);
}
check('C6: first candidate unsuitable, second suitable -> accepted (every candidate is considered)',
    is_array(accept($P, req([cand('Hunt', HUNT_SRC, HUNT_RES, 77, 'x:5', ['protectedTarget'=>true]), $goatB]))));
check('C7: facts of another world -> rejected', !is_array(accept($P, req([$goatB], ['worldId'=>'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2']))));
check('C8: requester not the offer requester (other speaker) -> rejected by policy', !is_array(accept($P, req([$goatB], ['requester'=>PLAYER + 1]))));
check('C9: NPC no longer willing -> rejected by policy', !is_array(accept($P, req([$goatB], [], false))));
check('C10: expired offer -> rejected even with a good goat', !is_array(accept($P, req([$goatB]), 1000 + 1801)));
// D. propose keeps the exact-ref rule (no fabricated discoveryRef)
try { propose([$goatB], ['candidateId'=>'activity-proposal:2232299776:999', 'targetSerial'=>123456]); check('D1: propose with a ref not in the facts -> rejected', false); }
catch (Throwable $e) { check('D1: propose with a ref not in the facts -> rejected', $e->getMessage() === NOGROUND, $e->getMessage()); }
try { propose([$goatB], ['candidateId'=>$goatB['candidateId'], 'targetSerial'=>111]); check('D2: propose with right id, wrong serial -> rejected', false); }
catch (Throwable $e) { check('D2: propose with right id, wrong serial -> rejected', $e->getMessage() === NOGROUND, $e->getMessage()); }
// E. Mine (fixed building) keeps the exact-ref rule at accept
$mineA = cand('Mine', MINE_SRC, MINE_RES, 4001, 'activity-proposal:2232299776:5');
$PM = propose([$mineA], ['candidateId'=>$mineA['candidateId'], 'targetSerial'=>4001], 'Mine');
check('E1: Mine at accept with the same ref -> accepted', is_array(accept($PM, req([$mineA]))));
check('E2: Mine at accept with another mine under another id -> still rejected (relaxation is Hunt only)',
    accept($PM, req([cand('Mine', MINE_SRC, MINE_RES, 4002, 'activity-proposal:2232299776:6')])) === NOGROUND);
echo "imm26_u4_ground_hunt_accept: $pass passed, $fail failed\n";
exit($fail ? 1 : 0);
