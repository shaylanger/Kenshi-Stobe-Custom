#!/usr/bin/env python3
"""Round 7c: I6 renegotiation lost. The model sometimes writes deal_terms as the prompt's
own summary text ("shay pay 1500 Cats; Malzin unequip item Iron Hat") instead of JSON.
json_decode failed, and an ACCEPT then silently fell back to the old terms on the table.
Parse that summary format back into terms; log when neither form parses.

Usage: patch_round7c.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("lib/negotiation_phase1.php",
      """    $terms = json_decode(strval($response['deal_terms'] ?? ''), true);
    if ((!is_array($terms) || count($terms) === 0) && $decision === 'ACCEPT' && $open !== null) {""",
      """    $termsRaw = trim(strval($response['deal_terms'] ?? ''));
    $terms = json_decode($termsRaw, true);
    if (!is_array($terms) && $termsRaw !== '') {
        // Models sometimes echo the prompt's summary text instead of JSON.
        $terms = stobeDealParseTermsText($termsRaw);
        stobeDealLog($terms === null ? 'warn' : 'info', $terms === null
            ? 'Negotiation terms unreadable (neither JSON nor summary text)'
            : 'Negotiation terms parsed from summary text', ['npc'=>$npc, 'decision'=>$decision, 'terms'=>$termsRaw]);
    }
    if ((!is_array($terms) || count($terms) === 0) && $decision === 'ACCEPT' && $open !== null) {""")

patch("lib/negotiation_phase1.php",
      """/** Same agreement? Compares kinds, sides, amounts, items and quantities. */""",
      """/**
 * Terms written in stobeNegTermsSummary's format ("shay pay 1500 Cats; Malzin unequip item
 * Iron Hat [awaiting_player]"). Sides stay as names; stobeDealNormalizeConditionalTerms maps
 * them to npc/player. Returns null if any part doesn't parse.
 */
function stobeDealParseTermsText(string $text): ?array {
    $kinds = function_exists('stobeNegAllowedTermKinds')
        ? stobeNegAllowedTermKinds()
        : ['GIVE_CATS','GIVE_ITEM','RETURN_ITEM','STOP_ATTACK','FIRST_AID','UNEQUIP_ITEM','EQUIP_ITEM','PROMISE'];
    usort($kinds, static fn($a, $b) => strlen($b) - strlen($a));
    $terms = [];
    foreach (preg_split('/\\s*;\\s*/', trim($text)) ?: [] as $part) {
        $part = trim(preg_replace('/\\s*\\[[a-z_ ]+\\]\\s*$/i', '', $part) ?? $part);
        if ($part === '') continue;
        if (preg_match('/^(.+?)\\s+(?:pay|pays|give|gives)\\s+(\\d+)\\s+cats?\\b/i', $part, $m)) {
            $terms[] = ['kind'=>'GIVE_CATS', 'by'=>trim($m[1]), 'amount'=>intval($m[2])];
            continue;
        }
        $matched = false;
        foreach ($kinds as $kind) {
            $words = strtolower(str_replace('_', ' ', $kind));
            if (!preg_match('/^(.+?)\\s+' . preg_quote($words, '/') . '\\b\\s*:?\\s*(.*)$/i', $part, $m)) continue;
            $term = ['kind'=>$kind, 'by'=>trim($m[1])];
            $rest = trim($m[2]);
            if ($kind === 'PROMISE') $term['text'] = $rest;
            elseif ($kind === 'STOP_ATTACK') $term['target'] = 'player';
            elseif ($rest !== '') $term['item'] = $rest;
            $terms[] = $term;
            $matched = true;
            break;
        }
        if (!$matched) return null;
    }
    return count($terms) > 0 ? $terms : null;
}

/** Same agreement? Compares kinds, sides, amounts, items and quantities. */""")

print("patch_round7c: applied")
