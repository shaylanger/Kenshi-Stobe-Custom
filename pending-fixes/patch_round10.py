#!/usr/bin/env python3
"""Round 10: bug 26 (speech and recorded terms disagree; J2 quoted wrong totals) and the
server half of bug 27 (an NPC who calls for help lets her faction-mates join).

  26a  The deal-progress prompt line gets money totals: "agreed to pay X in total; paid Y;
       still owes Z" for each side, marked as the only numbers to use.
  26b  After capture on ACCEPT/COUNTER/PROPOSE, Cats amounts in her speech (digits and word
       numbers, near cats/now/after/total/pay/owe) that match no recorded amount, sum, paid
       or owed figure (or her purse) replace her line with a plain statement of the recorded
       terms, and a warning is logged. Lines that have already streamed are only logged.
  26c  deal_terms schema: numbers you say must equal the amounts in deal_terms.
  27   processor/chat.php "keeps it one-on-one": when her reply calls for help (same regex as
       stobeNegRegisterPersonalFight, now stobeNegCalledForHelp), ATTACK@<player> becomes
       ATTACK@<player>@help so Stobe.dll round 9 doesn't stand her faction-mates down.

Usage: patch_round10.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


# ---- 27: shared help regex --------------------------------------------------------------
patch("lib/negotiation_engine.php",
      """function stobeNegRegisterPersonalFight(string $npc, array $npcData, string $replyText): void {
    if (!stobeNegPersonalFightsEnabled()) return;
    if (preg_match("/\\b(help me|get (him|her|them)|guards?|boys|lads|friends|everyone|all of you|grab (him|her|them))\\b/i", $replyText)) {""",
      """/** The NPC's line calls her friends into the fight (J3: then they may join). */
function stobeNegCalledForHelp(string $replyText): bool {
    return preg_match("/\\b(help me|get (him|her|them)|guards?|boys|lads|friends|everyone|all of you|grab (him|her|them))\\b/i", $replyText) === 1;
}

function stobeNegRegisterPersonalFight(string $npc, array $npcData, string $replyText): void {
    if (!stobeNegPersonalFightsEnabled()) return;
    if (stobeNegCalledForHelp($replyText)) {""")

patch("processor/chat.php",
      """    foreach ($responseActions as $responseAction) {
        if (preg_match('/^ATTACK@(.+)$/i', strval($responseAction), $attackMatch)
            && strcasecmp(normalizeParticipantNameToken($attackMatch[1]), $playerName) === 0) {
            try { stobeNegRegisterPersonalFight($targetNpc, $npcData, strval($responseText ?? '')); } catch (Throwable $e) {}
            break;
        }
    }""",
      """    foreach ($responseActions as $actionIndex => $responseAction) {
        if (preg_match('/^ATTACK@(.+)$/i', strval($responseAction), $attackMatch)
            && strcasecmp(normalizeParticipantNameToken($attackMatch[1]), $playerName) === 0) {
            try { stobeNegRegisterPersonalFight($targetNpc, $npcData, strval($responseText ?? '')); } catch (Throwable $e) {}
            // She called for help: tell the DLL not to stand her faction-mates down.
            if (function_exists('stobeNegCalledForHelp') && stobeNegCalledForHelp(strval($responseText ?? ''))) {
                $responseActions[$actionIndex] = 'ATTACK@' . $attackMatch[1] . '@help';
            }
            break;
        }
    }""")

# ---- 26a: money totals in the deal-progress line ----------------------------------------
patch("lib/negotiation_engine.php",
      """            $lines[] = 'Deal progress (observed, authoritative): ' . implode('; ', $parts) . '.';
        }""",
      """            $lines[] = 'Deal progress (observed, authoritative): ' . implode('; ', $parts) . '.';
            if (function_exists('stobeDealMoneyTotalsLine')) {
                $moneyLine = stobeDealMoneyTotalsLine($state, $player);
                if ($moneyLine !== '') $lines[] = $moneyLine;
            }
        }""")

# ---- 26c: schema -------------------------------------------------------------------------
patch("lib/negotiation_phase1.php",
      """Never list a term that is physically impossible or invent an item.'""",
      """Never list a term that is physically impossible or invent an item. Any number of Cats you say out loud must equal an amount (or the total) in deal_terms.'""")

# ---- 26b: helpers ------------------------------------------------------------------------
patch("lib/negotiation_phase1.php",
      """function stobeDealSpeechClaimsCeasefire(string $text): bool {""",
      r"""/** Cats per side from a deal's term_state: total agreed, paid so far, still owed. */
function stobeDealMoneyTotals(array $state): array {
    $out = ['player'=>['total'=>0,'paid'=>0,'owed'=>0], 'npc'=>['total'=>0,'paid'=>0,'owed'=>0]];
    foreach ($state as $t) {
        if (!is_array($t) || strtoupper(strval($t['kind'] ?? '')) !== 'GIVE_CATS') continue;
        $by = ($t['by'] ?? '') === 'npc' ? 'npc' : 'player';
        $amount = max(0, intval($t['amount'] ?? 0));
        $status = strval($t['status'] ?? '');
        if (in_array($status, ['IMPOSSIBLE','UNMET','BETRAYED'], true)) continue;
        $paid = $status === 'VERIFIED' ? $amount : min($amount, max(0, intval($t['paid_so_far'] ?? 0)));
        $out[$by]['total'] += $amount;
        $out[$by]['paid'] += $paid;
        $out[$by]['owed'] += $amount - $paid;
    }
    return $out;
}

/** Prompt line: "Money (exact): Shay agreed to pay 500 Cats in total; paid 200; still owes 300." */
function stobeDealMoneyTotalsLine(array $state, string $player): string {
    $m = stobeDealMoneyTotals($state);
    $parts = [];
    if ($m['player']['total'] > 0) {
        $parts[] = $player . ' agreed to pay ' . $m['player']['total'] . ' Cats in total; paid ' . $m['player']['paid']
            . '; still owes ' . $m['player']['owed'];
    }
    if ($m['npc']['total'] > 0) {
        $parts[] = 'you agreed to pay ' . $m['npc']['total'] . ' Cats in total; paid ' . $m['npc']['paid']
            . '; still owe ' . $m['npc']['owed'];
    }
    if (count($parts) === 0) return '';
    return 'Money (exact; use only these numbers when you talk about amounts): ' . implode('. ', $parts) . '.';
}

/** Cats amounts the NPC says out loud (digits or words, next to cats/now/after/total/pay/owe). */
function stobeDealSpokenCatsAmounts(string $text): array {
    if (function_exists('stobeNegWordsToNumbers')) $text = stobeNegWordsToNumbers($text);
    $text = preg_replace('/(\d),(?=\d{3}\b)/', '$1', $text) ?? $text;
    $found = [];
    $patterns = [
        '/\b(\d+)\s+(?:more\s+|extra\s+)?cats?\b/i',
        '/\b(\d+)\s+(?:now|up\s*front|after(?:wards)?|later|in\s+total|total)\b/i',
        '/\b(?:total(?:\s+of)?|now|after(?:wards)?|up\s*front|later|pay(?:s|ing)?|paid|owes?|owed|another|rest(?:\s+of)?)\s+(?:(?:is|of|me|you|the|just|only|another|still)\s+){0,2}(\d+)\b/i',
    ];
    foreach ($patterns as $pattern) {
        if (preg_match_all($pattern, $text, $m)) {
            foreach ($m[1] as $n) {
                $n = intval($n);
                if ($n > 1) $found[$n] = true;
            }
        }
    }
    return array_keys($found);
}

/** Every Cats figure the recorded deal supports: each amount, sums per side and per timing, paid and owed. */
function stobeDealAllowedCatsAmounts(array $terms, array $state = [], int $purse = -1): array {
    $allowed = [];
    $sums = [];
    foreach ($terms as $t) {
        if (!is_array($t) || strtoupper(strval($t['kind'] ?? '')) !== 'GIVE_CATS') continue;
        $a = max(0, intval($t['amount'] ?? 0));
        $by = ($t['by'] ?? '') === 'npc' ? 'npc' : 'player';
        $when = strval($t['when'] ?? '') === 'after_player' ? 'after' : 'now';
        $allowed[$a] = true;
        $sums[$by] = ($sums[$by] ?? 0) + $a;
        $sums[$by . $when] = ($sums[$by . $when] ?? 0) + $a;
    }
    foreach ($sums as $s) $allowed[$s] = true;
    foreach ($state as $t) {
        if (!is_array($t) || strtoupper(strval($t['kind'] ?? '')) !== 'GIVE_CATS') continue;
        $a = max(0, intval($t['amount'] ?? 0));
        $p = max(0, intval($t['paid_so_far'] ?? 0));
        $allowed[$a] = true;
        $allowed[$p] = true;
        $allowed[max(0, $a - $p)] = true;
    }
    if (count($state) > 0) {
        foreach (stobeDealMoneyTotals($state) as $side) {
            foreach ($side as $v) $allowed[$v] = true;
        }
    }
    if ($purse >= 0) $allowed[$purse] = true;
    return $allowed;
}

/** One recorded term, from the NPC's side: "you pay me 300 Cats now", "I stop fighting". */
function stobeDealTermPhrase(array $t): string {
    $npcSide = ($t['by'] ?? '') === 'npc';
    $who = $npcSide ? 'I' : 'you';
    $kind = strtoupper(strval($t['kind'] ?? ''));
    $item = trim(preg_replace('/\s*\[[^\]]*\]/', '', strval($t['item'] ?? '')) ?? '');
    $qty = intval($t['quantity'] ?? 0);
    $thing = $item === '' ? 'it' : ($qty > 1 ? $qty . ' ' . $item : 'the ' . $item);
    $when = strval($t['when'] ?? '');
    $whenText = $when === 'now' ? ' now' : ($when !== '' ? ' after' : '');
    switch ($kind) {
        case 'GIVE_CATS':
            return $who . ($npcSide ? ' pay you ' : ' pay me ') . intval($t['amount'] ?? 0) . ' Cats' . $whenText;
        case 'GIVE_ITEM':
            return $who . ($npcSide ? ' give you ' : ' give me ') . $thing . $whenText;
        case 'RETURN_ITEM':
            return $who . ' return ' . $thing . $whenText;
        case 'UNEQUIP_ITEM':
            return $who . ' take off ' . $thing;
        case 'EQUIP_ITEM':
            return $who . ' put on ' . $thing;
        case 'STOP_ATTACK':
            return $who . ' stop fighting';
        case 'FIRST_AID':
            return $npcSide ? 'I patch you up' : 'you patch me up';
        case 'PROMISE':
            $text = trim(strval($t['text'] ?? ($t['subject'] ?? '')));
            return $who . ' promise' . ($text !== '' ? ' to ' . preg_replace('/^to\s+/i', '', $text) : '');
    }
    return $who . ' ' . strtolower(str_replace('_', ' ', $kind)) . ($item !== '' ? ' ' . $thing : '');
}

/** Plain statement of the recorded terms, used when her words quote different amounts. */
function stobeDealPlainTermsLine(array $terms, string $decision): string {
    $parts = [];
    // Her ceasefire goes last: "you pay me 300 Cats now and I stop fighting".
    usort($terms, static fn($a, $b) => (strtoupper(strval($a['kind'] ?? '')) === 'STOP_ATTACK') <=> (strtoupper(strval($b['kind'] ?? '')) === 'STOP_ATTACK'));
    foreach ($terms as $t) {
        if (is_array($t) && isset($t['kind'])) $parts[] = stobeDealTermPhrase($t);
    }
    if (count($parts) === 0) return '';
    $last = array_pop($parts);
    $body = count($parts) > 0 ? implode(', ', $parts) . ' and ' . $last : $last;
    return match ($decision) {
        'ACCEPT' => 'Deal: ' . $body . '.',
        'PROPOSE' => "Here's my offer: " . $body . '. Deal?',
        default => 'My terms: ' . $body . '. Deal?',
    };
}

/**
 * Bug 26: amounts in her speech must match the recorded deal. Returns null when they do
 * (or nothing is said about Cats), else ['line'=>plain terms, 'spoken'=>[...]].
 */
function stobeDealSpeechAmountCheck(string $text, string $npc, array $dealResult): ?array {
    $decision = strtoupper(strval($dealResult['decision'] ?? ''));
    if (!in_array($decision, ['ACCEPT','COUNTER','PROPOSE'], true)) return null;
    $terms = is_array($dealResult['terms'] ?? null) ? $dealResult['terms'] : [];
    if (count($terms) === 0) return null;
    $spoken = stobeDealSpokenCatsAmounts($text);
    if (count($spoken) === 0) return null;
    $state = [];
    try {
        $open = stobeDealOpenForNpc($npc);
        if ($open !== null && function_exists('stobeNegDecode')) $state = stobeNegDecode($open['term_state'] ?? []);
    } catch (Throwable $e) {
        $state = [];
    }
    $purse = -1;
    try {
        if (function_exists('stobeNegMoney') && function_exists('stobeNegNpcRow')) {
            $money = stobeNegMoney(stobeNegNpcRow($npc));
            if (!empty($money['known'])) $purse = intval($money['value']);
        }
    } catch (Throwable $e) {
    }
    $allowed = stobeDealAllowedCatsAmounts($terms, is_array($state) ? $state : [], $purse);
    $wrong = array_values(array_filter($spoken, static fn($n) => !isset($allowed[$n])));
    if (count($wrong) === 0) return null;
    $line = stobeDealPlainTermsLine($terms, $decision);
    if ($line === '') return null;
    return ['line'=>$line, 'spoken'=>$spoken, 'wrong'=>$wrong, 'allowed'=>array_keys($allowed)];
}

function stobeDealSpeechClaimsCeasefire(string $text): bool {""")

# ---- 26b: hook in chat.php (player-driven negotiation) -----------------------------------
patch("processor/chat.php",
      """            if (empty($dealResult['ok'])) {
                // Malformed terms: record nothing, but keep the NPC's own words unless they claim a deal.""",
      """            if (!empty($dealResult['ok']) && empty($dealResult['blocked_by_active'])
                && function_exists('stobeDealSpeechAmountCheck')) {
                // Bug 26: numbers she says must be the recorded ones.
                try {
                    $amountCheck = stobeDealSpeechAmountCheck($responseText, $targetNpc, $dealResult);
                } catch (Throwable $amountError) {
                    $amountCheck = null;
                }
                if ($amountCheck !== null) {
                    stobeLogWarn($alreadyStreamed
                        ? 'Negotiation speech amounts differ from recorded terms (already spoken)'
                        : 'Negotiation speech amounts differ from recorded terms; rewritten', [
                        'npc'=>$targetNpc, 'decision'=>strval($dealResult['decision'] ?? ''), 'text'=>$responseText,
                        'spoken'=>$amountCheck['spoken'], 'wrong'=>$amountCheck['wrong'], 'line'=>$amountCheck['line'],
                    ]);
                    if (!$alreadyStreamed) $responseText = $amountCheck['line'];
                }
            }
            if (empty($dealResult['ok'])) {
                // Malformed terms: record nothing, but keep the NPC's own words unless they claim a deal.""")

# ---- 26b: hook for NPC-initiated offers --------------------------------------------------
patch("lib/negotiation_engine.php",
      """            stobeLogInfo('NPC-initiated negotiation', ['npc'=>$npc, 'kind'=>$kind, 'result'=>$result]);""",
      """            stobeLogInfo('NPC-initiated negotiation', ['npc'=>$npc, 'kind'=>$kind, 'result'=>$result]);
            if (!empty($result['ok']) && function_exists('stobeDealSpeechAmountCheck')) {
                $amountCheck = stobeDealSpeechAmountCheck($text, $npc, $result);
                if ($amountCheck !== null) {
                    stobeLogWarn('Negotiation speech amounts differ from recorded terms; rewritten', [
                        'npc'=>$npc, 'decision'=>strval($result['decision'] ?? ''), 'text'=>$text,
                        'spoken'=>$amountCheck['spoken'], 'wrong'=>$amountCheck['wrong'], 'line'=>$amountCheck['line'],
                    ]);
                    $text = $amountCheck['line'];
                }
            }""")

print("patch_round10: applied")
