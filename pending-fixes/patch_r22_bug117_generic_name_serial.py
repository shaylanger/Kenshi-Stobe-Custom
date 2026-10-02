#!/usr/bin/env python3
"""Bug 117: after a reload a generic NPC was answered as another session's named NPC.

Run 9 (test 55): after reloading, Shay talked to a new raider, game name "Dust
Bandit" (serial 270019520). getNpcData("Dust Bandit") found no row of that name and
fell back to the newest NPC whose original name is "Dust Bandit": Garven, from an
earlier load (another serial). chat.php remapped the target to Garven, so the deal
was recorded with Garven; a second later the rename batch named serial 270019520
"Smeck [Dust Bandit]", the voice payment went to Smeck and Garven's deal stayed unpaid.

getNpcData() takes an optional live serial: the original-name fallback then only
returns a row whose stored serial (storage_id hand_<serial>) is that serial. chat.php
passes the target's live serial, so a new "Dust Bandit" stays itself (its deals are
keyed by the live serial and follow it after the rename).

Usage: patch_r22_bug117_generic_name_serial.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

data = root / 'lib' / 'data_functions.php'
d = data.read_text(encoding='utf-8')
if 'bug 117' not in d:
    edits = [
        ("""function getNpcData(string $name): array|false {
    $db = $GLOBALS["db"];
    $normalizedName = normalizeParticipantNameToken($name);
    if ($normalizedName === '') {
        return false;
    }
""",
         """function getNpcData(string $name, int $liveSerial = 0): array|false {
    $db = $GLOBALS["db"];
    $normalizedName = normalizeParticipantNameToken($name);
    if ($normalizedName === '') {
        return false;
    }
    // Bug 117: with a live serial, a generic name ("Dust Bandit") only falls back to a
    // renamed NPC that has that serial, never to another NPC from an earlier load.
    $serialFits = static function ($row) use ($liveSerial): bool {
        if (!is_array($row)) return false;
        if ($liveSerial <= 0) return true;
        $meta = normalizeCoreNpcMetadata($row['metadata'] ?? '{}');
        $sid = strval($meta['storage_id'] ?? '');
        if (!preg_match('/(?:^|_)(-?\\d+)$/', $sid, $m)) return false;
        $serial = intval($m[1]);
        if ($serial < 0) $serial += 4294967296;
        return $serial === $liveSerial;
    };
"""),
        ("""            if ($preferred) {
                return $preferred;
            }
        }
        return $exact;
    }

    return $db->fetchOne(
        "SELECT *
         FROM core_npc
         WHERE LOWER(COALESCE(original_name, '')) = LOWER($1)
         ORDER BY
           CASE WHEN COALESCE(metadata->>'storage_id', '') <> '' THEN 0 ELSE 1 END,
           gamets_last_updated DESC,
           updated_at DESC
         LIMIT 1",
        [$normalizedName]
    );
}""",
         """            if ($preferred && $serialFits($preferred)) {
                return $preferred;
            }
            if ($preferred && $liveSerial > 0) {
                stobeLogInfo('Generic name not mapped to an NPC with another serial (bug 117)', [
                    'name' => $normalizedName, 'live_serial' => $liveSerial, 'stored_npc' => strval($preferred['name'] ?? ''),
                ]);
            }
        }
        return $exact;
    }

    $fallback = $db->fetchOne(
        "SELECT *
         FROM core_npc
         WHERE LOWER(COALESCE(original_name, '')) = LOWER($1)
         ORDER BY
           CASE WHEN COALESCE(metadata->>'storage_id', '') <> '' THEN 0 ELSE 1 END,
           gamets_last_updated DESC,
           updated_at DESC
         LIMIT 1",
        [$normalizedName]
    );
    if ($fallback && !$serialFits($fallback)) {
        stobeLogInfo('Generic name not mapped to an NPC with another serial (bug 117)', [
            'name' => $normalizedName, 'live_serial' => $liveSerial, 'stored_npc' => strval($fallback['name'] ?? ''),
        ]);
        return false;
    }
    return $fallback;
}"""),
    ]
    for old, new in edits:
        assert d.count(old) == 1, 'anchor: ' + old[:70]
        d = d.replace(old, new)
    data.write_text(d, encoding='utf-8', newline='')
    print('patched', data)

chat = root / 'processor' / 'chat.php'
c = chat.read_text(encoding='utf-8')
if 'bug 117' not in c:
    old = """    $npcData = getNpcData($targetNpc);
    if (!$npcData) {
        storeNpcProfile($targetNpc, []);
        $npcData = getNpcData($targetNpc);"""
    new = """    // Bug 117: the live serial keeps a generic name from mapping to another load's NPC.
    $targetLiveSerial = function_exists('stobeResolveLiveParticipantSerial') ? stobeResolveLiveParticipantSerial($targetNpc) : 0;
    $npcData = getNpcData($targetNpc, $targetLiveSerial);
    if (!$npcData) {
        storeNpcProfile($targetNpc, []);
        $npcData = getNpcData($targetNpc, $targetLiveSerial);"""
    assert c.count(old) == 1, 'chat anchor'
    c = c.replace(old, new)
    chat.write_text(c, encoding='utf-8', newline='')
    print('patched', chat)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'bug 117' not in t:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    add = """// ---------------------------------------------------------------- 12d. bug 117: a generic name doesn't map to another load's NPC
fixtureNpc('Garvtest [Gen117 Bandit]', ['money'=>10, 'storage_id'=>'hand_111'], '', '', '100/100');
$db->exec("DELETE FROM core_npc_master WHERE LOWER(name)=LOWER('Gen117 Bandit')");
$db->exec("UPDATE core_npc_master SET original_name='Gen117 Bandit' WHERE name='Garvtest [Gen117 Bandit]'");
$g117 = getNpcData('Gen117 Bandit');
check('bug 117: without a serial the old fallback stays', is_array($g117) && $g117['name'] === 'Garvtest [Gen117 Bandit]', $g117['name'] ?? $g117);
$g117 = getNpcData('Gen117 Bandit', 111);
check('bug 117: same serial maps to the renamed NPC', is_array($g117) && $g117['name'] === 'Garvtest [Gen117 Bandit]', $g117['name'] ?? $g117);
check('bug 117: another serial does not', getNpcData('Gen117 Bandit', 222) === false);
$db->exec("DELETE FROM core_npc_master WHERE name='Garvtest [Gen117 Bandit]'");

"""
    assert t.count(anchor) == 1, 'test anchor'
    t = t.replace(anchor, add + anchor)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
