<?php
// OFFLINE selftest of sharehook.php on the disposable stobe_test DB (never a lane, never the live DB):
//   wsl.exe -d DwemerAI4Skyrim3 -u root -- bash -c 'cd /root/imm26/compose && STOBE_DB_NAME=stobe_test php /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/sharehook_selftest.php /root/imm26/compose'
// The tree argument is the server tree whose lib/ holds imm26_knowledge.php (default /root/imm26/compose). Prints `SELFTEST sharehook-<name> PASS|FAIL` and `SELFTEST SHAREHOOK ALL PASS|FAIL n/m`.
declare(strict_types=1);
set_exception_handler(function (Throwable $e) { echo 'FAIL ', get_class($e), ': ', $e->getMessage(), ' @', basename($e->getFile()), ':', $e->getLine(), "\n"; exit(1); });
$tree = rtrim($argv[1] ?? '/root/imm26/compose', '/');
if (getenv('STOBE_DB_NAME') !== 'stobe_test') throw new RuntimeException('STOBE_DB_NAME=stobe_test required');
chdir($tree);
require_once "$tree/lib/bootstrap.php"; require_once "$tree/lib/social_runtime.php"; require_once "$tree/lib/imm26_knowledge.php";
$db = $GLOBALS['db']; $n = 0; $ok = 0;
function chk(string $name, bool $c, string $info = ''): void { global $n, $ok; $n++; if ($c) $ok++; echo 'SELFTEST sharehook-', $name, $c ? ' PASS ' : ' FAIL ', $info, "\n"; }
function sql(string $s, array $p = []) { $r = $GLOBALS['db']->exec($s, $p); if ($r === false) throw new RuntimeException('SQL failed: ' . $s); return $r; }
function one(string $s, array $p = []) { $r = sql($s, $p); return pg_num_rows($r) ? pg_fetch_result($r, 0, 0) : null; }
function hook(string $sp, string $li, string $text, ?int $g = null): array {
    global $tree;
    $env = 'KAH_LANE_ROOT=' . escapeshellarg($tree) . ' KAH_LANE_LIB=' . escapeshellarg("$tree/lib") . ' KAH_LANE_DB=stobe_test STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 '
        . 'KAH_KNOWLEDGE_SCOPE=' . escapeshellarg('{"campaign_id":"sffcamp","timeline_epoch":"3"}');
    $cmd = $env . ' php ' . escapeshellarg(__DIR__ . '/sharehook.php') . ' ' . escapeshellarg($sp) . ' ' . escapeshellarg($li) . ' ' . escapeshellarg($text) . ($g !== null ? ' ' . $g : '') . ' 2>&1';
    $out = []; exec($cmd, $out, $rc); $last = trim((string)end($out));
    return [$rc, json_decode($last, true) ?: [], implode("\n", $out)];
}

const CAMP = 'sffcamp';
$P = ['Sff Cind [Hungry Bandit]' => 9101, 'Sff Torvath [Paladin Jehu]' => 9102, 'Sff Shay' => 9103, 'Sff Malzin' => 9104];
stobeKnowledgeEnsureSchema();
sql('DELETE FROM social_rumor WHERE campaign_id=$1', [CAMP]);
foreach ($P as $name => $serial) {
    sql('DELETE FROM core_npc_master_history WHERE name=$1', [$name]); sql('DELETE FROM core_npc WHERE name=$1', [$name]);
    sql("INSERT INTO core_npc(name,extended_data,metadata) VALUES($1,'{}'::jsonb,jsonb_build_object('storage_id',$2::text))", [$name, 'hand_' . $serial]);
}
sql("INSERT INTO general_settings(id,value) VALUES('PLAYER_NAME','Sff Shay') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");
$GLOBALS['stobeKnowledgeScopeOverride'] = ['campaign_id' => CAMP, 'timeline_epoch' => '3'];
$cid = (int)(getNpcData('Sff Cind [Hungry Bandit]')['id'] ?? 0); $tid = (int)(getNpcData('Sff Torvath [Paladin Jehu]')['id'] ?? 0);
$mid = (int)(getNpcData('Sff Malzin')['id'] ?? 0);
chk('fixture-npcs-resolve', $cid > 0 && $tid > 0 && $cid !== $tid, "cind=$cid torvath=$tid");
$T = 400000;
// Cind saw "Sff Shay" (a player-like name; hook skips a player LISTENER, not a player subject) attack Malzin
stobeKnowledgeRecord(['campaign_id' => CAMP, 'timeline_epoch' => '3'], ['holder_key' => "npc:$cid", 'holder_name' => 'Sff Cind [Hungry Bandit]', 'subject_key' => 'p:shay', 'subject_name' => 'Sff Shay',
    'victim_key' => "npc:$mid", 'victim_name' => 'Sff Malzin', 'incident_id' => 'sff-inc-1', 'component' => 'attack', 'claim_kind' => 'attack', 'claim_text' => 'Sff Shay attacked Sff Malzin',
    'severity' => 2, 'basis' => 'saw', 'source_name' => '', 'hops' => 0, 'confidence' => 'certain', 'game_ts' => $T - 600, 'learned_ts' => $T - 600, 'ttl_ts' => $T + 86400 * 3, 'attenuation' => 1]);

[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Torvath [Paladin Jehu]', 'Lovely weather by the gate today.', $T);
chk('unrelated-line-shares-nothing-exit1', $rc === 1 && ($j['shared'] ?? null) === [] && (int)($j['eligible'] ?? 0) === 1 && ($j['eligible_named'] ?? null) === [], substr($raw, 0, 200));
chk('no-row-before-the-line', (int)one("SELECT count(*) FROM social_rumor WHERE campaign_id=$1 AND basis='heard_from'", [CAMP]) === 0);

[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Torvath [Paladin Jehu]', 'I saw Sff Shay attack Sff Malzin with my own eyes.', $T);
chk('named-line-shares-exit0', $rc === 0 && count($j['shared'] ?? []) === 1 && ($j['shared'][0]['source'] ?? '') === 'Sff Cind [Hungry Bandit]' && ($j['shared'][0]['about'] ?? '') === 'Sff Shay', substr($raw, 0, 300));
$row = $db->fetchOne("SELECT * FROM social_rumor WHERE campaign_id=$1 AND basis='heard_from'", [CAMP]);
chk('row-is-heard_from-hops1-holder-torvath-source-cind', is_array($row) && (int)$row['hops'] === 1 && $row['holder_key'] === "npc:$tid" && $row['source_name'] === 'Sff Cind [Hungry Bandit]' && $row['confidence'] === 'hearsay' && (int)$row['learned_ts'] === $T,
    json_encode($row));
[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Torvath [Paladin Jehu]', 'Again: Sff Shay attacked Sff Malzin.', $T + 60);
chk('repeat-is-deduped-exit1', $rc === 1 && ($j['shared'] ?? null) === [] && (int)one("SELECT count(*) FROM social_rumor WHERE campaign_id=$1 AND basis='heard_from'", [CAMP]) === 1, substr($raw, 0, 200));
[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Malzin', 'I saw Sff Shay attack you, Sff Malzin.', $T);
chk('victim-listener-is-not-told-about-themselves', $rc === 1 && ($j['shared'] ?? null) === [], substr($raw, 0, 200));
[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Shay', 'I saw Sff Shay attack Sff Malzin.', $T);
chk('player-listener-gets-nothing', $rc === 1 && ($j['shared'] ?? null) === [], substr($raw, 0, 200));
[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Torvath [Paladin Jehu]', 'I saw Sff Shay attack Sff Malzin.', $T - 7200);
chk('rows-learned-after-the-clock-are-invisible', $rc === 1 && (int)($j['eligible'] ?? -1) === 0, substr($raw, 0, 200));
// default gamets = max(eventlog.gamets): insert a probe event, then call without the gamets argument
sql("DELETE FROM social_rumor WHERE campaign_id=$1 AND basis='heard_from'", [CAMP]);
$ev = (int)one('SELECT coalesce(max(gamets),0) FROM eventlog');
[$rc, $j, $raw] = hook('Sff Cind [Hungry Bandit]', 'Sff Torvath [Paladin Jehu]', 'I saw Sff Shay attack Sff Malzin.');
chk('default-gamets-is-eventlog-max', (int)($j['gamets'] ?? -1) === $ev, "gamets=" . ($j['gamets'] ?? '?') . " eventlog_max=$ev");
// wrong DB guard
$cmd = 'KAH_LANE_ROOT=' . escapeshellarg($tree) . ' KAH_LANE_LIB=' . escapeshellarg("$tree/lib") . ' KAH_LANE_DB=not_this_db STOBE_DB_NAME=stobe_test php ' . escapeshellarg(__DIR__ . '/sharehook.php') . ' a b c 2>&1';
$o = []; exec($cmd, $o, $rcw);
chk('wrong-database-refused', $rcw !== 0 && str_contains(implode("\n", $o), 'Wrong database'), substr(implode(' ', $o), 0, 120));
$cmd = 'env -u KAH_LANE_ROOT -u KAH_LANE_DB php ' . escapeshellarg(__DIR__ . '/sharehook.php') . ' a b c 2>&1';
$o = []; exec($cmd, $o, $rcn);
chk('missing-env-refused-exit2', $rcn === 2, "rc=$rcn");
// cleanup
sql('DELETE FROM social_rumor WHERE campaign_id=$1', [CAMP]);
foreach ($P as $name => $serial) { sql('DELETE FROM core_npc_master_history WHERE name=$1', [$name]); sql('DELETE FROM core_npc WHERE name=$1', [$name]); }
echo $ok === $n ? "SELFTEST SHAREHOOK ALL PASS $ok/$n\n" : "SELFTEST SHAREHOOK ALL FAIL $ok/$n\n";
exit($ok === $n ? 0 : 1);
