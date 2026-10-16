<?php
// imm26 20-a (Shay 2026-10-15): a plan change is a DEFERRED CONFIRM. An ACCEPTED trip stays unchanged and active while the new
// destination waits as a pending proposal; it ends (replaced) only after the player confirms AND the NPC accepts. A refused or
// unconfirmed swap never leaves the player without a trip.
// Run: STOBE_DB_NAME=stobe_test php tests/imm26_20a_deferred_confirm_regression.php   (flock /tmp/stobe-tests.lock)
require __DIR__ . '/../lib/bootstrap.php';
$db = $GLOBALS['db'];
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; }
    else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
if (strval(getenv('STOBE_DB_NAME')) !== 'stobe_test') { echo "refusing: STOBE_DB_NAME must be stobe_test\n"; exit(2); }

$oldPlayer = $db->fetchOne("SELECT value FROM general_settings WHERE id='PLAYER_NAME'");
register_shutdown_function(static function () use ($db, $oldPlayer): void {
    $db->exec("ROLLBACK");
    $db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
    if (is_array($oldPlayer)) $db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', $1)", [strval($oldPlayer['value'])]);
});
$db->exec("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('PLAYER_NAME', 'Shay')");
$GLOBALS['CACHE_CITY'] = 'The Hub';
$GLOBALS['STOBE_TRAVEL_SPEAKER'] = 'Shay';
$GLOBALS['CACHE_PEOPLE'] = '["Shay|hand_11111","UtPlan20a|hand_66666"]';

$db->exec('BEGIN');
$db->exec("DELETE FROM eventlog WHERE type IN ('travel_agreement','travel_alternatives')");
$db->exec("DELETE FROM core_npc_master WHERE name='UtPlan20a'");
$db->exec("INSERT INTO core_npc_master (name, metadata) VALUES ('UtPlan20a', '{\"storage_id\":\"hand_66666\"}'::jsonb)");
$db->exec("DELETE FROM location_zones");
$now = time();
foreach ([['The Hub',0],['Stumble Inn',4000],['Squin',-5000],['Vain',9000]] as [$z,$x]) {
    $db->exec("INSERT INTO location_zones (zone_name, city_name, x, y, z, last_seen_ts, metadata) VALUES ($2,'',$3,0,0,$1,'{}'::jsonb)", [$now - 10, $z, $x]);
}
$actor = 'UtPlan20a';
$npc = ['name'=>$actor, 'race'=>'Greenlander', 'faction'=>'No Faction', 'metadata'=>['storage_id'=>'hand_66666'],
    'extended_data'=>['relationships'=>['Shay'=>['aff'=>80]]]];
$key = 'travel-v1:66666:11111:';

function turn(array $d, string $line, int $gamets): array {
    global $actor, $npc;
    $GLOBALS['STOBE_TRAVEL_STATE'] = [];
    $raw = json_encode($d + ['travel_kind'=>'same_route','travel_leader'=>'npc','travel_reason'=>'test']);
    $text = 'Sure.'; $actions = ['TRAVEL_LOCATION@' . ($d['travel_destination'] ?? '')];
    stobeTravelCapture($raw, $actor, $npc, 'Shay', $line, $gamets, $text, $actions);
    return [$text, $actions];
}
function rows(string $key): array {
    $r = $GLOBALS['db']->fetchAll("SELECT data FROM eventlog WHERE type='travel_agreement' AND LEFT(data, LENGTH($1))=$1 ORDER BY rowid", [$key]);
    return array_map(static fn($x) => json_decode(substr(strval($x['data']), strlen($key)), true), is_array($r) ? $r : []);
}
function current_row(string $key): array { $r = rows($key); return $r ? $r[count($r) - 1] : []; }

// ---- an ACCEPTED trip to Stumble Inn
turn(['travel_decision'=>'PROPOSE','travel_destination'=>'Stumble Inn'], 'Walk with me to Stumble Inn.', 1000);
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>"Yes, let's go"], "Yes, let's go.", 1010);
$base = current_row($key);
check('setup: trip ACCEPTED to Stumble Inn', ($base['status'] ?? '') === 'ACCEPTED' && ($base['destination'] ?? '') === 'Stumble Inn', $base);
$oldId = strval($base['agreement_id'] ?? '');
$nRows = count(rows($key));

// ---- change request: old row untouched, change parked
[$text, $actions] = turn(['travel_decision'=>'REPLACE','travel_destination'=>'Squin','travel_player_quote'=>'go to Squin instead'], 'Actually, go to Squin instead.', 1100);
$cur = current_row($key);
check('change request: accepted row unchanged and active', ($cur['status'] ?? '') === 'ACCEPTED' && ($cur['agreement_id'] ?? '') === $oldId
    && ($cur['destination'] ?? '') === 'Stumble Inn' && count(rows($key)) === $nRows, ['rows'=>count(rows($key)), 'cur'=>$cur['status'] ?? null, 'text'=>$text]);
check('change request: no movement action dispatched', !array_filter($actions, static fn($a) => str_starts_with(strval($a), 'TRAVEL_LOCATION')), $actions);
$alt = stobeImm26AltRead($actor, 'Shay', 1100);
check('change request: pending proposal recorded for Squin', is_array($alt['pending_change'] ?? null)
    && ($alt['pending_change']['offer']['destination'] ?? '') === 'Squin' && ($alt['pending_change']['old_agreement_id'] ?? '') === $oldId, $alt);
check('prompt tail mentions the waiting change', str_contains(stobeImm26PromptTail($actor, $npc, 'Shay', 1100), 'waiting for the speaker'));

// ---- the NPC refuses a destination it will not go to: nothing parked beyond that, trip continues
[$text] = turn(['travel_decision'=>'NONE'], 'Actually, go to the cannibal camp instead.', 1110);
check('refused swap: trip continues unchanged', current_row($key)['agreement_id'] === $oldId && (current_row($key)['status'] ?? '') === 'ACCEPTED');
// ---- an unresolvable destination is refused before anything is parked
[$text] = turn(['travel_decision'=>'REPLACE','travel_destination'=>'Nowhere At All','travel_player_quote'=>'go to Nowhere At All instead'], 'Actually, go to Nowhere At All instead.', 1120);
check('unknown destination: refused, trip unchanged', current_row($key)['agreement_id'] === $oldId && (current_row($key)['status'] ?? '') === 'ACCEPTED', $text);

// ---- a reaffirm of the OLD trip while a change is pending does not swap
[$text] = turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>'still going to Stumble Inn'], 'We are still going to Stumble Inn, right? Yes, still going to Stumble Inn.', 1130);
check('reaffirm of the old destination keeps the old trip', current_row($key)['agreement_id'] === $oldId && (current_row($key)['status'] ?? '') === 'ACCEPTED', $text);

// ---- confirmation: old ends (replaced), new ACCEPTED
[$text, $actions] = turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Yes, confirmed'], 'Yes, confirmed.', 1200);
$all = rows($key);
$ended = array_values(array_filter($all, static fn($r) => ($r['agreement_id'] ?? '') === $oldId && ($r['status'] ?? '') === 'ENDED'));
check('confirm: old trip ENDED as replaced', count($ended) >= 1 && ($ended[0]['ended_reason'] ?? '') === 'replaced', array_column($ended, 'ended_reason'));
$cur = current_row($key);
check('confirm: new trip ACCEPTED to Squin and replaces the old', ($cur['status'] ?? '') === 'ACCEPTED' && ($cur['destination'] ?? '') === 'Squin' && ($cur['replaces'] ?? '') === $oldId, [$cur['status'] ?? null, $cur['destination'] ?? null, $text]);
$alt = stobeImm26AltRead($actor, 'Shay', 1200);
check('confirm: pending change cleared', !isset($alt['pending_change']), $alt);

// ---- a stale confirmation (no pending change) never replaces the accepted trip
$newId = strval($cur['agreement_id'] ?? '');
[$text] = turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>'Yes, confirmed'], 'Yes, confirmed.', 1300);
check('no pending change: an ACCEPT for another place does not swap the trip', current_row($key)['agreement_id'] === $newId && (current_row($key)['status'] ?? '') === 'ACCEPTED', $text);

// ================= imm26 sfQ (20-a / 20-d): the model answers the confirmation with the OLD destination (Squin) =================
// current trip: Squin (ACCEPTED). The player asks to go back to Stumble Inn; the change is parked.
$squinId = strval(current_row($key)['agreement_id'] ?? '');
turn(['travel_decision'=>'REPLACE','travel_destination'=>'Stumble Inn','travel_player_quote'=>'Stumble Inn instead'], 'Actually, Stumble Inn instead.', 2000);
$alt = stobeImm26AltRead($actor, 'Shay', 2000);
check('sfQ setup: change to Stumble Inn parked over the Squin trip', ($alt['pending_change']['offer']['destination'] ?? '') === 'Stumble Inn'
    && ($alt['pending_change']['old_agreement_id'] ?? '') === $squinId, $alt);
$tail = stobeImm26PromptTail($actor, $npc, 'Shay', 2000);
check('sfQ prompt: tells the model to ACCEPT the pending destination and quote the confirming words',
    str_contains($tail, 'travel_decision=ACCEPT with travel_destination=Stumble Inn') && str_contains($tail, 'travel_player_quote')
    && str_contains($tail, 'OLD trip') && str_contains($tail, 'do NOT answer NONE'), $tail);

// Negative: must NOT apply the pending change
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Take me to Vain'], 'Yes. Take me to Vain.', 2010);
check('sfQ: old destination echoed but the line names another place -> pending not applied', current_row($key)['agreement_id'] === $squinId
    && (current_row($key)['status'] ?? '') === 'ACCEPTED' && isset(stobeImm26AltRead($actor, 'Shay', 2010)['pending_change']));
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Yes, Squin'], 'Yes, Squin it is.', 2020);
check('sfQ: old destination echoed and the line names the old destination -> pending not applied', current_row($key)['agreement_id'] === $squinId);
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>"No, don't change it"], "No, don't change it.", 2030);
check('sfQ: negation -> pending not applied', current_row($key)['agreement_id'] === $squinId
    && isset(stobeImm26AltRead($actor, 'Shay', 2030)['pending_change']));
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Vain','travel_player_quote'=>'Yes.'], 'Yes.', 2040);
check('sfQ: model destination that is neither offered nor old -> pending not applied', current_row($key)['agreement_id'] === $squinId);

// Positive: a bare "Yes." answered with the OLD destination confirms the change
[$text] = turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Squin','travel_player_quote'=>'Yes.'], 'Yes.', 2100);
$cur = current_row($key);
check('sfQ: bare Yes. + model echoes old destination -> pending change applied (Stumble Inn ACCEPTED, replaces Squin)',
    ($cur['status'] ?? '') === 'ACCEPTED' && ($cur['destination'] ?? '') === 'Stumble Inn' && ($cur['replaces'] ?? '') === $squinId, [$cur, $text]);
$ended = array_filter(rows($key), static fn($r) => ($r['agreement_id'] ?? '') === $squinId && ($r['status'] ?? '') === 'ENDED');
check('sfQ: old Squin trip ENDED as replaced', count($ended) >= 1 && (array_values($ended)[0]['ended_reason'] ?? '') === 'replaced');
check('sfQ: pending change cleared after the confirm', !isset(stobeImm26AltRead($actor, 'Shay', 2100)['pending_change']));

// Expired pending change (older than 6 game hours) is never applied
$stumbleId = strval($cur['agreement_id'] ?? '');
turn(['travel_decision'=>'REPLACE','travel_destination'=>'Squin','travel_player_quote'=>'Squin instead'], 'Actually, Squin instead.', 3000);
check('sfQ setup: second change parked', ($alt = stobeImm26AltRead($actor, 'Shay', 3000)) && ($alt['pending_change']['offer']['destination'] ?? '') === 'Squin', $alt);
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>'Yes.'], 'Yes.', 3000 + 21601);
check('sfQ: expired pending change is not applied', current_row($key)['agreement_id'] === $stumbleId && (current_row($key)['destination'] ?? '') === 'Stumble Inn');

// Fresh pending change confirmed by a line that names the NEW place while the model still echoes the old one
turn(['travel_decision'=>'REPLACE','travel_destination'=>'Squin','travel_player_quote'=>'Squin instead'], 'Actually, Squin instead.', 40000);
turn(['travel_decision'=>'ACCEPT','travel_destination'=>'Stumble Inn','travel_player_quote'=>'Yes. Take me to Squin.'], 'Yes. Take me to Squin.', 40100);
$cur = current_row($key);
check('sfQ: "Yes. Take me to Squin." with the old destination echoed -> applied', ($cur['status'] ?? '') === 'ACCEPTED' && ($cur['destination'] ?? '') === 'Squin' && ($cur['replaces'] ?? '') === $stumbleId, $cur);

echo "imm26_20a_deferred_confirm: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
