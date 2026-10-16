// imm26-fix-acceptpropose: a premature model ACCEPT (no offer exists, complete valid intent) is treated as PROPOSE; nothing is granted.
// Real ActivityStore + adapter + stobeActivityChatFinish on TEMP tables (stobe_test only).
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') {
    check('accept-propose: needs STOBE_DB_NAME=stobe_test', false);
} else {
    require_once __DIR__ . '/../lib/activity/ActivityStore.php';
    require_once __DIR__ . '/../lib/activity/ActivityChat.php';
    $apDb = $GLOBALS['db'];
    foreach (['stobe_activity_outbox', 'stobe_activity_record', 'stobe_activity_chat_turn'] as $t) $apDb->exec("DROP TABLE IF EXISTS pg_temp.$t");
    $apDb->exec("CREATE TEMP TABLE stobe_activity_record (id text PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, requester bigint NOT NULL, revision integer NOT NULL, record jsonb NOT NULL)");
    $apDb->exec("CREATE UNIQUE INDEX stobe_activity_one_active_actor ON stobe_activity_record(world_id,actor) WHERE record->>'status' IN ('proposed','accepted')");
    $apDb->exec("CREATE TEMP TABLE stobe_activity_outbox (sequence bigserial PRIMARY KEY, world_id text NOT NULL, actor bigint NOT NULL, agreement_id text NOT NULL REFERENCES stobe_activity_record(id), revision integer NOT NULL, envelope jsonb NOT NULL, acknowledged boolean NOT NULL DEFAULT false, UNIQUE(agreement_id,revision))");
    $apDb->exec("CREATE TEMP TABLE stobe_activity_chat_turn (ticket text PRIMARY KEY, payload jsonb NOT NULL, expires_at bigint NOT NULL, consumed boolean NOT NULL DEFAULT false, result jsonb)");
    $apStore = new \Stobe\Activity\ActivityStore($apDb);
    $apWorld = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1'; $apPlayer = 9001;
    $apSrc = '1531903-Swamp Animal Traders.mod'; $apRes = '42241-rebirth.mod';
    $apRequest = static function(int $actor, string $playerText) use ($apWorld, $apPlayer, $apSrc, $apRes): array {
        return ['context'=>['worldId'=>$apWorld,'actor'=>$actor,'requester'=>$apPlayer,'now'=>1000], 'playerText'=>$playerText,
            'nativeFacts'=>['worldId'=>$apWorld,'actor'=>$actor,'requester'=>$apPlayer,'candidates'=>[['kind'=>'Hunt','sourceId'=>$apSrc,'resourceId'=>$apRes,'resourceName'=>'raw meat',
                'targetSerial'=>5001,'candidateId'=>'activity-proposal:1:1','pathReachable'=>true,'observedNow'=>true,'suitable'=>true,'activityPermitted'=>true,
                'protectedTarget'=>false,'hostile'=>false,'conflictingOrder'=>false,'x'=>1000.0,'y'=>10.0,'z'=>2000.0,'agreedTargets'=>[]]]],
            'routeCandidates'=>[['id'=>'local:s1:1','label'=>'higher ground to the east','actor_serial'=>$actor,'kind'=>'landmark','source'=>'native_local','x'=>4000.5,'y'=>20.25,'z'=>6000.75]]]; // fractional like native floats (an integral float does not survive the jsonb round trip as a float)
    };
    $apIntent = static fn(string $res) => json_encode(['kind'=>'Hunt','sourceId'=>'1531903-Swamp Animal Traders.mod','resourceId'=>$res,'quantity'=>3,
        'discoveryRef'=>['candidateId'=>'activity-proposal:1:1','targetSerial'=>5001],'agreedTargets'=>[],'routeRef'=>['candidateId'=>'local:s1:1']]);
    $apTurn = static function(array $request, ?array $record) use ($apStore): array {
        $ticket = $apStore->prepareChat(['context'=>$request['context']]);
        $apStore->transaction(static fn() => $apStore->claimChat($ticket));
        return ['ticket'=>$ticket,'request'=>$request,'record'=>$record,'affinity'=>10,'availability'=>['available'=>true]];
    };
    $apReply = static fn(string $decision, string $intent) => json_encode(['action'=>'Talk','activity_decision'=>$decision,'activity_intent'=>$intent,
        'travel_decision'=>'NONE','deal_decision'=>'NONE','deal_terms'=>'']);
    $apRows = static fn(int $actor) => $apDb->fetchAll('SELECT record FROM stobe_activity_record WHERE world_id=$1 AND actor=$2', [$apWorld, $actor]);

    // (a) ACCEPT + complete valid intent + record=null -> an offer is displayed and a 'proposed' record is stored; nothing is granted.
    $a = 7101; $text = 'Sure, let us go.'; $actions = ['Follow'];
    $ok = stobeActivityChatFinish($apTurn($apRequest($a, 'Hunt 3 meat with me'), null), $apReply('ACCEPT', $apIntent($apRes)), $text, $actions);
    $rows = $apRows($a); $rec = $rows ? json_decode($rows[0]['record'], true) : null;
    check('accept-propose: ACCEPT + valid intent + no offer is treated as an offer', $ok === true && count($rows) === 1 && ($rec['status'] ?? '') === 'proposed' && $actions === [], [$ok, $rows, $actions]);
    check('accept-propose: the offer text replaces the model prose', $text !== 'Sure, let us go.' && $text !== '' && !str_contains($text, 'not a workable option'), $text);
    $out = $apDb->fetchAll('SELECT 1 FROM stobe_activity_outbox WHERE world_id=$1 AND actor=$2', [$apWorld, $a]);
    check('accept-propose: nothing is granted (no outbox grant)', !$out, $out);

    // (b) ACCEPT + empty intent + no offer is still rejected, nothing stored.
    foreach (['' => 'empty', '{}' => 'empty object'] as $intentText => $label) {
        $b = 7102 + strlen($intentText); $text = 'Sure.'; $actions = ['Follow'];
        $ok = stobeActivityChatFinish($apTurn($apRequest($b, 'yes'), null), $apReply('ACCEPT', $intentText), $text, $actions);
        check("accept-propose: ACCEPT + $label intent + no offer is still rejected", $ok === true && !$apRows($b) && $actions === [] && str_contains($text, 'not a workable option'), [$ok, $text]);
    }

    // (c) ACCEPT with an existing proposed record still accepts it (the model intent is ignored).
    try {
    $c = 7110; $req = $apRequest($c, 'yes');
    $setup = $req; $setup['nativeFacts']['npcWilling'] = true;
    $prop = stobeActivityAdapter($setup)->propose($req['context'], json_decode($apIntent($apRes), true));
    $apStore->transaction(static function() use ($apStore, $prop): void { $apStore->propose($prop); });
    $req['consent'] = ['origin'=>'native_player_chat','worldId'=>$apWorld,'actor'=>$c,'requester'=>$apPlayer,'proposalId'=>$prop['agreement']['id'],
        'revision'=>$prop['revision'],'scopeDigest'=>$prop['scopeDigest'],'proposalWasDisplayed'=>true];
    $req['context']['now'] = 1005; // the answer comes after the offer
    $text = 'Alright.'; $actions = [];
    $ok = stobeActivityChatFinish($apTurn($req, $prop), $apReply('ACCEPT', ''), $text, $actions);
    $rows = $apRows($c); $rec = $rows ? json_decode($rows[0]['record'], true) : null;
    check('accept-propose: ACCEPT with an existing proposed record still accepts', $ok === true && count($rows) === 1 && ($rec['status'] ?? '') === 'accepted' && ($rec['agreement']['id'] ?? '') === $prop['agreement']['id'], [$ok, $text]);
    } catch (Throwable $e) { check('accept-propose: existing-record accept ran without exception', false, get_class($e) . ': ' . $e->getMessage()); }
}

