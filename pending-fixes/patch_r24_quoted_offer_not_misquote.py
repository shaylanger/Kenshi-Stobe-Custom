#!/usr/bin/env python3
"""Plan item 51: an NPC repeating the player's offer counts as a misquote.

Run 12, 4 of 5 "Negotiation speech amounts differ ... rewritten" warnings were her
quoting Shay's number before naming her own: "Sixty cats for the black rag? ...
Tell you what - eighty" (terms 80) was replaced by the plain line "My terms: you pay
me 80 Cats and I give you the Black Rag Shirt after. Deal?".
Now amounts the player said in this line are allowed when her reply also states a
recorded amount. If she never says the recorded amount ("Two hundred. For a whole
gang?" with terms 1000) the line is still rewritten.

Usage: patch_r24_quoted_offer_not_misquote.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, old, new, marker):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n}x: {old[:70]!r}'
    f.write_text(s.replace(old, new), encoding='utf-8')
    print('patched', rel)

patch('lib/negotiation_phase1.php',
      "function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult): ?array {",
      "function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult, string $playerMessage = ''): ?array {",
      "array $dealResult, string $playerMessage = ''): ?array {")
patch('lib/negotiation_phase1.php',
      """    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    $capped = is_array($dealResult['capped'] ?? null) ? $dealResult['capped'] : null;""",
      r"""    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    if (count($wrong) > 0 && trim($playerMessage) !== '') {
        // Item 51: she repeats the player's offer, then names a recorded amount
        // (often bare: "Tell you what - eighty").
        $bare = function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers($text) : $text;
        $namesHers = false;
        if (preg_match_all('/\b(\d+)\b/', preg_replace('/(\d),(?=\d{3}\b)/', '$1', $bare) ?? $bare, $bm)) {
            foreach ($bm[1] as $n) if (isset($allowed[intval($n)])) { $namesHers = true; break; }
        }
        if ($namesHers) {
            $theirs = array_flip(stobeDealSpokenCatsAmounts($playerMessage));
            $wrong = array_values(array_filter($wrong, static fn($n) => !isset($theirs[$n])));
        }
    }
    $capped = is_array($dealResult['capped'] ?? null) ? $dealResult['capped'] : null;""",
      "Item 51: she repeats the player's offer")
patch('processor/chat.php',
      "                        $amountCheck = stobeDealSpeechAmountCheck($responseText, $targetNpc, $dealResult);",
      "                        $amountCheck = stobeDealSpeechAmountCheck($responseText, $targetNpc, $dealResult, $message); // item 51",
      "$dealResult, $message); // item 51")

t = root / 'tests/negotiation_engine_regression.php'
s = t.read_text(encoding='utf-8')
if 'item 51:' not in s:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    assert s.count(anchor) == 1
    s = s.replace(anchor, r'''// ---------------------------------------------------------------- 12n. item 51: quoting the player's offer is not a misquote
$r51 = ['decision'=>'COUNTER', 'terms'=>[['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>80], ['kind'=>'GIVE_ITEM','by'=>'npc','to'=>'player','item'=>'Black Rag Shirt']]];
check('item 51: "Sixty cats...? Tell you what - eighty" is left alone',
    stobeDealSpeechAmountCheck("Sixty cats for the black rag? That's generous. Tell you what - eighty, and I'll hand it over.", 'NegTest51', $r51, "I'll give you 60 cats for that rag shirt. Deal?") === null);
check('item 51: without the player line it is still flagged',
    stobeDealSpeechAmountCheck("Sixty cats for the black rag? Tell you what - eighty.", 'NegTest51', $r51) !== null);
check('item 51: only the player\'s number, never hers: still rewritten',
    stobeDealSpeechAmountCheck("Sixty cats? For this? Insult money.", 'NegTest51', $r51, "I'll give you 60 cats for that rag shirt.") !== null);

''' + anchor)
    t.write_text(s, encoding='utf-8'); print('patched tests')
