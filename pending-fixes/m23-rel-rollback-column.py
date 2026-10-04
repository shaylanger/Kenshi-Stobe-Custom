#!/usr/bin/env python3
"""m23 fixer 10: loading an older save restored/cleared only extended_data.relationships; the core_npc.relationships
column (written by every stobePersistNpcRelationshipMap) kept the future map and stobeGetNpcRelationshipMap falls back
to / merges it, so a cleared grudge came back (rel-b55 fade: stale 'Rel Fenn' -> Shay -15 survived the reload).
Usage: m23-rel-rollback-column.py <tree root>   (edits lib/playthrough_rollback.php + tests/relationship_rollback_regression.php)"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])
def sub(path, old, new, count=1):
    p = root / path; s = p.read_text()
    if new in s: print(f"already applied: {path}"); return
    assert s.count(old) == count, f"anchor not found exactly {count}x in {path}: {old[:60]!r}"
    p.write_text(s.replace(old, new)); print(f"patched {path}")
L = 'lib/playthrough_rollback.php'
sub(L, """                SET extended_data = (" . $stripCurrent . ") || " . $restoredState . ",
                    updated_at = NOW()
                FROM latest""", """                SET extended_data = (" . $stripCurrent . ") || " . $restoredState . ",
                    -- m23: the relationships column mirrors the map (read as fallback/merge): restore it too
                    relationships = CASE WHEN COALESCE(latest.extended_data -> 'relationships', '{}'::jsonb) = '{}'::jsonb
                                         THEN '' ELSE (latest.extended_data -> 'relationships')::text END,
                    updated_at = NOW()
                FROM latest""")
sub(L, """                SET extended_data = " . $stripCurrent . ",
                    updated_at = NOW()
                WHERE NOT EXISTS (SELECT 1 FROM latest WHERE latest.npc_id = c.id)""", """                SET extended_data = " . $stripCurrent . ",
                    relationships = '', -- m23: else the column map comes back through stobeGetNpcRelationshipMap
                    updated_at = NOW()
                WHERE NOT EXISTS (SELECT 1 FROM latest WHERE latest.npc_id = c.id)""")
sub(L, """                  AND COALESCE(c.extended_data, '{}'::jsonb) ?| " . $relationshipKeyArray . "
                RETURNING c.id, c.name""", """                  AND (COALESCE(c.extended_data, '{}'::jsonb) ?| " . $relationshipKeyArray . "
                       OR COALESCE(c.relationships, '') <> '')
                RETURNING c.id, c.name""")
T = 'tests/relationship_rollback_regression.php'
sub(T, "foreach (['RelRb Malzin', 'RelRb Old', 'RelRb New'] as $n) {", "foreach (['RelRb Malzin', 'RelRb Old', 'RelRb New', 'RelRb Fenn', 'RelRb Stale'] as $n) {", count=2)
sub(T, """stobePersistNpcRelationshipMap('RelRb Malzin', ['Shay' => ['aff' => -80, 'type' => 'enemy']], getNpcData('RelRb Malzin'));
check('before the load she hates Shay', $aff('RelRb Malzin', 'Shay') === -80);""", """stobePersistNpcRelationshipMap('RelRb Malzin', ['Shay' => ['aff' => -80, 'type' => 'enemy'], 'RelRb Stranger' => ['aff' => -30, 'type' => 'enemy']], getNpcData('RelRb Malzin'));
check('before the load she hates Shay', $aff('RelRb Malzin', 'Shay') === -80);
// m23 (rel-b55 fade, 'Rel Fenn'): an NPC first met after the save whose map was written the normal way (column + extended_data)
$db->exec("INSERT INTO core_npc (name, extended_data) VALUES ('RelRb Fenn', '{}'::jsonb), ('RelRb Stale', '{}'::jsonb)");
stobePersistNpcRelationshipMap('RelRb Fenn', ['Shay' => ['aff' => -15, 'type' => 'neutral', 'note' => 'The fight with Shay is fading']], getNpcData('RelRb Fenn'));
// ... and one whose extended map an older rollback already cleared while the column kept it
$db->exec("UPDATE core_npc SET relationships = '{\\"Shay\\":{\\"aff\\":-15,\\"type\\":\\"neutral\\"}}', gamets_last_updated = 2000 WHERE name='RelRb Stale'");
$db->exec("UPDATE core_npc SET gamets_last_updated = 2000 WHERE name='RelRb Fenn'");
check('setup: the column holds the stale map', $aff('RelRb Stale', 'Shay') === -15 && $aff('RelRb Fenn', 'Shay') === -15);""")
sub(T, """check('an NPC first met after the save is cleared', $aff('RelRb New', 'Shay') === null, $rel('RelRb New'));""",
"""check('an NPC first met after the save is cleared', $aff('RelRb New', 'Shay') === null, $rel('RelRb New'));
check('m23: first met after the save, map persisted normally (column too): cleared', $aff('RelRb Fenn', 'Shay') === null, getNpcData('RelRb Fenn')['relationships'] ?? null);
check('m23: a stale column map left by an older rollback is cleared', $aff('RelRb Stale', 'Shay') === null, getNpcData('RelRb Stale')['relationships'] ?? null);
check('m23: a target she met after the save is gone after the restore', $aff('RelRb Malzin', 'RelRb Stranger') === null, getNpcData('RelRb Malzin')['relationships'] ?? null);""")
