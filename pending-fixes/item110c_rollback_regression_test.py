#!/usr/bin/env python3
"""Item 110 (c): regression check in tests/playthrough_rollback_regression.php.

An NPC whose snapshot at the cutoff carries a name another NPC row owns now
must be skipped (no restore error, no SQL warning, both rows unchanged).
Also checks that the rollback SQL-warning recorder keeps the warning text.

Usage: python3 item110c_rollback_regression_test.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "tests/playthrough_rollback_regression.php"
s = p.read_text()

block = r"""    // Item 110: a snapshot whose name another NPC row owns now (bug 117 renames) is skipped,
    // not a failed UPDATE on core_npc_name_key that fails the whole rollback.
    $nameOwnerNpc = $prefix . '_NAME_OWNER';
    $nameTakerNpc = $prefix . '_NAME_TAKER';
    storeNpcProfile($nameOwnerNpc, ['race' => 'Shek', 'faction' => 'Bandits', 'gender' => 'male']);
    storeNpcProfile($nameTakerNpc, ['race' => 'Shek', 'faction' => 'Bandits', 'gender' => 'male']);
    $ownerRow = $db->fetchOne('SELECT * FROM core_npc WHERE name = $1 LIMIT 1', [$nameOwnerNpc]);
    $takerRow = $db->fetchOne('SELECT * FROM core_npc WHERE name = $1 LIMIT 1', [$nameTakerNpc]);
    $ownerId = intval($ownerRow['id'] ?? 0);
    $takerId = intval($takerRow['id'] ?? 0);
    ptAssert($ownerId > 0 && $takerId > 0, 'Item 110: name owner/taker NPCs should exist');
    $db->exec('DELETE FROM core_npc_master_history WHERE npc_id IN ($1, $2)', [$ownerId, $takerId]);
    $db->exec("UPDATE core_npc SET gamets_last_updated = 1000 WHERE id = $1", [$ownerId]);
    $takerSnapshot = $takerRow;
    $takerSnapshot['name'] = $nameOwnerNpc;
    $takerSnapshot['personality'] = 'Taker text at the cutoff.';
    $takerSnapshot['gamets_last_updated'] = 1000;
    ptAssert(stobeInsertNpcHistorySnapshotFromRow($takerSnapshot, 'rollback_test_baseline'), 'Item 110: taker snapshot should be stored');
    $db->exec("UPDATE core_npc SET personality = 'Taker future text.', gamets_last_updated = 2000 WHERE id = $1", [$takerId]);
    $GLOBALS['pgr_operation'] = ['state' => ['previous' => 0]];
    pgr_begin_writes();
    $nameRestore = stobePlaythroughRestoreUnlockedNpcs(1500);
    $nameWarnings = $GLOBALS['pgr_sql_warnings'] ?? [];
    unset($GLOBALS['pgr_operation']);
    ptAssert(intval($nameRestore['errors'] ?? -1) === 0, 'Item 110: a taken snapshot name must not count as a restore error');
    ptAssert(count($nameWarnings) === 0, 'Item 110: no SQL warning during the restore, got: ' . implode(' | ', $nameWarnings));
    $ownerAfter = $db->fetchOne('SELECT name FROM core_npc WHERE id = $1', [$ownerId]);
    $takerAfter = $db->fetchOne('SELECT name, personality FROM core_npc WHERE id = $1', [$takerId]);
    ptAssert(($ownerAfter['name'] ?? '') === $nameOwnerNpc, 'Item 110: the name owner keeps its name');
    ptAssert(($takerAfter['name'] ?? '') === $nameTakerNpc, 'Item 110: the skipped NPC keeps its name');
    ptAssert(($takerAfter['personality'] ?? '') === 'Taker future text.', 'Item 110: the skipped NPC is not overwritten with another identity');
    $GLOBALS['pgr_operation'] = ['state' => ['previous' => 0]];
    pgr_begin_writes();
    pgr_note_sql_warning('pg_query_params(): Query failed: ERROR: test', '/x/postgresql.class.php', 55);
    ptAssert(!empty($GLOBALS['pgr_sql_failed']) && str_contains(strval($GLOBALS['pgr_sql_warnings'][0] ?? ''), 'ERROR: test @ postgresql.class.php:55'), 'Item 110: the rollback SQL warning text is recorded');
    pgr_begin_writes();
    ptAssert(empty($GLOBALS['pgr_sql_failed']) && empty($GLOBALS['pgr_sql_warnings']), 'Item 110: warnings before the rollback writes do not count');
    unset($GLOBALS['pgr_operation']);
    $GLOBALS['pgr_sql_failed'] = false;

    // Pure threshold helper checks.
"""

pairs = [
    ("require_once __DIR__ . '/../lib/player_base_functions.php';\n",
     "require_once __DIR__ . '/../lib/player_base_functions.php';\n"
     "require_once __DIR__ . '/../lib/playthrough_guard.php';\n"),
    ("    // Pure threshold helper checks.\n", block),
    ("    $relationshipTestRows = $db->fetchAll(\n"
     "        'SELECT id FROM core_npc WHERE name IN ($1, $2, $3)',\n"
     "        [$lockedRelationshipNpc, $futureRelationshipNpc, $individualMemoryNpc]\n"
     "    );\n",
     "    $relationshipTestRows = $db->fetchAll(\n"
     "        'SELECT id FROM core_npc WHERE name IN ($1, $2, $3) OR name LIKE $4',\n"
     "        [$lockedRelationshipNpc, $futureRelationshipNpc, $individualMemoryNpc, $prefix . '_NAME_%']\n"
     "    );\n"),
]
for old, new in pairs:
    if new in s:
        print("already applied")
        continue
    assert s.count(old) == 1, f"anchor not found once: {old[:70]!r}"
    s = s.replace(old, new)
p.write_text(s)
print("ok")
