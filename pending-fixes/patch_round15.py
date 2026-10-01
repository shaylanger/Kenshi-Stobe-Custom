#!/usr/bin/env python3
"""Round 15 (server): bugs 34, 35, 36, 37, 38, 41, 42 from test-run-2026-09-30-r3.md.

  34  Payment confirmed after the chat reply: her side waited for her next line. After a voice
      hand-over, the chat request now ticks the deal itself (up to ~4 s) so the settle
      directive is queued in time for the same-turn send (bug 29's block).
  35  The underway-deal amount check replaced her whole reply when she echoed the player's NEW
      offer. Amounts the player just said are allowed, and only the sentences with a wrong
      amount are dropped (the progress line is used only if nothing is left).
  36  "Four hundred then. You take off your hat… Deal?" was not seen as an offer (a number but
      no "cats"). A number >= 10 together with "deal", or "<number> then / it is", counts.
  37  COUNTER/ACCEPT/PROPOSE with empty deal_terms was dropped silently. It's now remembered,
      and the next negotiation turn reminds her to restate it with terms (bug 30's note).
  38  "Shay | squadmate" in a non-member NPC's Nearby People list. "squadmate" now shows only
      when the viewing NPC is in the player's faction; otherwise "player's squad".
  41  The combat pay window ran in real time, so a game pause made the player "breach" the
      deal. Combat deals also get a game-time deadline, and both must pass (30 min real-time
      cap for when no game time is seen at all).
  42  A breach reaction (or refund/settle) attached to a chat reply carried only its actions;
      its instruction never reached the LLM, so she said "Cats received" while attacking.
      Pending directive instructions are now added to the prompt.
Usage: patch_round15.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new, count=1):
    p = root / rel
    s = p.read_text()
    assert s.count(old) == count, f"{rel}: anchor found {s.count(old)}x (already applied?): {old[:70]!r}"
    p.write_text(s.replace(old, new))


ENG = "lib/negotiation_engine.php"
PH1 = "lib/negotiation_phase1.php"
VOICE = "lib/negotiation_voice.php"
CHAT = "processor/chat.php"
LIFE = "lib/lifelike_npc.php"

# ---- 41: pause-safe combat pay window ------------------------------------------------------
patch(ENG,
      "const STOBE_NEG_PAY_WINDOW_SECONDS = 60;",
      "const STOBE_NEG_PAY_WINDOW_GAMETS = 1950;        // bug 41: ~60 s of game time at 1x (about 32.5 gamets/s)\n"
      "const STOBE_NEG_PAY_WINDOW_REAL_CAP = 1800;      // bug 41: no game time seen at all (paused/closed): give up after 30 min\n"
      "const STOBE_NEG_PAY_WINDOW_SECONDS = 60;")
patch(ENG,
      "        $deadlineGamets = $kind === 'social' ? max(0, $gamets) + STOBE_NEG_SOCIAL_DEADLINE_GAMETS : 0;",
      "        // Bug 41: combat windows also run on game time, so a pause doesn't count against the player.\n"
      "        $deadlineGamets = $kind === 'social' ? max(0, $gamets) + STOBE_NEG_SOCIAL_DEADLINE_GAMETS\n"
      "            : ($gamets > 0 ? $gamets + STOBE_NEG_PAY_WINDOW_GAMETS : 0);")
patch(ENG,
      """    $expired = ($deadline > 0 && $now > $deadline);
    if (!$expired && $gametsDeadline > 0) {
        $latest = stobeNegLatestGamets();
        $expired = $latest > 0 && $latest > $gametsDeadline;
    }""",
      """    $expired = ($deadline > 0 && $now > $deadline);
    if ($gametsDeadline > 0 && stobeNegDealKindIsHostile($deal)) {
        // Bug 41: both clocks must run out (real time AND game time); a paused game stops the window.
        if ($expired) {
            $latest = stobeNegLatestGamets();
            $expired = $latest > 0 ? $latest > $gametsDeadline : ($now > $deadline + STOBE_NEG_PAY_WINDOW_REAL_CAP);
        }
    } elseif (!$expired && $gametsDeadline > 0) {
        $latest = stobeNegLatestGamets();
        $expired = $latest > 0 && $latest > $gametsDeadline;
    }""")

# ---- 34: settle in the same chat request after a hand-over ---------------------------------
patch(VOICE,
      "        stobeLogInfo('Voice hand-over dispatched', ['player'=>$player, 'npc'=>$npc, 'actions'=>$actions, 'message'=>$message]);",
      "        stobeLogInfo('Voice hand-over dispatched', ['player'=>$player, 'npc'=>$npc, 'actions'=>$actions, 'message'=>$message]);\n"
      "        $GLOBALS['STOBE_VOICE_HANDOVER_NPC'] = $npc; // bug 34: settle her side before this request ends")
patch(ENG,
      "/** Take the oldest fresh directive for one of the nearby NPCs (bored path). */",
      """/**
 * Bug 34: the player just handed something over in this chat request. Tick the deal until the
 * payment is confirmed and her waiting terms are queued (or nothing waits), up to $maxMs.
 */
function stobeNegSettleAfterHandover(string $npc, int $maxMs = 4000): void {
    $until = microtime(true) + $maxMs / 1000;
    do {
        stobeNegTick($npc);
        $deal = $GLOBALS['db']->fetchOne(
            "SELECT term_state FROM stobe_social_contract WHERE LOWER(npc_name)=LOWER($1) AND status='AWAITING_PERFORMANCE' ORDER BY updated_at DESC LIMIT 1",
            [$npc]
        );
        if (!is_array($deal)) return;
        $waiting = false;
        foreach (stobeNegDecode($deal['term_state'] ?? []) as $t) {
            if (($t['by'] ?? '') === 'npc' && ($t['status'] ?? '') === 'WAITING_FOR_PLAYER') { $waiting = true; break; }
        }
        if (!$waiting) return;
        usleep(400000);
    } while (microtime(true) < $until);
    stobeLogInfo('Settle after hand-over: payment not confirmed in time; her side waits', ['npc'=>$npc]);
}

/** Bug 42: instructions of directives about to ride on this NPC's chat reply (same windows as the attach). */
function stobeNegPendingDirectiveNotes(string $npc): array {
    $rows = $GLOBALS['db']->fetchAll(
        "SELECT kind, payload FROM stobe_negotiation_directive WHERE consumed_unix=0 AND created_unix >= $1 - (CASE kind WHEN 'refund' THEN 600 ELSE 45 END) AND LOWER(npc_name)=LOWER($2) AND kind = ANY($3::text[]) ORDER BY id",
        [time(), $npc, '{settle,reissue_truce,betray,breach_react,refund}']
    );
    $notes = [];
    foreach (is_array($rows) ? $rows : [] as $row) {
        $text = trim(strval(stobeNegDecode($row['payload'] ?? [])['instruction'] ?? ''));
        if ($text !== '' && !in_array($text, $notes, true)) $notes[] = $text;
    }
    return $notes;
}

/** Take the oldest fresh directive for one of the nearby NPCs (bored path). */""")
patch(CHAT,
      """// Bug 29: payment verified during this request queued her side (or a refund) after the
// reply went out. Send those actions now instead of waiting for the next line.""",
      """// Bug 34: the player handed something over in this request; wait (briefly) for the game to
// confirm it so her side is queued now and goes out below.
if (!$narratorMode && !empty($GLOBALS['STOBE_VOICE_HANDOVER_NPC']) && function_exists('stobeNegSettleAfterHandover')) {
    try { stobeNegSettleAfterHandover($targetNpc); } catch (Throwable $settleError) {
        stobeLogWarn('Settle after hand-over failed', ['npc'=>$targetNpc, 'error'=>$settleError->getMessage()]);
    }
}
// Bug 29: payment verified during this request queued her side (or a refund) after the
// reply went out. Send those actions now instead of waiting for the next line.""")

# ---- 42: directive instructions reach the prompt -------------------------------------------
patch(CHAT,
      """    if ($voiceHandoverNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $voiceHandoverNote . ']'];
    }
}
$negotiationActive = !$narratorMode""",
      """    if ($voiceHandoverNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $voiceHandoverNote . ']'];
    }
}
// Bug 42: what she is about to do anyway (breach reaction, refund, hand-over) must shape her words.
if (!$narratorMode && function_exists('stobeNegPendingDirectiveNotes')) {
    try {
        foreach (stobeNegPendingDirectiveNotes($targetNpc) as $directiveNote) {
            $messages[] = ['role' => 'user', 'content' => '[' . $directiveNote
                . ' This is already happening in the game; your words must match it. Deal progress, not what '
                . $playerName . ' claims, decides what was paid.]'];
        }
    } catch (Throwable $directiveNoteError) {
        stobeLogWarn('Directive notes failed', ['npc'=>$targetNpc, 'error'=>$directiveNoteError->getMessage()]);
    }
}
$negotiationActive = !$narratorMode""")

# ---- 35: amount check keeps her reply ------------------------------------------------------
patch(PH1,
      """function stobeDealProgressAmountCheck(string $text, string $npc): ?array {""",
      """function stobeDealProgressAmountCheck(string $text, string $npc, string $playerMessage = ''): ?array {""")
patch(PH1,
      """    $allowed = stobeDealAllowedCatsAmounts($terms, $state, stobeDealNpcPurse($npc));
    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    if (count($wrong) === 0) return null;
    $line = stobeDealProgressLine($terms, $state);
    if ($line === '') return null;
    return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>$wrong, 'allowed'=>array_keys($allowed)];""",
      """    $allowed = stobeDealAllowedCatsAmounts($terms, $state, stobeDealNpcPurse($npc));
    // Bug 35: echoing the player's new offer is not a wrong amount.
    foreach (stobeDealSpokenCatsAmounts($playerMessage) as $said) $allowed[$said] = true;
    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    if (count($wrong) === 0) return null;
    // Drop only the sentences with a wrong amount; the progress line only if nothing is left.
    $kept = [];
    foreach (preg_split('/(?<=[.!?])\\s+/', trim($text)) ?: [] as $sentence) {
        $bad = array_intersect(stobeDealSpokenCatsAmounts($sentence), $wrong);
        if (count($bad) === 0 && trim($sentence) !== '') $kept[] = trim($sentence);
    }
    $line = count($kept) > 0 ? implode(' ', $kept) : stobeDealProgressLine($terms, $state);
    if ($line === '') return null;
    return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>$wrong, 'allowed'=>array_keys($allowed)];""")
patch(CHAT,
      "$amountCheck = stobeDealProgressAmountCheck($responseText, $targetNpc);",
      "$amountCheck = stobeDealProgressAmountCheck($responseText, $targetNpc, $message);")

# ---- 36: "<number> … deal?" is an offer ----------------------------------------------------
patch(ENG,
      """    // Asking for her price is an offer too (bug 28).""",
      """    // Bug 36: a price with "deal" ("Four hundred then... Deal?"), or "<number> then / it is".
    if (preg_match_all('/\\b(\\d[\\d,]*)\\b/', $message, $numMatches)) {
        $bigNumber = false;
        foreach ($numMatches[1] as $n) { if (intval(str_replace(',', '', $n)) >= 10) { $bigNumber = true; break; } }
        if ($bigNumber && preg_match("/\\bdeal\\b|\\b\\d[\\d,]*\\s*(then|it is|it'?s a deal|and we'?re square)\\b/", $message)) return true;
    }
    // Asking for her price is an offer too (bug 28).""")

# ---- 37: empty terms remembered ------------------------------------------------------------
patch(PH1,
      "    if (!is_array($terms)) return ['ok'=>false,'error'=>'invalid_terms_json'];",
      "    if (!is_array($terms)) return ['ok'=>false,'error'=>'invalid_terms_json','decision'=>$decision];")
patch(PH1,
      """function stobeDealRememberUnrecordedAgreement(string $npc, string $playerMessage, string $reply): void {
    setConfOpt('STOBE_NEG_UNRECORDED_' . strtolower($npc), json_encode(['offer'=>$playerMessage, 'reply'=>$reply, 'at'=>time()], JSON_UNESCAPED_UNICODE));""",
      """function stobeDealRememberUnrecordedAgreement(string $npc, string $playerMessage, string $reply, string $decision = 'ACCEPT'): void {
    setConfOpt('STOBE_NEG_UNRECORDED_' . strtolower($npc), json_encode(['offer'=>$playerMessage, 'reply'=>$reply, 'at'=>time(), 'decision'=>$decision], JSON_UNESCAPED_UNICODE));""")
patch(PH1,
      """    if (stobeDealOpenForNpc($npc) !== null) return '';
    return 'In your last reply you agreed in words""",
      """    if (stobeDealOpenForNpc($npc) !== null) return '';
    $decision = strtoupper(strval($row['decision'] ?? 'ACCEPT'));
    if (in_array($decision, ['COUNTER','PROPOSE'], true)) {
        // Bug 37: she made an offer but gave no deal_terms.
        return 'In your last reply you made ' . ($decision === 'COUNTER' ? 'a counter-offer' : 'an offer') . ' to ' . $player
            . ' (you said: "' . strval($row['reply'] ?? '') . '") but gave no deal_terms, so nothing was recorded. '
            . 'If it still stands and they have not accepted it yet, set deal_decision to ' . $decision . ' and list its terms in deal_terms now.';
    }
    return 'In your last reply you agreed in words""")
patch(CHAT,
      """                stobeLogWarn('Negotiation rejected by deterministic validation', [
                    'npc'=>$targetNpc, 'error'=>strval($dealResult['error'] ?? 'unknown')
                ]);""",
      """                stobeLogWarn('Negotiation rejected by deterministic validation', [
                    'npc'=>$targetNpc, 'error'=>strval($dealResult['error'] ?? 'unknown')
                ]);
                // Bug 37: an offer or agreement with no readable terms: remind her next turn.
                if (strval($dealResult['error'] ?? '') === 'invalid_terms_json'
                    && in_array(strval($dealResult['decision'] ?? ''), ['ACCEPT','COUNTER','PROPOSE'], true)
                    && function_exists('stobeDealRememberUnrecordedAgreement')) {
                    stobeDealRememberUnrecordedAgreement($targetNpc, $message, $responseText, strval($dealResult['decision']));
                }""")

# ---- 38: squadmate only from a squad member's point of view --------------------------------
patch(LIFE,
      """        if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($other)) {
            $bits[] = 'squadmate';
        }""",
      """        if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($other)) {
            // Bug 38: "squadmate" only when the viewer is in the player's squad too.
            $bits[] = npcIsInPlayerFaction($npcData) ? 'squadmate' : "player's squad";
        }""")

print("round 15 applied to", root)
