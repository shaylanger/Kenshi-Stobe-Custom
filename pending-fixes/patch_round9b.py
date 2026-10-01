#!/usr/bin/env python3
"""Round 9b: K13. A "hat off and hand it over" deal has UNEQUIP_ITEM + GIVE_ITEM for the same
item. The give takes it straight off her head, so the separate unequip then found nothing
equipped and would go IMPOSSIBLE, failing the whole deal (and refunding the player). A verified
GIVE_ITEM of the same item now satisfies the UNEQUIP term.

Usage: patch_round9b.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_engine.php"
t = p.read_text(encoding="utf-8")
old = """    if ($by === 'npc') {
        if ($status !== 'DISPATCHED') return $term;
"""
new = """    if ($by === 'npc') {
        if ($status !== 'DISPATCHED') return $term;
        if ($kind === 'UNEQUIP_ITEM') {
            // Handing the item over takes it off: a verified GIVE_ITEM of the same item covers this.
            $itemBase = static fn($s): string => strtolower(trim(preg_replace('/\s*\[[^\]]*\]/', '', strval($s)) ?? ''));
            foreach (stobeNegDecode($deal['term_state'] ?? []) as $other) {
                if (is_array($other) && ($other['kind'] ?? '') === 'GIVE_ITEM' && ($other['by'] ?? '') === 'npc'
                    && ($other['status'] ?? '') === 'VERIFIED' && $itemBase($term['item'] ?? '') !== ''
                    && $itemBase($other['item'] ?? '') === $itemBase($term['item'] ?? '')) {
                    $term['status'] = 'VERIFIED';
                    $note($term, 'satisfied_by_hand_over');
                    return $term;
                }
            }
        }
"""
assert t.count(old) == 1, "anchor"
p.write_text(t.replace(old, new), encoding="utf-8")
print("patch_round9b: applied")
