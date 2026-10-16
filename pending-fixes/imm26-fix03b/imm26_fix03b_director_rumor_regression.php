<?php
// imm26 fix03b (row 03-b): rumor sharing also runs for director-mode scenes. Fails on a tree without stobeDirectorShareRumors.
// Runs on stobe_test or the social phase-1 DB.
declare(strict_types=1);
set_exception_handler(function (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), ' @', basename($e->getFile()), ':', $e->getLine(), "\n"; exit(1); });
$dbName = getenv('STOBE_DB_NAME');
if (!in_array($dbName, ['stobe_test', 'stobe_social_phase1_test'], true)) throw new RuntimeException('Test DB required');
require_once __DIR__ . '/../lib/bootstrap.php';
require_once __DIR__ . '/../lib/social_runtime.php';
require_once __DIR__ . '/../lib/relationship_manager.php';
require_once __DIR__ . '/../lib/imm26_knowledge.php';
$db = $GLOBALS['db']; $n = 0;
function ok(bool $c, string $what): void { global $n; if (!$c) throw new RuntimeException('FAIL: ' . $what); ++$n; }
function sql(string $s, array $p = []): mixed { $r = $GLOBALS['db']->exec($s, $p); if ($r === false) throw new RuntimeException('SQL failed: ' . $s); return $r; }
ok(function_exists('stobeDirectorShareRumors') && function_exists('stobeDirectorRumorEnabled'), 'director rumor helper exists');

const CAMP = 'f3bcamp';
const P = ['F3 Victim'=>[7201,'Blue'], 'F3 Attacker'=>[7202,'Red'], 'F3 Witness'=>[7210,'Grey'], 'F3 Bee'=>[7220,'Hub'], 'F3 Cee'=>[7221,'Hub'], 'F3 Dee'=>[7222,'Hub']];
stobeKnowledgeEnsureSchema();
foreach (['social_event_inbox','social_incident','social_belief','social_effect','social_evidence','social_checkpoint','social_rumor','npc_ties'] as $t) sql("DELETE FROM $t WHERE campaign_id=\$1", [CAMP]);
foreach (P as $name => [$serial]) {
    sql('DELETE FROM core_npc_master_history WHERE name=$1', [$name]); sql('DELETE FROM core_npc WHERE name=$1', [$name]);
    sql("INSERT INTO core_npc(name,extended_data,metadata) VALUES($1,'{}'::jsonb,jsonb_build_object('storage_id',$2::text))", [$name, 'hand_' . $serial]);
}
sql("INSERT INTO general_settings(id,value) VALUES('SOCIAL_RELATIONSHIP_MODE','enabled') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");
sql("INSERT INTO general_settings(id,value) VALUES('PLAYER_NAME','F3 Player') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");
sql("DELETE FROM general_settings WHERE id='STOBE_DIRECTOR_RUMOR_ENABLED'");
putenv('STOBE_DIRECTOR_RUMOR_ENABLED');
$GLOBALS['stobeKnowledgeScopeOverride'] = ['campaign_id'=>CAMP, 'timeline_epoch'=>'3'];
RelationshipManager::setRelationship('F3 Bee', 'F3 Victim', 76);
$store = new SocialStore($db);
function ent(string $name): array { [$serial, $faction] = P[$name]; return ['entity_key'=>"s9:3:$serial", 'serial'=>$serial, 'name'=>$name, 'storage_id'=>"hand_$serial", 'faction'=>$faction, 'in_player_faction'=>false, 'conscious'=>true]; }
function rumor(string $holder, string $subject = 'F3 Attacker'): ?array {
    $r = $GLOBALS['db']->fetchOne('SELECT * FROM social_rumor WHERE campaign_id=$1 AND holder_name=$2 AND subject_name=$3', [CAMP, $holder, $subject]);
    return is_array($r) ? $r : null;
}
$DAY = 86400; $T0 = 10 * $DAY;
$e = ['schema_version'=>1, 'event_id'=>'s9:3:1', 'incident_id'=>'s9:3:1', 'campaign_id'=>CAMP, 'timeline_epoch'=>'3', 'native_session_id'=>'s9', 'sequence'=>1,
    'game_ts'=>$T0, 'event_kind'=>'attack', 'origin'=>'gameplay', 'actor'=>ent('F3 Attacker'), 'target'=>ent('F3 Victim'), 'state_before'=>[], 'state_after'=>[],
    'witnesses'=>[['entity'=>ent('F3 Witness'), 'conscious'=>true, 'perceived'=>true]], 'facts'=>['source'=>'structured', 'victim_targeting_actor'=>false]];
$r = $store->ingest($e, ['campaign_id'=>CAMP, 'timeline_epoch'=>'3', 'native_session_id'=>'s9'], 'enabled');
ok(($r['status'] ?? '') === 'captured', 'seed incident captured');
ok(rumor('F3 Witness') && rumor('F3 Witness')['basis'] === 'saw', 'witness holds it first-hand');

$actors = [];
foreach (array_keys(P) as $name) $actors[$name] = getNpcData($name);
$line = fn(string $s, string $l, string $t) => ['speaker'=>$s, 'listener'=>$l, 'text'=>$t];
$NOW = $T0 + $DAY;

// kill switch OFF (setting): nothing happens, even for a perfect line.
sql("INSERT INTO general_settings(id,value) VALUES('STOBE_DIRECTOR_RUMOR_ENABLED','0') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");
ok(!stobeDirectorRumorEnabled(), 'setting 0 turns the switch off');
ok(stobeDirectorShareRumors([$line('F3 Witness', 'F3 Bee', 'I saw F3 Attacker go for F3 Victim.')], $actors, $NOW) === [] && rumor('F3 Bee') === null, 'kill switch off: no hearsay row');
sql("DELETE FROM general_settings WHERE id='STOBE_DIRECTOR_RUMOR_ENABLED'");
ok(stobeDirectorRumorEnabled(), 'default is on');
putenv('STOBE_DIRECTOR_RUMOR_ENABLED=off');
ok(!stobeDirectorRumorEnabled() && stobeDirectorShareRumors([$line('F3 Witness', 'F3 Bee', 'I saw F3 Attacker go for F3 Victim.')], $actors, $NOW) === [] && rumor('F3 Bee') === null, 'env kill switch off: nothing');
putenv('STOBE_DIRECTOR_RUMOR_ENABLED');

// switch on: a scene line without the subject, a line to the player, and a self-line pass nothing on.
ok(stobeDirectorShareRumors([$line('F3 Witness', 'F3 Cee', 'Lovely weather by the gate today.'),
    $line('F3 Witness', 'F3 Player', 'I saw F3 Attacker hit F3 Victim.'), $line('F3 Witness', 'F3 Witness', 'F3 Attacker again.')], $actors, $NOW) === [] && rumor('F3 Cee') === null,
    'no subject spoken / player listener / self: nothing passed on');
// told about themselves: no row for a victim listener.
ok(stobeDirectorShareRumors([$line('F3 Witness', 'F3 Victim', 'I saw F3 Attacker hit you.')], $actors, $NOW) === [] && (rumor('F3 Victim')['basis'] ?? '') !== 'heard_from', 'victim listener: no hearsay row (own first-hand row untouched)');
// a scene with several lines: the line naming the subject creates hearsay for ITS listener only.
$scene = [$line('F3 Witness', 'F3 Cee', 'Lovely weather by the gate today.'), $line('F3 Cee', 'F3 Witness', 'Not bad at all.'),
    $line('F3 Witness', 'F3 Bee', 'Careful: F3 Attacker went for F3 Victim near the gate.'), $line('F3 Bee', 'F3 Dee', 'F3 Attacker hurt F3 Victim, I heard.')];
$shared = stobeDirectorShareRumors($scene, $actors, $NOW);
$bee = rumor('F3 Bee');
ok(count($shared) === 1 && $bee && $bee['basis'] === 'heard_from' && (int)$bee['hops'] === 1 && $bee['source_name'] === 'F3 Witness' && $bee['confidence'] === 'hearsay',
    'director line naming the subject: listener holds hearsay (heard_from, hops=1, source=speaker)');
ok(rumor('F3 Cee') === null && rumor('F3 Dee') === null, 'other listeners and a hearsay holder re-telling it (no re-spread): no rows');
ok(stobeDirectorShareRumors([$line('F3 Witness', 'F3 Bee', 'Once more, F3 Attacker is trouble.')], $actors, $NOW + 60) === [], 'repeat telling creates nothing new');

// wiring: the scene generator calls the helper after the history COMMIT (source order check).
$src = (string)file_get_contents(__DIR__ . '/../lib/director_scene.php');
$commit = strpos($src, "exec('COMMIT')"); $call = strpos($src, 'stobeDirectorShareRumors($turns, $actors, $gamets)');
ok($commit !== false && $call !== false && $call > $commit, 'stobeGenerateDirectorScene calls the rumor helper after the history commit');

sql("DELETE FROM general_settings WHERE id='PLAYER_NAME'");
echo "imm26_fix03b_director_rumor_regression: $n checks passed\n";
