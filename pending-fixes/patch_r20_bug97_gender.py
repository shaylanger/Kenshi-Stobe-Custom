#!/usr/bin/env python3
"""Bug 97: bandits called Malzin "him". Her gender appeared in only 7 of 38
prompt mentions; the people-awareness lines ("Malzin | player's squad |
doing:...") had none, so the model guessed. Fix: those lines carry
"female"/"male" from core_npc_master.gender, e.g. "Malzin (female) | ...".
Usage: patch_r20_bug97_gender.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/lifelike_npc.php", [
    ("""        $bits = [$name];
        if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($other)) {
            // Bug 38: "squadmate" only when the viewer is in the player's squad too.""",
     """        // Bug 97: say the gender so nobody calls Malzin "him".
        $gender = strtolower(trim(strval($other['gender'] ?? '')));
        $bits = [in_array($gender, ['female', 'male'], true) ? $name . ' (' . $gender . ')' : $name];
        if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($other)) {
            // Bug 38: "squadmate" only when the viewer is in the player's squad too."""),
    ("""        $name = trim(strval(explode('|', $text, 2)[0] ?? ''));
        $mentioned""",
     """        $name = trim(strval(explode('|', $text, 2)[0] ?? ''));
        $name = trim(preg_replace('/\\s*\\((?:female|male)\\)$/', '', $name) ?? $name); // bug 97 tag
        $mentioned"""),
])
