#!/usr/bin/env python3
"""Round 10b: bug 26 while a deal is underway (Shay's option 1).

Once a deal is agreed, her reply streams sentence by sentence, so round 10's amount check
came too late. Now, during an underway deal, the stream holds everything from the first
sentence that mentions money (Cats amounts, owe, paid, the rest). The held part is
checked against the ledger and then spoken. Lines without money talk stream as before.

Also, plain talk about an underway deal (deal_decision NONE, or re-accepting the open
deal) is checked against the deal's terms and paid/owed figures. A wrong amount replaces
the held part with the real figures ("You've paid me 350 of the 500 Cats; you still owe
me 150.").

Usage: patch_round10b.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


# ---- negotiation_phase1.php: helpers -----------------------------------------------------
patch("lib/negotiation_phase1.php",
      """function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult): ?array {""",
      r"""/** A sentence talks about money (used to hold the stream back during an underway deal). */
function stobeDealSpeechMentionsMoney(string $text): bool {
    if (count(stobeDealSpokenCatsAmounts($text)) > 0) return true;
    return preg_match("/\b(cats?|owe[sd]?|owing|paid|the rest|how much)\b/i", $text) === 1;
}

/** NPC's purse, or -1 when unknown. */
function stobeDealNpcPurse(string $npc): int {
    try {
        if (function_exists('stobeNegMoney') && function_exists('stobeNegNpcRow')) {
            $money = stobeNegMoney(stobeNegNpcRow($npc));
            if (!empty($money['known'])) return intval($money['value']);
        }
    } catch (Throwable $e) {
    }
    return -1;
}

/** "You've paid me 350 of the 500 Cats; you still owe me 150." from the recorded deal. */
function stobeDealProgressLine(array $terms, array $state): string {
    if (count($state) === 0) $state = $terms; // nothing observed yet: all still owed
    $m = stobeDealMoneyTotals($state);
    $out = [];
    $p = $m['player'];
    if ($p['total'] > 0) {
        $out[] = $p['owed'] <= 0 ? "You've paid me all " . $p['total'] . ' Cats.'
            : ($p['paid'] > 0 ? "You've paid me " . $p['paid'] . ' of the ' . $p['total'] . ' Cats; you still owe me ' . $p['owed'] . '.'
                : 'You still owe me ' . $p['owed'] . ' Cats.');
    }
    $n = $m['npc'];
    if ($n['total'] > 0) {
        $out[] = $n['owed'] <= 0 ? "I've paid you all " . $n['total'] . ' Cats.'
            : ($n['paid'] > 0 ? "I've paid you " . $n['paid'] . ' of the ' . $n['total'] . ' Cats; I still owe you ' . $n['owed'] . '.'
                : 'I still owe you ' . $n['owed'] . ' Cats.');
    }
    return implode(' ', $out);
}

/**
 * Bug 26 for a deal that's underway: amounts she says about it must be its recorded
 * amounts or paid/owed figures. Returns null when they are, else the corrected line.
 */
function stobeDealProgressAmountCheck(string $text, string $npc): ?array {
    $spoken = stobeDealSpokenCatsAmounts($text);
    if (count($spoken) === 0) return null;
    $open = stobeDealOpenForNpc($npc);
    if ($open === null) return null;
    $terms = json_decode(strval($open['terms'] ?? '[]'), true);
    $terms = is_array($terms) ? array_values(array_filter($terms, 'is_array')) : [];
    $state = function_exists('stobeNegDecode') ? stobeNegDecode($open['term_state'] ?? []) : [];
    $state = is_array($state) ? $state : [];
    $allowed = stobeDealAllowedCatsAmounts($terms, $state, stobeDealNpcPurse($npc));
    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    if (count($wrong) === 0) return null;
    $line = stobeDealProgressLine($terms, $state);
    if ($line === '') return null;
    return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>$wrong, 'allowed'=>array_keys($allowed)];
}

function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult): ?array {""")

patch("lib/negotiation_phase1.php",
      """    $purse = -1;
    try {
        if (function_exists('stobeNegMoney') && function_exists('stobeNegNpcRow')) {
            $money = stobeNegMoney(stobeNegNpcRow($npc));
            if (!empty($money['known'])) $purse = intval($money['value']);
        }
    } catch (Throwable $e) {
    }
    $allowed = stobeDealAllowedCatsAmounts($terms, is_array($state) ? $state : [], $purse);""",
      """    $allowed = stobeDealAllowedCatsAmounts($terms, is_array($state) ? $state : [], stobeDealNpcPurse($npc));""")

# ---- chat_helper_functions.php: hold the stream from the first money sentence -----------
H = "lib/chat_helper_functions.php"
patch(H,
      """    unset($streamMeta['suppress_tts'], $streamMeta['defer_structured_stream']);""",
      """    unset($streamMeta['suppress_tts'], $streamMeta['defer_structured_stream'], $streamMeta['hold_stream_on_money']);
    // Underway deal: speak normally, but hold everything from the first sentence about money.
    $holdOnMoney = !empty($meta['hold_stream_on_money']) && function_exists('stobeDealSpeechMentionsMoney');""")

patch(H,
      """        $rawResponse = '';
        $chunksEmitted = 0;
        $messageStreamBuffer = '';""",
      """        $rawResponse = '';
        $chunksEmitted = 0;
        $heldBack = false;
        $spokenText = '';
        $heldFrom = '';
        $messageStreamBuffer = '';""")

patch(H,
      """        $emitStructuredDialogue = function (string $deltaText = '', bool $flushRemainder = false) use (
            &$messageStreamBuffer,
            &$chunksEmitted,""",
      """        $emitStructuredDialogue = function (string $deltaText = '', bool $flushRemainder = false) use (
            &$messageStreamBuffer,
            &$chunksEmitted,
            &$heldBack,
            &$spokenText,
            &$heldFrom,
            $holdOnMoney,""")

patch(H,
      """                    if ($sentenceChunk === '') {
                        continue;
                    }
                    if ($ttsQueue) {""",
      """                    if ($sentenceChunk === '') {
                        continue;
                    }
                    if ($holdOnMoney && !$heldBack && stobeDealSpeechMentionsMoney($sentenceChunk)) {
                        $heldBack = true;
                        $heldFrom = $sentenceChunk;
                    }
                    if ($heldBack) {
                        continue;
                    }
                    $spokenText .= ($spokenText === '' ? '' : ' ') . $sentenceChunk;
                    if ($ttsQueue) {""")

patch(H,
      """                if ($remainingChunk === '') {
                    continue;
                }
                if ($ttsQueue) {""",
      """                if ($remainingChunk === '') {
                    continue;
                }
                if ($holdOnMoney && !$heldBack && stobeDealSpeechMentionsMoney($remainingChunk)) {
                    $heldBack = true;
                    $heldFrom = $remainingChunk;
                }
                if ($heldBack) {
                    continue;
                }
                $spokenText .= ($spokenText === '' ? '' : ' ') . $remainingChunk;
                if ($ttsQueue) {""")

patch(H,
      """        $result['chunks_emitted'] = $chunksEmitted;
        return $result;""",
      """        $result['chunks_emitted'] = $chunksEmitted;
        $result['held_back'] = $heldBack;
        $result['spoken_text'] = $spokenText;
        $result['held_from'] = $heldFrom;
        return $result;""")

# ---- processor/chat.php ------------------------------------------------------------------
C = "processor/chat.php"
patch(C,
      """$alreadyStreamed = false;""",
      """$alreadyStreamed = false;
$streamHeldBack = false;     // round 10b: money talk held back mid-reply
$streamSpokenPrefix = '';    // sentences already spoken before the hold
$streamHeldFrom = '';        // first held sentence
$streamSpeakOverride = null; // corrected held part (amount check)""")

patch(C,
      """            'defer_structured_stream' => $negotiationDefer,""",
      """            'defer_structured_stream' => $negotiationDefer,
            'hold_stream_on_money' => $negotiationActive && !$negotiationDefer,""")

patch(C,
      """        $alreadyStreamed = intval($streamResult['chunks_emitted'] ?? 0) > 0;""",
      """        $alreadyStreamed = intval($streamResult['chunks_emitted'] ?? 0) > 0;
        if (!empty($streamResult['held_back'])) {
            // Part of the reply is still unspoken: check it, then speak it at the end.
            $streamHeldBack = true;
            $streamSpokenPrefix = trim(strval($streamResult['spoken_text'] ?? ''));
            $streamHeldFrom = trim(strval($streamResult['held_from'] ?? ''));
            $alreadyStreamed = false;
        }""")

patch(C,
      """                try {
                    $amountCheck = stobeDealSpeechAmountCheck($responseText, $targetNpc, $dealResult);
                } catch (Throwable $amountError) {
                    $amountCheck = null;
                }""",
      """                try {
                    $underwayStatus = strval($negotiationOpenDeal['status'] ?? '');
                    if (in_array($underwayStatus, ['ACCEPTED','AWAITING_PERFORMANCE'], true)
                        && (strval($dealResult['decision'] ?? '') === 'NONE' || !empty($dealResult['already_active']))
                        && function_exists('stobeDealProgressAmountCheck')) {
                        // Talk about the deal that's underway: amounts must be its paid/owed figures.
                        $amountCheck = stobeDealProgressAmountCheck($responseText, $targetNpc);
                    } else {
                        $amountCheck = stobeDealSpeechAmountCheck($responseText, $targetNpc, $dealResult);
                    }
                } catch (Throwable $amountError) {
                    $amountCheck = null;
                }""")

patch(C,
      """                    if (!$alreadyStreamed) $responseText = $amountCheck['line'];""",
      """                    if (!$alreadyStreamed) {
                        $responseText = trim($streamSpokenPrefix . ' ' . $amountCheck['line']);
                        if ($streamSpokenPrefix !== '') $streamSpeakOverride = $amountCheck['line'];
                    }""")

patch(C,
      """} else {
    stobeStreamDialogueResponse(
        $targetNpc,
        $npcData,
        $responseText,
        $responseActions,""",
      """} else {
    $textToSpeak = $responseText;
    if ($streamHeldBack && $streamSpokenPrefix !== '') {
        // The start was already spoken; speak only the held part.
        if ($streamSpeakOverride !== null) {
            $textToSpeak = $streamSpeakOverride;
        } elseif ($streamHeldFrom !== '' && ($heldPos = strpos($responseText, $streamHeldFrom)) !== false) {
            $textToSpeak = substr($responseText, $heldPos);
        } else {
            stobeLogWarn('Held-back reply: held part not found, speaking the full line', ['npc'=>$targetNpc, 'text'=>$responseText]);
        }
    }
    stobeStreamDialogueResponse(
        $targetNpc,
        $npcData,
        $textToSpeak,
        $responseActions,""")

print("patch_round10b: applied")
