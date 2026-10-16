<?php
// imm26 huntA (Shay 2026-10-16): when an agreed job (Hunt/Mine/ClearGroup) FAILS, the NPC says right away that it gives up and why.
// Server side: the failed terminal event carries ending=failed, is stored with the marker, is claimable under urgent spacing
// (20 s global / 40 s per NPC, ttl 300 s, priority 6) where an ordinary plan_changed is not, and the remark instruction says "giving up".
// DB test (stobe_test): flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/imm26_huntA_giveup_regression.php
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/situated_dialogue.php';
require_once __DIR__ . '/../lib/activity/ActivityLifecycle.php';
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 400) : '') . "\n"; }
}
$db = $GLOBALS['db'];
function cleanup(): void {
    $GLOBALS['db']->exec("DELETE FROM eventlog WHERE type='situated_event' AND data LIKE 'situated-v1:9200%'");
    $GLOBALS['db']->exec("DELETE FROM eventlog WHERE type='situated_remark_claim' AND data LIKE '%\"actor_serial\":9200%'");
}
cleanup();
$G = 6000; $allow = fn(string $k) => true;
$record = ['status'=>'failed', 'failureReason'=>'timeout', 'revision'=>4, 'lastNow'=>$G,
    'agreement'=>['id'=>'agr-h1', 'kind'=>'Hunt', 'actor'=>920001, 'requester'=>920002, 'resourceId'=>'raw_meat', 'quantity'=>1]];
$text = stobeActivityOutcomeText($record);
check('outcome text names the reason', is_string($text) && str_contains($text, 'no progress for too long') && str_contains($text, 'without success'), $text);

$failedEv = ['event_id'=>'activity:agr-h1:4:failed', 'activity_id'=>'agr-h1', 'kind'=>'plan_changed', 'ending'=>'failed', 'fact'=>$text];
$plainEv  = ['event_id'=>'activity:agr-h1:4:plain', 'activity_id'=>'agr-h1', 'kind'=>'plan_changed', 'fact'=>'The plan changed.'];

// 1. The marker is stored only for failed endings.
check('record failed ending', stobeSituatedRecordEvent(920001, 920002, $G, $failedEv));
$row = $db->fetchOne("SELECT data FROM eventlog WHERE type='situated_event' AND data LIKE 'situated-v1:920001:%' ORDER BY rowid DESC LIMIT 1");
check('stored row carries ending=failed', is_array($row) && str_contains($row['data'], '"ending":"failed"'), $row);
check('record plain plan_changed', stobeSituatedRecordEvent(920003, 920002, $G, $plainEv));
$row2 = $db->fetchOne("SELECT data FROM eventlog WHERE type='situated_event' AND data LIKE 'situated-v1:920003:%' ORDER BY rowid DESC LIMIT 1");
check('plain event has no ending marker', is_array($row2) && !str_contains($row2['data'], '"ending"'), $row2);

// 2. Spacing: another remark 45 s ago blocks an ordinary plan_changed (60 s / 180 s) but not a failed ending (20 s / 40 s).
$claim45 = function (int $actor) use ($G) {
    storeEvent('situated_remark_claim', time(), $G, json_encode(['actor_serial'=>$actor, 'event_id'=>'older', 'kind'=>'progress']), 'pending', '', '', false);
    // storeEvent stamps localts with the current time whatever the argument is, so age the claim row directly.
    $GLOBALS['db']->exec("UPDATE eventlog SET localts=localts-45 WHERE type='situated_remark_claim' AND data LIKE '%\"actor_serial\":$actor,%'");
};
$claim45(920001); $claim45(920003);
check('ordinary plan_changed blocked 45 s after a remark', stobeSituatedClaimForSerials(920003, 920002, 'A', 'B', $G, [], [], $allow) === null);
$c = stobeSituatedClaimForSerials(920001, 920002, 'A', 'B', $G, [], [], $allow);
check('failed ending claimable 45 s after a remark', is_array($c) && ($c['ending'] ?? '') === 'failed' && $c['event_id'] === 'activity:agr-h1:4:failed', $c);
check('failed ending is claimed only once', stobeSituatedClaimForSerials(920001, 920002, 'A', 'B', $G, [], [], $allow) === null);

// 3. Validity: ttl 300 s for a failed ending (plain plan_changed also 300 s; check the failed one outranks an injury observation).
cleanup();
$prefix = 'situated-v1:920004:';
$put = function (string $id, string $kind, array $extra) use ($prefix, $G) {
    storeEvent('situated_event', time(), $G, $prefix . json_encode(['event_id'=>$id, 'activity_id'=>'z', 'requester_serial'=>920002, 'kind'=>$kind, 'fact'=>"fact $id", 'recorded_unix'=>time() - 10] + $extra), 'pending', '', '', false);
};
$put('e-injury', 'injury', []);
$put('e-fail', 'plan_changed', ['ending'=>'failed']);
$c2 = stobeSituatedClaimForSerials(920004, 920002, 'A', 'B', $G, [], [], $allow);
check('failed ending (priority 6) outranks injury (5)', is_array($c2) && $c2['event_id'] === 'e-fail', $c2);
cleanup();
$old = ['event_id'=>'e-old', 'activity_id'=>'z', 'requester_serial'=>920002, 'kind'=>'plan_changed', 'ending'=>'failed', 'fact'=>'x', 'recorded_unix'=>time() - 320];
storeEvent('situated_event', time(), $G, 'situated-v1:920005:' . json_encode($old), 'pending', '', '', false);
check('failed ending older than 300 s is not claimable', stobeSituatedClaimForSerials(920005, 920002, 'A', 'B', $G, [], [], $allow) === null);
cleanup();

// 4. Instruction: failed ending says it gives up and why; ordinary events do not.
$ins = stobeSituatedRemarkInstruction(['kind'=>'plan_changed', 'ending'=>'failed', 'fact'=>$text]);
check('instruction says giving up + reason', str_contains($ins, 'giving up') && str_contains($ins, 'why') && str_contains($ins, 'no progress for too long'), $ins);
check('instruction keeps speech-only guard', str_contains($ins, 'do not start, repeat, cancel or redirect'), $ins);
$ins2 = stobeSituatedRemarkInstruction(['kind'=>'plan_changed', 'fact'=>'The plan changed.']);
check('ordinary instruction has no giving-up text', !str_contains($ins2, 'giving up'), $ins2);
check('instruction survives hostile fact', !str_contains(stobeSituatedRemarkInstruction(['kind'=>'plan_changed', 'ending'=>'failed', 'fact'=>'<b>x</b>']), '<b>'));

// 5. Wiring.
$act = file_get_contents(__DIR__ . '/../activity.php');
check("activity.php: failed report sets ending", str_contains($act, "'ending'=>\$record['status']==='failed'?'failed':''"));
$lib = file_get_contents(__DIR__ . '/../lib/situated_dialogue.php');
check('situated_dialogue: urgent policy for failed ending', str_contains($lib, "'priority'=>6,'urgent'=>true"));
echo "pass=$pass fail=$fail\n";
exit($fail === 0 ? 0 : 1);
