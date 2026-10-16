<?php
// imm26 wpR2: deals and repair agreements resume after a save/load. Run ONLY against a test database:
//   STOBE_DB_NAME=stobe_test php tests/imm26_wpR2_resume_regression.php
// Fails before the patch (deal windows expire across a reload, repair terms go IMPOSSIBLE on any load) and passes after.
require __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/negotiation_engine.php';
require_once __DIR__ . '/../lib/social_repair_agreements.php';
foreach (['STOBE_NEG_STOBE_LOG','STOBE_NEG_KFP_LOG'] as $v) {
    if (getenv($v) === false || getenv($v) === '') { $f = sys_get_temp_dir() . '/wpr2_' . strtolower($v) . '.log'; file_put_contents($f, ''); putenv("$v=$f"); }
}
$db = $GLOBALS['db'];
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
stobeNegEnsureSchema();
$NPC = 'WprTestNpc';
$made = [];
function mk(string $status, int $ageSeconds, string $kind = 'social'): string {
    global $db, $NPC, $made;
    $id = 'wpr2-' . bin2hex(random_bytes(6));
    $db->exec("INSERT INTO stobe_social_contract (contract_id,npc_name,player_name,status,terms,kind,updated_at)
               VALUES ($1,$2,'WprPlayer',$3,'[]'::jsonb,$4, NOW() - make_interval(secs => $5::double precision))", [$id, $NPC, $status, $kind, $ageSeconds]);
    $made[] = $id;
    return $id;
}
function st(string $id): string { global $db; $r = $db->fetchOne("SELECT status FROM stobe_social_contract WHERE contract_id=$1", [$id]); return strval($r['status'] ?? ''); }
function ageOf(string $id): int { global $db; $r = $db->fetchOne("SELECT EXTRACT(EPOCH FROM (NOW()-updated_at))::int AS a FROM stobe_social_contract WHERE contract_id=$1", [$id]); return intval($r['a'] ?? -1); }
function setAge(string $id, int $age): void { global $db; $db->exec("UPDATE stobe_social_contract SET updated_at=NOW() - make_interval(secs => $2::double precision) WHERE contract_id=$1", [$id, $age]); }
function clockAt(string $token, int $lastTick): void {
    global $db;
    try { $db->exec("DELETE FROM stobe_deal_clock"); $db->exec("INSERT INTO stobe_deal_clock (id,load_token,last_tick_unix) VALUES (1,$1,$2)", [$token, $lastTick]); } catch (Throwable $e) {}
}
function reloadTick(string $newToken): void { $GLOBALS['STOBE_DEAL_LOAD_TOKEN_OVERRIDE'] = $newToken; stobeNegTick(); }
function cleanup(): void { global $db, $made; foreach ($made as $id) { $db->exec("DELETE FROM stobe_negotiation_directive WHERE contract_id=$1", [$id]); $db->exec("DELETE FROM stobe_social_contract WHERE contract_id=$1", [$id]); } try { $db->exec("DELETE FROM stobe_deal_clock"); } catch (Throwable $e) {} }

try {
    putenv('STOBE_DEAL_RESUME_ENABLED'); // default on
    $GLOBALS['STOBE_DEAL_LOAD_TOKEN_OVERRIDE'] = 'c|1|s1';

    // 1. PROPOSED deal 9 min old at the last tick; the game was closed 5 min (reload). It must survive, then really expire.
    $p = mk('PROPOSED', 840);                 // wall age now 14 min = 9 min at the last tick + 5 min closed
    $a = mk('ACCEPTED', 400);                 // 100 s at the last tick (< 2 min window)
    $pOld = mk('PROPOSED', 960);              // 11 min at the last tick: already expired then
    clockAt('c|1|s1', time() - 300);
    reloadTick('c|2|s2');
    check('PROPOSED survives a reload inside its 10 min window', st($p) === 'PROPOSED', st($p));
    check('PROPOSED age is frozen across the reload (about 540 s)', abs(ageOf($p) - 540) <= 5, ageOf($p));
    check('ACCEPTED survives a reload inside its 2 min window', st($a) === 'ACCEPTED', st($a));
    check('a window that had already run out at the last tick is not revived', st($pOld) === 'EXPIRED', st($pOld));
    setAge($p, 640);                           // 100 s later it is really past 10 min
    setAge($a, 130);
    reloadTick('c|2|s2');                      // same load: no new pause
    check('PROPOSED really expires after the extended time', st($p) === 'EXPIRED', st($p));
    check('ACCEPTED really goes IMPOSSIBLE after the extended time', st($a) === 'IMPOSSIBLE', st($a));

    // 2. No reload (same load token): the wall-clock windows are unchanged.
    $q = mk('PROPOSED', 700);
    clockAt('c|2|s2', time() - 300);
    reloadTick('c|2|s2');
    check('same load: an expired offer still expires', st($q) === 'EXPIRED', st($q));

    // 3. Hard caps: one reload pauses at most 1200 s, one deal at most 3600 s in total.
    $c = mk('PROPOSED', 0);
    for ($n = 3; $n <= 7; $n++) { clockAt('c|' . ($n - 1) . '|s', time() - 5000); reloadTick('c|' . $n . '|s'); }
    $row = $db->fetchOne("SELECT resume_shift_total AS t, resume_shifts AS s FROM stobe_social_contract WHERE contract_id=$1", [$c]);
    check('total pause per deal is capped at 3600 s', intval($row['t'] ?? -1) === 3600, $row);
    check('a single reload pauses at most 1200 s', max(array_map(fn($x) => intval($x['seconds']), json_decode(strval($row['s'] ?? '[]'), true) ?: [[ 'seconds'=>99999 ]])) === 1200, $row);

    // 4. Kill switch.
    putenv('STOBE_DEAL_RESUME_ENABLED=0');
    $k = mk('PROPOSED', 840);
    clockAt('c|7|s', time() - 300);
    reloadTick('c|8|s');
    check('kill switch STOBE_DEAL_RESUME_ENABLED=0: no pause, offer expires as before', st($k) === 'EXPIRED', st($k));
    $kRow = $db->fetchOne("SELECT resume_shift_total AS t FROM stobe_social_contract WHERE contract_id=$1", [$k]);
    check('kill switch: nothing recorded', intval($kRow['t'] ?? -1) === 0, $kRow);
    putenv('STOBE_DEAL_RESUME_ENABLED');

    // 5. A pending NPC directive queued before the reload stays deliverable.
    $d = mk('AWAITING_PERFORMANCE', 0);
    $db->exec("INSERT INTO stobe_negotiation_directive (npc_name,kind,contract_id,payload,created_unix) VALUES ($1,'resume_deal',$2,'{}'::jsonb,$3)", [$NPC, $d, time() - 200]);
    clockAt('c|8|s', time() - 150);
    reloadTick('c|9|s');
    $dir = $db->fetchOne("SELECT created_unix FROM stobe_negotiation_directive WHERE contract_id=$1", [$d]);
    check('pending directive is shifted with the pause', abs(intval($dir['created_unix'] ?? 0) - (time() - 50)) <= 5, $dir);

    // 6. NPC-side 45 s dispatch window and the player-side pay window honour the pause (only pauses after the dispatch).
    $now = time();
    $deal = ['contract_id'=>'wpr2-x', 'npc_name'=>$NPC, 'npc_serial'=>0, 'player_name'=>'WprPlayer', 'status'=>'AWAITING_PERFORMANCE', 'kind'=>'social', 'baseline'=>[], 'term_state'=>[], 'deadline_gamets'=>0];
    $npcTerm = ['i'=>0, 'kind'=>'FIRST_AID', 'by'=>'npc', 'status'=>'DISPATCHED', 'dispatched_unix'=>$now - 100, 'evidence'=>[]];
    $paused = $deal + ['resume_shifts'=>[['at_unix'=>$now - 5, 'seconds'=>300]], 'resume_shift_total'=>300];
    $early = $deal + ['resume_shifts'=>[['at_unix'=>$now - 200, 'seconds'=>300]], 'resume_shift_total'=>300];
    check('NPC dispatch 45 s window is paused by a reload after the dispatch', stobeNegEvaluateTerm($npcTerm, $paused, 'WprPlayer', $now)['status'] === 'DISPATCHED');
    check('NPC dispatch window still times out with no pause', stobeNegEvaluateTerm($npcTerm, $deal, 'WprPlayer', $now)['status'] === 'IMPOSSIBLE');
    check('a pause from before the dispatch does not extend it', stobeNegEvaluateTerm($npcTerm, $early, 'WprPlayer', $now)['status'] === 'IMPOSSIBLE');
    $payTerm = ['i'=>0, 'kind'=>'GIVE_CATS', 'by'=>'player', 'status'=>'AWAITING_PLAYER', 'amount'=>100, 'dispatched_unix'=>$now - 100, 'deadline_unix'=>$now - 30, 'evidence'=>[]];
    check('player pay window is paused by a reload after it started', stobeNegEvaluateTerm($payTerm, $paused, 'WprPlayer', $now)['status'] === 'AWAITING_PLAYER');
    check('player pay window still expires with no pause', stobeNegEvaluateTerm($payTerm, $deal, 'WprPlayer', $now)['status'] === 'UNMET');

    if (!function_exists('stobeSocialRepairScopeCurrent')) { check('scope helper stobeSocialRepairScopeCurrent exists', false); function stobeSocialRepairScopeCurrent(array $s, array $c): bool { return ($s['timeline_epoch'] ?? null) === ($c['timeline_epoch'] ?? null) && ($s['campaign_id'] ?? null) === ($c['campaign_id'] ?? null) && ($s['native_session_id'] ?? null) === ($c['native_session_id'] ?? null); } } // before the patch: only exact scopes match
    // 7. Repair agreement scope: same campaign + later load continues; everything else is rejected.
    $scope = ['campaign_id'=>'camp1', 'timeline_epoch'=>'5', 'native_session_id'=>'sessA', 'giver_storage_id'=>'g1', 'recipient_storage_id'=>'r1', 'acceptance_gamets'=>0];
    $cur = fn(array $o) => $o + ['campaign_id'=>'camp1', 'timeline_epoch'=>'6', 'native_session_id'=>'sessB'];
    check('scope: identical scope is current', stobeSocialRepairScopeCurrent($scope, ['campaign_id'=>'camp1', 'timeline_epoch'=>'5', 'native_session_id'=>'sessA']));
    check('scope: same campaign, later load continues', stobeSocialRepairScopeCurrent($scope, $cur([])));
    check('scope: different campaign (another save) is rejected', !stobeSocialRepairScopeCurrent($scope, $cur(['campaign_id'=>'camp2'])));
    check('scope: older epoch (rollback) is rejected', !stobeSocialRepairScopeCurrent($scope, $cur(['timeline_epoch'=>'4'])));
    check('scope: same epoch other session (forged) is rejected', !stobeSocialRepairScopeCurrent($scope, $cur(['timeline_epoch'=>'5'])));
    check('scope: non-numeric epoch is rejected', !stobeSocialRepairScopeCurrent($scope, $cur(['timeline_epoch'=>'7x'])));
    check('scope: empty session is rejected', !stobeSocialRepairScopeCurrent($scope, $cur(['native_session_id'=>''])));
    check('scope: frozen scope without storage ids is rejected', !stobeSocialRepairScopeCurrent(['giver_storage_id'=>''] + $scope, $cur([])));
    putenv('STOBE_REPAIR_RESCOPE_ENABLED=0');
    check('kill switch STOBE_REPAIR_RESCOPE_ENABLED=0: later load is rejected again', !stobeSocialRepairScopeCurrent($scope, $cur([])));
    check('kill switch: identical scope still current', stobeSocialRepairScopeCurrent($scope, ['campaign_id'=>'camp1', 'timeline_epoch'=>'5', 'native_session_id'=>'sessA']));
    putenv('STOBE_REPAIR_RESCOPE_ENABLED');

    // 8. The term evaluator: scope gate (live session is authenticated server-side).
    $oldSession = $db->fetchOne("SELECT value FROM stobe_meta.settings WHERE key='PLAYTHROUGH_SESSION'");
    $oldCampaign = $db->fetchOne("SELECT value FROM public.conf_opts WHERE id='PLAYTHROUGH_CAMPAIGN_ID'");
    $oldMode = getSetting('SOCIAL_RELATIONSHIP_MODE', 'off');
    $character = str_repeat('ab', 16);
    $setSession = function (int $load, string $client, string $char) use ($db): void {
        $db->exec("INSERT INTO stobe_meta.settings (key,value) VALUES ('PLAYTHROUGH_SESSION',$1) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value",
            [json_encode(['status'=>'ready', 'auth_mode'=>'current_campaign', 'token'=>str_repeat('cd', 16), 'character_id'=>$char, 'load_id'=>$load, 'client_id'=>$client])]);
        $db->exec("INSERT INTO public.conf_opts (id,value) VALUES ('PLAYTHROUGH_CAMPAIGN_ID',$1) ON CONFLICT (id) DO UPDATE SET value=EXCLUDED.value", [$char]);
    };
    try {
        setSetting('SOCIAL_RELATIONSHIP_MODE', 'enabled');
        $setSession(5, 'clientA', $character);
        $s0 = stobeSocialScope($db);
        $evalScope = $s0 + ['giver_storage_id'=>'g1', 'recipient_storage_id'=>'r1', 'acceptance_gamets'=>0, 'deadline_gamets'=>PHP_INT_MAX >> 1];
        $evalDeal = ['contract_id'=>'wpr2-e', 'npc_name'=>$NPC, 'status'=>'AWAITING_PERFORMANCE', 'baseline'=>['repair_binding_scope'=>$evalScope, 'repair_action_tickets'=>[['term_index'=>0, 'action_id'=>str_repeat('a', 64)]]]];
        $evalTerm = ['i'=>0, 'kind'=>'GIVE_ITEM', 'by'=>'player', 'item'=>'Dried Meat', 'quantity'=>1, 'status'=>'AWAITING_PLAYER', 'evidence'=>[]];
        $notes = static fn(?array $t): string => strval(($t['evidence'] ?? [[]])[count($t['evidence'] ?? [[]]) - 1]['note'] ?? '');
        $setSession(5, 'clientA', $character);
        $r = stobeSocialRepairEvaluateAgreementTicketTerm($evalTerm, $evalDeal, time());
        check('term gate: same load passes the scope gate', $notes($r) !== 'exact_restitution_scope_changed', $notes($r));
        $setSession(9, 'clientB', $character);
        $r = stobeSocialRepairEvaluateAgreementTicketTerm($evalTerm, $evalDeal, time());
        check('term gate: later load of the same campaign no longer goes IMPOSSIBLE scope_changed', $notes($r) !== 'exact_restitution_scope_changed', $notes($r));
        $setSession(9, 'clientB', str_repeat('ef', 16));
        $r = stobeSocialRepairEvaluateAgreementTicketTerm($evalTerm, $evalDeal, time());
        check('term gate: another save (campaign) is still IMPOSSIBLE scope_changed', ($r['status'] ?? '') === 'IMPOSSIBLE' && $notes($r) === 'exact_restitution_scope_changed', $notes($r));
        $setSession(9, 'clientB', $character);
        putenv('STOBE_REPAIR_RESCOPE_ENABLED=0');
        $r = stobeSocialRepairEvaluateAgreementTicketTerm($evalTerm, $evalDeal, time());
        check('term gate: kill switch restores the old behaviour', ($r['status'] ?? '') === 'IMPOSSIBLE' && $notes($r) === 'exact_restitution_scope_changed', $notes($r));
        putenv('STOBE_REPAIR_RESCOPE_ENABLED');
    } finally {
        if ($oldSession) $db->exec("UPDATE stobe_meta.settings SET value=$1 WHERE key='PLAYTHROUGH_SESSION'", [$oldSession['value']]);
        if ($oldCampaign) $db->exec("UPDATE public.conf_opts SET value=$1 WHERE id='PLAYTHROUGH_CAMPAIGN_ID'", [$oldCampaign['value']]);
        else $db->exec("DELETE FROM public.conf_opts WHERE id='PLAYTHROUGH_CAMPAIGN_ID'");
        setSetting('SOCIAL_RELATIONSHIP_MODE', $oldMode);
    }
} finally {
    putenv('STOBE_DEAL_RESUME_ENABLED'); putenv('STOBE_REPAIR_RESCOPE_ENABLED');
    cleanup();
}
echo "\nwpR2 resume: $pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
