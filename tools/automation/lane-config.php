<?php
// lane-config.php: one-time settings for a private imm26 lane DB (generalised from C:\KenshiTestRuns\imm26-5090\config.php).
// Run by lane-backend.sh provision with the lane env sourced (STOBE_DB_NAME etc.) and LANE_ROOT / LANE_DB set.
// LLM connector rows are NOT set here: lane-llm-apply.sh owns them (one per-rig file C:\KenshiTestRuns\lane-llm.json).
$root = getenv('LANE_ROOT'); $want = getenv('LANE_DB');
if (!$root || !$want) throw new RuntimeException('LANE_ROOT/LANE_DB missing');
require "$root/site/lib/bootstrap.php";
require_once "$root/site/lib/social_runtime.php";
require_once "$root/site/lib/playthrough_switching.php";
$db = $GLOBALS['db'];
if (($db->fetchOne('select current_database() as d')['d'] ?? '') !== $want) throw new RuntimeException('wrong database');
$columns = $db->fetchAll("SELECT column_name FROM information_schema.columns WHERE table_name='core_profiles' AND (column_name LIKE '%llm%' OR column_name LIKE '%connector') AND data_type='integer'");
foreach ($columns as $c) { $n = $c['column_name']; if (!preg_match('/^[a-z_]+$/', $n)) throw new RuntimeException('column'); $db->exec('UPDATE core_profiles SET ' . $n . '=1'); }
$db->exec("UPDATE core_profiles SET metadata=jsonb_set(COALESCE(metadata,'{}'::jsonb),'{CONTEXT_HISTORY}','10'::jsonb)");
$tag = 'Isolated 5090 imm26 lane ' . $want;
setSetting('SOCIAL_RELATIONSHIP_MODE', 'enabled', 'general', $tag);
setSetting('DYNAMIC_PROFILE_ENABLED', 'false', 'general', $tag);
setSetting('HTTP_TIMEOUT', '600', 'general', $tag);
$c = ptp_connect(); ptr_ensure_schema($c); ptr_write($c, 'PLAYTHROUGH_AUTO_SWITCH', true);
echo json_encode(['database' => $db->fetchOne('select current_database() as d'), 'roles' => $columns, 'social_mode' => stobeSocialMode()], JSON_PRETTY_PRINT), "\n";
