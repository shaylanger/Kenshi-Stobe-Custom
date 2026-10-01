#!/usr/bin/env python3
"""Round 7f: the 7c summary-text parser was too lenient. On "Shay gives 2500 cats, Malzin
unequips iron hat and black cloth shirt." it matched only the Cats and dropped the rest.
The leftover "2500 cats" then looked like a subset of the deal that had just finished, so the
7d guard discarded the new deal.

The parser now has to account for the whole text (otherwise null, and the deal is rejected
loudly), and it understands simple prose: clauses split on ; , or ". ", verbs
pay/give N cats, unequip/take off/remove X [and Y], equip/put on X [and Y], give X, promise: X.

Usage: patch_round7f.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_phase1.php"
text = p.read_text(encoding="utf-8")
start = text.index("function stobeDealParseTermsText(string $text): ?array {")
end = text.index("/** Same agreement? Compares kinds, sides, amounts, items and quantities. */")
assert start < end

NEW = r"""function stobeDealParseTermsText(string $text): ?array {
    $splitItems = static function (string $list): array {
        $out = [];
        foreach (preg_split('/\s*(?:,|\band\b|&)\s*/i', $list) ?: [] as $item) {
            $item = trim(preg_replace('/^(?:the|her|his|my|your|their)\s+/i', '', trim($item)) ?? $item);
            if ($item !== '') $out[] = $item;
        }
        return $out;
    };
    $terms = [];
    $text = trim(preg_replace('/\s*\[[a-z_ ]+\]/i', '', $text) ?? $text);
    foreach (preg_split('/\s*;\s*|,\s+(?=\S+\s+(?:pay|pays|give|gives|unequip|unequips|take|takes|remove|removes|equip|equips|put|puts|promise|promises|stop|stops)\b)|\.\s+/i', $text) ?: [] as $part) {
        $part = trim(rtrim(trim($part), '.'));
        if ($part === '') continue;
        if (preg_match('/^(.+?)\s+(?:pay|pays|give|gives)\s+(\d+)\s+cats?$/i', $part, $m)) {
            $terms[] = ['kind'=>'GIVE_CATS', 'by'=>trim($m[1]), 'amount'=>intval($m[2])];
        } elseif (preg_match('/^(.+?)\s+(?:unequips?(?:\s+items?)?|takes?\s+off|removes?)\s+(.+)$/i', $part, $m)) {
            foreach ($splitItems($m[2]) as $item) $terms[] = ['kind'=>'UNEQUIP_ITEM', 'by'=>trim($m[1]), 'item'=>$item];
        } elseif (preg_match('/^(.+?)\s+(?:equips?(?:\s+items?)?|puts?\s+on)\s+(.+)$/i', $part, $m)) {
            foreach ($splitItems($m[2]) as $item) $terms[] = ['kind'=>'EQUIP_ITEM', 'by'=>trim($m[1]), 'item'=>$item];
        } elseif (preg_match('/^(.+?)\s+promises?\s*:?\s*(.+)$/i', $part, $m)) {
            $terms[] = ['kind'=>'PROMISE', 'by'=>trim($m[1]), 'text'=>trim($m[2])];
        } elseif (preg_match('/^(.+?)\s+(?:returns?\s+item|returns?)\s+([^,]+)$/i', $part, $m) && !preg_match('/\d+\s*cats?/i', $m[2])) {
            $terms[] = ['kind'=>'RETURN_ITEM', 'by'=>trim($m[1]), 'item'=>trim($m[2])];
        } elseif (preg_match('/^(.+?)\s+(?:gives?\s+item|gives?)\s+([^,]+)$/i', $part, $m) && !preg_match('/\d+\s*cats?/i', $m[2])) {
            $terms[] = ['kind'=>'GIVE_ITEM', 'by'=>trim($m[1]), 'item'=>trim($m[2])];
        } elseif (preg_match('/^(.+?)\s+(?:stops?\s+attack(?:ing)?|stops?\s+fighting)$/i', $part, $m)) {
            $terms[] = ['kind'=>'STOP_ATTACK', 'by'=>trim($m[1]), 'target'=>'player'];
        } elseif (preg_match('/^(.+?)\s+first\s+aid\b(.*)$/i', $part, $m)) {
            $terms[] = ['kind'=>'FIRST_AID', 'by'=>trim($m[1])];
        } else {
            return null; // anything unaccounted for: refuse rather than record half a deal
        }
    }
    return count($terms) > 0 ? $terms : null;
}

"""
p.write_text(text[:start] + NEW + text[end:], encoding="utf-8")
print("patch_round7f: applied")
