#!/usr/bin/env python3
"""Round 16 (server): bug 43. After a stop deal she said her gang "aren't mine to call off",
while the DLL (round 15) stands her faction-mates down with her. The combat-deal rules now
tell her so.
Usage: patch_round16.py <StobeServer root>
"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / "lib/negotiation_phase1.php"
s = p.read_text()
old = """        $rules .= " An accepted or countered combat deal must include your STOP_ATTACK.";"""
new = """        $rules .= " An accepted or countered combat deal must include your STOP_ATTACK.";
        // Bug 43: her STOP_ATTACK stands down her faction-mates too (DLL round 15).
        $rules .= " When you stop fighting the player, your own faction's people who joined the fight stand down with you:"
            . " you can call them off, so never say they are not yours to call off.";"""
assert s.count(old) == 1, "anchor not found (already applied?)"
p.write_text(s.replace(old, new))
print("patched", p)
