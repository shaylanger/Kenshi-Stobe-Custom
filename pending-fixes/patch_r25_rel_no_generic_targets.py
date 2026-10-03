#!/usr/bin/env python3
"""Relationship fix R3: no relationship entries for generic, unnamed NPC names.

Run 12: Malzin had entries for "Hungry Bandit" and "Dust Bandit Bowman" (template names
of unnamed NPCs). Such an entry later applies to every NPC still called that.
Now a target with no "[...]" whose name is the bracket part of a named NPC
("Ket [Hungry Bandit]") is skipped when updates are applied. Existing entries are
removed once by tools/cleanup_generic_relationships.php (backup first).

Usage: patch_r25_rel_no_generic_targets.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
f = root / 'lib/chat_helper_functions.php'
s = f.read_text(encoding='utf-8')
if 'function stobeIsGenericNpcName(' in s:
    print('already patched', f); sys.exit(0)

FUNC = r'''/** R3: an unnamed template name ("Hungry Bandit") that named NPCs carry in brackets. */
function stobeIsGenericNpcName(string $name): bool {
    $name = trim($name);
    if ($name === '' || str_contains($name, '[')) return false;
    static $cache = [];
    $k = strtolower($name);
    if (array_key_exists($k, $cache)) return $cache[$k];
    try {
        $row = $GLOBALS['db']->fetchOne("SELECT 1 AS x FROM core_npc_master WHERE LOWER(name) LIKE $1 LIMIT 1", ['% [' . $k . ']']);
        return $cache[$k] = is_array($row);
    } catch (Throwable $e) {
        return $cache[$k] = false;
    }
}

'''
anchor = "function stobeApplyRelationshipUpdatesMap(array $relationshipMap, array $updates, array $allowedTargets = []): array {"
assert s.count(anchor) == 1
s = s.replace(anchor, FUNC + anchor)
old = """        $target = normalizeParticipantNameToken($targetRaw);
        if ($target === '') {
            continue;
        }
        $targetLower = strtolower($target);"""
assert s.count(old) == 1, 'target anchor'
s = s.replace(old, """        $target = normalizeParticipantNameToken($targetRaw);
        if ($target === '') {
            continue;
        }
        if (stobeIsGenericNpcName($target)) {
            continue; // R3: no entries for unnamed template names
        }
        $targetLower = strtolower($target);""")
f.write_text(s, encoding='utf-8')
print('patched', f)

t = root / 'tests/relationship_stance_regression.php'
ts = t.read_text(encoding='utf-8')
if 'R3:' not in ts:
    anchor = 'echo "\\n$pass passed, $fail failed\\n";'
    ts = ts.replace(anchor, r'''// R3: no entries for generic names
$GLOBALS['db']->exec("DELETE FROM core_npc_master WHERE name IN ('Rex3 [Rel3 Bandit]')");
$GLOBALS['db']->exec("INSERT INTO core_npc_master (name) VALUES ('Rex3 [Rel3 Bandit]')");
$r3 = stobeApplyRelationshipUpdatesMap([], [['target' => 'Rel3 Bandit', 'aff_delta' => -5], ['target' => 'Rex3 [Rel3 Bandit]', 'aff_delta' => -5]]);
check('R3: "Rel3 Bandit" (generic) skipped, "Rex3 [Rel3 Bandit]" kept', !isset($r3['map']['Rel3 Bandit']) && isset($r3['map']['Rex3 [Rel3 Bandit]']), $r3['map']);
$GLOBALS['db']->exec("DELETE FROM core_npc_master WHERE name IN ('Rex3 [Rel3 Bandit]')");
''' + anchor)
    t.write_text(ts, encoding='utf-8'); print('patched tests')
