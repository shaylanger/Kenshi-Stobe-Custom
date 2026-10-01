#!/usr/bin/env python3
"""Round 9c: one-sided social deals. Malzin's counter "I'll strip for fifteen hundred" carried
terms with only the player's 1500 (no UNEQUIP terms). The ledger recorded it, the payment
"completed" it, and nothing came off.

  - A social deal must have something the NPC does. If a counter/accept lists only the
    player's side, the NPC terms of the deal on the table carry over; if there are none,
    it's rejected ("Let's get the terms straight first.").
  - The deal_terms schema asks for both sides explicitly.

Usage: patch_round9c.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_phase1.php"
t = p.read_text(encoding="utf-8")

old1 = "Never list a term that is physically impossible or invent an item.'"
new1 = ("Always list BOTH sides: what the player gives AND what you give or do (for example UNEQUIP_ITEM for each "
        "piece of clothing you take off). Never list a term that is physically impossible or invent an item.'")
assert t.count(old1) == 1, "anchor 1"
t = t.replace(old1, new1)

old2 = "    $terms = stobeDealPromoteClothingPromises($terms, $npcData);\n"
new2 = """    $terms = stobeDealPromoteClothingPromises($terms, $npcData);
    // A social deal needs something from the NPC. Counters often restate only the price:
    // keep the NPC's side from the deal on the table, else refuse the one-sided terms.
    $effectiveKind = $open !== null ? (strval($open['kind'] ?? $kind) ?: $kind) : $kind;
    if ($effectiveKind === 'social' && count($terms) > 0) {
        $npcSide = array_filter($terms, static fn($t) => is_array($t) && ($t['by'] ?? '') === 'npc');
        if (count($npcSide) === 0) {
            $openTerms = $open !== null ? json_decode(strval($open['terms'] ?? '[]'), true) : [];
            $carried = array_values(array_filter(is_array($openTerms) ? $openTerms : [], static fn($t) => is_array($t) && ($t['by'] ?? '') === 'npc'));
            if (count($carried) === 0) {
                stobeDealLog('warn', 'Negotiation rejected: one-sided terms (nothing from the NPC)', ['npc'=>$npc, 'decision'=>$decision]);
                return ['ok'=>false, 'error'=>'one_sided_terms'];
            }
            $terms = array_merge($terms, $carried);
            stobeDealLog('info', 'Negotiation: NPC side carried over from the deal on the table', ['npc'=>$npc, 'decision'=>$decision]);
        }
    }
"""
assert t.count(old2) == 1, "anchor 2"
t = t.replace(old2, new2)
p.write_text(t, encoding="utf-8")
print("patch_round9c: applied")
