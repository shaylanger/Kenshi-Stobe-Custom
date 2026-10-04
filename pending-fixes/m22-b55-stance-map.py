#!/usr/bin/env python3
"""B55 chat / item 6: the stance block (and its fight <memory> line) read only extended_data.relationships,
but live affinities sit in the core_npc 'relationships' column -> no stance block, no memory line in chat.
Use stobeGetNpcRelationshipMap (column + extended merged). Usage: m22-b55-stance-map.py <tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])
f = root / 'lib/chat_helper_functions.php'
s = f.read_text()
old = """    $ext = function_exists('normalizeNpcExtendedDataPayload') ? normalizeNpcExtendedDataPayload($npcData['extended_data'] ?? []) : (is_array($npcData['extended_data'] ?? null) ? $npcData['extended_data'] : []);
    $rels = $ext['relationships'] ?? [];
    if (is_string($rels)) { $d = json_decode($rels, true); $rels = is_array($d) ? $d : []; }
    if (!is_array($rels)) return null;
"""
new = """    // m22 B55: live affinities sit in the core_npc relationships column; extended_data alone missed them (no stance, no memory).
    if (function_exists('stobeGetNpcRelationshipMap')) {
        $rels = stobeGetNpcRelationshipMap($npcData);
    } else {
        $ext = function_exists('normalizeNpcExtendedDataPayload') ? normalizeNpcExtendedDataPayload($npcData['extended_data'] ?? []) : (is_array($npcData['extended_data'] ?? null) ? $npcData['extended_data'] : []);
        $rels = $ext['relationships'] ?? [];
        if (is_string($rels)) { $d = json_decode($rels, true); $rels = is_array($d) ? $d : []; }
    }
    if (!is_array($rels)) return null;
"""
if 'm22 B55: live affinities' not in s:
    assert s.count(old) == 1, 'anchor stobeRelationshipEntryFor'
    s = s.replace(old, new); f.write_text(s)
t = root / 'tests/relationship_stance_regression.php'
ts = t.read_text()
anchor = "check('no entry: no block',"
add = """$colNpc = ['relationships' => json_encode(['Shay' => ['aff' => -11, 'type' => 'neutral', 'note' => 'attacked me']]), 'extended_data' => '{}'];
check('m22 B55: entry in the relationships column only -> stance block', str_contains(stobeBuildRelationshipStanceBlock('Rel Mira', $colNpc, 'Shay', false), 'how_you_feel_about_them'));
"""
if 'm22 B55: entry in the relationships column' not in ts:
    assert ts.count(anchor) == 1, 'anchor test'
    ts = ts.replace(anchor, add + anchor); t.write_text(ts)
print('ok', root)
