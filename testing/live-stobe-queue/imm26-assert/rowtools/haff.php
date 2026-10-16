<?php
// Lane-agnostic H-AFF: KAH_LANE_ROOT=/tmp/stobe-... KAH_LANE_DB=<db> php haff.php "<npc>" "<counterpart>" [<value> <type|read>]. Private lane DB only.
// (generalised from imm26-5090-i4/haff.php; refuses any database that is not the expected one)
$b = getenv('KAH_LANE_ROOT'); $expectDb = getenv('KAH_LANE_DB');
if (!$b || !$expectDb) { fwrite(STDERR, "KAH_LANE_ROOT/KAH_LANE_DB not set\n"); exit(2); }
require "$b/site/lib/bootstrap.php"; require_once "$b/site/lib/relationship_manager.php";
if (($GLOBALS['db']->fetchOne('select current_database() as d')['d'] ?? '') !== $expectDb) throw new RuntimeException('Wrong database');
[$_, $npc, $cp, $val, $type] = array_pad($argv, 5, null);
$before = RelationshipManager::getRelationships($npc);
if ($val !== null && $type !== null && $type !== 'read') { if (!RelationshipManager::setRelationship($npc, $cp, (int)$val, $type)) throw new RuntimeException('setRelationship failed'); }
echo json_encode(['npc' => $npc, 'counterpart' => $cp, 'before' => $before, 'after' => RelationshipManager::getRelationships($npc)], JSON_UNESCAPED_SLASHES), "\n";
