#!/usr/bin/env python3
"""Item 70: generic template keys ("Dust Bandit Bowman") and legacy types (ally/distrust/annoyed...)
came back with the save-follow restore (playthrough_rollback.php writes old maps back in SQL).
- stobeNormalizeRelationshipMap (every map read and write) drops generic keys (R3 predicate).
- legacy types are mapped onto the official list (R1 + a few legacy words) in stored maps only.
- stobeRelationshipCleanStoredMaps() cleans stored maps in place; run after the restore and once now.
Usage: item70_relationship_restore_cleanup.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text(encoding='utf-8')
    if new in s:
        print(f'{rel}: already patched'); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n} times'
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'{rel}: patched')

H = 'lib/chat_helper_functions.php'
patch(H,
'''        if (stobeIsIgnoredRelationshipTarget($target)) {
            return;
        }

        $affRaw = 0;''',
'''        if (stobeIsIgnoredRelationshipTarget($target)) {
            return;
        }
        if (function_exists('stobeIsGenericNpcName') && stobeIsGenericNpcName($target)) {
            return; // item 70: no template-name entries, also not from restored or old maps (R3)
        }

        $affRaw = 0;''')
patch(H,
'''/** R3: an unnamed template name ("Hungry Bandit") that named NPCs carry in brackets. */''',
'''/** Item 70: a stored (legacy) type on the official list: R1's mapping plus old words seen in maps; '' = keep. */
function stobeRelationshipLegacyType(string $raw): string {
    $c = stobeCanonicalRelationshipType($raw);
    if ($c !== '') return $c;
    $extra = ['trust'=>'platonic', 'trusting'=>'platonic', 'respectful'=>'admirer', 'distant'=>'neutral',
        'dispute'=>'rival', 'truce'=>'wary', 'negotiation'=>'transactional'];
    return $extra[strtolower(trim($raw))] ?? '';
}

/**
 * Item 70: clean stored relationship maps in place (generic template keys dropped, legacy types
 * mapped); entries are otherwise kept as they are (aff, note, timestamps). Returns counts.
 */
function stobeRelationshipCleanStoredMaps(): array {
    $db = $GLOBALS['db'];
    $rows = $db->fetchAll("SELECT id, name, extended_data->'relationships' AS rel FROM core_npc WHERE jsonb_typeof(extended_data->'relationships')='object'");
    $out = ['npcs'=>0, 'keys_dropped'=>0, 'types_mapped'=>0];
    foreach (is_array($rows) ? $rows : [] as $row) {
        $map = json_decode(strval($row['rel'] ?? ''), true);
        if (!is_array($map)) continue;
        $changed = false;
        foreach ($map as $key => $entry) {
            if (stobeIsGenericNpcName(strval($key))) { unset($map[$key]); $out['keys_dropped']++; $changed = true; continue; }
            if (is_array($entry) && isset($entry['type'])) {
                $t = stobeRelationshipLegacyType(strval($entry['type']));
                if ($t !== '' && $t !== strtolower(trim(strval($entry['type'])))) { $map[$key]['type'] = $t; $out['types_mapped']++; $changed = true; }
            }
        }
        if (!$changed) continue;
        $json = count($map) > 0 ? json_encode($map) : '{}';
        $db->exec(
            "UPDATE core_npc SET extended_data = jsonb_set(COALESCE(extended_data, '{}'::jsonb), '{relationships}', $2::jsonb, true),
                    relationships = CASE WHEN COALESCE(relationships, '') <> '' THEN $3 ELSE relationships END
              WHERE id = $1",
            [intval($row['id']), $json, count($map) > 0 ? $json : '']
        );
        $out['npcs']++;
    }
    return $out;
}

/** R3: an unnamed template name ("Hungry Bandit") that named NPCs carry in brackets. */''')

R = 'lib/playthrough_rollback.php'
patch(R,
'''        $counts = [
            'restored' => intval($result['restored'] ?? 0),
            'cleared' => intval($result['cleared'] ?? 0),
            'errors' => 0,
            'sample_names' => trim(strval($result['sample_names'] ?? '')),
        ];''',
'''        $counts = [
            'restored' => intval($result['restored'] ?? 0),
            'cleared' => intval($result['cleared'] ?? 0),
            'errors' => 0,
            'sample_names' => trim(strval($result['sample_names'] ?? '')),
        ];
        // Item 70: restored maps can be older than R1/R3: drop template keys, map old types.
        if ($counts['restored'] > 0 && function_exists('stobeRelationshipCleanStoredMaps')) {
            try {
                $counts['cleaned'] = stobeRelationshipCleanStoredMaps();
            } catch (Throwable $cleanError) {
                stobeLogWarn('PLAYTHROUGH: relationship map cleanup failed (item 70)', ['error' => $cleanError->getMessage()]);
            }
        }''')

T = 'tests/relationship_stance_regression.php'
patch(T,
'''// R1: types onto the list''',
'''// Item 70: maps read back (restored saves, old rows) drop template keys and map legacy types
$db70 = $GLOBALS['db'];
$db70->exec("DELETE FROM core_npc_master WHERE name IN ('Kip70 [NegTest70 Bowman]')");
$db70->exec("INSERT INTO core_npc_master (name, metadata, created_at, updated_at) VALUES ('Kip70 [NegTest70 Bowman]', '{}'::jsonb, NOW(), NOW())");
$m70 = stobeNormalizeRelationshipMap(['NegTest70 Bowman' => ['aff'=>-20, 'type'=>'rival'], 'Shay' => ['aff'=>30, 'type'=>'distrust'],
    'Malzin' => ['aff'=>40, 'type'=>'trusting'], 'Kip70 [NegTest70 Bowman]' => ['aff'=>5, 'type'=>'whatever']]);
check('item 70: a generic template key is dropped on read', !isset($m70['NegTest70 Bowman']) && isset($m70['Kip70 [NegTest70 Bowman]']), array_keys($m70));
check('item 70: legacy type words map onto the list (distrust -> suspicious, trusting -> platonic, whatever -> keep)',
    stobeRelationshipLegacyType('distrust') === 'suspicious' && stobeRelationshipLegacyType('trusting') === 'platonic' && stobeRelationshipLegacyType('whatever') === '');
$db70->exec("DELETE FROM core_npc WHERE name='NegTest70 Holder'");
$db70->exec("INSERT INTO core_npc (name, extended_data) VALUES ('NegTest70 Holder', $1::jsonb)",
    [json_encode(['relationships' => ['NegTest70 Bowman' => ['aff'=>-20,'type'=>'rival','updated_at'=>1790952609], 'Shay' => ['aff'=>30,'type'=>'ally','updated_at'=>1790952609]]])]);
$c70 = stobeRelationshipCleanStoredMaps();
$row70 = json_decode(strval($db70->fetchOne("SELECT extended_data->'relationships' AS r FROM core_npc WHERE name='NegTest70 Holder'")['r'] ?? ''), true);
check('item 70: stored maps are cleaned in place (key dropped, ally -> platonic, timestamp kept)',
    is_array($row70) && !isset($row70['NegTest70 Bowman']) && ($row70['Shay']['type'] ?? '') === 'platonic' && intval($row70['Shay']['updated_at'] ?? 0) === 1790952609, [$c70, $row70]);
$db70->exec("DELETE FROM core_npc WHERE name='NegTest70 Holder'");
$db70->exec("DELETE FROM core_npc_master WHERE name='Kip70 [NegTest70 Bowman]'");

// R1: types onto the list''')
