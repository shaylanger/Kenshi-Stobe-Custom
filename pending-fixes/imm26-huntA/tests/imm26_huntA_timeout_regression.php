<?php
// imm26 huntA1 (Shay 2026-10-16): a Hunt/Mine/ClearGroup agreement's native no-progress limit is 10000 game seconds (was 1800 = ~55 s real).
// Pure: real adapter, no database.   php tests/imm26_huntA_timeout_regression.php   (fails before the patch, passes after)
declare(strict_types=1);
set_exception_handler(function (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), ' @', basename($e->getFile()), ':', $e->getLine(), "\n"; exit(1); });
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 400) : '') . "\n"; }
}
require_once __DIR__ . '/../lib/activity/ActivityAgreementAdapter.php';
require_once __DIR__ . '/../lib/activity/ActivityService.php';
const HUNT_SRC = '1531903-Swamp Animal Traders.mod'; const HUNT_RES = '42241-rebirth.mod';
const PLAYER = 9001; const ACTOR = 2232299776; const W = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1';
$cand = ['kind'=>'Hunt', 'sourceId'=>HUNT_SRC, 'resourceId'=>HUNT_RES, 'targetSerial'=>396362304, 'candidateId'=>'activity-proposal:2232299776:76',
    'pathReachable'=>true, 'observedNow'=>true, 'suitable'=>true, 'activityPermitted'=>true, 'protectedTarget'=>false, 'hostile'=>false,
    'conflictingOrder'=>false, 'x'=>1000.0, 'y'=>10.0, 'z'=>2000.0, 'agreedTargets'=>[]];
$route = ['id'=>'local:s1:1', 'label'=>'near Goat to the west', 'actor_serial'=>ACTOR, 'kind'=>'landmark', 'source'=>'native_local', 'x'=>1200.0, 'y'=>10.0, 'z'=>2100.0];
$r = ['context'=>['worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'now'=>1000],
    'nativeFacts'=>['worldId'=>W, 'actor'=>ACTOR, 'requester'=>PLAYER, 'npcWilling'=>true, 'candidates'=>[$cand]], 'routeCandidates'=>[$route]];
$P = stobeActivityAdapter($r)->propose($r['context'], ['kind'=>'Hunt', 'sourceId'=>HUNT_SRC, 'resourceId'=>HUNT_RES, 'quantity'=>1,
    'discoveryRef'=>['candidateId'=>$cand['candidateId'], 'targetSerial'=>$cand['targetSerial']], 'agreedTargets'=>[], 'routeRef'=>['candidateId'=>'local:s1:1']]);
$a = $P['agreement'] ?? [];
check('Hunt proposed', ($P['status'] ?? '') === 'proposed', $P['status'] ?? null);
check('no-progress limit is 10000 game seconds', ($a['noProgressTimeout'] ?? 0) === 10000, $a['noProgressTimeout'] ?? null);
check('limit is at least 9800 (5 real minutes at speed 1, ~32.8 game-s per real second)', ($a['noProgressTimeout'] ?? 0) >= 9800);
check('limit is shorter than the agreement lifetime (expiresAt still ends the job)', ($a['noProgressTimeout'] ?? 0) < ($a['expiresAt'] ?? 0) - 1000, [$a['noProgressTimeout'] ?? null, $a['expiresAt'] ?? null]);
echo "pass=$pass fail=$fail\n";
exit($fail ? 1 : 0);
