<?php
// Forced witness line for row 03-b (imm26-sfFixA). Runs the server's OWN gossip hook, stobeKnowledgeShareFromSpeech() (the call processor/bored.php makes after
// every NPC -> NPC line), for a scripted line, so the hearsay row is created exactly as a spoken line would create it (basis heard_from, source = speaker, hops 1,
// the same dedupe, effect and attenuation) without waiting for the LLM to name the subject (20/20 + 6/6 + 24/24 live tries never did).
//   KAH_LANE_ROOT=/tmp/stobe-... KAH_LANE_DB=<db> php sharehook.php "<speaker full name>" "<listener full name>" "<spoken text>" [<gamets>]
// Private lane DB only: refuses any database that is not KAH_LANE_DB. Offline selftests: KAH_LANE_LIB=<tree>/lib, KAH_KNOWLEDGE_SCOPE='{"campaign_id":"..","timeline_epoch":".."}'.
// Prints ONE json line: speaker/listener ids, gamets, scope, the speaker's first-hand rows that were eligible, and `shared` (the rows the hook created).
$b = getenv('KAH_LANE_ROOT'); $expectDb = getenv('KAH_LANE_DB');
if (!$b || !$expectDb) { fwrite(STDERR, "KAH_LANE_ROOT/KAH_LANE_DB not set\n"); exit(2); }
$lib = getenv('KAH_LANE_LIB') ?: "$b/site/lib";
require "$lib/bootstrap.php"; require_once "$lib/social_runtime.php"; require_once "$lib/imm26_knowledge.php";
if (($GLOBALS['db']->fetchOne('select current_database() as d')['d'] ?? '') !== $expectDb) { fwrite(STDERR, "Wrong database (expected $expectDb)
"); exit(3); } // not a throw: bootstrap's exception handler exits 0 silently
[$_, $speaker, $listener, $text, $gamets] = array_pad($argv, 5, null);
if (!$speaker || !$listener || !$text) { fwrite(STDERR, "usage: sharehook.php <speaker> <listener> <text> [gamets]\n"); exit(2); }
$ov = getenv('KAH_KNOWLEDGE_SCOPE');
if ($ov) $GLOBALS['stobeKnowledgeScopeOverride'] = json_decode($ov, true);
$db = $GLOBALS['db'];
$gamets = $gamets !== null && ctype_digit((string)$gamets) ? (int)$gamets : (int)($db->fetchOne('select coalesce(max(gamets),0) as g from eventlog')['g'] ?? 0);
$sp = getNpcData($speaker); $li = getNpcData($listener);
$scope = stobeKnowledgeScope();
$out = ['speaker' => $speaker, 'speaker_id' => (int)($sp['id'] ?? 0), 'listener' => $listener, 'listener_id' => (int)($li['id'] ?? 0), 'gamets' => $gamets,
    'scope' => $scope ? ($scope['campaign_id'] . '/' . ($scope['timeline_epoch'] ?? '')) : null, 'text' => $text];
if ($scope && $out['speaker_id'] > 0) {
    $rows = $db->fetchAll("SELECT id,subject_name,victim_name,basis,severity,learned_ts FROM social_rumor WHERE campaign_id=$1 AND holder_key=$2 AND status='active' AND hops=0
        AND basis IN ('experienced','saw','heard') AND learned_ts<=$3 AND ttl_ts>$3 ORDER BY severity DESC, game_ts DESC LIMIT 40", [$scope['campaign_id'], 'npc:' . $out['speaker_id'], $gamets]) ?: [];
    $out['eligible'] = count($rows);
    $out['eligible_named'] = array_values(array_map(fn($r) => $r['id'] . ':' . $r['subject_name'] . '>' . $r['victim_name'], array_filter($rows, fn($r) => stobeKnowledgeMentions($text, $r['subject_name']))));
}
$shared = stobeKnowledgeShareFromSpeech($speaker, is_array($sp) ? $sp : [], $listener, $text, $gamets);
$out['shared'] = $shared;
if ($shared && function_exists('stobeLogInfo')) stobeLogInfo('NPC gossip passed on', ['speaker' => $speaker, 'shared' => $shared, 'via' => 'forced-hook']);
echo json_encode($out, JSON_UNESCAPED_SLASHES), "\n";
exit($shared ? 0 : 1);
