<?php
// imm26 wpR3: open social windows follow the campaign across loads (audit gap 5). Runs through SocialStore::ingest.
// Run: flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/imm26_wpR3_social_window_resume_regression.php
// Touches only campaigns 'campR3*' and NPCs named 'R3 *'; restores the settings it changes.
declare(strict_types=1);
if (!in_array(getenv('STOBE_DB_NAME'), ['stobe_test', 'stobe_social_phase1_test'], true)) throw new RuntimeException('Dedicated test DB required');
require_once __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/social_runtime.php';
$db = $GLOBALS['db']; $n = 0;
function ok(bool $c, string $what): void { global $n; if (!$c) throw new RuntimeException('FAIL: ' . $what); ++$n; }
function sql(string $s, array $p = []): mixed { $r = $GLOBALS['db']->exec($s, $p); if ($r === false) throw new RuntimeException('SQL failed: ' . $s); return $r; }
function one(string $s, array $p = []): ?array { return pg_fetch_assoc(sql($s, $p)) ?: null; }
function affOf(string $a, string $b): int { return (int)(stobeRelationshipEntryFor(getNpcData($a), $b)['aff'] ?? 0); }
function r3Set(string $id, ?string $v): void {
    if ($v === null) sql('DELETE FROM general_settings WHERE id=$1', [$id]);
    else sql('INSERT INTO general_settings(id,value) VALUES($1,$2) ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value', [$id, $v]);
}
function cleanup(): void {
    foreach (['social_event_inbox','social_incident','social_belief','social_effect','social_evidence','social_checkpoint'] as $t) sql("DELETE FROM $t WHERE campaign_id LIKE 'campR3%'");
    sql("DELETE FROM core_npc_master_history WHERE name LIKE 'R3 %'"); sql("DELETE FROM core_npc WHERE name LIKE 'R3 %'");
}
$saved = [];
foreach (['SOCIAL_RELATIONSHIP_MODE', 'SOCIAL_FIGHT_RULES', 'STOBE_SOCIAL_WINDOW_RESUME_ENABLED', 'STOBE_SOCIAL_WINDOW_RESUME_MAX'] as $id) {
    $row = one('SELECT value FROM general_settings WHERE id=$1', [$id]); $saved[$id] = $row ? $row['value'] : null;
}
function restore(): void { global $saved; foreach ($saved as $id => $v) r3Set($id, $v); }
cleanup();
const P = ['R3 Brute'=>[701,'Red'], 'R3 Patient'=>[702,'Blue'], 'R3 Donor'=>[703,'Hub'], 'R3 Hungry'=>[704,'Blue'],
    'R3 Brute B'=>[711,'Red'], 'R3 Patient B'=>[712,'Blue'], 'R3 V1'=>[721,'Blue'], 'R3 V2'=>[722,'Blue'], 'R3 V3'=>[723,'Blue'], 'R3 Att'=>[724,'Red']];
foreach (P as $name => [$serial]) sql("INSERT INTO core_npc(name,extended_data,metadata) VALUES($1,'{}'::jsonb,jsonb_build_object('storage_id',$2::text))", [$name, 'hand_' . $serial]);
r3Set('SOCIAL_RELATIONSHIP_MODE', 'enabled'); r3Set('SOCIAL_FIGHT_RULES', 'rel');
r3Set('STOBE_SOCIAL_WINDOW_RESUME_ENABLED', null); r3Set('STOBE_SOCIAL_WINDOW_RESUME_MAX', null);
$store = new SocialStore($db);
$ctx = ['campaign'=>'campR3', 'epoch'=>'9', 'sess'=>'sessA', 'seq'=>0];
// A "load": new epoch + new native session for the same campaign.
function load(string $campaign, string $epoch, string $sess): void { global $ctx; $ctx = ['campaign'=>$campaign, 'epoch'=>$epoch, 'sess'=>$sess, 'seq'=>0]; }
function ent(string $name, ?bool $conscious = true): array {
    global $ctx; [$serial, $faction] = P[$name];
    return ['entity_key'=>"{$ctx['sess']}:{$ctx['epoch']}:$serial", 'serial'=>$serial, 'name'=>$name, 'storage_id'=>"hand_$serial", 'faction'=>$faction, 'in_player_faction'=>false, 'conscious'=>$conscious];
}
function send(string $kind, ?array $actor, ?array $target, array $facts, int $ts): array {
    global $ctx, $store; ++$ctx['seq']; $id = "{$ctx['sess']}:{$ctx['epoch']}:{$ctx['seq']}";
    $e = ['schema_version'=>1, 'event_id'=>$id, 'incident_id'=>$id, 'campaign_id'=>$ctx['campaign'], 'timeline_epoch'=>$ctx['epoch'], 'native_session_id'=>$ctx['sess'],
        'sequence'=>$ctx['seq'], 'game_ts'=>$ts, 'event_kind'=>$kind, 'origin'=>'gameplay', 'actor'=>$actor, 'target'=>$target,
        'state_before'=>[], 'state_after'=>[], 'witnesses'=>[], 'facts'=>['source'=>'structured'] + $facts];
    $r = $store->ingest($e, ['campaign_id'=>$ctx['campaign'], 'timeline_epoch'=>$ctx['epoch'], 'native_session_id'=>$ctx['sess']], 'enabled');
    if (($r['status'] ?? '') !== 'captured') throw new RuntimeException("FAIL: event $id ($kind @$ts) not captured: " . ($r['status'] ?? '?'));
    return $r;
}
function vit(string $pre, float $h, float $b, float $l): array { return [$pre.'known'=>true, $pre.'health'=>$h, $pre.'blood'=>$b, $pre.'bleed'=>$l]; }
function aid(string $provider, string $recipient, int $ts): array {
    return send('aid', ent($provider), ent($recipient), vit('before_', -0.6, 0.3, 0.5) + vit('after_', -0.3, 0.3, 0.0) + ['conscious_before'=>true, 'seconds'=>20, 'item'=>'Bandages'], $ts);
}
function attack(string $a, string $b, int $ts): void { send('attack', ent($a), ent($b), ['victim_targeting_actor'=>false], $ts); }
function copies(string $campaign, string $epoch): int { return (int)one("SELECT count(*) n FROM social_incident WHERE campaign_id=\$1 AND timeline_epoch=\$2 AND state ? 'resumed_from'", [$campaign, $epoch])['n']; }

try {
    // 1. Injury episode / own-harm window survives a reload: the attacker "heals" his victim in the next load -> still no trust.
    attack('R3 Brute', 'R3 Patient', 1000);
    load('campR3', '10', 'sessB');
    $before = affOf('R3 Patient', 'R3 Brute');
    $r = aid('R3 Brute', 'R3 Patient', 1500);
    ok(($r['effects'][0]['status'] ?? '') === 'no_trust_from_own_harm' && affOf('R3 Patient', 'R3 Brute') === $before, 'T1 own-harm window resumed after reload: no trust for the attacker');
    $row = one("SELECT state,game_ts FROM social_incident WHERE campaign_id='campR3' AND timeline_epoch='10' AND state->>'kind'='combat'");
    $st = json_decode($row['state'] ?? '{}', true);
    ok($row && (int)$row['game_ts'] === 1000 && ($st['victim'] ?? '') === 'sessB:10:702' && ($st['resumed_from']['epoch'] ?? '') === '9', 'T1 copy re-keyed to the new load, game time kept');
    ok(one("SELECT 1 x FROM social_incident WHERE campaign_id='campR3' AND timeline_epoch='10' AND incident_id='resume:marker'") !== null, 'T1 marker written (runs once per load)');
    ok(one("SELECT 1 x FROM social_checkpoint WHERE campaign_id='campR3' AND timeline_epoch='10' AND incident_id=\$1", [$row ? one("SELECT incident_id i FROM social_incident WHERE campaign_id='campR3' AND timeline_epoch='10' AND state->>'kind'='combat'")['i'] : 'x']) !== null, 'T1 copy is checkpointed (a rollback keeps it)');
    // 2. Food-gift window survives a reload.
    load('campR3', '10', 'sessB'); // same load continues
    $ctx['seq'] = 1;               // sequence continues after the aid above
    send('item_transfer', ent('R3 Hungry'), ent('R3 Donor'), ['items'=>['Dried Meat'=>3], 'to_ground'=>false, 'food_items'=>['Dried Meat'=>3], 'recipient_hunger'=>1.4], 5000);
    load('campR3', '11', 'sessC'); // reload #2
    $fed0 = affOf('R3 Hungry', 'R3 Donor');
    $r = send('eat', ent('R3 Hungry'), null, ['items'=>['Dried Meat'=>1], 'hunger_before'=>1.4, 'hunger_after'=>2.0], 5100);
    ok(($r['effects'][0]['status'] ?? '') !== 'own_food' && affOf('R3 Hungry', 'R3 Donor') > $fed0, 'T2 food-gift window resumed after reload: donor credited (' . ($r['effects'][0]['status'] ?? '?') . ')');
    // 3. Chain of loads: the epoch-9 harm is still known in epoch 11 (newest copy wins, no duplicates).
    $b3 = affOf('R3 Patient', 'R3 Brute');
    $r = aid('R3 Brute', 'R3 Patient', 5200);
    ok(($r['effects'][0]['status'] ?? '') === 'no_trust_from_own_harm' && affOf('R3 Patient', 'R3 Brute') === $b3, 'T3 two reloads later the harm window is still resumed');
    ok((int)one("SELECT count(*) n FROM social_incident WHERE campaign_id='campR3' AND timeline_epoch='11' AND state->>'kind'='combat'")['n'] === 1, 'T3 exactly one combat copy in the third load');

    // 4. Kill switch: off = old behaviour (the window is lost; the attacker is credited).
    r3Set('STOBE_SOCIAL_WINDOW_RESUME_ENABLED', 'false');
    load('campR3b', '9', 'sessA'); attack('R3 Brute B', 'R3 Patient B', 1000);
    load('campR3b', '10', 'sessB');
    $r = aid('R3 Brute B', 'R3 Patient B', 1500);
    ok(($r['effects'][0]['status'] ?? '') !== 'no_trust_from_own_harm' && copies('campR3b', '10') === 0 && one("SELECT 1 x FROM social_incident WHERE campaign_id='campR3b' AND incident_id='resume:marker'") === null, 'T4 kill switch off: nothing resumed (old behaviour)');
    r3Set('STOBE_SOCIAL_WINDOW_RESUME_ENABLED', null);

    // 5. Hard cap.
    r3Set('STOBE_SOCIAL_WINDOW_RESUME_MAX', '2');
    load('campR3c', '9', 'sessA'); attack('R3 Att', 'R3 V1', 1000); attack('R3 Att', 'R3 V2', 1010); attack('R3 Att', 'R3 V3', 1020);
    load('campR3c', '10', 'sessB'); aid('R3 Att', 'R3 V1', 1500);
    ok(copies('campR3c', '10') === 2, 'T5 hard cap: only 2 of 3 open incidents resumed (' . copies('campR3c', '10') . ')');
    ok((int)(json_decode(one("SELECT state FROM social_incident WHERE campaign_id='campR3c' AND timeline_epoch='10' AND incident_id='resume:marker'")['state'], true)['over_cap'] ?? 0) === 1, 'T5 over-cap count recorded');
    r3Set('STOBE_SOCIAL_WINDOW_RESUME_MAX', null);

    // 6. Loading an OLDER time does not resume newer rows.
    load('campR3d', '9', 'sessA'); attack('R3 Att', 'R3 V1', 50000);
    load('campR3d', '10', 'sessB'); aid('R3 Att', 'R3 V2', 100);
    ok(copies('campR3d', '10') === 0, 'T6 older-time load: rows from the future are not resumed');
    // 7. A window that already expired (more than a game day) is not resumed.
    load('campR3e', '9', 'sessA'); attack('R3 Att', 'R3 V1', 1000);
    load('campR3e', '10', 'sessB'); aid('R3 Att', 'R3 V2', 1000 + 90000);
    ok(copies('campR3e', '10') === 0, 'T7 expired window not resumed');
    echo "$n imm26 wpR3 social window resume checks passed\n";
} finally {
    cleanup(); restore();
}
