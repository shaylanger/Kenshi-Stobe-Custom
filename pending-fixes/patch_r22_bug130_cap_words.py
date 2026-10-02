#!/usr/bin/env python3
"""Bug 130: the bug 91 cap lowers an accepted amount, but her words keep the old one.

Run 9 (test 18): Peraxis offered 300 to surrender; Shay: "Make it 400 and we're
done." Peraxis: "Four hundred, then. Cats are yours..." with ACCEPT 400. The cap
(common bandit: 300) recorded 300 ACCEPTED, so she said 400 and paid 300.

The cap stands (Shay's offer-size rule), so the words must follow it:
- an ACCEPT whose Cats were capped is a COUNTER at the cap (she can't accept it);
- the result carries 'capped'; the speech check then replaces her line with
  "I can't go above 300 Cats. My terms: ... Deal?" unless she already said the
  capped amount;
- "Four hundred, then." counts as a spoken amount (a bare number as its own
  sentence or before "then"), so the stream holds it back for the check.

Usage: patch_r22_bug130_cap_words.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_phase1.php'
text = path.read_text(encoding='utf-8')
if 'bug 130' in text:
    print('already patched')
    sys.exit(0)

edits = [
    # 1. remember the cap, turn a capped ACCEPT into a COUNTER
    ("""        [$offerCap, $offerCarried, $offerTier] = stobeNegOfferCap($npc, $npcData);
        foreach ($terms as $ti => $term) {
            if (($term['kind'] ?? '') !== 'GIVE_CATS' || ($term['by'] ?? '') !== 'npc') continue;
            $amount = intval($term['amount'] ?? 0);
            if ($amount <= $offerCap) continue;
            stobeDealLog('info', 'NPC offer capped (bug 91)', ['npc'=>$npc, 'offered'=>$amount, 'cap'=>$offerCap, 'carried'=>$offerCarried, 'tier'=>$offerTier]);
""",
     """        [$offerCap, $offerCarried, $offerTier] = stobeNegOfferCap($npc, $npcData);
        foreach ($terms as $ti => $term) {
            if (($term['kind'] ?? '') !== 'GIVE_CATS' || ($term['by'] ?? '') !== 'npc') continue;
            $amount = intval($term['amount'] ?? 0);
            if ($amount <= $offerCap) continue;
            stobeDealLog('info', 'NPC offer capped (bug 91)', ['npc'=>$npc, 'offered'=>$amount, 'cap'=>$offerCap, 'carried'=>$offerCarried, 'tier'=>$offerTier]);
            $capped = ['from'=>$amount, 'to'=>max(0, $offerCap)];
"""),
    ("""        $terms = array_values($terms);
    }
    // Bug 32: her own weapon only goes""",
     """        $terms = array_values($terms);
        if ($capped !== null && $decision === 'ACCEPT') {
            // Bug 130: she can't accept more than the cap; what's recorded is her counter at the cap.
            $decision = 'COUNTER';
            stobeDealLog('info', 'Negotiation: accept above the cap recorded as a counter at the cap (bug 130)', ['npc'=>$npc, 'capped'=>$capped]);
        }
    }
    // Bug 32: her own weapon only goes"""),
    ("""    if (in_array($kind, ['surrender','assist'], true)) {
        [$offerCap,""",
     """    $capped = null;
    if (in_array($kind, ['surrender','assist'], true)) {
        [$offerCap,"""),
    # 2. results carry the cap
    ("""        return ['ok'=>true,'decision'=>$decision,'id'=>$openId,'terms'=>$terms,'status'=>$state,'kind'=>$kind];""",
     """        return ['ok'=>true,'decision'=>$decision,'id'=>$openId,'terms'=>$terms,'status'=>$state,'kind'=>$kind] + ($capped !== null ? ['capped'=>$capped] : []);"""),
    ("""    return ['ok'=>true,'decision'=>$decision,'id'=>$id,'terms'=>$terms,'status'=>$state,'kind'=>$kind];
}""",
     """    return ['ok'=>true,'decision'=>$decision,'id'=>$id,'terms'=>$terms,'status'=>$state,'kind'=>$kind] + ($capped !== null ? ['capped'=>$capped] : []);
}"""),
    # 3. "Four hundred, then." is a spoken amount
    ("""        '/\\b(?:total(?:\\s+of)?|now|after(?:wards)?|up\\s*front|later|pay(?:s|ing)?|paid|owes?|owed|another|rest(?:\\s+of)?)\\s+(?:(?:is|of|me|you|the|just|only|another|still)\\s+){0,2}(\\d+)\\b/i',
    ];""",
     """        '/\\b(?:total(?:\\s+of)?|now|after(?:wards)?|up\\s*front|later|pay(?:s|ing)?|paid|owes?|owed|another|rest(?:\\s+of)?)\\s+(?:(?:is|of|me|you|the|just|only|another|still)\\s+){0,2}(\\d+)\\b/i',
        // Bug 130: "Four hundred, then." / "400. Fine." (a bare amount as its own sentence)
        '/(?:^|[.!?]\\s+)(\\d+)(?=\\s*(?:[,.!?]|then\\b))/i',
    ];"""),
    # 4. the speech check enforces the cap
    ("""    $allowed = stobeDealAllowedCatsAmounts($terms, is_array($state) ? $state : [], stobeDealNpcPurse($npc));
    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    if (count($wrong) === 0) return null;
    $line = stobeDealPlainTermsLine($terms, $decision);
    if ($line === '') return null;
    return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>$wrong, 'allowed'=>array_keys($allowed)];
}""",
     """    $allowed = stobeDealAllowedCatsAmounts($terms, is_array($state) ? $state : [], stobeDealNpcPurse($npc));
    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    $capped = is_array($dealResult['capped'] ?? null) ? $dealResult['capped'] : null;
    if ($capped !== null && (count($spoken) === 0 || count($wrong) > 0)) {
        // Bug 130: the cap lowered what she agreed to; say the capped terms, not hers.
        $line = stobeDealPlainTermsLine($terms, $decision);
        if ($line === '') return null;
        $line = "I can't go above " . intval($capped['to']) . ' Cats. ' . $line;
        return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>count($wrong) > 0 ? $wrong : [intval($capped['from'])], 'allowed'=>array_keys($allowed)];
    }
    if (count($wrong) === 0) return null;
    $line = stobeDealPlainTermsLine($terms, $decision);
    if ($line === '') return null;
    return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>$wrong, 'allowed'=>array_keys($allowed)];
}"""),
    ("""    $terms = is_array($dealResult['terms'] ?? null) ? $dealResult['terms'] : [];
    if (count($terms) === 0) return null;
    $spoken = stobeDealSpokenCatsAmounts($text);
    if (count($spoken) === 0) return null;""",
     """    $terms = is_array($dealResult['terms'] ?? null) ? $dealResult['terms'] : [];
    if (count($terms) === 0) return null;
    $spoken = stobeDealSpokenCatsAmounts($text);
    if (count($spoken) === 0 && empty($dealResult['capped'])) return null;"""),
]
for old, new in edits:
    assert text.count(old) == 1, 'anchor not found exactly once: ' + old[:80]
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
