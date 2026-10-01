#!/usr/bin/env python3
"""Round 12: bugs 28-31 from run 2 (test-run-2026-09-30-r2.md).

  28  "Then name your price for …" didn't start negotiation, so her price wasn't recorded.
      Price questions (name your price, what's your price/counter, how much for/to, what
      would it take, what do you want for, make me an offer) now count as offers.
  29  Accept + pay in one line: the payment was verified during the request, but her side
      (settle directive) was queued after her reply went out, so it waited for the next
      line (the refund in the fight waited 4 min). Pending directives are now sent as
      actions at the end of the same chat request.
  30  She agreed in words ("Fine - coin first…") but deal_decision was NONE, so nothing
      was recorded. It's logged and remembered; on the next negotiation turn (within
      3 min) she gets one note: record it now as ACCEPT if she still agrees. The schema
      also says: agreeing to the terms as offered is ACCEPT, not COUNTER.
  31  "…then you take off your Black Rag Shirt" was recorded as GIVE_ITEM (hand to the
      player). If the player asked for an item she's wearing to be taken off and didn't
      ask for it to be handed over, her GIVE_ITEM of it becomes UNEQUIP_ITEM.

Usage: patch_round12.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


E = "lib/negotiation_engine.php"
P = "lib/negotiation_phase1.php"
C = "processor/chat.php"

# ---- 28 ------------------------------------------------------------------------------------
patch(E,
      """function stobeNegLooksLikeSocialOffer(string $message): bool {
    if (!stobeNegPhaseEnabled(6)) return false;
    $message = function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers(strtolower($message)) : $message;""",
      """function stobeNegLooksLikeSocialOffer(string $message): bool {
    if (!stobeNegPhaseEnabled(6)) return false;
    $message = function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers(strtolower($message)) : $message;
    // Asking for her price is an offer too (bug 28).
    if (preg_match("/\\b(name your price|what'?s your (price|counter|offer)|what is your (price|counter|offer)|your counter\\b|how much (for|to|would|do you want|you want)|what would (it|that) (take|cost)|what'?d (it|that) take|what do you want for|make me an offer|what would you take)/", strtolower($message))) {
        return true;
    }""")

# ---- 31 + 30 helpers (phase1) -----------------------------------------------------------
patch(P,
      """// ---- Bug 32: an NPC's own weapon ----------------------------------------------------""",
      r"""// ---- Bug 31: "take it off" is UNEQUIP, not a hand-over ----------------------------------

/** The player asked for something to be taken off, and not handed over. */
function stobeDealPlayerAsksTakeOffOnly(string $playerMessage): bool {
    $m = strtolower($playerMessage);
    if (!preg_match("/\b(take (it|them|that|those|your [a-z' -]{1,40}) off|take off|remove|unequip|strip)\b/", $m)) return false;
    return !preg_match("/\b(hand|give|pass|toss|throw)\b[^.?!]{0,40}\b(me|over)\b|\bto me\b|\bmine\b|\bi get\b/", $m);
}

/** Her GIVE_ITEM of something she's wearing becomes UNEQUIP_ITEM when the player only asked her to take it off. */
function stobeDealFixTakeOffTerms(array $terms, array|false $npcData, string $playerMessage): array {
    if (!is_array($npcData) || trim($playerMessage) === '' || !stobeDealPlayerAsksTakeOffOnly($playerMessage)) return $terms;
    if (!function_exists('stobeNegInventoryDisplayNames')) return $terms;
    $worn = stobeNegInventoryDisplayNames(strval($npcData['equipment'] ?? ''));
    $said = strtolower($playerMessage);
    foreach ($terms as $i => $t) {
        if (!is_array($t) || ($t['by'] ?? '') !== 'npc' || strtoupper(strval($t['kind'] ?? '')) !== 'GIVE_ITEM') continue;
        $item = strtolower(trim(preg_replace('/\s*\[[^\]]*\]|\s*\([^)]*\)/', '', strval($t['item'] ?? '')) ?? ''));
        if ($item === '') continue;
        $isWorn = false;
        foreach ($worn as $lower => $display) {
            if ($item === $lower || str_contains($lower, $item) || str_contains($item, $lower)) { $isWorn = true; break; }
        }
        // It must be the item the player named ("your Black Rag Shirt", "the shirt").
        $named = false;
        foreach (preg_split('/\s+/', $item) ?: [] as $word) {
            if (strlen($word) >= 4 && str_contains($said, $word)) { $named = true; break; }
        }
        if (!$isWorn || !$named) continue;
        $terms[$i]['kind'] = 'UNEQUIP_ITEM';
        unset($terms[$i]['to']);
        stobeDealLog('info', 'Negotiation term fixed: take-off request recorded as UNEQUIP_ITEM, not GIVE_ITEM', ['item'=>$t['item'] ?? '']);
    }
    return $terms;
}

// ---- Bug 30: agreed in words, nothing recorded -------------------------------------------

/** Her line agrees to the offer on the table. */
function stobeDealSpeechAgrees(string $text): bool {
    $t = strtolower($text);
    if (preg_match("/\b(no deal|not a deal|that'?s not a deal|not happening|forget it|no way|not for|stays on|stays where|i refuse)\b/", $t)) return false;
    return preg_match("/\b(fine|deal|agreed|done|you'?ve got (a|yourself a) deal|it'?s a deal|you'?re on|sounds fair|alright,? then|all right,? then)\b/", $t) === 1;
}

function stobeDealRememberUnrecordedAgreement(string $npc, string $playerMessage, string $reply): void {
    setConfOpt('STOBE_NEG_UNRECORDED_' . strtolower($npc), json_encode(['offer'=>$playerMessage, 'reply'=>$reply, 'at'=>time()], JSON_UNESCAPED_UNICODE));
    stobeDealLog('warn', 'Negotiation: NPC agreed in words but recorded no deal (reminder queued for next turn)', ['npc'=>$npc, 'offer'=>$playerMessage, 'reply'=>$reply]);
}

/** One-shot note for the next negotiation turn, or ''. */
function stobeDealTakeUnrecordedAgreement(string $npc, string $player): string {
    $key = 'STOBE_NEG_UNRECORDED_' . strtolower($npc);
    $raw = getConfOpt($key, '');
    if ($raw === '') return '';
    setConfOpt($key, '');
    $row = json_decode($raw, true);
    if (!is_array($row) || time() - intval($row['at'] ?? 0) > 180) return '';
    if (stobeDealOpenForNpc($npc) !== null) return '';
    return 'In your last reply you agreed in words to this offer from ' . $player . ': "' . strval($row['offer'] ?? '')
        . '" (you said: "' . strval($row['reply'] ?? '') . '"). It was not recorded as a deal. If you still agree, '
        . 'set deal_decision to ACCEPT and list its terms in deal_terms now.';
}

// ---- Bug 32: an NPC's own weapon ----------------------------------------------------""")

patch(P,
      """    $terms = stobeDealPromoteClothingPromises($terms, $npcData);""",
      """    $terms = stobeDealPromoteClothingPromises($terms, $npcData);
    $terms = stobeDealFixTakeOffTerms($terms, $npcData, $playerMessage);""")

# schema: UNEQUIP vs GIVE, ACCEPT vs COUNTER
patch(P,
      """Any number of Cats you say out loud must equal an amount (or the total) in deal_terms.'""",
      """Any number of Cats you say out loud must equal an amount (or the total) in deal_terms. Taking something off and keeping it is UNEQUIP_ITEM; use GIVE_ITEM only when you hand it to the player.'""")
patch(P,
      """        'description'=>'Your decision about an actual offer in this conversation (PROPOSE when you make the first offer); NONE if no negotiation.'""",
      """        'description'=>'Your decision about an actual offer in this conversation (PROPOSE when you make the first offer); NONE if no negotiation. If your words agree to the offer as it stands (even with "coin first"), this is ACCEPT, not COUNTER or NONE; COUNTER only when you change the terms.'""")

# ---- 30: chat.php remember + remind ------------------------------------------------------
patch(C,
      """    if ($acceptNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $acceptNote . ']'];
    }
}""",
      """    if ($acceptNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $acceptNote . ']'];
    }
}
// Bug 30: last turn she agreed in words but no deal was recorded: remind her once.
if ($negotiationActive && function_exists('stobeDealTakeUnrecordedAgreement')) {
    $unrecordedNote = stobeDealTakeUnrecordedAgreement($targetNpc, $playerName);
    if ($unrecordedNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $unrecordedNote . ']'];
    }
}""")

patch(C,
      """            if (!empty($dealResult['ok']) && empty($dealResult['blocked_by_active'])
                && function_exists('stobeDealSpeechAmountCheck')) {""",
      """            if (!empty($dealResult['ok']) && strval($dealResult['decision'] ?? '') === 'NONE'
                && empty($dealResult['blocked_by_active']) && empty($dealResult['duplicate_of'])
                && $negotiationOpenDeal === null && function_exists('stobeDealSpeechAgrees')
                && stobeDealSpeechAgrees($responseText) && stobeNegLooksLikeSocialOffer($message)) {
                // Bug 30: she agreed in words, but nothing was recorded.
                stobeDealRememberUnrecordedAgreement($targetNpc, $message, $responseText);
            }
            if (!empty($dealResult['ok']) && empty($dealResult['blocked_by_active'])
                && function_exists('stobeDealSpeechAmountCheck')) {""")

# ---- 29: send directives queued during this request ---------------------------------------
patch(C,
      """        stobeNegVoiceHandover($targetNpc, $npcData, $playerName, $message, intval($gamets));
    }
}""",
      """        stobeNegVoiceHandover($targetNpc, $npcData, $playerName, $message, intval($gamets));
    }
}
// Bug 29: payment verified during this request queued her side (or a refund) after the
// reply went out. Send those actions now instead of waiting for the next line.
if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {
    try {
        $lateDirectiveActions = stobeNegAttachPendingForChat($targetNpc, []);
        if (count($lateDirectiveActions) > 0) {
            streamResponse($targetNpc, 'ScriptQueue', '', $npcData, $lateDirectiveActions, 'chat', $replyTarget, $gamets);
            stobeLogInfo('Negotiation directive sent in the same turn (after the reply)', ['npc'=>$targetNpc, 'actions'=>$lateDirectiveActions]);
        }
    } catch (Throwable $lateDirectiveError) {
        stobeLogWarn('Late negotiation directive send failed', ['npc'=>$targetNpc, 'error'=>$lateDirectiveError->getMessage()]);
    }
}""")

print("patch_round12: applied")
