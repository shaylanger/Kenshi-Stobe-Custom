<?php
// imm26-sfTrav: the travel PROPOSE test seam (lib/imm26_travel_test_inject.php + the guarded call in processor/chat.php before stobeTravelCapture).
// Run: flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST=<lane>/socket php tests/imm26_sfTrav_inject_travel.php <mode> [npc]
//   lane     : tree is /tmp/stobe-*/site with STOBE_DB_HOST inside the lane root (the selftest builds that): full behaviour
//   notlane  : any other tree: the seam must be inert even with a marker
//   armed    : the marker was written by inject-travel.sh (selftest step): one NPC turn must become a real PROPOSED trip, then the player's Yes accepts
// Uses the real eventlog / location_zones of stobe_test inside BEGIN/ROLLBACK (like imm26_20a_deferred_confirm_regression.php).
require __DIR__ . '/../lib/bootstrap.php';
$db = $GLOBALS['db'];
$mode = $argv[1] ?? 'lane';
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . substr(json_encode($detail), 0, 500) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }
if (!function_exists('stobeTravelTestInjectApply')) {
    $f = __DIR__ . '/../lib/imm26_travel_test_inject.php';
    if (is_file($f)) require_once $f;
}
if (!function_exists('stobeTravelTestInjectApply')) { echo "FAIL B1 seam not installed (lib/imm26_travel_test_inject.php missing)\n"; exit(1); }

$site = realpath(__DIR__ . '/..');
$marker = dirname($site) . '/test-inject-travel.json';
if ($mode !== 'armed') @unlink($marker);
foreach (glob(dirname($site) . '/test-inject-travel.fired-*.json') ?: [] as $f) if ($mode !== 'armed') @unlink($f);

$oldPlayer = $db->fetchOne("SELECT value FROM general_settings WHERE id='PLAYER_NAME'");
register_shutdown_function(static function () use ($db, $oldPlayer, $marker): void {
    $db->exec("ROLLBACK");
    $db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
    if (is_array($oldPlayer)) $db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', $1)", [strval($oldPlayer['value'])]);
    @unlink($marker);
});
$db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', 'Shay')");
$GLOBALS['CACHE_CITY'] = 'The Hub';
$GLOBALS['STOBE_TRAVEL_SPEAKER'] = 'Shay';
$GLOBALS['CACHE_PEOPLE'] = '["Shay|hand_11111","UtTrav|hand_77777","UtTravB|hand_77778"]';
$db->exec('BEGIN');
$db->exec("DELETE FROM eventlog WHERE type IN ('travel_agreement','travel_alternatives')");
$db->exec("DELETE FROM core_npc_master WHERE name IN ('UtTrav','UtTravB')");
$db->exec("INSERT INTO core_npc_master (name, metadata) VALUES ('UtTrav', '{\"storage_id\":\"hand_77777\"}'::jsonb), ('UtTravB', '{\"storage_id\":\"hand_77778\"}'::jsonb)");
$db->exec("DELETE FROM location_zones");
$now = time();
foreach ([['The Hub',0],['Stumble Inn',4000],['Squin',-5000],['Vain',9000]] as [$z,$x]) {
    $db->exec("INSERT INTO location_zones (zone_name, city_name, x, y, z, last_seen_ts, metadata) VALUES ($2,'',$3,0,0,$1,'{}'::jsonb)", [$now - 10, $z, $x]);
}
$npcFor = static fn(string $n, string $sid, int $aff): array => ['name'=>$n, 'race'=>'Greenlander', 'faction'=>'No Faction', 'metadata'=>['storage_id'=>$sid],
    'extended_data'=>['relationships'=>['Shay'=>['aff'=>$aff]]]];
$actor = 'UtTrav'; $npc = $npcFor($actor, 'hand_77777', 80);
$key = 'travel-v1:77777:11111:';
function newRequest(): void { $GLOBALS['STOBE_TRAVEL_STATE'] = []; }
function rows(string $key): array {
    $r = $GLOBALS['db']->fetchAll("SELECT data FROM eventlog WHERE type='travel_agreement' AND LEFT(data, LENGTH($1))=$1 ORDER BY rowid", [$key]);
    return array_map(static fn($x) => json_decode(substr(strval($x['data']), strlen($key)), true), is_array($r) ? $r : []);
}
function current_row(string $key): array { $r = rows($key); return $r ? $r[count($r) - 1] : []; }
$arm = static function(array $spec) use ($marker): void {
    file_put_contents($marker, json_encode($spec + ['schema'=>'STOBE_TEST_TRAVEL_INJECT_V1','expires_at'=>time()+600,'npc'=>'UtTrav','destination'=>'Squin','kind'=>'same_route','leader'=>'npc','row'=>'selftest']));
};
$fired = static fn() => glob(dirname($site) . '/test-inject-travel.fired-*.json') ?: [];
$modelNone = json_encode(['action'=>'Talk','message'=>'Hmm, maybe later.','travel_decision'=>'NONE','travel_kind'=>'','travel_leader'=>'','travel_destination'=>'']);
$apply = static function(string $line, int $gamets, string $who = 'UtTrav', ?array $n = null, bool $streamed = false) use ($modelNone, &$npc): array {
    global $actor;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];   // a new PHP request per chat turn
    $text = 'Hmm, maybe later.'; $actions = ['TRAVEL_LOCATION@Squin'];
    $raw = stobeTravelTestInjectApply($modelNone, $who, $n ?? $npc, 'Shay', $line, $gamets, $text, $actions, $streamed);
    return [$raw, $text, $actions, $GLOBALS['STOBE_TRAVEL_TEST_INJECT_RESULT'] ?? ''];
};

if ($mode === 'notlane') {
    $arm([]);
    [$raw, $text, , $res] = $apply('Take me to Squin.', 1000);
    check('N1: non-lane tree + marker: gate closed, model reply unchanged, no trip row', $raw === $modelNone && $res === 'gate_closed' && !rows($key), [$res, rows($key)]);
    check('N2: marker not consumed outside a lane', is_file($marker) && !$fired());
    check('N3: lane gate returns null outside /tmp/stobe-*/site', stobeTravelTestInjectLaneRoot() === null);
    echo "imm26_sfTrav_inject_travel notlane: $pass passed, $fail failed\n";
    exit($fail ? 1 : 0);
}

if ($mode === 'armed') {
    // the marker came from inject-travel.sh: npc name from argv[2]
    $who = $argv[2] ?? 'UtTrav';
    check('A0: script-written marker present', is_file($marker));
    [$raw, $text, $actions, $res] = $apply('Take me to Squin.', 2000, $who);
    $cur = current_row($key);
    check('A1: script-armed marker became a real PROPOSED trip (Squin, same_route, npc leads)', $res === 'fired' && ($cur['status'] ?? '') === 'PROPOSED'
        && ($cur['destination'] ?? '') === 'Squin' && ($cur['kind'] ?? '') === 'same_route' && ($cur['leader'] ?? '') === 'npc', [$res, $cur]);
    check('A2: marker consumed (one-shot)', !is_file($marker) && count($fired()) === 1);
    $t = ['Sure.']; $text2 = 'Lead the way.'; $a2 = ['TRAVEL_LOCATION@Squin'];
    newRequest(); stobeTravelCapture(json_encode(['travel_decision'=>'ACCEPT','travel_kind'=>'same_route','travel_leader'=>'npc','travel_destination'=>'Squin',
        'travel_player_quote'=>'Yes, let\'s go', 'travel_reason'=>'']), $actor, $npc, 'Shay', "Yes, let's go.", 2010, $text2, $a2);
    $cur = current_row($key);
    check('A3: the player\'s Yes reaches ACCEPTED through the normal path', ($cur['status'] ?? '') === 'ACCEPTED' && ($cur['destination'] ?? '') === 'Squin', $cur);
    echo "imm26_sfTrav_inject_travel armed: $pass passed, $fail failed\n";
    exit($fail ? 1 : 0);
}

// ---------------------------------------------------------------- lane mode
check('L0: lane gate resolves a lane root', stobeTravelTestInjectLaneRoot() !== null && is_dir(stobeTravelTestInjectLaneRoot()), stobeTravelTestInjectLaneRoot());

// B1: no marker -> nothing changes (the seam is only reached when the marker exists; a direct call must also be inert)
[$raw, $text, , $res] = $apply('Take me to Squin.', 1000);
check('B1: no marker: model reply unchanged, no row', $raw === $modelNone && !rows($key) && $res === 'marker_invalid', [$res, rows($key)]);

// B2: armed -> real PROPOSED via stobeTravelCapture
$arm([]);
[$raw, $text, $actions, $res] = $apply('Take me to Squin.', 1000);
$cur = current_row($key);
check('B2: armed -> result fired, ordinary capture handed a NONE (no double record)', $res === 'fired' && json_decode($raw, true)['travel_decision'] === 'NONE', [$res, $raw]);
check('B3: a real PROPOSED travel_agreement exists: Squin, same_route, npc leads, agreement id, grounded point, plan hash',
    ($cur['status'] ?? '') === 'PROPOSED' && ($cur['destination'] ?? '') === 'Squin' && ($cur['kind'] ?? '') === 'same_route' && ($cur['leader'] ?? '') === 'npc'
    && strval($cur['agreement_id'] ?? '') !== '' && is_array($cur['destination_point'] ?? null) && strval($cur['plan_hash'] ?? '') !== '', $cur);
check('B4: exactly one row written', count(rows($key)) === 1, count(rows($key)));
check('B5: offer text names the stored destination; no movement action (PROPOSE grants nothing)', str_contains($text, 'Squin') && str_contains($text, 'Shall we go')
    && !array_filter($actions, static fn($a) => str_starts_with(strval($a), 'TRAVEL_LOCATION')), [$text, $actions]);
check('B6: marker consumed, one fired file with result proposed', !is_file($marker) && count($fired()) === 1
    && (json_decode(file_get_contents($fired()[0]), true)['result'] ?? '') === 'proposed');
// one-shot
[$raw] = $apply('Take me to Squin.', 1001);
check('B7: one-shot: a second turn is inert (no marker)', $raw === $modelNone && count(rows($key)) === 1);

// B8: the player's Yes -> ACCEPTED through the unchanged path (needs the model's ACCEPT with an exact quote)
$t = 'Lead the way.'; $a = ['TRAVEL_LOCATION@Squin'];
newRequest(); stobeTravelCapture(json_encode(['travel_decision'=>'ACCEPT','travel_kind'=>'same_route','travel_leader'=>'npc','travel_destination'=>'Squin',
    'travel_player_quote'=>"Yes, let's go", 'travel_reason'=>'']), $actor, $npc, 'Shay', "I'm fine. Yes, let's go.", 1010, $t, $a);
$cur2 = current_row($key);
check('B8: the player\'s Yes accepts the SAME agreement (ACCEPTED, same id, TRAVEL_LOCATION kept)', ($cur2['status'] ?? '') === 'ACCEPTED'
    && ($cur2['agreement_id'] ?? '') === ($cur['agreement_id'] ?? 'x') && in_array('TRAVEL_LOCATION@Squin', $a, true), [$cur2, $a]);
// B9: ACCEPT without a stored offer is still refused (canned line) -> proves the seam is the only thing that supplied the offer
$db->exec("DELETE FROM eventlog WHERE type='travel_agreement'"); newRequest();
$t = 'Sure.'; $a = ['TRAVEL_LOCATION@Squin'];
newRequest(); stobeTravelCapture(json_encode(['travel_decision'=>'ACCEPT','travel_kind'=>'same_route','travel_leader'=>'npc','travel_destination'=>'Squin',
    'travel_player_quote'=>"Yes, let's go", 'travel_reason'=>'']), $actor, $npc, 'Shay', "Yes, let's go.", 1020, $t, $a);
check('B9: control: a Yes with no stored offer is still refused (no seam, no row)', !rows($key) && str_contains($t, 'concrete travel offer'), [$t, rows($key)]);

// C: other NPC / expired / not groundable / accepted trip -> inert, marker kept (or consumed only on fire)
$arm(['npc'=>'SomeoneElse']);
[$raw, , , $res] = $apply('Take me to Squin.', 1100);
check('C1: marker names another NPC: inert, marker kept', $raw === $modelNone && $res === 'other_actor' && is_file($marker) && !rows($key), $res);
$arm(['npc'=>'UtTravB']);   // a name that is a prefix of nothing for UtTrav: "UtTravB" must not match "UtTrav"
[$raw, , , $res] = $apply('Take me to Squin.', 1101);
check('C2: no prefix confusion (marker UtTravB vs actor UtTrav)', $res === 'other_actor' && !rows($key), $res);
$arm(['npc'=>'UtTrav [Traders Guild]']);
[, , , $res] = $apply('Take me to Squin.', 1102, 'UtTrav');
check('C3: marker with a longer name than the actor does not fire', $res === 'other_actor', $res);
$arm(['npc'=>'any']);
[, , , $res] = $apply('Take me to Squin.', 1103, 'UtTravB', $npcFor('UtTravB', 'hand_77778', 80));
check('C4: npc "any" fires for whichever NPC speaks first', $res === 'fired' && ($GLOBALS['STOBE_TRAVEL_TEST_INJECT_RESULT'] ?? '') === 'fired', $res);
$db->exec("DELETE FROM eventlog WHERE type='travel_agreement'"); newRequest(); foreach ($fired() as $f) @unlink($f);
$arm(['expires_at'=>time()-5]);
[$raw, , , $res] = $apply('Take me to Squin.', 1110);
check('C5: expired marker: inert', $raw === $modelNone && $res === 'marker_expired' && !rows($key), $res);
$arm(['destination'=>'Nowhere At All']);
[$raw, , , $res] = $apply('Take me to Squin.', 1120);
check('C6: destination that does not ground: model reply used, marker kept, nothing recorded', $raw === $modelNone && $res === 'no_candidate' && is_file($marker) && !rows($key), $res);
$arm(['kind'=>'duel_meeting']);
[$raw, , , $res] = $apply('Take me to Squin.', 1121);
check('C7: marker kind outside same_route|detour|guide is refused (no meeting kinds)', $raw === $modelNone && $res === 'marker_terms', $res);
$arm(['leader'=>'player', 'kind'=>'guide']);
[, $text, , $res] = $apply('Take me to Squin.', 1130);
$cur = current_row($key);
check('C8: kind guide forces npc leader through the product path; PROPOSED recorded', $res === 'fired' && ($cur['status'] ?? '') === 'PROPOSED' && ($cur['kind'] ?? '') === 'guide' && ($cur['leader'] ?? '') === 'npc', [$res, $cur]);
$db->exec("DELETE FROM eventlog WHERE type='travel_agreement'"); newRequest(); foreach ($fired() as $f) @unlink($f);

// D: product gates still apply (no hand insert): a refusing NPC gets the product's own refusal and no PROPOSED row
$rude = $npcFor('UtTrav', 'hand_77777', -50);
$arm([]);
[$raw, $text, $actions, $res] = $apply('Take me to Squin.', 1200, 'UtTrav', $rude);
check('D1: NPC that distrusts the player: the product refusal text, result refused, no PROPOSED row', $res === 'refused' && str_contains($text, "don't trust you") && !rows($key), [$res, $text, rows($key)]);
check('D2: the refused attempt still consumed the marker (one-shot) and recorded result refused', !is_file($marker) && (json_decode(file_get_contents($fired()[0]), true)['result'] ?? '') === 'refused');
foreach ($fired() as $f) @unlink($f);

// E: text options
$arm(['keep_text'=>true]);
[, $text, , $res] = $apply('Take me to Squin.', 1300);
check('E1: keep_text keeps the model\'s own words', $res === 'fired' && $text === 'Hmm, maybe later.', $text);
$db->exec("DELETE FROM eventlog WHERE type='travel_agreement'"); newRequest(); foreach ($fired() as $f) @unlink($f);
$arm([]);
[, $text, , $res] = $apply('Take me to Squin.', 1310, 'UtTrav', null, true);
check('E2: already streamed text is not replaced; the trip is still PROPOSED', $res === 'fired' && $text === 'Hmm, maybe later.' && (current_row($key)['status'] ?? '') === 'PROPOSED', [$res, $text]);
$db->exec("DELETE FROM eventlog WHERE type='travel_agreement'"); newRequest(); foreach ($fired() as $f) @unlink($f);

// F: empty destination = first local candidate / known place that grounds (none known in this synthetic NPC -> inert, marker kept); an ACCEPTED trip is never overwritten
$arm(['destination'=>'']);
[$raw, , , $res] = $apply('Take me somewhere.', 1400);
check('F1: empty destination and nothing known to the NPC: inert, marker kept, no row', $raw === $modelNone && $res === 'no_candidate' && is_file($marker) && !rows($key), [$res, rows($key)]);
@unlink($marker);
$t = 'ok'; $a = ['TRAVEL_LOCATION@Stumble Inn'];
newRequest(); stobeTravelCapture(json_encode(['travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc','travel_destination'=>'Stumble Inn','travel_player_quote'=>'','travel_reason'=>'']),
    $actor, $npc, 'Shay', 'Take me to Stumble Inn.', 1410, $t, $a);
newRequest(); stobeTravelCapture(json_encode(['travel_decision'=>'ACCEPT','travel_kind'=>'same_route','travel_leader'=>'npc','travel_destination'=>'Stumble Inn','travel_player_quote'=>'Yes','travel_reason'=>'']),
    $actor, $npc, 'Shay', 'Yes.', 1411, $t, $a);
check('F2a: setup: ACCEPTED trip to Stumble Inn', (current_row($key)['status'] ?? '') === 'ACCEPTED', current_row($key));
$arm(['destination'=>'Vain']);
$before = count(rows($key));
[$raw, , , $res] = $apply('Take me to Vain.', 1420);
check('F2: an ACCEPTED trip is never overwritten: trip_active, marker kept, no new row', $res === 'trip_active' && $raw === $modelNone && is_file($marker) && count(rows($key)) === $before, [$res, $before, count(rows($key))]);

echo "imm26_sfTrav_inject_travel lane: $pass passed, $fail failed\n";
exit($fail ? 1 : 0);
