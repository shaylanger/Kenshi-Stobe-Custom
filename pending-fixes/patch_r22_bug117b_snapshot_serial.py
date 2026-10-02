#!/usr/bin/env python3
"""Bug 117 (part 2): the participant snapshot hijacked another NPC's profile.

Run 10 retest: a new raider "Dust Bandit" (serial 59814452) was matched by
resolveSnapshotTargetNpcName() to "Tarvek [Dust Bandit]" (serial 1977172864) by
original name alone (146 candidates, "ambiguous"): his snapshot was written into
Tarvek's row, chat went to Tarvek, and the rename batch then renamed Tarvek's row
to "Gannor [Dust Bandit]" (his memories and deals went with it).

When the incoming participant has a serial and no profile has that serial, the
original-name fallback only claims profiles without a serial: never one that
belongs to another NPC.

Usage: patch_r22_bug117b_snapshot_serial.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
data = root / 'lib' / 'data_functions.php'
d = data.read_text(encoding='utf-8')
if 'bug 117, snapshot' not in d:
    edits = [
        ("""            if ($exactLooksPlaceholder) {
                $preferredByOriginal = $db->fetchOne(
                    "SELECT name
                     FROM core_npc
                     WHERE LOWER(COALESCE(original_name, '')) = LOWER($1)
                       AND COALESCE(metadata->>'storage_id', '') <> ''""",
         """            // Bug 117, snapshot: with a serial that matched no profile, a profile with a serial is another NPC.
            if ($exactLooksPlaceholder && count($storageIdVariants) === 0) {
                $preferredByOriginal = $db->fetchOne(
                    "SELECT name
                     FROM core_npc
                     WHERE LOWER(COALESCE(original_name, '')) = LOWER($1)
                       AND COALESCE(metadata->>'storage_id', '') <> ''"""),
        ("""        $byOriginalName = $db->fetchOne(
            "SELECT name
             FROM core_npc
             WHERE LOWER(original_name) = LOWER($1)
             ORDER BY updated_at DESC, gamets_last_updated DESC
             LIMIT 1",
            [$candidateOriginalName]
        );""",
         """        $byOriginalName = $db->fetchOne(
            "SELECT name
             FROM core_npc
             WHERE LOWER(original_name) = LOWER($1)
               AND ($2 = '' OR COALESCE(metadata->>'storage_id', '') = '')
             ORDER BY updated_at DESC, gamets_last_updated DESC
             LIMIT 1",
            [$candidateOriginalName, count($storageIdVariants) > 0 ? 'serial' : '']
        );"""),
    ]
    for old, new in edits:
        assert d.count(old) == 1, 'anchor: ' + old[:70]
        d = d.replace(old, new)
    data.write_text(d, encoding='utf-8', newline='')
    print('patched', data)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'bug 117: snapshot' not in t:
    anchor = """check('bug 117: another serial does not', getNpcData('Gen117 Bandit', 222) === false);
"""
    add = """check('bug 117: snapshot with another serial is not matched to him', (resolveSnapshotTargetNpcName('Gen117 Bandit', 'hand_222')['name'] ?? '') === 'Gen117 Bandit');
check('bug 117: snapshot with his serial is', (resolveSnapshotTargetNpcName('Gen117 Bandit', 'hand_111')['name'] ?? '') === 'Garvtest [Gen117 Bandit]');
check('bug 117: snapshot without a serial keeps the old match', (resolveSnapshotTargetNpcName('Gen117 Bandit', '')['name'] ?? '') === 'Garvtest [Gen117 Bandit]');
"""
    assert t.count(anchor) == 1, 'test anchor'
    t = t.replace(anchor, anchor + add)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
