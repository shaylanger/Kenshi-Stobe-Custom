<?php
// imm26-inv26 hardening (rows 26-b/26-d diagnosis): the addressed NPC is absent from the request's `people` (native BuildPeopleJson drops a chat target beyond
// TalkRadius 80; PTT/voice sends legitimately reach a partner that far), so stobeActivityChatBegin's identity check resolved the NPC to 0 and threw
// 'Activity chat identity mismatch', swallowed by processor/chat.php without ever logging the reason. Fix: the NPC lookup uses the stored-serial fallback
// (unambiguous name only) and the chat.php warn carries the error message.
// Offline on TEMP tables in stobe_test. Run:
//   STOBE_DB_NAME=stobe_test php tests/imm26_inv26_far_target_regression.php   (flock /tmp/stobe-tests.lock)
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 700) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/activity/ActivityStore.php';
require_once __DIR__ . '/../lib/activity/ActivityChat.php';
$db = $GLOBALS['db'];
putenv('STOBE_ACTIVITY_ENABLED=1');

foreach (['stobe_activity_outbox', 'stobe_activity_record', 'stobe_activity_chat_turn', 'stobe_activity_request_nonce', 'core_npc_master'] as $t) $db->exec("DROP TABLE IF EXISTS pg_temp.$t");
$db->exec("CREATE TEMP TABLE stobe_activity_record (id text PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, requester bigint NOT NULL, revision integer NOT NULL, record jsonb NOT NULL)");
$db->exec("CREATE TEMP TABLE stobe_activity_outbox (sequence bigserial PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, agreement_id text NOT NULL REFERENCES stobe_activity_record(id), revision integer NOT NULL, envelope jsonb NOT NULL, acknowledged boolean NOT NULL DEFAULT false, UNIQUE(agreement_id,revision))");
$db->exec("CREATE TEMP TABLE stobe_activity_chat_turn (ticket text PRIMARY KEY, payload jsonb NOT NULL, expires_at bigint NOT NULL, consumed boolean NOT NULL DEFAULT false, result jsonb)");
$db->exec("CREATE TEMP TABLE core_npc_master (name text, metadata jsonb)");
$db->exec("INSERT INTO core_npc_master (name, metadata) VALUES ('UtFarNpc', '{\"storage_id\":\"hand_101\"}'::jsonb)");
$db->exec("INSERT INTO core_npc_master (name, metadata) VALUES ('UtDupNpc', '{\"storage_id\":\"hand_201\"}'::jsonb), ('UTDUPNPC', '{\"storage_id\":\"hand_202\"}'::jsonb)");
$store = new \Stobe\Activity\ActivityStore($db);

const W1 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1';
function begin_for(\Stobe\Activity\ActivityStore $store, string $npc, int $actor): array {
    $text = 'Cancel that.';
    $req = ['context'=>['worldId'=>W1, 'actor'=>$actor, 'requester'=>9001, 'now'=>1000], 'playerText'=>$text,
        'nativeFacts'=>['worldId'=>W1, 'actor'=>$actor, 'requester'=>9001, 'candidates'=>[]], 'routeCandidates'=>[]];
    $ticket = $store->transaction(static fn() => $store->prepareChat($req));
    $_SERVER['HTTP_X_STOBE_ACTIVITY_TICKET'] = $ticket;
    $GLOBALS['CACHE_PEOPLE'] = '["Shay|hand_9001"]';      // the NPC is NOT in people (beyond TalkRadius)
    $messages = [];
    try { $turn = stobeActivityChatBegin($messages, $text, $npc, 'Shay'); return ['turn'=>$turn, 'error'=>null]; }
    catch (Throwable $e) { return ['turn'=>null, 'error'=>$e->getMessage()]; }
}

$r = begin_for($store, 'UtFarNpc', 101);
check('far target: ChatBegin resolves the NPC through the stored serial and returns the turn', $r['error'] === null && is_array($r['turn']) && ($r['turn']['request']['context']['actor'] ?? 0) === 101, $r['error']);
$r = begin_for($store, 'UtFarNpc', 999);
check('control: a ticket for a DIFFERENT actor than the stored serial is still an identity mismatch', $r['turn'] === null && $r['error'] === 'Activity chat identity mismatch', $r);
$r = begin_for($store, 'UtDupNpc', 201);
check('control: an ambiguous stored name (two serials) is still an identity mismatch', $r['turn'] === null && $r['error'] === 'Activity chat identity mismatch', $r);
$r = begin_for($store, 'UtUnknownNpc', 101);
check('control: a name with no stored serial is still an identity mismatch', $r['turn'] === null && $r['error'] === 'Activity chat identity mismatch', $r);

$chatSrc = (string)@file_get_contents(__DIR__ . '/../processor/chat.php');
check('processor/chat.php: the "Activity chat context rejected" warn carries the exception message', (bool)preg_match("/'Activity chat context rejected',\s*\[[^\]]*'error'\s*=>\s*\\\$activityError->getMessage\(\)/", $chatSrc));

echo "imm26_inv26_far_target: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
