#!/usr/bin/env python3
"""Item 110 (b): a save load's NPC restore failed on core_npc's unique name.

Restoring an NPC row to its snapshot at the load's game time wrote the
snapshot's name back, but another core_npc row owns that name now (spawned
NPCs get a new name per load and several rows share one storage_id, bug 117;
the identity fallback even matched three Slavemonger Guards to the snapshot of
"Vorn [Hungry Bandit]"): "duplicate key value violates unique constraint
core_npc_name_key". The UPDATE failed and the whole playthrough rollback was
marked failed ("A rollback write failed.").

Fix: when the snapshot's name belongs to another NPC row, that row is the
snapshot's NPC; skip this restore (count it as skipped, log it) instead of
overwriting this NPC with another identity or failing the rollback.

Usage: python3 item110b_rollback_npc_name_taken.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/playthrough_rollback.php"
s = p.read_text()

pairs = [
    ("        if (function_exists('stobeInsertNpcHistorySnapshotFromRow')) {\n"
     "            stobeInsertNpcHistorySnapshotFromRow($row, 'rollback_pre_restore');\n"
     "        }\n"
     "\n"
     "        $ok = stobePlaythroughRestoreNpcFromHistory($npcId, $historyRow, $preserveRelationships);\n",
     "        // Item 110: core_npc.name is unique. If another row owns the snapshot's name now\n"
     "        // (spawned NPCs are renamed per load, bug 117), that row is the snapshot's NPC: skip.\n"
     "        $snapshotName = trim(strval($historyRow['name'] ?? ''));\n"
     "        $nameOwner = $snapshotName === '' ? false\n"
     "            : $db->fetchOne('SELECT id FROM core_npc WHERE name = $1 AND id <> $2 LIMIT 1', [$snapshotName, $npcId]);\n"
     "        if (is_array($nameOwner) && intval($nameOwner['id'] ?? 0) > 0) {\n"
     "            $skipped++;\n"
     "            stobeLogWarn('PLAYTHROUGH: skipped NPC restore, snapshot name belongs to another NPC', [\n"
     "                'npc_id' => $npcId,\n"
     "                'name' => strval($row['name'] ?? ''),\n"
     "                'snapshot_name' => $snapshotName,\n"
     "                'name_owner_id' => intval($nameOwner['id']),\n"
     "                'history_id' => intval($historyRow['history_id'] ?? 0),\n"
     "            ]);\n"
     "            continue;\n"
     "        }\n"
     "\n"
     "        if (function_exists('stobeInsertNpcHistorySnapshotFromRow')) {\n"
     "            stobeInsertNpcHistorySnapshotFromRow($row, 'rollback_pre_restore');\n"
     "        }\n"
     "\n"
     "        $ok = stobePlaythroughRestoreNpcFromHistory($npcId, $historyRow, $preserveRelationships);\n"),
]
for old, new in pairs:
    if new in s:
        print("already applied")
        continue
    assert s.count(old) == 1, f"anchor not found once: {old[:70]!r}"
    s = s.replace(old, new)
p.write_text(s)
print("ok")
