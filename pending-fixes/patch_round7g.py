#!/usr/bin/env python3
"""Round 7g: I10 — a payment counted for two deals. The pre-deal lookback stops 2 s after the
previous deal with this NPC, but stobeNegCatsExecuted() is then called with start - 3, so the
window reached 1 s into the previous deal and re-counted its payment (I4's 2500 verified the
tobacco deal's 200). Keep a 6 s margin so the 3 s slack can't cross back.

Usage: patch_round7g.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_engine.php"
t = p.read_text(encoding="utf-8")
old = "        $lookback = min(120, max(0, intval($prev['age'] ?? 120) - 2));"
new = ("        // Payment searches start 3 s before dispatch_unix; keep clear of the previous deal's payment.\n"
       "        $lookback = min(120, max(0, intval($prev['age'] ?? 120) - 6));")
assert t.count(old) == 1, "anchor"
p.write_text(t.replace(old, new), encoding="utf-8")
print("patch_round7g: applied")
