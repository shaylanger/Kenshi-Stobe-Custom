#!/usr/bin/env python3
"""Item 43: a two-part order does only one part.

Run 12: "give me all your bread and all your dried meat" gave only the bread (a reply
carries one action), while she said "You took my food". Shay: do both hand-overs.
When the player asks for several carried items in one line and her reply already hands
one of them over, the missing hand-overs are added (GIVE_ITEM per item she carries;
"all"/plural = everything, "both" = 2, a number = that many, else 1). An item her reply
refuses in the same sentence ("the meat stays") is left out.

Usage: patch_r26_43_multi_handover.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])


def patch(rel, marker, pairs):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', f)
        return
    for old, new in pairs:
        assert s.count(old) == 1, f'{rel}: anchor not unique/missing: {old[:70]!r}'
        s = s.replace(old, new)
    assert marker in s, f'{rel}: marker missing after patch'
    f.write_text(s, encoding='utf-8')
    print('patched', f)


FUNC = r'''/** Work orders a non-faction NPC never takes from the player (feature 1). */
function stobeNonFactionWorkOrderCommands(): array {'''

NEW_FUNC = r'''/**
 * Item 43: the items a player's line asks her to hand over, in order:
 * [['part'=>'dried meat', 'qty'=>int|null (null = all)], ...]. Empty if it isn't a hand-over request.
 */
function stobeParseHandoverRequest(string $playerLine): array {
    $m = strtolower(function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers($playerLine) : $playerLine);
    if (preg_match("/\b(don'?t|do\s+not|never|keep)\b/", $m)) return [];
    if (!preg_match("/\b(?:give|hand|pass|toss|throw|bring)\s+(?:me|over)\s+(.+?)(?:[.?!;]|$)/", $m, $mm)) return [];
    $out = [];
    foreach (preg_split('/\s*(?:,\s*and\s+|,\s*|\s+and\s+|\s*&\s*)/', $mm[1]) ?: [] as $raw) {
        $p = trim(preg_replace("/\b(please|now|too|as well|then)\b/", '', $raw) ?? $raw);
        $qty = 1;
        if (preg_match('/^(?:all|every|each)\b(?:\s+of)?/', $p)) $qty = null;
        elseif (preg_match('/^both\b(?:\s+of)?/', $p)) $qty = 2;
        elseif (preg_match('/^(\d{1,4})\b/', $p, $n)) $qty = max(1, intval($n[1]));
        $p = trim(preg_replace("/^(?:all|every|each|both|\d{1,4})\b(?:\s+of)?\s*|\b(?:your|the|my|those|these|that|this|some|a|an|of)\b\s*/", '', $p) ?? $p);
        $p = trim(preg_replace('/\s+/', ' ', $p) ?? $p);
        if ($p === '' || strlen($p) < 3) continue;
        $out[] = ['part'=>$p, 'qty'=>$qty];
    }
    return $out;
}

/**
 * Item 43: the player asked for several carried items in one line and her reply hands
 * over one of them (a reply carries one action): the missing GIVE_ITEM actions.
 */
function stobeInferMissingHandovers(string $playerLine, array|false $npcData, array $actions, string $reply, string $playerName): array {
    if ($playerName === '' || !is_array($npcData) || !function_exists('stobeNegInventoryCounts')
        || !function_exists('stobeNegItemMatchesTerm')) return [];
    $given = [];
    foreach ($actions as $a) {
        $parts = explode('@', strval($a));
        if (strtoupper(trim($parts[0])) !== 'GIVE_ITEM' || count($parts) < 3) continue;
        if (strcasecmp(trim($parts[1]), $playerName) !== 0 && strtolower(trim($parts[1])) !== 'player') continue;
        $given[] = strtolower(trim($parts[2]));
    }
    if (count($given) === 0) return [];
    $wanted = stobeParseHandoverRequest($playerLine);
    if (count($wanted) < 2) return [];
    $counts = stobeNegInventoryCounts(strval($npcData['inventory'] ?? ''));
    $display = function_exists('stobeItemListDisplayNames') ? stobeItemListDisplayNames(strval($npcData['inventory'] ?? '')) : [];
    $sentences = preg_split('/(?<=[.!?])\s+/', strtolower($reply)) ?: [];
    $added = [];
    foreach ($wanted as $w) {
        $part = $w['part'];
        $match = '';
        foreach ($counts as $name => $qty) {
            if ($qty < 1) continue;
            if (stobeNegItemMatchesTerm($name, $part) || stobeNegItemMatchesTerm($name, rtrim($part, 's'))) { $match = $name; break; }
        }
        if ($match === '') continue;
        $covered = false;
        foreach ($given as $g) {
            if ($g === $match || stobeNegItemMatchesTerm($match, $g) || stobeNegItemMatchesTerm($g, $part)) { $covered = true; break; }
        }
        if ($covered) continue;
        // Her reply keeps this one ("the meat stays", "not the meat").
        $head = strval(array_slice(preg_split('/\s+/', rtrim($part, 's')) ?: [''], -1)[0]);
        $refused = false;
        foreach ($sentences as $sentence) {
            if ($head !== '' && str_contains($sentence, $head)
                && preg_match("/\b(no|not|won'?t|stays|keep|keeping|mine|never|can'?t)\b/", $sentence)) { $refused = true; break; }
        }
        if ($refused) continue;
        // "all"/no number with a plural ("your breads") = everything she carries.
        $all = $w['qty'] === null || ($w['qty'] === 1 && preg_match('/s$/', $part) === 1 && !preg_match('/ss$/', $part));
        $qty = $all ? $counts[$match] : min($w['qty'], $counts[$match]);
        $added[] = 'GIVE_ITEM@' . $playerName . '@' . ($display[$match] ?? ucwords($match)) . '@' . max(1, intval($qty));
        $given[] = $match;
    }
    return $added;
}

/** Work orders a non-faction NPC never takes from the player (feature 1). */
function stobeNonFactionWorkOrderCommands(): array {'''

patch('lib/chat_helper_functions.php', 'function stobeInferMissingHandovers(', [(FUNC, NEW_FUNC)])

CALL_OLD = '''if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {
    try {
        $responseActions = stobeNegAttachPendingForChat($targetNpc, $responseActions);'''
CALL_NEW = '''if (!$narratorMode && function_exists('stobeInferMissingHandovers')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $missingHandovers = stobeInferMissingHandovers(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''), $npcData, $responseActions,
        strval($responseText ?? ''), strval($playerName ?? ''));
    if (count($missingHandovers) > 0) {
        $responseActions = array_merge($responseActions, $missingHandovers);
        stobeLogInfo('Two-part hand-over: missing GIVE_ITEM added (item 43)', ['npc'=>$targetNpc, 'added'=>$missingHandovers]);
    }
}
''' + CALL_OLD

patch('processor/chat.php', "missing GIVE_ITEM added (item 43)", [(CALL_OLD, CALL_NEW)])
