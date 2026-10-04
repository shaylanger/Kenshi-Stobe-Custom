#!/usr/bin/env python3
"""m25 (batch I, A8 "no bread goal"): a save load rolled the squad member Avarek back as a
"future-only NPC" (no history snapshot at or before the loaded game time) and DELETED her row.
The next chat re-created her by JIT with an empty faction, so npcIsInPlayerFaction() was false,
the bug-76 work-goal inference skipped "Avarek, make 2 bread." and no goal was queued.
Fix: the rollback never deletes an NPC of the player's own faction (the squad is in the loaded
save; the next NPC sync refreshes the row). Regression check in playthrough_rollback_regression.

Usage: python3 m25-rollback-squad.py <tree root>   (live tree and ss-merge)
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, anchor, new, marker):
    p = root / rel
    s = p.read_text()
    if marker in s:
        print(f"{rel}: already patched"); return
    assert s.count(anchor) == 1, f"{rel}: anchor found {s.count(anchor)}x"
    p.write_text(s.replace(anchor, new))
    print(f"{rel}: patched")

patch('lib/playthrough_rollback.php',
"""            if ($preserveRelationships) {
                $skipped++;
                continue;
            }
            if (function_exists('stobeInsertNpcHistorySnapshotFromRow')) {
                stobeInsertNpcHistorySnapshotFromRow($row, 'rollback_delete_future_npc');""",
"""            if ($preserveRelationships) {
                $skipped++;
                continue;
            }
            // m25 (A8): never delete a member of the player's own faction. The squad is in the
            // loaded save; deleting the row made the next chat re-create it with no faction, so
            // orders to a squad member were treated as a stranger's ("make 2 bread": no goal).
            if (function_exists('npcIsInPlayerFaction') && trim(strval($row['faction'] ?? '')) !== ''
                && npcIsInPlayerFaction($row)) {
                $skipped++;
                stobeLogInfo('PLAYTHROUGH: kept future-only squad NPC (m25)', [
                    'npc_id' => $npcId, 'name' => strval($row['name'] ?? ''), 'gamets' => $rowGamets, 'cutoff' => $cutoff,
                ]);
                continue;
            }
            if (function_exists('stobeInsertNpcHistorySnapshotFromRow')) {
                stobeInsertNpcHistorySnapshotFromRow($row, 'rollback_delete_future_npc');""",
"kept future-only squad NPC (m25)")

patch('tests/playthrough_rollback_regression.php',
"""    ptAssert(!$db->fetchOne('SELECT id FROM core_npc WHERE id = $1', [$futureNpcId]), 'Disabled preservation must retain future-only NPC deletion');
""",
"""    ptAssert(!$db->fetchOne('SELECT id FROM core_npc WHERE id = $1', [$futureNpcId]), 'Disabled preservation must retain future-only NPC deletion');

    // m25 (A8): a future-only NPC of the player's own faction (a squad member) is never deleted.
    $squadIdentity = getCurrentPlayerFactionIdentity();
    $squadFaction = trim(strval($squadIdentity['name'] ?? 'Nameless'))
        . (trim(strval($squadIdentity['id'] ?? '')) !== '' ? ' [' . trim(strval($squadIdentity['id'])) . ']' : '');
    $futureSquadNpc = $prefix . '_FUTURE_SQUAD';
    storeNpcProfile($futureSquadNpc, ['race' => 'Greenlander', 'faction' => $squadFaction, 'gender' => 'female']);
    $futureSquadRow = $db->fetchOne('SELECT * FROM core_npc WHERE name = $1 LIMIT 1', [$futureSquadNpc]);
    $futureSquadId = intval($futureSquadRow['id'] ?? 0);
    ptAssert($futureSquadId > 0 && npcIsInPlayerFaction($futureSquadRow), 'm25: future-only squad NPC should exist in the player faction');
    $db->exec('UPDATE core_npc SET lock_profile = FALSE, gamets_last_updated = 2000 WHERE id = $1', [$futureSquadId]);
    $db->exec('DELETE FROM core_npc_master_history WHERE npc_id = $1', [$futureSquadId]);
    $squadRollback = stobePlaythroughRestoreUnlockedNpcs(1500);
    ptAssert($squadRollback['errors'] === 0, 'm25: rollback with a future-only squad NPC should succeed');
    $squadAfter = $db->fetchOne('SELECT faction FROM core_npc WHERE id = $1', [$futureSquadId]);
    ptAssert(is_array($squadAfter), 'm25: rollback must not delete a future-only squad NPC');
    ptAssert(strval($squadAfter['faction'] ?? '') === $squadFaction, 'm25: the kept squad NPC keeps its faction');
    $db->exec('DELETE FROM core_npc WHERE id = $1', [$futureSquadId]);
""",
"m25 (A8): a future-only NPC of the player's own faction")
