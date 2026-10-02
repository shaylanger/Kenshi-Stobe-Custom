#!/usr/bin/env python3
"""Bug 96: "We're done here." to Skovrek was recorded as ACCEPT of his open
assist offer: stobeNegPlayerAcceptsOfferNote() took single words (done, fine,
ok, sure...) anywhere in the line as acceptance.
Fix: stobeNegLooksLikeAcceptance(): clear acceptance words (deal, agreed,
accept, you're on, you got it) anywhere, or a short reply (<= 4 words) that is
a yes/sure/ok/fine/done; never conversation-enders ("we're done", "done here").
Usage: patch_r20_bug96_accept.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/negotiation_engine.php", [
    ("function stobeNegPlayerAcceptsOfferNote(string $npc, string $message): string {",
     """/**
 * Bug 96: does this player line accept an open offer? Clear acceptance words
 * anywhere, or a short yes-type reply; never a conversation-ender ("we're done").
 */
function stobeNegLooksLikeAcceptance(string $text): bool {
    $text = strtolower(trim($text));
    if ($text === '' || str_ends_with($text, '?')) return false;
    if (preg_match("/\\b(no deal|not|don'?t|won'?t|never|nah|no way)\\b/", $text)) return false;
    if (preg_match("/\\b(we'?re|we are|i'?m|i am) done\\b|\\bdone (here|talking|with)\\b|\\bthat'?s (it|enough)\\b/", $text)) return false;
    if (preg_match("/\\b(deal|agreed|agree|accept|accepted|you got it|you'?re on)\\b/", $text)) return true;
    $words = array_values(array_filter(preg_split('/\\s+/', trim(preg_replace("/[^a-z0-9' ]+/", ' ', $text))) ?: []));
    return count($words) > 0 && count($words) <= 4
        && preg_match("/\\b(yes|yeah|yep|sure|ok|okay|fine|done)\\b/", $text) === 1;
}

function stobeNegPlayerAcceptsOfferNote(string $npc, string $message): string {"""),
    ("""        if ($text === '' || str_ends_with($text, '?')) return '';
        if (!preg_match("/\\b(deal|agreed|agree|accept|accepted|fine|okay|ok|yes|sure|done|you got it|you'?re on)\\b/", $text)) return '';
        if (preg_match("/\\b(no deal|not|don'?t|won'?t|never|nah|no way)\\b/", $text)) return '';
""",
     """        if (!stobeNegLooksLikeAcceptance($text)) return ''; // bug 96
"""),
])
