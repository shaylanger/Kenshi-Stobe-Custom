<?php
// imm26 WP 10d-S (row 10-d, "return the exact stolen item"): offline server regression for the exact-restitution chain.
// The payloads copy the REAL native shape of SOCIAL_CAPTURE kind=item_transfer from
//   C:\KenshiTestRuns\multi-instance\inst3\logs\20261015-173237-stop\stobe.log:1259 (verified machete, hand_478759776,
//   V=hand_971557632 -> T=hand_1216186496) and inst4 (stackable water: {"verified":false}).
// Chain: caught theft with verified exact proof -> the receiver gets the SAME item back (item_key kept, from/to reversed)
//   => social_repair incident + restitution_relief row (+1..+3); the theft row stays. Controls get no relief.
// Only rows of campaign camp10ds and the Rst* core_npc rows are touched (safe on any *_test DB).
// Run (scratch DB): STOBE_DB_NAME=stobe_10ds_test php tests/imm26_10dS_returned_property_regression.php
declare(strict_types=1);
$dbName = strval(getenv('STOBE_DB_NAME') ?: '');
if ($dbName === '' || $dbName === 'stobe' || !preg_match('/test/i', $dbName)) throw new RuntimeException('Set STOBE_DB_NAME to a test database');
require_once __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/social_runtime.php';
$db = $GLOBALS['db']; $pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
function sql(string $s, array $p = []): mixed { $r = $GLOBALS['db']->exec($s, $p); if ($r === false) throw new RuntimeException('SQL failed: ' . $s . ' ' . $GLOBALS['db']->GetLastError()); return $r; }
function one(string $s, array $p = []): mixed { $r = sql($s, $p); return pg_num_rows($r) ? pg_fetch_result($r, 0, 0) : null; }
const CAMP = 'camp10ds';
foreach (['social_event_inbox','social_incident','social_belief','social_effect','social_evidence','social_checkpoint'] as $t) sql("DELETE FROM $t WHERE campaign_id=$1", [CAMP]);
sql("DELETE FROM core_npc WHERE name LIKE 'Rst %'");
sql("INSERT INTO general_settings(id,value) VALUES('SOCIAL_RELATIONSHIP_MODE','enabled') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");
$store = new SocialStore($db); $seq = 0; $ts = 10000;

/** Scenario people: owner V, thief T. Serials copy the real log in scenario A; others are distinct so storage ids never collide. */
function person(string $name, int $serial, bool $conscious = true): array {
    return ['entity_key'=>"camp10ds:11:$serial", 'serial'=>$serial, 'name'=>$name, 'storage_id'=>"hand_$serial", 'faction'=>'Blue', 'in_player_faction'=>false, 'conscious'=>$conscious];
}
function makeNpc(string $name, int $serial, int $rows = 1): void {
    for ($i = 0; $i < $rows; ++$i)
        sql("INSERT INTO core_npc(name,extended_data,metadata) VALUES($1,'{}'::jsonb,jsonb_build_object('storage_id',$2::text))", [$name . ($i ? " dup$i" : ''), 'hand_' . $serial]);
}
/** Real native proof: whole-stack exact instance, v -> t on theft, t -> v on return. */
function proof(int $from, int $to, string $itemKey = 'hand_478759776', string $proto = '55411-ArkWeaponPack.mod', string $type = 'machete', int $qty = 1): array {
    return ['verified'=>true, 'method'=>'same_live_item_whole_stack', 'items'=>[['item_key'=>$itemKey, 'prototype_id'=>$proto, 'type_key'=>$type,
        'quantity'=>$qty, 'from_storage_id'=>"hand_$from", 'to_storage_id'=>"hand_$to"]]];
}
/** Raw ingest of a native item_transfer; returns the ingest result. */
function transfer(?array $actor, ?array $target, array $facts, string $session = 'sess10', string $epoch = '11'): array {
    global $seq, $store, $ts; ++$seq; $ts += 60;
    $e = ['schema_version'=>1, 'event_id'=>"camp10ds:$epoch:$seq", 'incident_id'=>"camp10ds:$epoch:$seq", 'campaign_id'=>CAMP, 'timeline_epoch'=>$epoch,
        'native_session_id'=>$session, 'sequence'=>$seq, 'game_ts'=>$ts, 'event_kind'=>'item_transfer', 'origin'=>'gameplay', 'actor'=>$actor, 'target'=>$target,
        'state_before'=>[], 'state_after'=>[], 'witnesses'=>[], 'facts'=>['source'=>'structured'] + $facts];
    return $store->ingest($e, ['campaign_id'=>CAMP, 'timeline_epoch'=>$epoch, 'native_session_id'=>$session], 'enabled');
}
/** Like transfer() but returns ['error'=>message] when the event contract rejects the payload. */
function tryTransfer(?array $actor, ?array $target, array $facts, string $session = 'sess10', string $epoch = '11'): array {
    try { return transfer($actor, $target, $facts, $session, $epoch); } catch (DomainException $e) { return ['error'=>$e->getMessage()]; }
}
/** Theft event exactly as the native emits it (actor = taker, target = loser). */
function theftFacts(array $proof, array $items, ?bool $caught = true, int $loserLeft = 5): array {
    return ['transfer_evidence'=>$proof, 'items'=>$items, 'to_ground'=>false, 'food_items'=>new stdClass(), 'recipient_hunger'=>3.0,
        'stolen_items'=>$items, 'caught'=>$caught, 'loser_inventory_total'=>$loserLeft, 'loser_hunger'=>0.972];
}
/** Return event: actor = receiver (the former owner), target = giver (the former thief). */
function returnFacts(array $proof, array $items): array {
    return ['transfer_evidence'=>$proof, 'items'=>$items, 'to_ground'=>false, 'food_items'=>new stdClass(), 'recipient_hunger'=>2.0,
        'stolen_items'=>new stdClass(), 'caught'=>null, 'loser_inventory_total'=>3, 'loser_hunger'=>2.0];
}
function stt(array $r): string { return strval($r['effects'][0]['status'] ?? ($r['status'] ?? '')); }
function relief(int $v, int $t): array {
    return array_map('intval', array_column(pg_fetch_all(sql("SELECT delta FROM social_effect WHERE campaign_id=$1 AND component='restitution_relief'
        AND detail->>'observer_storage_id'=$2 AND detail->>'culprit_storage_id'=$3", [CAMP, "hand_$v", "hand_$t"])) ?: [], 'delta'));
}
function count_one(string $q, array $p = []): int { return (int)one($q, $p); }
function theftRows(int $v, int $t): int {
    return count_one("SELECT count(*) FROM social_effect WHERE campaign_id=$1 AND component IN ('theft','petty_theft','major_theft','all_property_theft')
        AND detail->>'observer_storage_id'=$2 AND detail->>'culprit_storage_id'=$3", [CAMP, "hand_$v", "hand_$t"]);
}
function repairsFor(int $v, int $t): int {
    return count_one(
        "SELECT count(*) FROM social_incident r WHERE r.campaign_id=$1 AND r.state->>'kind'='social_repair' AND r.state->'material_receipts' IS NOT NULL
         AND EXISTS (SELECT 1 FROM jsonb_each(r.state->'material_receipts') m WHERE m.value->>'recipient_storage_id'=$2 AND m.value->>'giver_storage_id'=$3)", [CAMP, "hand_$v", "hand_$t"]);
}
function giftRows(int $v, int $t): int {
    return count_one("SELECT count(*) FROM social_effect WHERE campaign_id=$1 AND component='gift'
        AND detail->>'observer_storage_id'=$2 AND detail->>'culprit_storage_id'=$3", [CAMP, "hand_$v", "hand_$t"]);
}
$KATANA = ['item_key'=>'hand_478759776', 'proto'=>'55411-ArkWeaponPack.mod', 'type'=>'machete'];

// ---------------- A: the happy path with the exact real serials ----------------
[$V, $T] = [971557632, 1216186496];
makeNpc('Rst Owner A', $V); makeNpc('Rst Thief A', $T);
$vp = person('Rst Owner A', $V); $tp = person('Rst Thief A', $T);
$r = transfer($tp, $vp, theftFacts(proof($V, $T), ['machete'=>1]));
check('A1: theft captured', ($r['status'] ?? '') === 'captured' && stt($r) === 'effect' || ($r['status'] ?? '') === 'captured', $r);
$theftInc = sql("SELECT state FROM social_incident WHERE campaign_id=$1 AND state->>'kind'='theft' AND state->'owner'->>'storage_id'=$2", [CAMP, "hand_$V"]);
$ts0 = pg_num_rows($theftInc) ? json_decode(pg_fetch_result($theftInc, 0, 0), true) : [];
check('A2: theft incident keeps the verified exact proof (hand_478759776)', ($ts0['transfer_evidence']['method'] ?? '') === 'same_live_item_whole_stack'
    && ($ts0['transfer_evidence']['items'][0]['item_key'] ?? '') === 'hand_478759776' && ($ts0['caught'] ?? null) === true, $ts0);
check('A3: caught theft wrote the harm row', theftRows($V, $T) === 1, theftRows($V, $T));
$theftDelta = (int)one("SELECT delta FROM social_effect WHERE campaign_id=$1 AND component IN ('theft','petty_theft') AND detail->>'observer_storage_id'=$2 LIMIT 1", [CAMP, "hand_$V"]);
check('A4: theft delta in the pinned range (-18..-3)', $theftDelta <= -3 && $theftDelta >= -18, $theftDelta);
// the thief hands the SAME machete back: same item_key, from/to reversed, actor = receiver V, target = giver T
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]));
$rel = relief($V, $T);
check('A5: restitution_relief row exists with +1..+3', count($rel) === 1 && $rel[0] >= 1 && $rel[0] <= 3, [$rel, $r]);
check('A6: a social_repair incident records the exact item', repairsFor($V, $T) === 1
    && count_one("SELECT count(*) FROM social_incident WHERE campaign_id=$1 AND state->>'kind'='social_repair' AND state->'verified_items' ? 'hand_478759776'", [CAMP]) === 1);
check('A7: the theft row is NOT erased (theft is remembered)', theftRows($V, $T) === 1 && (int)one("SELECT delta FROM social_effect WHERE campaign_id=$1 AND component IN ('theft','petty_theft') AND detail->>'observer_storage_id'=$2 LIMIT 1", [CAMP, "hand_$V"]) === $theftDelta);
check('A8: the return is not scored as a gift', giftRows($V, $T) === 0);
$net = (int)one("SELECT sum(delta) FROM social_effect WHERE campaign_id=$1 AND applied AND detail->>'observer_storage_id'=$2 AND detail->>'culprit_storage_id'=$3", [CAMP, "hand_$V", "hand_$T"]);
check('A9: net relationship is still negative after the return', $net < 0 && $net === $theftDelta + $rel[0], [$net, $theftDelta, $rel]);
// handing the same item over again (a new polling event, no transfer_id) must not pay twice
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]));
check('A10: repeat of the same return: duplicate_return, no second relief row', count(relief($V, $T)) === 1 && stt($r) === 'duplicate_return', [relief($V, $T), $r]);

// ---------------- B: stackable / unverified ----------------
[$V, $T] = [2000001, 2000002];
makeNpc('Rst Owner B', $V); makeNpc('Rst Thief B', $T);
$vp = person('Rst Owner B', $V); $tp = person('Rst Thief B', $T);
transfer($tp, $vp, theftFacts(['verified'=>false], ['water'=>1]));
check('B1: stackable theft (verified:false) keeps no exact proof', count_one("SELECT count(*) FROM social_incident WHERE campaign_id=$1 AND state->>'kind'='theft' AND state->'owner'->>'storage_id'=$2
    AND state->'transfer_evidence' IS NOT NULL AND state->>'transfer_evidence' <> 'null'", [CAMP, "hand_$V"]) === 0);
$r = transfer($vp, $tp, returnFacts(proof($T, $V, 'hand_1', 'p.mod', 'water'), ['water'=>1]));
check('B2: verified return of an unproven theft: no restitution', relief($V, $T) === [] && repairsFor($V, $T) === 0, [relief($V, $T), $r]);
$r = transfer($vp, $tp, returnFacts(['verified'=>false], ['water'=>1]));
check('B3: unverified return (stack merge): no restitution, no gift credit', relief($V, $T) === [] && giftRows($V, $T) === 0 && stt($r) === 'return_unverified', [stt($r), relief($V, $T)]);

// ---------------- C: wrong item identity ----------------
[$V, $T] = [2000011, 2000012];
makeNpc('Rst Owner C', $V); makeNpc('Rst Thief C', $T);
$vp = person('Rst Owner C', $V); $tp = person('Rst Thief C', $T);
transfer($tp, $vp, theftFacts(proof($V, $T), ['machete'=>1]));
$r = transfer($vp, $tp, returnFacts(proof($T, $V, 'hand_999999999'), ['machete'=>1]));
check('C1: different item_key (a new machete): return_unattributed, no relief', relief($V, $T) === [] && stt($r) === 'return_unattributed', [stt($r), relief($V, $T)]);
$r = transfer($vp, $tp, returnFacts(proof($T, $V, 'hand_478759776', 'other.mod'), ['machete'=>1]));
check('C2: same key but different prototype: no relief', relief($V, $T) === [], [stt($r), relief($V, $T)]);
$r = tryTransfer($vp, $tp, returnFacts(proof($V, $T), ['machete'=>1]));
check('C3: wrong direction (proof V->T on a T->V event) is rejected by the event contract, no relief', isset($r['error']) && relief($V, $T) === [], $r);
$wrong = proof($T, $V); $wrong['items'][0]['to_storage_id'] = 'hand_555';
$r = tryTransfer($vp, $tp, returnFacts($wrong, ['machete'=>1]));
check('C4: item handed to a third party instead of V is rejected by the event contract, no relief', isset($r['error']) && relief($V, $T) === [], $r);

// ---------------- D: different native session / epoch ----------------
[$V, $T] = [2000021, 2000022];
makeNpc('Rst Owner D', $V); makeNpc('Rst Thief D', $T);
$vp = person('Rst Owner D', $V); $tp = person('Rst Thief D', $T);
transfer($tp, $vp, theftFacts(proof($V, $T), ['machete'=>1]));
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]), 'sess10-after-restart');
check('D1: return in a different native session: no relief', relief($V, $T) === [], [stt($r), relief($V, $T)]);
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]), 'sess10', '12');
check('D2: return after a save/load (different timeline epoch): no relief', relief($V, $T) === [], [stt($r), relief($V, $T)]);
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]));
check('D3: the same return inside the original session still pays (the controls above consumed nothing)', count(relief($V, $T)) === 1, [stt($r), relief($V, $T)]);

// ---------------- E: unconscious receiver ----------------
[$V, $T] = [2000031, 2000032];
makeNpc('Rst Owner E', $V); makeNpc('Rst Thief E', $T);
$vp = person('Rst Owner E', $V); $tp = person('Rst Thief E', $T);
transfer($tp, $vp, theftFacts(proof($V, $T), ['machete'=>1]));
$r = transfer(person('Rst Owner E', $V, false), $tp, returnFacts(proof($T, $V), ['machete'=>1]));
check('E1: receiver unconscious: return_awareness_unverified, no relief', relief($V, $T) === [] && stt($r) === 'return_awareness_unverified', [stt($r), relief($V, $T)]);

// ---------------- F: duplicate core_npc rows for one storage id ----------------
[$V, $T] = [2000041, 2000042];
makeNpc('Rst Owner F', $V, 2); makeNpc('Rst Thief F', $T);
$vp = person('Rst Owner F', $V); $tp = person('Rst Thief F', $T);
transfer($tp, $vp, theftFacts(proof($V, $T), ['machete'=>1]));
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]));
check('F1: two core_npc rows for the owner: material recorded, no relief row', relief($V, $T) === [] && stt($r) === 'material_recorded_identity_unresolved' && repairsFor($V, $T) === 1, [stt($r), relief($V, $T)]);

// ---------------- G: no prior theft = plain gift ----------------
[$V, $T] = [2000051, 2000052];
makeNpc('Rst Owner G', $V); makeNpc('Rst Thief G', $T);
$vp = person('Rst Owner G', $V); $tp = person('Rst Thief G', $T);
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]));
check('G1: no prior theft: no restitution, no repair incident', relief($V, $T) === [] && repairsFor($V, $T) === 0, [stt($r), relief($V, $T)]);
check('G2: it is an ordinary gift to the receiver', giftRows($V, $T) === 1, giftRows($V, $T));

// ---------------- H: theft not caught (V did not see it): nothing to repair ----------------
[$V, $T] = [2000061, 2000062];
makeNpc('Rst Owner H', $V); makeNpc('Rst Thief H', $T);
$vp = person('Rst Owner H', $V); $tp = person('Rst Thief H', $T);
transfer($tp, $vp, theftFacts(proof($V, $T), ['machete'=>1], null));
$r = transfer($vp, $tp, returnFacts(proof($T, $V), ['machete'=>1]));
check('H1: uncaught theft (caught:null) has no recorded harm: no relief row', relief($V, $T) === [] && theftRows($V, $T) === 0, [stt($r), relief($V, $T)]);

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
