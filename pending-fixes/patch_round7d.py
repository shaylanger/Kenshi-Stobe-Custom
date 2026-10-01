#!/usr/bin/env python3
"""Round 7d: bug 7 variant. After a deal completes, the NPC's closing "deal" line can
carry only part of the same terms (e.g. just "player pay 1500 Cats"). The just-finished
guard only matched identical terms, so a partial duplicate was recorded and verified by
the same payment. A subset of a just-finished deal now counts as that deal.

Usage: patch_round7d.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("lib/negotiation_phase1.php",
      """            if (is_array($rowTerms) && !stobeDealTermsDiffer($rowTerms, $terms)) {""",
      """            if (is_array($rowTerms) && (!stobeDealTermsDiffer($rowTerms, $terms) || stobeDealTermsSubsetOf($terms, $rowTerms))) {""")

patch("lib/negotiation_phase1.php",
      """/** True while no term of this deal has been carried out or sent to the game. */""",
      """/** Every term of $sub also appears in $of (same kind, side, amount, item, quantity). */
function stobeDealTermsSubsetOf(array $sub, array $of): bool {
    $sig = static fn(array $t): string => strtoupper(strval($t['kind'] ?? '')) . '|' . strval($t['by'] ?? '') . '|'
        . intval($t['amount'] ?? 0) . '|' . strtolower(trim(strval($t['item'] ?? ''))) . '|' . max(1, intval($t['quantity'] ?? 1));
    $have = array_map($sig, array_values(array_filter($of, 'is_array')));
    $want = array_map($sig, array_values(array_filter($sub, 'is_array')));
    if (count($want) === 0) return false;
    foreach ($want as $w) {
        if (!in_array($w, $have, true)) return false;
    }
    return true;
}

/** True while no term of this deal has been carried out or sent to the game. */""")

print("patch_round7d: applied")
