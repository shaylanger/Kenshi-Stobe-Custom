<?php
// imm26-sfO: the activity PROPOSE test seam (lib/activity/ActivityTestInject.php + the guarded call in stobeActivityChatFinish).
// Runs with STOBE_DB_NAME=stobe_test (TEMP tables). Two modes:
//   php tests/imm26_sfO_inject_propose.php lane      : tree is /tmp/stobe-*/site, STOBE_DB_HOST inside the lane root (selftest builds that); full behaviour
//   php tests/imm26_sfO_inject_propose.php notlane   : any other tree (e.g. the live-like compose tree): the seam must be inert even with a marker
// Fails on a tree without the seam (case A2 etc.), passes after pending-fixes/imm26-sfO/apply.py.
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/activity/ActivityAgreementAdapter.php';
require_once __DIR__ . '/../lib/activity/ActivityService.php';
require_once __DIR__ . '/../lib/activity/ActivityConfig.php';
require_once __DIR__ . '/../lib/activity/activity_prompt.php';
require_once __DIR__ . '/../lib/destination_discovery.php';
require_once __DIR__ . '/../lib/activity/ActivityStore.php';
require_once __DIR__ . '/../lib/activity/ActivityChat.php';
$mode = $argv[1] ?? 'lane';
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 400) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "FAIL needs STOBE_DB_NAME=stobe_test\n"; exit(1); }

$site = realpath(__DIR__ . '/..');
$marker = dirname($site) . '/test-inject-activity.json';
if ($mode !== 'armed') @unlink($marker);   // armed mode: the marker was written by inject-propose.sh
$db = $GLOBALS['db'];
foreach (['stobe_activity_outbox', 'stobe_activity_record', 'stobe_activity_chat_turn'] as $t) $db->exec("DROP TABLE IF EXISTS pg_temp.$t");
$db->exec("CREATE TEMP TABLE stobe_activity_record (id text PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, requester bigint NOT NULL, revision integer NOT NULL, record jsonb NOT NULL)");
$db->exec("CREATE UNIQUE INDEX stobe_activity_one_active_actor ON stobe_activity_record(world_id,actor) WHERE record->>'status' IN ('proposed','accepted')");
$db->exec("CREATE TEMP TABLE stobe_activity_outbox (sequence bigserial PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, agreement_id text NOT NULL REFERENCES stobe_activity_record(id), revision integer NOT NULL, envelope jsonb NOT NULL, acknowledged boolean NOT NULL DEFAULT false, UNIQUE(agreement_id,revision))");
$db->exec("CREATE TEMP TABLE stobe_activity_chat_turn (ticket text PRIMARY KEY, payload jsonb NOT NULL, expires_at bigint NOT NULL, consumed boolean NOT NULL DEFAULT false, result jsonb)");
$store = new \Stobe\Activity\ActivityStore($db);
$W = 'cccccccccccccccccccccccccccccccc'; $PLAYER = 9001;
$SRC = '1531903-Swamp Animal Traders.mod'; $RES = '42241-rebirth.mod';
$CAMP = ['candidateId' => 'v1:' . str_repeat('a', 48), 'scopeDigest' => str_repeat('b', 64)];
function reqFor(int $actor, string $text, array $cands, int $now = 1000): array {
    global $W, $PLAYER;
    return ['context'=>['worldId'=>$W,'actor'=>$actor,'requester'=>$PLAYER,'now'=>$now], 'playerText'=>$text,
        'nativeFacts'=>['worldId'=>$W,'actor'=>$actor,'requester'=>$PLAYER,'candidates'=>$cands],
        'routeCandidates'=>[['id'=>'local:s1:'.$actor,'label'=>'higher ground to the east','actor_serial'=>$actor,'kind'=>'landmark','source'=>'native_local','x'=>4000.5,'y'=>20.25,'z'=>6000.75]]];
}
function huntCand(array $o = []): array {
    global $SRC, $RES;
    return $o + ['kind'=>'Hunt','sourceId'=>$SRC,'resourceId'=>$RES,'resourceName'=>'raw meat','targetSerial'=>5001,'candidateId'=>'activity-proposal:1:1','pathReachable'=>true,'observedNow'=>true,
        'suitable'=>true,'activityPermitted'=>true,'protectedTarget'=>false,'hostile'=>false,'conflictingOrder'=>false,'x'=>1000.0,'y'=>10.0,'z'=>2000.0,'agreedTargets'=>[]];
}
function clearCand(array $o = []): array {
    global $CAMP;
    return $o + ['kind'=>'ClearGroup','sourceId'=>'camp-threats','resourceId'=>'','targetSerial'=>303,'candidateId'=>'activity-candidate-1','pathReachable'=>true,'observedNow'=>true,
        'suitable'=>true,'activityPermitted'=>true,'protectedTarget'=>false,'hostile'=>false,'conflictingOrder'=>false,'x'=>1000.0,'y'=>10.0,'z'=>2000.0,'agreedTargets'=>[303,404],'campZone'=>$CAMP];
}
$mkTurn = static function(array $request, ?array $record) use ($store): array {
    $ticket = $store->prepareChat(['context'=>$request['context']]);
    $store->transaction(static fn() => $store->claimChat($ticket));
    return ['ticket'=>$ticket,'request'=>$request,'record'=>$record,'affinity'=>10,'availability'=>['available'=>true]];
};
$noneReply = json_encode(['action'=>'Talk','message'=>'Hmm, maybe later.','activity_decision'=>'NONE','activity_intent'=>'','travel_decision'=>'NONE','deal_decision'=>'NONE','deal_terms'=>'']);
$rows = static fn(int $actor) => $db->fetchAll('SELECT record FROM stobe_activity_record WHERE world_id=$1 AND actor=$2 ORDER BY revision', [$W, $actor]);
$arm = static function(array $spec) use ($marker): void {
    file_put_contents($marker, json_encode($spec + ['schema'=>'STOBE_TEST_ACTIVITY_INJECT_V1','expires_at'=>time()+600,'actor'=>0,'row'=>'selftest','target'=>'','quantity'=>1]));
};
$firedFiles = static fn() => glob(dirname($site) . '/test-inject-activity.fired-*.json') ?: [];
if ($mode !== 'armed') foreach ($firedFiles() as $f) @unlink($f);

if ($mode === 'notlane') {
    // The live-like tree: marker present, gate must stay closed, the model's NONE stays NONE.
    $arm(['kind'=>'Hunt']);
    $text = 'Hmm.'; $actions = ['Follow'];
    $ok = stobeActivityChatFinish($mkTurn(reqFor(7301, 'hunt with me', [huntCand()]), null), $noneReply, $text, $actions);
    check('N1: non-lane tree + marker: model NONE stays NONE (seam inert)', $ok === false && !$rows(7301), [$ok, $rows(7301)]);
    check('N2: marker is not consumed outside a lane', is_file($marker));
    if (function_exists('stobeActivityTestInjectLaneRoot')) check('N3: lane gate returns null outside /tmp/stobe-*/site', stobeActivityTestInjectLaneRoot() === null);
    @unlink($marker);
    echo "imm26_sfO_inject_propose notlane: $pass passed, $fail failed\n";
    exit($fail ? 1 : 0);
}

// ---- armed mode: the marker was written by inject-propose.sh (selftest step); one NPC turn must become a real PROPOSE.
// usage: php tests/imm26_sfO_inject_propose.php armed <actor serial> <Hunt|ClearGroup>
if ($mode === 'armed') {
    $actorA = intval($argv[2] ?? 0); $kindA = strval($argv[3] ?? 'Hunt');
    check('P0: script-written marker present', is_file($marker));
    $text = 'Hmm.'; $actions = ['Follow'];
    $cands = $kindA === 'ClearGroup' ? [huntCand(), clearCand()] : [huntCand(), clearCand()];
    $ok = stobeActivityChatFinish($mkTurn(reqFor($actorA, 'hello', $cands), null), $noneReply, $text, $actions);
    $r = $rows($actorA); $rec = $r ? json_decode($r[0]['record'], true) : null;
    check("P1: script-armed $kindA -> proposed $kindA record via the real path", $ok === true && ($rec['status'] ?? '') === 'proposed' && ($rec['agreement']['kind'] ?? '') === $kindA, [$ok, $rec['status'] ?? null, $rec['agreement']['kind'] ?? null]);
    check('P2: marker consumed', !is_file($marker) && count($firedFiles()) === 1);
    echo "imm26_sfO_inject_propose armed: $pass passed, $fail failed\n";
    exit($fail ? 1 : 0);
}

// ---- lane mode
// A. control: no marker -> the model's NONE is untouched
$text = 'Hmm.'; $actions = ['Follow'];
$ok = stobeActivityChatFinish($mkTurn(reqFor(7201, 'want to hunt?', [huntCand()]), null), $noneReply, $text, $actions);
check('A1: no marker: model NONE -> no proposal', $ok === false && !$rows(7201), [$ok, $rows(7201)]);

// B. Hunt armed for actor 7202: a NONE model reply still produces a real PROPOSE
$arm(['kind'=>'Hunt','actor'=>7202,'row'=>'26-a']);
$text = 'Hmm.'; $actions = ['Follow'];
$ok = stobeActivityChatFinish($mkTurn(reqFor(7202, 'want to hunt goats?', [huntCand()]), null), $noneReply, $text, $actions);
$r = $rows(7202); $rec = $r ? json_decode($r[0]['record'], true) : null;
check('B1: armed Hunt: a proposed Hunt record is stored by the real propose path', $ok === true && count($r) === 1 && ($rec['status'] ?? '') === 'proposed' && ($rec['agreement']['kind'] ?? '') === 'Hunt', [$ok, $rec['status'] ?? null]);
check('B2: record carries the turn\'s own grounding (candidate id, serial, route id, real scope digest)',
    ($rec['discoveryRef'] ?? null) === ['candidateId'=>'activity-proposal:1:1','targetSerial'=>5001] && ($rec['routeRef']['candidateId'] ?? '') === 'local:s1:7202' && preg_match('/^[a-f0-9]{64}$/', strval($rec['scopeDigest'] ?? '')) === 1, $rec);
check('B3: speech is the product offer text (what native binds), actions cleared', str_starts_with($text, 'Shall we travel to higher ground to the east to hunt for 1 raw meat together?') && $actions === [], [$text, $actions]);
check('B4: marker consumed (one-shot) and a fired file recorded', !is_file($marker) && count($firedFiles()) === 1);
$resRow = $db->fetchOne('SELECT result FROM stobe_activity_chat_turn ORDER BY ticket LIMIT 1');
// B5: second turn of the same NPC with a NONE reply is untouched
$text = 'Hmm.'; $actions = [];
$ok2 = stobeActivityChatFinish($mkTurn(reqFor(7202, 'so?', [huntCand()]), $rec), $noneReply, $text, $actions);
$r = $rows(7202);
check('B5: one-shot: next NONE turn is not re-injected (still one proposed record)', $ok2 === false && count($r) === 1, [$ok2, count($r)]);
// B6: the player's own "Yes" accepts the injected offer through the unchanged path (consent evidence from the player's turn)
$req = reqFor(7202, 'Yes', [huntCand()], 1005);
$req['consent'] = ['origin'=>'native_player_chat','worldId'=>$W,'actor'=>7202,'requester'=>$PLAYER,'proposalId'=>$rec['agreement']['id'],'revision'=>$rec['revision'],
    'scopeDigest'=>$rec['scopeDigest'],'proposalWasDisplayed'=>true];
$text = 'ok'; $actions = [];
$okY = stobeActivityChatFinish($mkTurn($req, $rec), json_encode(['action'=>'Talk','activity_decision'=>'ACCEPT','activity_intent'=>'','travel_decision'=>'NONE','deal_decision'=>'NONE','deal_terms'=>'']), $text, $actions);
$r = $rows(7202); $last = $r ? json_decode(end($r)['record'], true) : null;
$out = $db->fetchAll('SELECT envelope FROM stobe_activity_outbox WHERE world_id=$1 AND actor=$2', [$W, 7202]);
check('B6: player "Yes" -> record accepted + grant envelope in the outbox (rest of the row runs for real)', $okY === true && ($last['status'] ?? '') === 'accepted' && count($out) === 1, [$okY, $last['status'] ?? null, count($out)]);
foreach ($firedFiles() as $f) @unlink($f);

// C. other actor: marker for 7203 does not fire on 7204
$arm(['kind'=>'Hunt','actor'=>7203]);
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkTurn(reqFor(7204, 'hunt?', [huntCand()]), null), $noneReply, $text, $actions);
check('C1: marker for another actor: no proposal, marker kept', $ok === false && !$rows(7204) && is_file($marker), [$ok]);
@unlink($marker);

// D. expired marker
$arm(['kind'=>'Hunt','expires_at'=>time()-5]);
$ok = stobeActivityChatFinish($mkTurn(reqFor(7205, 'hunt?', [huntCand()]), null), $noneReply, $text, $actions);
check('D1: expired marker: no proposal', $ok === false && !$rows(7205));
@unlink($marker);

// E. nothing groundable in this turn: model reply kept, marker kept for a retry
$arm(['kind'=>'Hunt']);
$ok = stobeActivityChatFinish($mkTurn(reqFor(7206, 'hunt?', [huntCand(['suitable'=>false])]), null), $noneReply, $text, $actions);
check('E1: no suitable candidate: no proposal (never fabricates a target), marker kept', $ok === false && !$rows(7206) && is_file($marker));
$ok = stobeActivityChatFinish($mkTurn(reqFor(7206, 'hunt?', [huntCand(['suitable'=>false]), huntCand(['candidateId'=>'activity-proposal:1:2','targetSerial'=>5002])]), null), $noneReply, $text, $actions);
$r = $rows(7206); $rec6 = $r ? json_decode($r[0]['record'], true) : null;
check('E2: retry with a suitable second candidate: proposes THAT one', $ok === true && ($rec6['discoveryRef']['targetSerial'] ?? 0) === 5002, $rec6['discoveryRef'] ?? null);
$arm(['kind'=>'Hunt','target'=>'nomatch']);
$ok = stobeActivityChatFinish($mkTurn(reqFor(7207, 'hunt?', [huntCand()]), null), $noneReply, $text, $actions);
check('E3: target filter that matches nothing: no proposal', $ok === false && !$rows(7207));
$arm(['kind'=>'Hunt','target'=>'5009']);
$ok = stobeActivityChatFinish($mkTurn(reqFor(7208, 'hunt?', [huntCand(), huntCand(['candidateId'=>'activity-proposal:1:9','targetSerial'=>5009])]), null), $noneReply, $text, $actions);
$r = $rows(7208); $rec8 = $r ? json_decode($r[0]['record'], true) : null;
check('E4: target filter by serial picks that target', $ok === true && ($rec8['discoveryRef']['targetSerial'] ?? 0) === 5009, $rec8['discoveryRef'] ?? null);
@unlink($marker); foreach ($firedFiles() as $f) @unlink($f);

// F. ClearGroup with a camp zone
$arm(['kind'=>'ClearGroup','row'=>'14-c']);
$text = 'Hmm.'; $actions = [];
$ok = stobeActivityChatFinish($mkTurn(reqFor(7209, 'clear them out', [huntCand(), clearCand()]), null), $noneReply, $text, $actions);
$r = $rows(7209); $recC = $r ? json_decode($r[0]['record'], true) : null;
check('F1: armed ClearGroup: proposed ClearGroup record with the fixed target set and camp scope',
    $ok === true && ($recC['status'] ?? '') === 'proposed' && ($recC['agreement']['kind'] ?? '') === 'ClearGroup' && ($recC['agreement']['agreedTargets'] ?? null) === [303, 404] && ($recC['agreement']['campZone'] ?? null) === $CAMP, $recC['agreement'] ?? null);
check('F2: ClearGroup offer text', str_contains($text, 'clear out the identified group') && str_contains($text, '2 enemies'), $text);
@unlink($marker); foreach ($firedFiles() as $f) @unlink($f);

// H. NPC name instead of a serial (resolved like the chat speaker; stored serial of core_npc_master as the fallback)
$db->exec("DELETE FROM core_npc_master WHERE name='SfoTestNpc'");
$ins = $db->exec("INSERT INTO core_npc_master(name,metadata) VALUES('SfoTestNpc','{\"storage_id\":\"7211\"}'::jsonb)");
if ($ins === false) { check('H0: could not create the name row', false); }
else {
    $arm(['kind'=>'Hunt','npc'=>'SfoTestNpc']);
    $ok = stobeActivityChatFinish($mkTurn(reqFor(7212, 'hunt?', [huntCand()]), null), $noneReply, $text, $actions);
    check('H1: npc name resolves to another serial: no proposal, marker kept', $ok === false && !$rows(7212) && is_file($marker));
    $ok = stobeActivityChatFinish($mkTurn(reqFor(7211, 'hunt?', [huntCand()]), null), $noneReply, $text, $actions);
    check('H2: npc name resolves to the speaker\'s serial: proposed', $ok === true && count($rows(7211)) === 1);
    $db->exec("DELETE FROM core_npc_master WHERE name='SfoTestNpc'");
    @unlink($marker); foreach ($firedFiles() as $f) @unlink($f);
}

// G. gate: a DB socket outside the lane root closes the seam even in a /tmp/stobe-*/site tree
$arm(['kind'=>'Hunt']);
$saved = getenv('STOBE_DB_HOST');
putenv('STOBE_DB_HOST=/var/run/postgresql');
$ok = stobeActivityChatFinish($mkTurn(reqFor(7210, 'hunt?', [huntCand()]), null), $noneReply, $text, $actions);
check('G1: DB socket outside the lane root: seam closed (no proposal, marker kept)', $ok === false && !$rows(7210) && is_file($marker));
putenv('STOBE_DB_HOST=' . $saved);
@unlink($marker);
echo "imm26_sfO_inject_propose lane: $pass passed, $fail failed\n";
exit($fail ? 1 : 0);
