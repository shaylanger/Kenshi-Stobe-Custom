#!/usr/bin/env python3
"""Bug 88: accepted surrender (Grevik) dispatched GIVE_CATS but not STOP_ATTACK;
the term went IMPOSSIBLE "action_blocked_by_policy" and he attacked again.
normalizeActionTagToken drops STOP_ATTACK when the NPC isn't flagged in combat
(disallow_stop_attack) -- Grevik had already stood down. A STOP_ATTACK that an
accepted deal requires (deal_sanctioned_give) must never be dropped.
Usage: patch_r19_bug88_surrender_stop.py <StobeServer tree root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "lib/chat_helper_functions.php"; s = p.read_text()
a = """    if (boolval($config['disallow_stop_attack'] ?? false) &&
        $command === 'STOP_ATTACK') {
        return '';
    }"""
b = """    if (boolval($config['disallow_stop_attack'] ?? false) &&
        $command === 'STOP_ATTACK' &&
        !boolval($config['deal_sanctioned_give'] ?? false)) { // an accepted deal's ceasefire always goes (bug 88)
        return '';
    }"""
if b not in s:
    assert s.count(a) == 1, "anchor not found"
    s = s.replace(a, b)
p.write_text(s); print("patched", p)
