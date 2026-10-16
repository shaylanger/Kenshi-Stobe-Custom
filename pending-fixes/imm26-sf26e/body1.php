
// ---- sf26e additions: chat-turn tables and a Finish driver ----------------------------------------------------------------
require_once __DIR__ . '/../lib/activity/ActivityChat.php';
foreach (['stobe_activity_chat_turn', 'stobe_activity_request_nonce'] as $t) $db->exec("DROP TABLE IF EXISTS pg_temp.$t");
$db->exec("CREATE TEMP TABLE stobe_activity_chat_turn (ticket text PRIMARY KEY, payload jsonb NOT NULL, expires_at bigint NOT NULL, consumed boolean NOT NULL DEFAULT false, result jsonb)");
/** One chat turn through the real prepare/claim/Finish path; returns [handled, text, chatResult, actions]. */
function finish_turn(\Stobe\Activity\ActivityStore $store, array $request, ?array $record, string $raw): array {
    $ticket = $store->transaction(static fn() => $store->prepareChat($request));
    $claimed = $store->transaction(static fn() => $store->claimChat($ticket));
    $claimed['nativeFacts'] = stobeActivityEnrichFacts($claimed['nativeFacts'] ?? []);   // what stobeActivityChatBegin does
    $turn = ['ticket'=>$ticket, 'request'=>$claimed, 'record'=>$record, 'affinity'=>50, 'availability'=>['available'=>true, 'reasons'=>[]]];
    $text = 'model prose'; $actions = ['SOMETHING'];
    $handled = stobeActivityChatFinish($turn, $raw, $text, $actions);
    return [$handled, $text, $store->chatResult($ticket, $claimed['context']['worldId']), $actions];
}

$A = new_actor();
$prop = make_job($store, W1, $A, 1000, 'Hunt', false);
sweep($store, W2, 1100);
$rq = req(W2, $A, 1110, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:9:8')], [route($A, 'local:s2:50', 'a ridge', 4001.5, 20.5, 6001.5)]);
$moved = chat($store, $rq);
check('seed: proposal rebound in W2 (same id, still proposed, revision+1)', is_array($moved) && $moved['agreement']['id'] === $prop['agreement']['id'] && $moved['status'] === 'proposed'
    && $moved['revision'] === $prop['revision'] + 1, $moved['status'] ?? null);
check('seed: resumed note for a proposed record no longer says "do not ask for consent again"', is_array($moved) && !str_contains(strval($moved['resume']['note'] ?? ''), 'do not ask for consent again')
    && str_contains(strval($moved['resume']['note'] ?? ''), 'NOT accepted'), $moved['resume']['note'] ?? null);

// (1a) the player's Yes right after the load: the native map is empty, so no consent rides along; the model says ACCEPT with intent null
$rq1 = $rq; $rq1['context']['now'] = 1120; $rq1['playerText'] = "Yes, let's do it";
[$handled, $text, $res] = finish_turn($store, $rq1, $moved, json_encode(['activity_decision'=>'ACCEPT', 'activity_intent'=>'']));
check('redisplay: ACCEPT without consent on a proposed record re-displays it (decision PROPOSE, offerDisplayed, offerText set)',
    $handled === true && ($res['decision'] ?? '') === 'PROPOSE' && ($res['offerDisplayed'] ?? false) === true && strval($res['offerText'] ?? '') !== '' && empty($res['rejected']), $res);
check('redisplay: the spoken text is the offer sentence, not "Are you agreeing"', $text === ($res['offerText'] ?? null) && str_contains($text, 'Shall we travel to a ridge'), $text);
$after = row($moved['agreement']['id']);
check('redisplay: record id, revision, status and digest unchanged; the result carries that same record; no grant written',
    $after['status'] === 'proposed' && $after['revision'] === $moved['revision'] && ($res['record']['agreement']['id'] ?? '') === $moved['agreement']['id']
    && ($res['record']['revision'] ?? -1) === $moved['revision'] && ($res['record']['scopeDigest'] ?? '') === $moved['scopeDigest'] && outbox(W2) === [], $after['status']);

// (1b) the displayed offer is now bound natively; the next Yes carries consent for exactly that revision/digest
$rq2 = $rq; $rq2['context']['now'] = 1130; $rq2['playerText'] = "Yes, let's do it";
$rq2['consent'] = ['origin'=>'native_player_chat', 'worldId'=>W2, 'actor'=>$A, 'requester'=>PLAYER, 'proposalId'=>$moved['agreement']['id'],
    'revision'=>$moved['revision'], 'scopeDigest'=>$moved['scopeDigest'], 'proposalWasDisplayed'=>true, 'playerText'=>"Yes, let's do it"];
[$handled, $text, $res2] = finish_turn($store, $rq2, row($moved['agreement']['id']), json_encode(['activity_decision'=>'ACCEPT', 'activity_intent'=>'']));
$ob = array_values(array_filter(outbox(W2), static fn($x) => $x['id'] === $moved['agreement']['id']));
check('consent: the second Yes (native-style consent) accepts the same record and writes exactly one grant', $handled === true && ($res2['record']['status'] ?? '') === 'accepted'
    && ($res2['offerDisplayed'] ?? true) === false && count($ob) === 1 && $ob[0]['operation'] === 'grant', [$res2['decision'] ?? null, $res2['record']['status'] ?? null, $res2['rejected'] ?? null, count($ob)]);

// (1c) controls: consent that does not match is still refused by accept() (not re-displayed); an accepted record is never turned into a re-display
$B = new_actor();
$p2 = make_job($store, W2, $B, 1200, 'Mine', false);
$rq3 = req(W2, $B, 1210, [cand('Mine', MINE_SRC, MINE_RES, 5001, 'activity-proposal:1:1')], [route($B, 'local:s1:1', 'higher ground to the east', 4000.5, 20.5, 6000.5)]);
$rq3['playerText'] = 'yes'; $rq3['consent'] = ['origin'=>'native_player_chat', 'worldId'=>W2, 'actor'=>$B, 'requester'=>PLAYER, 'proposalId'=>$p2['agreement']['id'],
    'revision'=>$p2['revision'] + 5, 'scopeDigest'=>$p2['scopeDigest'], 'proposalWasDisplayed'=>true, 'playerText'=>'yes'];
[$handled, $text, $res3] = finish_turn($store, $rq3, $p2, json_encode(['activity_decision'=>'ACCEPT', 'activity_intent'=>'']));
check('control: wrong-revision consent is still refused through accept() (no re-display, record stays proposed)', ($res3['rejected'] ?? false) === true
    && row($p2['agreement']['id'])['status'] === 'proposed' && str_contains($text, 'Are you agreeing'), [$res3, $text]);
$C = new_actor();
$a3 = make_job($store, W2, $C, 1300, 'Hunt', true);
$rq4 = req(W2, $C, 1310, [cand('Hunt', HUNT_SRC, HUNT_RES, 5001, 'activity-proposal:1:1')], [route($C, 'local:s1:1', 'higher ground to the east', 4000.5, 20.5, 6000.5)]);
$rq4['playerText'] = 'Cancel that.';
[$handled, $text, $res4] = finish_turn($store, $rq4, $a3, json_encode(['activity_decision'=>'ACCEPT', 'activity_intent'=>'']));
check('control: ACCEPT on an already accepted record is not turned into a re-display', ($res4['decision'] ?? '') !== 'PROPOSE' && empty($res4['offerDisplayed']), $res4);

echo "imm26_sf26e_consent_redisplay: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
