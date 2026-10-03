#!/usr/bin/env python3
"""Item 41: she claims the player has gear she is still wearing.

Run 12: right after re-equipping her katana Malzin said "You've got my larder and my
blade both" (the prompt listed the katana under Equipment). A sentence that says the
player has / took / was given one of her worn items, while that item is still in her
Equipment, is dropped before it's spoken (per sentence in the stream; on the whole reply
for deferred/held-back replies). If the player's own line names the item (he asked for
it this turn), the check is off for that item.

Usage: patch_r26_41_false_gear_claim.py <StobeServer tree>  (idempotent)
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


GUARD = r'''// ---- Item 41: she says the player has gear she is still wearing ------------------------

/**
 * A sentence saying the player has / took / was given one of her worn items while it is
 * still in her Equipment: returns that item's display name, or ''. If the player's line
 * names the item (he asked for it this turn), that item is not checked.
 */
function stobeFalseGearClaim(string $sentence, array|false $npcData, string $playerMessage = ''): string {
    if (!is_array($npcData) || !function_exists('stobeNegInventoryDisplayNames')) return '';
    $s = strtolower($sentence);
    $spans = [];
    if (preg_match_all("/\b(?:you(?:'ve| have)?\s+(?:got|taken|took|have|own|kept|keep)\s+(?:both\s+|all\s+)?(?:of\s+)?my|(?:gave|given|handed|passed)\s+(?:you|over)\s+(?:both\s+|all\s+)?my|you\s+(?:hold|holding)\s+my)\s+([a-z' -]{2,80})/", $s, $m)) {
        $spans = array_merge($spans, $m[1]);
    }
    if (preg_match_all("/\bmy\s+([a-z' -]{2,40}?)\s+(?:is|are)\s+(?:yours|with you|in your)/", $s, $m)) {
        $spans = array_merge($spans, $m[1]);
    }
    if (count($spans) === 0) return '';
    $worn = stobeNegInventoryDisplayNames(strval($npcData['equipment'] ?? ''));
    if (count($worn) === 0) return '';
    $weapons = function_exists('stobeDealEquippedWeapons') ? stobeDealEquippedWeapons($npcData) : [];
    $asked = strtolower($playerMessage);
    foreach ($spans as $span) {
        foreach ($worn as $lower => $display) {
            $words = preg_split('/\s+/', $lower) ?: [];
            $head = strval(end($words));
            $named = str_contains($span, $lower)
                || (strlen($head) >= 3 && preg_match('/\b' . preg_quote($head, '/') . 's?\b/', $span));
            $isWeapon = isset($weapons[$lower]);
            if (!$named && $isWeapon && preg_match('/\b(weapon|blade|sword)s?\b/', $span)) $named = true;
            if (!$named) continue;
            $askedFor = str_contains($asked, $lower)
                || (strlen($head) >= 3 && preg_match('/\b' . preg_quote($head, '/') . 's?\b/', $asked))
                || ($isWeapon && preg_match('/\b(weapon|blade|sword)s?\b/', $asked));
            if ($askedFor) continue;
            return $display;
        }
    }
    return '';
}

/** Drops item-41 sentences from a whole reply: ['text'=>..., 'dropped'=>[sentence, ...]]. */
function stobeDropFalseGearClaims(string $text, array|false $npcData, string $playerMessage = ''): array {
    $kept = [];
    $dropped = [];
    foreach (preg_split('/(?<=[.!?])\s+/', trim($text)) ?: [] as $sentence) {
        if (trim($sentence) === '') continue;
        if (stobeFalseGearClaim($sentence, $npcData, $playerMessage) !== '') { $dropped[] = $sentence; continue; }
        $kept[] = $sentence;
    }
    if (count($dropped) === 0) return ['text'=>$text, 'dropped'=>[]];
    return ['text'=>count($kept) > 0 ? implode(' ', $kept) : 'Hm.', 'dropped'=>$dropped];
}

/** Item 44: the player said the NPC pays them N Cats'''

patch('lib/negotiation_phase1.php', 'function stobeFalseGearClaim(', [
    ('/** Item 44: the player said the NPC pays them N Cats', GUARD),
])

CHECK_SENTENCE = '''                    if ($gearCheck && stobeFalseGearClaim($sentenceChunk, $actorData, $gearPlayerMsg) !== '') {
                        $gearDropped[] = $sentenceChunk; // item 41: a false claim about her gear
                        continue;
                    }
                    if ($holdOnMoney && !$heldBack && stobeDealSpeechMentionsMoney($sentenceChunk)) {'''
CHECK_REMAINING = '''                if ($gearCheck && stobeFalseGearClaim($remainingChunk, $actorData, $gearPlayerMsg) !== '') {
                    $gearDropped[] = $remainingChunk; // item 41
                    continue;
                }
                if ($holdOnMoney && !$heldBack && stobeDealSpeechMentionsMoney($remainingChunk)) {'''

patch('lib/chat_helper_functions.php', '$gearDropped[] = $sentenceChunk; // item 41', [
    ("    unset($streamMeta['suppress_tts'], $streamMeta['defer_structured_stream'], $streamMeta['hold_stream_on_money']);",
     "    unset($streamMeta['suppress_tts'], $streamMeta['defer_structured_stream'], $streamMeta['hold_stream_on_money'], $streamMeta['player_message']);\n"
     "    // Item 41: sentences claiming the player has gear she still wears are not spoken.\n"
     "    $gearPlayerMsg = strval($meta['player_message'] ?? '');\n"
     "    $gearCheck = function_exists('stobeFalseGearClaim');"),
    ("        $heldFrom = '';\n        $messageStreamBuffer = '';",
     "        $heldFrom = '';\n        $gearDropped = [];\n        $messageStreamBuffer = '';"),
    ("            &$heldFrom,\n            $holdOnMoney,",
     "            &$heldFrom,\n            &$gearDropped,\n            $gearCheck,\n            $gearPlayerMsg,\n            $holdOnMoney,"),
    ("                    if ($holdOnMoney && !$heldBack && stobeDealSpeechMentionsMoney($sentenceChunk)) {", CHECK_SENTENCE),
    ("                if ($holdOnMoney && !$heldBack && stobeDealSpeechMentionsMoney($remainingChunk)) {", CHECK_REMAINING),
    ("        $finalActions = [];\n        $finalAction = trim(strval($finalSnapshot['action_tag'] ?? ''));",
     "        if (count($gearDropped) > 0) {\n"
     "            foreach ($gearDropped as $gearSentence) {\n"
     "                $finalMessage = trim(preg_replace('/\\s+/', ' ', str_replace($gearSentence, '', $finalMessage)) ?? $finalMessage);\n"
     "            }\n"
     "            if ($finalMessage === '') {\n"
     "                $finalMessage = 'Hm.';\n"
     "                if ($chunksEmitted === 0 && !$heldBack) {\n"
     "                    streamResponse($actor, 'ScriptQueue', $finalMessage, $actorData, [], $streamEventType, $streamListener, $streamGamets, $streamOptions);\n"
     "                    $chunksEmitted++;\n"
     "                }\n"
     "            }\n"
     "            stobeLogWarn('False gear claim not spoken (item 41)', ['npc'=>$actor, 'dropped'=>$gearDropped]);\n"
     "        }\n"
     "        $finalActions = [];\n        $finalAction = trim(strval($finalSnapshot['action_tag'] ?? ''));"),
    ("        $result['held_from'] = $heldFrom;\n        return $result;",
     "        $result['held_from'] = $heldFrom;\n        $result['gear_claims_dropped'] = $gearDropped;\n        return $result;"),
])

patch('processor/chat.php', "False gear claim dropped (item 41)", [
    ("            'stream_listener' => $speaker, // bug 95: replies go to whoever spoke\n",
     "            'stream_listener' => $speaker, // bug 95: replies go to whoever spoke\n"
     "            'player_message' => strval($message ?? ''), // item 41\n"),
    ("        $responseText = sanitizeForKenshi(trim(strval($streamResult['response_text'] ?? '')));\n",
     "        $responseText = sanitizeForKenshi(trim(strval($streamResult['response_text'] ?? '')));\n"
     "        if (function_exists('stobeDropFalseGearClaims')) {\n"
     "            // Item 41: a deferred/held-back reply still holds the sentence; the streamed one is already clean.\n"
     "            $gearFix = stobeDropFalseGearClaims($responseText, $npcData, strval($message ?? ''));\n"
     "            if (count($gearFix['dropped']) > 0) {\n"
     "                stobeLogWarn('False gear claim dropped (item 41)', ['npc'=>$targetNpc, 'dropped'=>$gearFix['dropped']]);\n"
     "                $responseText = $gearFix['text'];\n"
     "            }\n"
     "        }\n"),
])
