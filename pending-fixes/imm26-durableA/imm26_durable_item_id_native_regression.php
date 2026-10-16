<?php
// imm26 10-f OPTION A: restitution after a save/load, matched by the NATIVE durable item id (sdi1-...), option B fingerprint as fallback.
// Fails on the baseline server (a cross-load return was always return_unattributed / no verified repair).
// Run: flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/imm26_durable_item_id_native_regression.php
// Touches only campaigns 'campDur*' and NPCs named 'DurA *'; restores the setting it changes.
declare(strict_types=1);
set_exception_handler(function (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), ' @', basename($e->getFile()), ':', $e->getLine(), "\n"; exit(1); });
if (!in_array(getenv('STOBE_DB_NAME'), ['stobe_test', 'stobe_social_phase1_test'], true)) throw new RuntimeException('Dedicated test DB required');
require_once __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/social_runtime.php';
require_once __DIR__ . '/../lib/social_repair_agreements.php';
$db = $GLOBALS['db']; $n = 0;
function ok(bool $c, string $what): void { global $n; if (!$c) throw new RuntimeException('FAIL: ' . $what); ++$n; }
function sql(string $s, array $p = []): mixed { $r = $GLOBALS['db']->exec($s, $p); if ($r === false) throw new RuntimeException('SQL failed: ' . $s); return $r; }
function one(string $s, array $p = []): ?array { return pg_fetch_assoc(sql($s, $p)) ?: null; }
function setting(string $id, ?string $v): void {
    if ($v === null) sql('DELETE FROM general_settings WHERE id=$1', [$id]);
    else sql('INSERT INTO general_settings(id,value) VALUES($1,$2) ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value', [$id, $v]);
}
$savedId = one('SELECT value FROM general_settings WHERE id=$1', ['STOBE_REPAIR_DURABLE_ID_ENABLED']); $savedId = $savedId ? $savedId['value'] : null;
$savedFp = one('SELECT value FROM general_settings WHERE id=$1', ['STOBE_REPAIR_FINGERPRINT_ENABLED']); $savedFp = $savedFp ? $savedFp['value'] : null;
$savedMode = one('SELECT value FROM general_settings WHERE id=$1', ['SOCIAL_RELATIONSHIP_MODE']); $savedMode = $savedMode ? $savedMode['value'] : null;
function cleanup(): void {
    foreach (['social_event_inbox','social_incident','social_belief','social_effect','social_evidence','social_checkpoint'] as $t) sql("DELETE FROM $t WHERE campaign_id LIKE 'campDurA%'");
    sql("DELETE FROM core_npc_master_history WHERE name LIKE 'DurA %'"); sql("DELETE FROM core_npc WHERE name LIKE 'DurA %'");
}
cleanup();
setting('SOCIAL_RELATIONSHIP_MODE', 'enabled'); setting('STOBE_REPAIR_FINGERPRINT_ENABLED', null); setting('STOBE_REPAIR_DURABLE_ID_ENABLED', null);
const P = ['DurA Owner'=>8101, 'DurA Thief'=>8102, 'DurA Owner2'=>8103, 'DurA Thief2'=>8104, 'DurA Owner3'=>8105, 'DurA Thief3'=>8106,
    'DurA Owner4'=>8107, 'DurA Thief4'=>8108, 'DurA Owner5'=>8109, 'DurA Thief5'=>8110, 'DurA Owner6'=>8111, 'DurA Thief6'=>8112, 'DurA Owner7'=>8113, 'DurA Thief7'=>8114];
foreach (P as $name => $serial) sql("INSERT INTO core_npc(name,extended_data,metadata) VALUES($1,'{}'::jsonb,jsonb_build_object('storage_id',$2::text))", [$name, 'hand_' . $serial]);
$store = new SocialStore($db); $seq = 0;

// A "load" = (epoch, session). Entities and item keys are load-local, storage ids are the durable character identity.
function ent(string $name, string $epoch, string $session, bool $conscious = true): array {
    $serial = P[$name];
    return ['entity_key'=>"$session:$epoch:$serial", 'serial'=>$serial, 'name'=>$name, 'storage_id'=>"hand_$serial", 'faction'=>'Blue', 'in_player_faction'=>false, 'conscious'=>$conscious];
}
function send(string $camp, string $epoch, string $session, array $actor, array $target, array $facts, int $ts): array {
    global $seq, $store; ++$seq;
    $e = ['schema_version'=>1, 'event_id'=>"$session:$epoch:$seq", 'incident_id'=>"$session:$epoch:$seq", 'campaign_id'=>$camp, 'timeline_epoch'=>$epoch, 'native_session_id'=>$session,
        'sequence'=>$seq, 'game_ts'=>$ts, 'event_kind'=>'item_transfer', 'origin'=>'gameplay', 'actor'=>$actor, 'target'=>$target,
        'state_before'=>[], 'state_after'=>[], 'witnesses'=>[], 'facts'=>['source'=>'structured'] + $facts];
    $r = $store->ingest($e, ['campaign_id'=>$camp, 'timeline_epoch'=>$epoch, 'native_session_id'=>$session], 'enabled');
    return $r;
}
// $stacks: list of [item_key, prototype_id, type_key, quantity, ?durable_item_id]
function evidence(array $stacks, string $from, string $to): array {
    $items = [];
    foreach ($stacks as $s) {
        $row = ['item_key'=>$s[0], 'prototype_id'=>$s[1], 'type_key'=>$s[2], 'quantity'=>$s[3], 'from_storage_id'=>$from, 'to_storage_id'=>$to];
        if (isset($s[4])) $row['durable_item_id'] = $s[4];
        $items[] = $row;
    }
    return ['verified'=>true, 'method'=>'same_live_item_whole_stack', 'items'=>$items];
}
function totals(array $stacks): array { $t = []; foreach ($stacks as $s) $t[$s[2]] = ($t[$s[2]] ?? 0) + $s[3]; return $t; }
function theft(string $camp, string $epoch, string $session, string $thief, string $owner, array $stacks, int $ts): void {
    $items = totals($stacks);
    $r = send($camp, $epoch, $session, ent($thief, $epoch, $session), ent($owner, $epoch, $session), ['items'=>$items, 'to_ground'=>false, 'food_items'=>[], 'recipient_hunger'=>null,
        'stolen_items'=>$items, 'caught'=>true, 'loser_inventory_total'=>20, 'loser_hunger'=>null,
        'transfer_evidence'=>evidence($stacks, 'hand_' . P[$owner], 'hand_' . P[$thief])], $ts);
    if (($r['status'] ?? '') !== 'captured') throw new RuntimeException('FAIL: theft not captured: ' . json_encode($r));
}
function giveBack(string $camp, string $epoch, string $session, string $thief, string $owner, array $stacks, int $ts): array {
    $items = totals($stacks);
    $r = send($camp, $epoch, $session, ent($owner, $epoch, $session), ent($thief, $epoch, $session), ['items'=>$items, 'to_ground'=>false, 'food_items'=>[], 'recipient_hunger'=>null,
        'stolen_items'=>[], 'caught'=>null, 'loser_inventory_total'=>10, 'loser_hunger'=>2.0,
        'transfer_evidence'=>evidence($stacks, 'hand_' . P[$thief], 'hand_' . P[$owner])], $ts);
    if (($r['status'] ?? '') !== 'captured') throw new RuntimeException('FAIL: return not captured: ' . json_encode($r));
    return $r;
}
function repairState(string $camp): ?array {
    $row = one("SELECT state FROM social_incident WHERE campaign_id=\$1 AND state->>'kind'='social_repair' ORDER BY game_ts DESC LIMIT 1", [$camp]);
    return $row ? json_decode($row['state'], true) : null;
}
function credited(string $camp): int { $s = repairState($camp); return $s ? array_sum(array_map('intval', $s['returned_quantities'] ?? [])) : 0; }
function statusOf(array $r): string { return strval($r['effects'][0]['status'] ?? ''); }
const A = ['4', 'sA']; const B = ['5', 'sB']; const C = ['6', 'sC'];
$T = 100000;
const ID1 = 'sdi1-00112233aabbccdd'; const ID2 = 'sdi1-ffeeddcc99887766'; const ID3 = 'sdi1-1234567890abcdef';

// 1. THE FIX: reload between theft and return, the item has a new load-local key (hand_777) and the SAME durable id -> credited to the ORIGINAL item,
//    even though the type fingerprint would be ambiguous (two identical stolen stacks, only one carries the returned id).
theft('campDurAX', ...A, ...['DurA Thief', 'DurA Owner', [['hand_601', 'Knife_proto', 'knife', 1, ID1], ['hand_602', 'Knife_proto', 'knife', 1, ID2]], $T]);
giveBack('campDurAX', ...B, ...['DurA Thief', 'DurA Owner', [['hand_777', 'Knife_proto', 'knife', 1, ID2]], $T + 600]);
$s = repairState('campDurAX');
ok(credited('campDurAX') === 1, 'cross-load return with the same durable id is credited even when the type fingerprint is ambiguous (' . json_encode($s['returned_quantities'] ?? null) . ')');
ok(isset($s['verified_items']['hand_602']) && !isset($s['verified_items']['hand_601']) && ($s['verified_items']['hand_602']['return_item_key'] ?? '') === 'hand_777',
   'credit is recorded against the ORIGINAL item that carried that id (hand_602), not the other identical knife');

// 2. A returned item with an id that matches NO original is a known different object: never credited, and never rescued by the fingerprint.
theft('campDurAWrong', ...A, ...['DurA Thief2', 'DurA Owner2', [['hand_611', 'Knife_proto', 'knife', 1, ID1]], $T]);
$r = giveBack('campDurAWrong', ...B, ...['DurA Thief2', 'DurA Owner2', [['hand_788', 'Knife_proto', 'knife', 1, ID3]], $T + 600]);
ok(credited('campDurAWrong') === 0 && statusOf($r) === 'return_unattributed', 'returned item with a different durable id: NOT credited, not fingerprinted (' . statusOf($r) . ')');

// 3. Fallback to option B: original carried an id but the returned item has none (id lost) -> unique fingerprint still credits.
theft('campDurAFall', ...A, ...['DurA Thief3', 'DurA Owner3', [['hand_621', 'IronBar_proto', 'iron bar', 2, ID1]], $T]);
giveBack('campDurAFall', ...B, ...['DurA Thief3', 'DurA Owner3', [['hand_789', 'IronBar_proto', 'iron bar', 2]], $T + 600]);
ok(credited('campDurAFall') === 2, 'no id on the returned item: option B fingerprint fallback credits');
// 3b. Neither side has an id (old DLL / ground item): option B unchanged.
theft('campDurANone', ...A, ...['DurA Thief4', 'DurA Owner4', [['hand_631', 'IronBar_proto', 'iron bar', 2]], $T]);
giveBack('campDurANone', ...B, ...['DurA Thief4', 'DurA Owner4', [['hand_790', 'IronBar_proto', 'iron bar', 2]], $T + 600]);
ok(credited('campDurANone') === 2, 'neither side has an id: option B fingerprint unchanged');

// 4. Identity is exact: a smaller whole stack (thief used some) with the same id is credited for what came back; a LARGER one is not.
theft('campDurAQty', ...A, ...['DurA Thief5', 'DurA Owner5', [['hand_641', 'Bread_proto', 'bread', 5, ID1]], $T]);
giveBack('campDurAQty', ...B, ...['DurA Thief5', 'DurA Owner5', [['hand_791', 'Bread_proto', 'bread', 3, ID1]], $T + 600]);
ok(credited('campDurAQty') === 3, 'same id, smaller stack (3 of 5 came back): credited 3');
theft('campDurAQty2', ...A, ...['DurA Thief6', 'DurA Owner6', [['hand_651', 'Bread_proto', 'bread', 2, ID1]], $T]);
$r = giveBack('campDurAQty2', ...B, ...['DurA Thief6', 'DurA Owner6', [['hand_792', 'Bread_proto', 'bread', 4, ID1]], $T + 600]);
ok(credited('campDurAQty2') === 0, 'same id but MORE than was stolen: NOT credited');

// 5. Same id but a different prototype/type is not credited (corrupt or collided id).
theft('campDurAProto', ...A, ...['DurA Thief7', 'DurA Owner7', [['hand_661', 'IronBar_proto', 'iron bar', 2, ID1]], $T]);
$r = giveBack('campDurAProto', ...B, ...['DurA Thief7', 'DurA Owner7', [['hand_793', 'OtherBar_proto', 'iron bar', 2, ID1]], $T + 600]);
ok(credited('campDurAProto') === 0, 'same id, different prototype: NOT credited');

// 6. Duplicate id among the originals (never produced by the DLL) -> ambiguous, not id-matched (type fingerprint also ambiguous).
theft('campDurADup', ...A, ...['DurA Thief', 'DurA Owner', [['hand_671', 'Knife_proto', 'knife', 1, ID1], ['hand_672', 'Knife_proto', 'knife', 1, ID1]], $T]);
$r = giveBack('campDurADup', ...B, ...['DurA Thief', 'DurA Owner', [['hand_794', 'Knife_proto', 'knife', 1, ID1]], $T + 600]);
ok(credited('campDurADup') === 0, 'duplicate durable id among the stolen items: NOT credited');

// 7. Replay / second return of the same stack never exceeds the stolen quantity.
$again = giveBack('campDurAX', ...C, ...['DurA Thief', 'DurA Owner', [['hand_888', 'Knife_proto', 'knife', 1, ID2]], $T + 1200]);
ok(credited('campDurAX') === 1, 'second return of the same id after another reload does not exceed the stolen quantity');

// 8. Same-load path is unchanged by ids (exact key).
theft('campDurASame', ...A, ...['DurA Thief2', 'DurA Owner2', [['hand_501', 'IronBar_proto', 'iron bar', 2, ID1]], $T]);
giveBack('campDurASame', ...A, ...['DurA Thief2', 'DurA Owner2', [['hand_501', 'IronBar_proto', 'iron bar', 2, ID1]], $T + 60]);
ok(credited('campDurASame') === 2, 'same load, same key: credited (unchanged)');

// 9. Kill switches: id off + fingerprint on -> the ambiguous fingerprint refuses; fingerprint off + id on -> the id match still credits; both unavailable -> nothing.
setting('STOBE_REPAIR_DURABLE_ID_ENABLED', '0');
theft('campDurAOff', ...A, ...['DurA Thief3', 'DurA Owner3', [['hand_681', 'Knife_proto', 'knife', 1, ID1], ['hand_682', 'Knife_proto', 'knife', 1, ID2]], $T]);
$r = giveBack('campDurAOff', ...B, ...['DurA Thief3', 'DurA Owner3', [['hand_795', 'Knife_proto', 'knife', 1, ID2]], $T + 600]);
ok(credited('campDurAOff') === 0, 'durable-id match disabled: the ambiguous fingerprint refuses');
setting('STOBE_REPAIR_DURABLE_ID_ENABLED', null);
setting('STOBE_REPAIR_FINGERPRINT_ENABLED', '0');
theft('campDurAOff2', ...A, ...['DurA Thief4', 'DurA Owner4', [['hand_691', 'Knife_proto', 'knife', 1, ID1], ['hand_692', 'Knife_proto', 'knife', 1, ID2]], $T]);
giveBack('campDurAOff2', ...B, ...['DurA Thief4', 'DurA Owner4', [['hand_796', 'Knife_proto', 'knife', 1, ID2]], $T + 600]);
ok(credited('campDurAOff2') === 1, 'fingerprint disabled but ids on: the id match still credits');
theft('campDurAOff3', ...A, ...['DurA Thief5', 'DurA Owner5', [['hand_701', 'IronBar_proto', 'iron bar', 2]], $T]);
giveBack('campDurAOff3', ...B, ...['DurA Thief5', 'DurA Owner5', [['hand_797', 'IronBar_proto', 'iron bar', 2]], $T + 600]);
ok(credited('campDurAOff3') === 0, 'fingerprint disabled, no ids: nothing credited');
setting('STOBE_REPAIR_FINGERPRINT_ENABLED', null);

// 10. Contract: a malformed durable_item_id rejects the event.
$bad = false;
try { theft('campDurABad', ...A, ...['DurA Thief6', 'DurA Owner6', [['hand_711', 'IronBar_proto', 'iron bar', 2, 'not-an-id']], $T]); } catch (Throwable $e) { $bad = true; }
ok($bad, 'malformed durable_item_id is rejected');

// 11. Matcher guards still apply to id matches (rollback / forged same epoch / swapped direction).
$ev = ['campaign_id'=>'c', 'timeline_epoch'=>'5', 'native_session_id'=>'sB'];
$row = ['timeline_epoch'=>'4']; $theftRow = ['native_session_id'=>'sA'];
$orig = [['item_key'=>'k1', 'prototype_id'=>'p', 'type_key'=>'t', 'quantity'=>1, 'durable_item_id'=>ID1, 'from_storage_id'=>'own', 'to_storage_id'=>'thf']];
$ret = [['item_key'=>'k9', 'prototype_id'=>'p', 'type_key'=>'t', 'quantity'=>1, 'durable_item_id'=>ID1, 'from_storage_id'=>'thf', 'to_storage_id'=>'own']];
ok(stobeSocialRepairFingerprintKeyMap($ev, $row, $theftRow, $ret, $orig, 'thf', 'own') === ['k9'=>'k1'], 'matcher: same id maps the load-local key to the original');
ok(stobeSocialRepairFingerprintKeyMap(['timeline_epoch'=>'3'] + $ev, $row, $theftRow, $ret, $orig, 'thf', 'own') === [], 'matcher: older epoch refused');
ok(stobeSocialRepairFingerprintKeyMap(['timeline_epoch'=>'4'] + $ev, $row, $theftRow, $ret, $orig, 'thf', 'own') === [], 'matcher: same epoch other session refused');
ok(stobeSocialRepairFingerprintKeyMap($ev, $row, $theftRow, $ret, $orig, 'own', 'thf') === [], 'matcher: swapped giver/recipient refused');

cleanup(); setting('STOBE_REPAIR_DURABLE_ID_ENABLED', $savedId); setting('STOBE_REPAIR_FINGERPRINT_ENABLED', $savedFp); setting('SOCIAL_RELATIONSHIP_MODE', $savedMode);
echo "OK imm26_durable_item_id_native_regression: $n checks passed\n";
