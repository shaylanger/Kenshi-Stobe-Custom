#!/usr/bin/env python3
"""Round 9e: an ACCEPT with deal_terms '{"accepted": true}' (valid JSON, but no terms) left the
deal COUNTERED silently: the "accept what's on the table" fallback only ran for empty/invalid
JSON. JSON without any term objects now counts as no terms.

Usage: patch_round9e.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_phase1.php"
t = p.read_text(encoding="utf-8")
old = """    if ((!is_array($terms) || count($terms) === 0) && $decision === 'ACCEPT' && $open !== null) {"""
new = """    // Valid JSON that holds no terms ('{"accepted": true}') is the same as no terms.
    if (is_array($terms)) {
        $hasTerm = false;
        foreach ($terms as $candidate) {
            if (is_array($candidate) && isset($candidate['kind'])) { $hasTerm = true; break; }
        }
        if (!$hasTerm) $terms = [];
    }
    if ((!is_array($terms) || count($terms) === 0) && $decision === 'ACCEPT' && $open !== null) {"""
assert t.count(old) == 1, "anchor"
p.write_text(t.replace(old, new), encoding="utf-8")
print("patch_round9e: applied")
