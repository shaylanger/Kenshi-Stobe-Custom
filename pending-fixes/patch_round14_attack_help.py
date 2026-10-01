#!/usr/bin/env python3
"""Round 14: keep ATTACK@<target>@help intact (bug 39).

The action normalizer's ATTACK branch ran the whole argument through $sanitizeInlineText,
which strips every '@', so "shay@help" became "shayhelp": the DLL could not resolve the
target and her faction-mates were never called in (bug 27's fix never reached the game).
Usage: patch_round14_attack_help.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/chat_helper_functions.php"
s = p.read_text()
old = """    if ($command === 'ATTACK') {
        $targetName = $sanitizeInlineText($argument, 120);
        if ($targetName === '') {
            return 'ATTACK@';
        }
        return 'ATTACK@' . $targetName;
    }"""
new = """    if ($command === 'ATTACK') {
        // Bug 39: keep the "@help" flag (she called her faction-mates in); the sanitizer strips '@'.
        $helpFlag = '';
        if (preg_match('/^(.*)@help\\s*$/i', $argument, $helpMatch)) {
            $argument = $helpMatch[1];
            $helpFlag = '@help';
        }
        $targetName = $sanitizeInlineText($argument, 120);
        if ($targetName === '') {
            return 'ATTACK@';
        }
        return 'ATTACK@' . $targetName . $helpFlag;
    }"""
assert s.count(old) == 1, "anchor not found (already applied?)"
p.write_text(s.replace(old, new))
print("patched", p)
