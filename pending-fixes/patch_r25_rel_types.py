#!/usr/bin/env python3
"""Relationship fix R1 (run 12 findings): the evaluator writes types outside the list.

Malzin's map had "annoyed", "ally", "distrust", "acquaintance"; an unknown type also
overwrote a real one (anything unreadable became "neutral").
Now the evaluator is given the official type list, its type is mapped onto that list
(ally/friend -> platonic, annoyed/irritated -> wary, distrust -> suspicious,
acquaintance -> neutral, lover/partner -> romantic, family -> familial, hate/hostile ->
enemy, ...), and a type that still doesn't fit keeps the old one.

Usage: patch_r25_rel_types.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
f = root / 'lib/chat_helper_functions.php'
s = f.read_text(encoding='utf-8')
if 'function stobeCanonicalRelationshipType(' in s:
    print('already patched', f); sys.exit(0)

def sub(old, new):
    global s
    assert s.count(old) == 1, f'anchor found {s.count(old)}x: {old[:70]!r}'
    s = s.replace(old, new)

FUNC = r'''/** R1: the official relationship types (plus the two the affinity inference uses). */
function stobeRelationshipTypeList(): array {
    return ['romantic','platonic','familial','professional','rival','enemy','neutral','nemesis','estranged',
        'transactional','protective','indebted','fanatical','mentor','student','servant','client','patron','crush',
        'ex','betrayed','suspicious','admirer','jealous','fearful','obsessed','awed','contempt','pitying','grateful',
        'curious','dismissive','wary'];
}

/** R1: an evaluator type mapped onto the list, or '' when it doesn't fit (keep the old type). */
function stobeCanonicalRelationshipType(string $raw): string {
    $t = strtolower(trim($raw));
    if ($t === '') return '';
    if (in_array($t, stobeRelationshipTypeList(), true)) return $t;
    $syn = [
        'ally'=>'platonic', 'allies'=>'platonic', 'friend'=>'platonic', 'friendly'=>'platonic', 'friendship'=>'platonic',
        'companion'=>'platonic', 'comrade'=>'platonic', 'squadmate'=>'platonic', 'teammate'=>'platonic', 'trusted'=>'platonic',
        'acquaintance'=>'neutral', 'stranger'=>'neutral', 'indifferent'=>'neutral',
        'annoyed'=>'wary', 'irritated'=>'wary', 'wary_of'=>'wary', 'cautious'=>'wary', 'uneasy'=>'wary', 'guarded'=>'wary',
        'distrust'=>'suspicious', 'distrustful'=>'suspicious', 'mistrust'=>'suspicious',
        'lover'=>'romantic', 'partner'=>'romantic', 'spouse'=>'romantic', 'wife'=>'romantic', 'husband'=>'romantic', 'love'=>'romantic',
        'family'=>'familial', 'sibling'=>'familial', 'sister'=>'familial', 'brother'=>'familial', 'parent'=>'familial', 'child'=>'familial',
        'hate'=>'enemy', 'hatred'=>'enemy', 'hostile'=>'enemy', 'foe'=>'enemy',
        'boss'=>'patron', 'employer'=>'patron', 'employee'=>'servant', 'subordinate'=>'servant',
        'business'=>'transactional', 'trade'=>'transactional', 'customer'=>'client',
        'respect'=>'admirer', 'respected'=>'admirer', 'impressed'=>'admirer', 'afraid'=>'fearful', 'scared'=>'fearful',
        'grudge'=>'betrayed', 'disdain'=>'contempt', 'scorn'=>'contempt', 'thankful'=>'grateful',
    ];
    return $syn[$t] ?? '';
}

'''
sub("function stobeApplyRelationshipUpdatesMap(array $relationshipMap, array $updates, array $allowedTargets = []): array {",
    FUNC + "function stobeApplyRelationshipUpdatesMap(array $relationshipMap, array $updates, array $allowedTargets = []): array {")
sub("""        if ($typeCandidate !== '') {
            $newType = stobeNormalizeRelationshipTypeToken($typeCandidate);
        }""",
    """        if ($typeCandidate !== '') {
            $canonical = stobeCanonicalRelationshipType($typeCandidate); // R1
            if ($canonical !== '') $newType = $canonical;
        }""")
sub("""            . "  <rule>Use lowercase one-word types. If type should not change, omit type or leave it empty.</rule>\\n\"""",
    """            . "  <rule>Use lowercase one-word types. If type should not change, omit type or leave it empty.</rule>\\n"
            . "  <rule>type must be one of: " . implode(', ', stobeRelationshipTypeList()) . ".</rule>\\n\"""")
f.write_text(s, encoding='utf-8')
print('patched', f)

t = root / 'tests/relationship_stance_regression.php'
ts = t.read_text(encoding='utf-8')
if 'R1:' not in ts:
    anchor = 'echo "\\n$pass passed, $fail failed\\n";'
    assert ts.count(anchor) == 1
    ts = ts.replace(anchor, r'''// R1: types onto the list
check('R1: ally -> platonic, annoyed -> wary, distrust -> suspicious', stobeCanonicalRelationshipType('ally') === 'platonic'
    && stobeCanonicalRelationshipType('Annoyed') === 'wary' && stobeCanonicalRelationshipType('distrust') === 'suspicious');
check('R1: unknown type is empty (keeps the old one)', stobeCanonicalRelationshipType('whatever') === '');
$r1 = stobeApplyRelationshipUpdatesMap(['Shay' => ['aff' => 60, 'type' => 'romantic']], [['target' => 'Shay', 'aff_delta' => 1, 'type' => 'zzz']]);
check('R1: an unknown type does not wipe "romantic"', ($r1['map']['Shay']['type'] ?? '') === 'romantic', $r1['map']);
''' + anchor)
    t.write_text(ts, encoding='utf-8'); print('patched tests')
