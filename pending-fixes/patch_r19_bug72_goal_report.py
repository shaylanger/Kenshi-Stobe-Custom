#!/usr/bin/env python3
"""Bug 72: goal reports (and other initiative turns) are lost when Stobe.dll
sends mode=director and the director finds no cast (only the player + 1 NPC).
- goal_report directives never use director mode.
- a failed director scene falls back to a normal spoken turn.
Usage: patch_r19_bug72_goal_report.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]); p = root / "processor/bored.php"; s = p.read_text()
a1 = """        if (strval($negDirective['kind'] ?? '') === 'goal_report') {
            $forceDirectiveTurn = true;
        } else {"""
b1 = """        if (strval($negDirective['kind'] ?? '') === 'goal_report') {
            $forceDirectiveTurn = true;
            $forceDirectorMode = false; // the DLL may have asked for director mode (bug 72)
        } else {"""
a2 = """    try {
        stobeGenerateDirectorScene($candidateNames, $speakerNpc, $listener,
            (string)($_GET['direction'] ?? ''), (int)$gamets);
    } catch (Throwable $error) {
        stobeLogWarn('Director scene failed', ['error' => $error->getMessage()]);
        echo 'error';
    }
    return;
}"""
b2 = """    try {
        stobeGenerateDirectorScene($candidateNames, $speakerNpc, $listener,
            (string)($_GET['direction'] ?? ''), (int)$gamets);
        return;
    } catch (Throwable $error) {
        // e.g. "No eligible Director cast" with only the player and one NPC:
        // speak a normal turn instead of dropping it (bug 72)
        stobeLogWarn('Director scene failed; normal turn instead', ['error' => $error->getMessage(), 'speaker' => $speakerNpc]);
        $forceDirectorMode = false;
    }
}"""
for a, b in ((a1, b1), (a2, b2)):
    if b in s: continue
    assert s.count(a) == 1, "anchor not found: " + a[:60]
    s = s.replace(a, b)
p.write_text(s); print("patched", p)
