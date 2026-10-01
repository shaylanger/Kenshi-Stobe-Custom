#!/usr/bin/env python3
"""Bug 91: Grevik (Dust Bandit) offered 1000, then 9000 cats (all he carried)
to be spared, and offered twice in one long fight.
Shay's caps: common/starving bandit 50-300; leader/named boss up to ~1000;
wealthy (traders, nobles) scaled to what they carry; never more than 30-40 %
(35 %) of what they carry; broke -> item/info or beg. Once per NPC per fight.
- stobeNegOfferCap(): the cap; told to the model in the surrender/assist
  instruction and enforced on the captured terms (speech rewrite follows).
- Per-NPC initiative cooldown 600 s -> 1800 s.
Usage: patch_r19_bug91_offer_caps.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

CAP = r'''/**
 * Bug 91: most Cats an NPC offers to be spared / for help. Common bandits
 * 50-300, leaders/bosses up to ~1000, wealthy NPCs scaled to their purse;
 * never more than 35 % of what they carry (Shay, 2026-10-01).
 * Returns [cap, carried, tier].
 */
function stobeNegOfferCap(string $npc, array $npcData): array {
    $meta = function_exists('normalizeNpcMetadataPayload')
        ? normalizeNpcMetadataPayload($npcData['metadata'] ?? []) : (is_array($npcData['metadata'] ?? null) ? $npcData['metadata'] : []);
    $carried = max(0, intval($meta['money'] ?? ($npcData['money'] ?? 0)));
    $who = strtolower($npc . ' ' . strval($npcData['faction'] ?? '') . ' ' . strval($meta['faction'] ?? '') . ' ' . strval($meta['title'] ?? ''));
    if (preg_match('/\b(traders?|merchants?|caravans?|nobles?|lords?|lady|shopkeepers?|barman|bartenders?|innkeepers?)\b/', $who)) {
        $tier = 'wealthy'; $tierCap = PHP_INT_MAX;
    } elseif (preg_match('/\b(leaders?|boss|king|queen|chief|captain|warlord|commander|elder)\b/', $who)) {
        $tier = 'leader'; $tierCap = 1000;
    } else {
        $tier = 'common'; $tierCap = 300;
    }
    $cap = min($tierCap, intval(floor($carried * 0.35)));
    return [max(0, $cap), $carried, $tier];
}

function stobeDealCaptureResponse('''

patch("lib/negotiation_phase1.php", [
    ("function stobeDealCaptureResponse(", CAP),
    ("""        if (!$ceasefire) $terms[] = ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'];
    }""",
     """        if (!$ceasefire) $terms[] = ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'];
    }
    if (in_array($kind, ['surrender','assist'], true)) {
        [$offerCap, $offerCarried, $offerTier] = stobeNegOfferCap($npc, $npcData);
        foreach ($terms as $ti => $term) {
            if (($term['kind'] ?? '') !== 'GIVE_CATS' || ($term['by'] ?? '') !== 'npc') continue;
            $amount = intval($term['amount'] ?? 0);
            if ($amount <= $offerCap) continue;
            stobeDealLog('info', 'NPC offer capped (bug 91)', ['npc'=>$npc, 'offered'=>$amount, 'cap'=>$offerCap, 'carried'=>$offerCarried, 'tier'=>$offerTier]);
            if ($offerCap > 0) {
                $terms[$ti]['amount'] = $offerCap;
            } else {
                unset($terms[$ti]); // broke: no Cats in the deal
            }
        }
        $terms = array_values($terms);
    }"""),
])

patch("lib/negotiation_engine.php", [
    ("const STOBE_NEG_INITIATIVE_NPC_COOLDOWN = 600;    // \"once per NPC per fight\"",
     "const STOBE_NEG_INITIATIVE_NPC_COOLDOWN = 1800;   // \"once per NPC per fight\" (a long fight outlasted 600 s, bug 91)"),
    ("""            if ($hostileToPlayer && stobeNegPhaseEnabled(4) && $ratio < stobeNegCourageThreshold($personality, 0.35)) {
                stobeNegQueueDirective($name, 'surrender', '', [""",
     """            [$offerCap, $offerCarried] = function_exists('stobeNegOfferCap') ? stobeNegOfferCap($name, $data) : [0, 0];
            $offerLine = $offerCap > 0
                ? 'You carry about ' . $offerCarried . ' Cats; if you offer Cats, offer at most ' . $offerCap . ' (keep it modest). '
                : 'You have next to no Cats: offer an item, information or just beg - do not offer Cats. ';
            if ($hostileToPlayer && stobeNegPhaseEnabled(4) && $ratio < stobeNegCourageThreshold($personality, 0.35)) {
                stobeNegQueueDirective($name, 'surrender', '', ["""),
    ("""                        . 'In character, decide whether to beg for your life or offer something (Cats, items, surrender) in exchange for being spared. '""",
     """                        . 'In character, decide whether to beg for your life or offer something (Cats, items, surrender) in exchange for being spared. '
                        . $offerLine"""),
    ("""                        . 'In character, call out to ' . $player . ' for help. You may promise a reward that you can actually give. '""",
     """                        . 'In character, call out to ' . $player . ' for help. You may promise a reward that you can actually give. '
                        . $offerLine"""),
])
