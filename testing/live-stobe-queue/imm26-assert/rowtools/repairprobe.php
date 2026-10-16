<?php
// repairprobe.php (imm26 reloadrows-B, row 10-e): read-only probe of the wpR2 restitution-scope gate against the REAL playthrough session of a lane.
//   KAH_LANE_ROOT=/tmp/stobe-... KAH_LANE_DB=<db> php repairprobe.php scope [npc]            -> JSON {scope: live scope, ingest_mode, rescope_enabled}
//   KAH_LANE_ROOT=... KAH_LANE_DB=... php repairprobe.php eval '<scope-json from "scope">' [npc]  -> JSON {live, cases:{name:{status,note,returned_null}}}
// No DB write at all: the "agreements" are in-memory deals whose frozen repair_binding_scope is the pre-load scope (or a variant of it); the term evaluator
// reads the CURRENT scope from stobe_meta.settings PLAYTHROUGH_SESSION, which the game's reload changed. Private lane DB only (refuses any other).
$b = getenv('KAH_LANE_ROOT'); $expectDb = getenv('KAH_LANE_DB');
if (!$b || !$expectDb) { fwrite(STDERR, "KAH_LANE_ROOT/KAH_LANE_DB not set\n"); exit(2); }
require "$b/site/lib/bootstrap.php";
require_once "$b/site/lib/negotiation_engine.php";
require_once "$b/site/lib/social_runtime.php";
require_once "$b/site/lib/social_repair_agreements.php";
if (($GLOBALS['db']->fetchOne('select current_database() as d')['d'] ?? '') !== $expectDb) throw new RuntimeException('Wrong database');
$mode = $argv[1] ?? '';
$db = $GLOBALS['db'];
try { $live = stobeSocialScope($db); } catch (Throwable $e) { echo json_encode(['error' => 'scope: ' . $e->getMessage()]), "\n"; exit(0); }
$ingest = function_exists('stobeSocialIngestMode') ? stobeSocialIngestMode() : 'unknown';
$rescope = function_exists('stobeSocialRepairRescopeEnabled') ? stobeSocialRepairRescopeEnabled() : null;
if ($mode === 'scope') {
    echo json_encode(['mode' => 'scope', 'scope' => $live, 'ingest_mode' => $ingest, 'rescope_enabled' => $rescope], JSON_UNESCAPED_SLASHES), "\n";
    exit(0);
}
if ($mode !== 'eval') { fwrite(STDERR, "usage: scope|eval\n"); exit(2); }
$in = json_decode($argv[2] ?? '', true);
$s0 = is_array($in) ? ($in['scope'] ?? null) : null;
if (!is_array($s0) || !isset($s0['campaign_id'], $s0['timeline_epoch'], $s0['native_session_id'])) { echo json_encode(['error' => 'bad pre-load scope argument']), "\n"; exit(0); }
$npc = trim(strval($argv[3] ?? 'Cind')) ?: 'Cind';
$extra = ['giver_storage_id' => 'g1', 'recipient_storage_id' => 'r1', 'acceptance_gamets' => 0, 'deadline_gamets' => PHP_INT_MAX >> 1];
$term = ['i' => 0, 'kind' => 'RETURN_ITEM', 'by' => 'player', 'item' => 'Bread', 'quantity' => 1, 'status' => 'AWAITING_PLAYER', 'evidence' => []];
$other = strval($s0['campaign_id']) === str_repeat('ab', 16) ? str_repeat('cd', 16) : str_repeat('ab', 16);
$cases = [
    'same_campaign_later_load' => $s0 + $extra,
    'other_save' => array_merge($s0 + $extra, ['campaign_id' => $other]),
    'older_epoch' => array_merge($s0 + $extra, ['timeline_epoch' => strval(intval($live['timeline_epoch']) + 1000)]),
    'unprovable_after_reload' => array_merge($s0 + $extra, ['deadline_gamets' => 0]),
    'same_load_deadline_control' => array_merge($live + $extra, ['deadline_gamets' => 0]),
];
$out = [];
foreach ($cases as $name => $scope) {
    $deal = ['contract_id' => 'rb10e-' . $name, 'npc_name' => $npc, 'player_name' => 'Shay', 'status' => 'AWAITING_PERFORMANCE',
        'baseline' => ['repair_binding_scope' => $scope, 'repair_action_tickets' => [['term_index' => 0, 'action_id' => str_repeat('a', 64)]]]];
    try {
        $r = stobeSocialRepairEvaluateAgreementTicketTerm($term, $deal, time());
        $ev = is_array($r) ? ($r['evidence'] ?? []) : [];
        $out[$name] = ['status' => is_array($r) ? strval($r['status'] ?? '') : 'null', 'note' => $ev ? strval($ev[count($ev) - 1]['note'] ?? '') : '', 'returned_null' => $r === null];
    } catch (Throwable $e) { $out[$name] = ['status' => 'error', 'note' => substr($e->getMessage(), 0, 160), 'returned_null' => false]; }
}
echo json_encode(['mode' => 'eval', 'live' => $live, 'ingest_mode' => $ingest, 'rescope_enabled' => $rescope, 'cases' => $out], JSON_UNESCAPED_SLASHES), "\n";
