#!/usr/bin/env python3
"""Bug 119: asked to put on something she already wears, she tries to equip it.

Run 9 (test 16): "Put your black rag shirt back on" while she wore it: EQUIP_ITEM
("Let me get it back on"); KenshiFP refused harmlessly, but her words were wrong.
Worse, when she did say "it's already on", the old premature-claim rewrite turned
it into "Let me put it on".

- Prompt: when the player asks her to put on / wear an item she already wears (and
  carries no unworn one like it), the turn gets a note: "You are already wearing your
  Black Rag Shirt: say so, don't use EquipItem for it."
- Safety net in streamResponse: EQUIP_ITEM of a worn item (no unworn copy carried)
  is dropped before the premature-claim rewrite; an unspoken "let me put it on" line
  becomes "My <item>'s already on."

Usage: patch_r22_bug119_worn_item_equip.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

# ---- lib/chat_helper_functions.php: helpers + safety net
lib = root / 'lib' / 'chat_helper_functions.php'
text = lib.read_text(encoding='utf-8')
if 'bug 119' not in text:
    helper_anchor = "function stobeSpeechClaimsEquipDone(string $message): bool {"
    helpers = r"""/** "Black Rag Shirt [Shoddy] x1 value 96, ..." -> ['black rag shirt' => 'Black Rag Shirt'] */
function stobeItemListDisplayNames(string $text): array {
    $names = [];
    foreach (preg_split('/,\s*(?=[^,]*\bx\d+)/', $text) ?: [] as $entry) {
        if (!preg_match('/^\s*(.+?)\s+x\d+\b/', $entry, $m)) continue;
        $display = trim(preg_replace('/\s*\[[^\]]*\]|\s*\([^)]*\)/', '', $m[1]) ?? '');
        if ($display !== '') $names[strtolower($display)] = $display;
    }
    return $names;
}

/** A name matches an item: same name, one inside the other, or the same last word ("shirt"). */
function stobeItemNameMatches(string $query, string $itemLower, bool $loose = true): bool {
    $q = strtolower(trim(preg_replace('/\s*\[[^\]]*\]|\s*\([^)]*\)/', '', $query) ?? ''));
    $q = trim(preg_replace('/^(?:your|my|her|his|the|that|this)\s+/', '', $q) ?? $q);
    if ($q === '') return false;
    if ($q === $itemLower || str_contains($itemLower, $q) || str_contains($q, $itemLower)) return true;
    if (!$loose) return false;
    $qWords = preg_split('/\s+/', $q) ?: [];
    $iWords = preg_split('/\s+/', $itemLower) ?: [];
    return count($qWords) > 1 && end($qWords) === end($iWords) && count(array_intersect($qWords, $iWords)) >= 2;
}

/**
 * Bug 119: the worn item an equip request names, when she carries no unworn one like it.
 * Returns the worn display names ('' list when it isn't a worn item).
 */
function stobeWornItemsMatching(string $query, array|false $npcData): array {
    if (!is_array($npcData) || trim($query) === '') return [];
    $worn = stobeItemListDisplayNames(strval($npcData['equipment'] ?? ''));
    $carried = stobeItemListDisplayNames(strval($npcData['inventory'] ?? ''));
    foreach ($carried as $lower => $display) {
        if (stobeItemNameMatches($query, $lower)) return []; // an unworn one: equipping it is real
    }
    foreach ([false, true] as $loose) { // the exact item first, "same kind" only if none
        $hits = [];
        foreach ($worn as $lower => $display) {
            if (stobeItemNameMatches($query, $lower, $loose)) $hits[] = $display;
        }
        if (count($hits) > 0) return $hits;
    }
    return [];
}

/** Bug 119: prompt note when the player asks her to put on what she already wears, or ''. */
function stobeWornItemRequestNote(string $playerMessage, array|false $npcData): string {
    $m = strtolower($playerMessage);
    if (!preg_match("/\b(put|get|slip|pull|throw)\b[^.?!]{0,50}\bon\b|\b(wear|equip|don)\b/", $m)) return '';
    if (preg_match("/\b(take|took|get|pull)\b[^.?!]{0,30}\boff\b|\bremove|unequip|strip/", $m)) return '';
    if (!is_array($npcData)) return '';
    $worn = stobeItemListDisplayNames(strval($npcData['equipment'] ?? ''));
    $hits = [];
    foreach ($worn as $lower => $display) {
        $words = preg_split('/\s+/', $lower) ?: [];
        // The full name, or "your <last word>" ("put your shirt back on").
        if (str_contains($m, $lower) || preg_match('/\b' . preg_quote(end($words), '/') . 's?\b/', $m)) {
            if (count(stobeWornItemsMatching($display, $npcData)) > 0) $hits[] = $display;
        }
    }
    if (count($hits) === 0) return '';
    return 'You are already wearing your ' . implode(' and your ', $hits)
        . ': say it is already on; do not use EquipItem for it.';
}

"""
    assert text.count(helper_anchor) == 1, 'helper anchor'
    text = text.replace(helper_anchor, helpers + helper_anchor)
    net_old = """        if (str_starts_with($normalizedAction, 'EQUIP_ITEM@')) {
            $equipQuery = trim(substr($normalizedAction, strlen('EQUIP_ITEM@')));
            if (stobeSpeechClaimsEquipDone($message)) {"""
    net_new = """        if (str_starts_with($normalizedAction, 'EQUIP_ITEM@')) {
            $equipQuery = trim(substr($normalizedAction, strlen('EQUIP_ITEM@')));
            $wornHits = stobeWornItemsMatching($equipQuery, $actorData);
            if (count($wornHits) > 0) {
                // Bug 119: she already wears it; nothing to equip.
                stobeLogInfo('Equip of an item she already wears dropped (bug 119)', ['actor'=>$actor, 'item'=>$equipQuery, 'worn'=>$wornHits]);
                if ($message !== '' && preg_match("/\\b(let me|i(?:'|’)ll|gonna|going to)\\b[^.?!]{0,40}\\bon\\b/i", $message)) {
                    $message = 'My ' . $wornHits[0] . "'s already on.";
                }
                continue;
            }
            if (stobeSpeechClaimsEquipDone($message)) {"""
    assert text.count(net_old) == 1, 'safety net anchor'
    text = text.replace(net_old, net_new)
    lib.write_text(text, encoding='utf-8', newline='')
    print('patched', lib)

# ---- processor/chat.php: the prompt note
chat = root / 'processor' / 'chat.php'
c = chat.read_text(encoding='utf-8')
if 'bug 119' not in c:
    anchor = """// Mid-fight replies skip the model's hidden reasoning step (setting COMBAT_FAST_REPLIES)."""
    add = """// Bug 119: asked to put on what she already wears: tell her it's on.
if (!$narratorMode && strcasecmp($speaker, $playerName) === 0 && function_exists('stobeWornItemRequestNote')) {
    $wornNote = stobeWornItemRequestNote($message, $npcData);
    if ($wornNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $wornNote . ']'];
        stobeLogInfo('Worn item note added (bug 119)', ['npc'=>$targetNpc, 'note'=>$wornNote]);
    }
}
"""
    assert c.count(anchor) == 1, 'chat anchor'
    c = c.replace(anchor, add + anchor)
    chat.write_text(c, encoding='utf-8', newline='')
    print('patched', chat)

# ---- regression checks
test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'bug 119' not in t:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    add = """// ---------------------------------------------------------------- 12b. bug 119: putting on what she already wears
$wornNpc = ['equipment'=>'Black Cloth Shirt [Shoddy] x1 value 202, Black Rag Shirt [Shoddy] x1 value 96, Iron Hat [Shoddy] x1 value 526',
    'inventory'=>'Basic First Aid Kit x1 value 67'];
check('bug 119: worn item named in an equip action', stobeWornItemsMatching('Black Rag Shirt', $wornNpc) === ['Black Rag Shirt'], stobeWornItemsMatching('Black Rag Shirt', $wornNpc));
check('bug 119: an unworn copy can be equipped', stobeWornItemsMatching('Black Rag Shirt', array_merge($wornNpc, ['inventory'=>'Black Rag Shirt x1 value 96'])) === []);
check('bug 119: something she does not wear is not matched', stobeWornItemsMatching('Leather Vest', $wornNpc) === []);
$note119 = stobeWornItemRequestNote('Put your black rag shirt back on.', $wornNpc);
check('bug 119: note for "put your black rag shirt back on"', str_contains($note119, 'Black Rag Shirt') && !str_contains($note119, 'Iron Hat'), $note119);
check('bug 119: no note for taking it off', stobeWornItemRequestNote('Take your black rag shirt off.', $wornNpc) === '');
check('bug 119: no note for an item she does not wear', stobeWornItemRequestNote('Put on the leather vest.', $wornNpc) === '');

"""
    assert t.count(anchor) == 1, 'test anchor'
    t = t.replace(anchor, add + anchor)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
