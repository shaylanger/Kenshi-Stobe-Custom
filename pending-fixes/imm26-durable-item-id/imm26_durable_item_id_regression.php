<?php
// imm26 durable item id: restitution after a save/load, matched by a strict server-side fingerprint (no native change).
// Fails on the baseline server (a cross-load return was always return_unattributed / no verified repair).
// Run: flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/imm26_durable_item_id_regression.php
// Touches only campaigns 'campDur*' and NPCs named 'Dur *'; restores the setting it changes.
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
$savedFp = one('SELECT value FROM general_settings WHERE id=$1', ['STOBE_REPAIR_FINGERPRINT_ENABLED']); $savedFp = $savedFp ? $savedFp['value'] : null;
$savedMode = one('SELECT value FROM general_settings WHERE id=$1', ['SOCIAL_RELATIONSHIP_MODE']); $savedMode = $savedMode ? $savedMode['value'] : null;
function cleanup(): void {
    foreach (['social_event_inbox','social_incident','social_belief','social_effect','social_evidence','social_checkpoint'] as $t) sql("DELETE FROM $t WHERE campaign_id LIKE 'campDur%'");
    sql("DELETE FROM core_npc_master_history WHERE name LIKE 'Dur %'"); sql("DELETE FROM core_npc WHERE name LIKE 'Dur %'");
}
cleanup();
setting('SOCIAL_RELATIONSHIP_MODE', 'enabled'); setting('STOBE_REPAIR_FINGERPRINT_ENABLED', null);
const P = ['Dur Owner'=>8101, 'Dur Thief'=>8102, 'Dur Owner2'=>8103, 'Dur Thief2'=>8104, 'Dur Owner3'=>8105, 'Dur Thief3'=>8106,
    'Dur Owner4'=>8107, 'Dur Thief4'=>8108, 'Dur Owner5'=>8109, 'Dur Thief5'=>8110, 'Dur Owner6'=>8111, 'Dur Thief6'=>8112, 'Dur Owner7'=>8113, 'Dur Thief7'=>8114];
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
// $stacks: list of [item_key, prototype_id, type_key, quantity]
function evidence(array $stacks, string $from, string $to): array {
    $items = [];
    foreach ($stacks as [$key, $proto, $type, $qty]) $items[] = ['item_key'=>$key, 'prototype_id'=>$proto, 'type_key'=>$type, 'quantity'=>$qty, 'from_storage_id'=>$from, 'to_storage_id'=>$to];
    return ['verified'=>true, 'method'=>'same_live_item_whole_stack', 'items'=>$items];
}
function totals(array $stacks): array { $t = []; foreach ($stacks as [, , $type, $qty]) $t[$type] = ($t[$type] ?? 0) + $qty; return $t; }
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

// 1. Baseline same-load path: exact key, unchanged.
theft('campDurSame', ...A, ...['Dur Thief', 'Dur Owner', [['hand_501', 'IronBar_proto', 'iron bar', 2]], $T]);
giveBack('campDurSame', ...A, ...['Dur Thief', 'Dur Owner', [['hand_501', 'IronBar_proto', 'iron bar', 2]], $T + 60]);
ok(credited('campDurSame') === 2, 'same load, same key: credited (unchanged)');
// 1b. Same load but a different key stays refused (exactness unchanged).
theft('campDurSame2', ...A, ...['Dur Thief2', 'Dur Owner2', [['hand_511', 'IronBar_proto', 'iron bar', 2]], $T]);
$r = giveBack('campDurSame2', ...A, ...['Dur Thief2', 'Dur Owner2', [['hand_999', 'IronBar_proto', 'iron bar', 2]], $T + 60]);
ok(credited('campDurSame2') === 0 && statusOf($r) === 'return_unattributed', 'same load, different key: NOT credited, ' . statusOf($r));

// 2. THE FIX: reload between theft and return, the item has a new load-local key, unique fingerprint -> credited to the ORIGINAL item.
theft('campDurX', ...A, ...['Dur Thief3', 'Dur Owner3', [['hand_601', 'IronBar_proto', 'iron bar', 2]], $T]);
giveBack('campDurX', ...B, ...['Dur Thief3', 'Dur Owner3', [['hand_777', 'IronBar_proto', 'iron bar', 2]], $T + 600]);
$s = repairState('campDurX');
ok(credited('campDurX') === 2, 'cross-load unique whole stack: credited (' . json_encode($s['returned_quantities'] ?? null) . ')');
ok(isset($s['verified_items']['hand_601']) && $s['verified_items']['hand_601']['quantity'] === 2
   && ($s['verified_items']['hand_601']['return_item_key'] ?? '') === 'hand_777' && ($s['verified_items']['hand_601']['matched_by'] ?? '') === 'cross_load_fingerprint',
   'cross-load credit is recorded against the original item key and keeps the load-local return key');
// 2b. Replaying the same receipt is not credited twice; returning the item AGAIN after a second reload does not exceed the stolen quantity.
$again = giveBack('campDurX', ...C, ...['Dur Thief3', 'Dur Owner3', [['hand_888', 'IronBar_proto', 'iron bar', 2]], $T + 1200]);
ok(credited('campDurX') === 2, 'a second return of the same stack does not exceed the stolen quantity');

// 3. Ambiguity: two stolen stacks with the same fingerprint, one returned -> not credited.
theft('campDurAmb', ...A, ...['Dur Thief4', 'Dur Owner4', [['hand_701', 'Knife_proto', 'knife', 1], ['hand_702', 'Knife_proto', 'knife', 1]], $T]);
$r = giveBack('campDurAmb', ...B, ...['Dur Thief4', 'Dur Owner4', [['hand_790', 'Knife_proto', 'knife', 1]], $T + 600]);
ok(credited('campDurAmb') === 0 && statusOf($r) === 'return_unattributed', 'ambiguous fingerprint (two identical stolen stacks): NOT credited, ' . statusOf($r));
// 3b. Two identical returned stacks against one stolen: also ambiguous.
theft('campDurAmb2', ...A, ...['Dur Thief5', 'Dur Owner5', [['hand_711', 'Knife_proto', 'knife', 2]], $T]);
$r = giveBack('campDurAmb2', ...B, ...['Dur Thief5', 'Dur Owner5', [['hand_791', 'Knife_proto', 'knife', 1], ['hand_792', 'Knife_proto', 'knife', 1]], $T + 600]);
ok(credited('campDurAmb2') === 0, 'different quantity split (2 stolen as one stack, returned as 1+1): NOT credited');

// 4. Different prototype / quantity / type: not credited.
theft('campDurDiff', ...A, ...['Dur Thief6', 'Dur Owner6', [['hand_801', 'IronBar_proto', 'iron bar', 2]], $T]);
$r = giveBack('campDurDiff', ...B, ...['Dur Thief6', 'Dur Owner6', [['hand_880', 'OtherBar_proto', 'iron bar', 2]], $T + 600]);
ok(credited('campDurDiff') === 0, 'same type but different prototype: NOT credited');
$r = giveBack('campDurDiff', ...B, ...['Dur Thief6', 'Dur Owner6', [['hand_881', 'IronBar_proto', 'iron bar', 1]], $T + 700]);
ok(credited('campDurDiff') === 0, 'same prototype but a different quantity: NOT credited');
$r = giveBack('campDurDiff', ...B, ...['Dur Thief6', 'Dur Owner6', [['hand_882', 'Katana_proto', 'katana', 1]], $T + 800]);
ok(credited('campDurDiff') === 0, 'different item name entirely: NOT credited');

// 5. Kill switch: identical scenario to 2 is refused when the fingerprint match is disabled.
setting('STOBE_REPAIR_FINGERPRINT_ENABLED', '0');
theft('campDurOff', ...A, ...['Dur Thief7', 'Dur Owner7', [['hand_901', 'IronBar_proto', 'iron bar', 2]], $T]);
$r = giveBack('campDurOff', ...B, ...['Dur Thief7', 'Dur Owner7', [['hand_977', 'IronBar_proto', 'iron bar', 2]], $T + 600]);
ok(credited('campDurOff') === 0 && statusOf($r) === 'return_unattributed', 'kill switch off: cross-load return NOT credited, ' . statusOf($r));
setting('STOBE_REPAIR_FINGERPRINT_ENABLED', null);

// 6. Pure guards of the matcher (scope: rollback / forged same epoch / other campaign / non-numeric epoch).
$ev = ['campaign_id'=>'c', 'timeline_epoch'=>'5', 'native_session_id'=>'sB'];
$row = ['timeline_epoch'=>'4']; $theft = ['native_session_id'=>'sA'];
$orig = [['item_key'=>'k1', 'prototype_id'=>'p', 'type_key'=>'t', 'quantity'=>1, 'from_storage_id'=>'own', 'to_storage_id'=>'thf']];
$ret = [['item_key'=>'k9', 'prototype_id'=>'p', 'type_key'=>'t', 'quantity'=>1, 'from_storage_id'=>'thf', 'to_storage_id'=>'own']];
ok(stobeSocialRepairFingerprintKeyMap($ev, $row, $theft, $ret, $orig, 'thf', 'own') === ['k9'=>'k1'], 'matcher: unique fingerprint maps the load-local key to the original');
ok(stobeSocialRepairFingerprintKeyMap(['timeline_epoch'=>'3'] + $ev, $row, $theft, $ret, $orig, 'thf', 'own') === [], 'matcher: older epoch (rollback) refused');
ok(stobeSocialRepairFingerprintKeyMap(['timeline_epoch'=>'4'] + $ev, $row, $theft, $ret, $orig, 'thf', 'own') === [], 'matcher: same epoch other session (forged) refused');
ok(stobeSocialRepairFingerprintKeyMap(['timeline_epoch'=>'5x'] + $ev, $row, $theft, $ret, $orig, 'thf', 'own') === [], 'matcher: non-numeric epoch refused');
$wrongWay = [['from_storage_id'=>'own', 'to_storage_id'=>'thf'] + $ret[0]];
ok(stobeSocialRepairFingerprintKeyMap($ev, $row, $theft, $wrongWay, $orig, 'thf', 'own') === [], 'matcher: a return in the wrong direction refused');
ok(stobeSocialRepairFingerprintKeyMap($ev, $row, $theft, $ret, $orig, 'own', 'thf') === [], 'matcher: swapped giver/recipient refused');
ok(stobeSocialRepairFingerprintKeyMap($ev, $row, ['native_session_id'=>''], $ret, $orig, 'thf', 'own') === [], 'matcher: missing original session refused');

cleanup(); setting('STOBE_REPAIR_FINGERPRINT_ENABLED', $savedFp); setting('SOCIAL_RELATIONSHIP_MODE', $savedMode);
echo "OK imm26_durable_item_id_regression: $n checks passed\n";
