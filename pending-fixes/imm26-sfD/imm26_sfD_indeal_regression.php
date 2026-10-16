<?php
// imm26-sfD: social_property.php inDeal() must not treat a finished contract (resolved_at NULL) as an open deal forever.
// Run (WSL): bash /root/imm26/runsocial.sh <tree> imm26_sfD_indeal_regression   (dedicated DB stobe_social_phase1_test, like social_property_regression)
declare(strict_types=1);
if (getenv('STOBE_DB_NAME') !== 'stobe_social_phase1_test') throw new RuntimeException('Dedicated social DB required');
require_once __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/social_runtime.php';
require_once __DIR__ . '/../lib/social_agreements.php';
require_once __DIR__ . '/../lib/negotiation_engine.php';
$db = $GLOBALS['db']; $n = 0;
function ok(bool $c, string $what): void { global $n; if (!$c) throw new RuntimeException('FAIL: ' . $what); ++$n; }
function sql(string $s, array $p = []): mixed { $r = $GLOBALS['db']->exec($s, $p); if ($r === false) throw new RuntimeException('SQL failed: ' . $s . ' ' . $GLOBALS['db']->GetLastError()); return $r; }

// one (taker, giver) pair per case so no day budget / dedupe interferes: serial, faction, squad
$names = [];
for ($i = 1; $i <= 8; ++$i) { $names["Sd Taker $i"] = [700 + $i, 'Blue', false]; $names["Sd Giver $i"] = [720 + $i, 'Nameless', false]; }
foreach ($names as $name => [$serial]) {
    sql('DELETE FROM core_npc_master_history WHERE name=$1', [$name]); sql('DELETE FROM core_npc WHERE name=$1', [$name]);
    sql("INSERT INTO core_npc(name,extended_data,metadata) VALUES($1,'{}'::jsonb,jsonb_build_object('storage_id',$2::text))", [$name, 'hand_' . $serial]);
}
sql("DELETE FROM general_settings WHERE id='SOCIAL_RELATIONSHIP_MODE'; INSERT INTO general_settings(id,value) VALUES('SOCIAL_RELATIONSHIP_MODE','enabled')");
foreach (['social_event_inbox','social_incident','social_belief','social_effect','social_evidence','social_checkpoint'] as $t) sql("DELETE FROM $t");
$store = new SocialStore($db); $seq = 0;
function ent(string $name): array {
    global $names; [$serial, $faction, $squad] = $names[$name];
    return ['entity_key'=>"camp5c:11:$serial", 'serial'=>$serial, 'name'=>$name, 'storage_id'=>"hand_$serial", 'faction'=>$faction, 'in_player_faction'=>$squad, 'conscious'=>true];
}
function hand(string $to, string $from, int $ts): string {
    global $seq, $store; ++$seq;
    $e = ['schema_version'=>1, 'event_id'=>"camp5c:11:$seq", 'incident_id'=>"camp5c:11:$seq", 'campaign_id'=>'camp5', 'timeline_epoch'=>'11', 'native_session_id'=>'sess5',
        'sequence'=>$seq, 'game_ts'=>$ts, 'event_kind'=>'item_transfer', 'origin'=>'gameplay', 'actor'=>ent($to), 'target'=>ent($from),
        'state_before'=>[], 'state_after'=>[], 'witnesses'=>[], 'facts'=>['source'=>'structured', 'items'=>['Iron Plates'=>1], 'to_ground'=>false, 'food_items'=>[],
            'recipient_hunger'=>null, 'stolen_items'=>[], 'caught'=>null, 'loser_inventory_total'=>10, 'loser_hunger'=>2.0]];
    $r = $store->ingest($e, ['campaign_id'=>'camp5', 'timeline_epoch'=>'11', 'native_session_id'=>'sess5'], 'enabled');
    if (($r['status'] ?? '') !== 'captured') throw new RuntimeException("FAIL: event $seq not captured: " . ($r['status'] ?? '?'));
    return strval($r['effects'][0]['status'] ?? '');
}
function contract(string $id, string $npc, string $status, int $perf, ?string $resolved, string $updated): void {
    sql("INSERT INTO stobe_social_contract(contract_id,npc_name,player_name,status,terms,performance_started_unix,resolved_at,updated_at) VALUES($1,$2,'Shay',$3,'[]'::jsonb,$4,"
        . ($resolved === null ? 'NULL' : $resolved) . ",$updated)", [$id, $npc, $status, $perf]);
}
try {
    sql("DELETE FROM stobe_social_contract WHERE contract_id LIKE 'sdtest%'");
    // 1. the sfD defect: CANCELLED, performance started, resolved_at NULL, last touched a day ago -> NOT a deal any more
    contract('sdtest-1', 'Sd Taker 1', 'CANCELLED', 1792128462, null, "now() - interval '1 day'");
    ok(hand('Sd Taker 1', 'Sd Giver 1', 1000) !== 'deal_payment', 'old CANCELLED contract with resolved_at NULL is not a deal (was: deal_payment forever)');
    // 2. same for EXPIRED / COMPLETE on the GIVER side
    contract('sdtest-2', 'Sd Giver 2', 'EXPIRED', 5, null, "now() - interval '2 hours'");
    ok(hand('Sd Taker 2', 'Sd Giver 2', 1010) !== 'deal_payment', 'old EXPIRED contract of the giver is not a deal');
    contract('sdtest-3', 'Sd Taker 3', 'COMPLETE', 5, null, "now() - interval '3 hours'");
    ok(hand('Sd Taker 3', 'Sd Giver 3', 1020) !== 'deal_payment', 'old COMPLETE contract with resolved_at NULL is not a deal');
    // 3. still a deal: awaiting performance / accepted with resolved_at NULL, whatever the age
    contract('sdtest-4', 'Sd Taker 4', 'AWAITING_PERFORMANCE', 1, null, "now() - interval '1 day'");
    ok(hand('Sd Taker 4', 'Sd Giver 4', 1030) === 'deal_payment', 'AWAITING_PERFORMANCE with resolved_at NULL is a deal');
    contract('sdtest-5', 'Sd Taker 5', 'ACCEPTED', 1, null, "now() - interval '1 day'");
    ok(hand('Sd Taker 5', 'Sd Giver 5', 1040) === 'deal_payment', 'ACCEPTED with resolved_at NULL is a deal');
    // 4. grace window kept: a contract that finished a minute ago (resolved_at set, or resolved_at NULL but touched a minute ago) still covers the payment
    contract('sdtest-6', 'Sd Taker 6', 'COMPLETE', 1, "now() - interval '1 minute'", "now() - interval '1 minute'");
    ok(hand('Sd Taker 6', 'Sd Giver 6', 1050) === 'deal_payment', 'COMPLETE resolved a minute ago: inside the 10-minute grace window');
    contract('sdtest-7', 'Sd Taker 7', 'CANCELLED', 1, null, "now() - interval '1 minute'");
    ok(hand('Sd Taker 7', 'Sd Giver 7', 1060) === 'deal_payment', 'CANCELLED touched a minute ago (resolved_at NULL): inside the grace window');
    // 5. a finished contract resolved long ago is not a deal
    contract('sdtest-8', 'Sd Taker 8', 'COMPLETE', 1, "now() - interval '1 hour'", "now() - interval '1 hour'");
    ok(hand('Sd Taker 8', 'Sd Giver 8', 1070) !== 'deal_payment', 'COMPLETE resolved an hour ago: outside the grace window');
} finally {
    sql("DELETE FROM stobe_social_contract WHERE contract_id LIKE 'sdtest%'");
    sql("UPDATE general_settings SET value='off' WHERE id='SOCIAL_RELATIONSHIP_MODE'");
}
echo "$n inDeal terminal-status regression checks passed\n";
