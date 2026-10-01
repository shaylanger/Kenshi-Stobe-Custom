#!/usr/bin/env python3
"""Round 13: show (and allow editing of) the player's row in the NPC
Relationship Affinities editor. The old filter hid it, and because the UI
save replaces the whole relationships map, saving a profile also deleted it.

Usage: patch_round13_rel_player.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "ext/relationship_system/relationship_editor.php"
s = p.read_text(encoding="utf-8")

old = """$playerNameToken = '';
if (function_exists('getSetting')) {
    $playerNameToken = strtolower(trim(strval(getSetting('PLAYER_NAME', 'Drifter'))));
}
$filteredRelationships = [];
foreach ($jsonbRelationships as $target => $payload) {
    $targetToken = strtolower(trim(strval($target)));
    if ($targetToken === '') {
        continue;
    }
    if (in_array($targetToken, ['player', 'the player', '#player_name#', 'dragonborn', 'the dragonborn'], true)) {
        continue;
    }
    if ($playerNameToken !== '' && $targetToken === $playerNameToken) {
        continue;
    }
    $filteredRelationships[$target] = $payload;
}
$jsonbRelationships = $filteredRelationships;
"""
new = """// Round 13: the player's row is shown and editable (the UI save replaces the
// whole map, so hiding it here also deleted it on save).
$filteredRelationships = [];
foreach ($jsonbRelationships as $target => $payload) {
    if (trim(strval($target)) === '') {
        continue;
    }
    $filteredRelationships[$target] = $payload;
}
$jsonbRelationships = $filteredRelationships;
"""
assert s.count(old) == 1, "anchor not found (already applied?)"
s = s.replace(old, new)

# The editor is include()d into stobenpcs.php and shares its scope. Its loops
# used $data, which clobbered the page's NPC list ($data) and made the grid
# below fatal (HTTP 500) whenever a relationship row was rendered.
import re
n = len(re.findall(r"\$data\b", s))
assert n == 14, f"expected 14 $data uses, found {n}"
s = re.sub(r"\$data\b", "$relPayload", s)
p.write_text(s, encoding="utf-8")
print("patched", p)
