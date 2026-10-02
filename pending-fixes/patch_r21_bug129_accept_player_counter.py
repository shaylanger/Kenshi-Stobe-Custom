#!/usr/bin/env python3
"""Bug 129: an NPC accepting the player's counter-offer is thrown away.

Run 9 (test 18): Peraxis offered 300 to surrender; Shay: "Make it 400 and
we're done." Peraxis: "Four hundred. Fine." with ACCEPT and terms of 400,
but the bug 96 guard ("on an NPC's own offer, ACCEPT stands only if the
player's line accepts it") dropped it: the ledger stayed at 300 PROPOSED.
The guard now lets ACCEPT through when the player's line names an amount
and her terms differ from her own offer: she's accepting his counter.

Usage: patch_r21_bug129_accept_player_counter.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_phase1.php'
text = path.read_text(encoding='utf-8')
old = """    if ($decision === 'ACCEPT' && $open !== null && strval($open['proposer'] ?? 'player') === 'npc'
        && function_exists('stobeNegLooksLikeAcceptance')
        && !stobeNegLooksLikeAcceptance(strtolower(trim($playerMessage)))) {"""
new = """    if ($decision === 'ACCEPT' && $open !== null && strval($open['proposer'] ?? 'player') === 'npc'
        && function_exists('stobeNegLooksLikeAcceptance')
        && !stobeNegLooksLikeAcceptance(strtolower(trim($playerMessage)))
        && !stobeDealAcceptsPlayerCounter($response, $open, $playerMessage)) {"""
helper = """/**
 * Bug 129: "Make it 400" -> "Four hundred. Fine." is her accepting the player's
 * counter: his line names an amount and her terms differ from her own offer.
 */
function stobeDealAcceptsPlayerCounter(array $response, array $open, string $playerMessage): bool {
    if (!preg_match('/\\d|\\b(hundred|thousand|fifty|twenty|thirty|forty|sixty|seventy|eighty|ninety)\\b/i', $playerMessage)) return false;
    $terms = json_decode(trim(strval($response['deal_terms'] ?? '')), true);
    if (!is_array($terms) || count($terms) === 0) return false;
    $openTerms = json_decode(strval($open['terms'] ?? '[]'), true);
    return function_exists('stobeDealTermsDiffer') && stobeDealTermsDiffer(is_array($openTerms) ? $openTerms : [], $terms);
}

function stobeDealCaptureResponse("""
if 'Bug 129' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'guard anchor not found exactly once'
assert text.count('function stobeDealCaptureResponse(') == 1, 'function anchor'
text = text.replace(old, new).replace('function stobeDealCaptureResponse(', helper, 1)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
