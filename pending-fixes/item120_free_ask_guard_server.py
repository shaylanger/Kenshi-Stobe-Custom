#!/usr/bin/env python3
"""Item 120: willingness lines enforced outside deal terms (free favour / free gift / pay-later asks).

Usage: python3 item120_free_ask_guard_server.py <StobeServer tree root>

- lib/relationship_trading.php: stobeRelFreeAskKind / stobeRelFreeAskPayment / stobeRelReplyTakesOn /
  stobeRelFreeAskGuard / stobeRelFirstAidForPlayerAllowed / stobeRelFavourRefusalLine.
- processor/chat.php: a free ask to an outsider is held until checked (deferred stream), then the guard
  refuses in character below the line (favour r < 30, gift r < GIFT_TRUST_THRESHOLD, pay-later r < 0) or
  turns an agreed heal into a real FIRST_AID@player.
- lib/chat_helper_functions.php: the outsider order gate lets FIRST_AID on the player through at r >= 30
  or under a deal (before: always refused as a "work order").
- lib/negotiation_engine.php: a CANCELLED/EXPIRED/REJECTED deal in the last 10 minutes no longer counts
  as deal context (it let an unpaid gift through at r=55).
Idempotent: a tree that already has the item 120 marker is left alone.
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, edits):
    p = root / rel
    s = p.read_text()
    for old, new, marker in edits:
        if marker in s:
            print(f"{rel}: already patched ({marker[:40]!r})")
            continue
        n = s.count(old)
        assert n == 1, f"{rel}: anchor found {n}x: {old[:80]!r}"
        s = s.replace(old, new)
        print(f"{rel}: patched ({marker[:40]!r})")
    p.write_text(s)

# ---------------------------------------------------------------- relationship_trading.php
REL_FUNCS = r'''

// ---------------------------------------------------------------- Item 120: free asks outside deal terms

/** Item 120: what the player asks an outsider for with this line: 'heal', 'favour', 'gift' or ''. */
function stobeRelFreeAskKind(string $message): string {
    $m = strtolower(str_replace(["\u{2019}", "\u{2018}"], "'", trim($message)));
    if ($m === '') return '';
    // A request: after "you"/"please" (would you, can you just ...) or at the start of a sentence ("Vel, fetch ...").
    $ask = "(?:\\b(?:you|please)\\b[^.?!]{0,25}?|(?:^|[.!?]\\s+)(?:[a-z']+,\\s*)?)";
    $heal = "\\b(?:bandage|patch\\s+(?:me|it|this|that|my|up)|give\\s+me\\s+first\\s+aid|first\\s+aid|heal\\s+(?:me|my|it|this|that|up)|stitch|splint|tend\\s+(?:to\\s+)?(?:me|my|this|that)|treat\\s+(?:me|my|this|that)|(?:look\\s+at|see\\s+to|fix)\\s+(?:my|this|that)\\s+(?:arm|leg|wound|cut|cuts|injur\\w*|head|chest|stomach|bleeding))";
    if (preg_match('/' . $ask . $heal . '/', $m)) return 'heal';
    $favour = "\\b(?:fetch|carry|haul|guard|protect|escort|watch\\s+(?:my|over)|keep\\s+watch|work\\s+for\\s+me|build|repair|cook\\s+(?:me|for\\s+me)|bring\\s+me|get\\s+me|follow\\s+me|come\\s+with\\s+me|walk\\s+me|take\\s+me\\s+to|deliver|rescue)\\b";
    if (preg_match('/' . $ask . $favour . '/', $m)) return 'favour';
    $gift = "\\b(?:give|hand|spare|toss|throw|gift|lend|loan)\\s+(?:me|us)\\b";
    if (preg_match('/' . $ask . $gift . '/', $m) || preg_match("/\\b(?:can|could|may)\\s+i\\s+(?:just\\s+)?(?:have|get|take)\\b/", $m)) return 'gift';
    return '';
}

/**
 * Item 120: does the ask offer payment? ['paid'=>bool, 'later_refused'=>bool]. "For free" / "nothing to pay
 * with" is never payment; paying later is payment only at r >= 0 (item 103 pay-later line).
 */
function stobeRelFreeAskPayment(string $message, int $r): array {
    $m = strtolower(str_replace(["\u{2019}", "\u{2018}"], "'", $message));
    if (preg_match("/\\b(for\\s+free|free\\s+of\\s+charge|nothing\\s+to\\s+pay|(?:can'?t|cannot|couldn'?t)\\s+pay|no\\s+(?:money|cats|coin)|(?:i'?m|i\\s+am)\\s+broke|on\\s+the\\s+house|for\\s+nothing)\\b/", $m)) {
        return ['paid' => false, 'later_refused' => false];
    }
    $pays = preg_match("/\\b(pay|paid|payment|\\d[\\d,]*\\s*(?:cats?|c)\\b|cats|coin|in\\s+exchange|in\\s+return|trade|swap|barter|owe\\s+you|reward)\\b/", $m) === 1;
    if (!$pays) return ['paid' => false, 'later_refused' => false];
    $later = preg_match("/\\b(later|tomorrow|next\\s+time|owe\\s+you|when\\s+i\\s+(?:can|get|have))\\b/", $m) === 1;
    if ($later && $r < STOBE_REL_PAY_LATER_MIN) return ['paid' => false, 'later_refused' => true];
    return ['paid' => true, 'later_refused' => false];
}

/** Item 120: her reply takes the ask on (words or actions) and turns nothing down. */
function stobeRelReplyTakesOn(string $reply, array $actions, string $player): bool {
    $t = strtolower(str_replace(["\u{2019}", "\u{2018}"], "'", trim($reply)));
    if (function_exists('stobeReplyRefusesOrder') && $t !== '' && stobeReplyRefusesOrder($reply)) return false;
    if (preg_match("/\\b(no(?!\\s+(?:problem|worries|trouble))|nope|not\\s+for\\s+free|nothing'?s\\s+free|what'?s\\s+in\\s+it|pay\\s+(?:me|first|up)|costs?|price|cats\\s+first|for\\s+nothing)\\b/", $t)) return false;
    foreach ($actions as $a) {
        $parts = explode('@', strval($a));
        $cmd = strtoupper(trim($parts[0]));
        $target = trim(strval($parts[1] ?? ''));
        if (in_array($cmd, ['FIRST_AID','BODYGUARD','GUARD_TARGET','FOLLOW','MOVE_TO_TARGET','RESCUE','PUT_IN_BED','TASK_GOAL','WORK_GOAL','REPAIR','BUILD','GIVE_ITEM','GIVE_CATS'], true)) return true;
        if ($cmd === 'ROLEPLAY_ACTION' && $target !== '' && stobeRelIsPlayerSide($target, $player)) return true;
    }
    return preg_match("/\\b(i'?ll|i\\s+will|let\\s+me|sure|fine|alright|all\\s+right|okay|ok|here(?:'?s|\\s+you\\s+go)?|take\\s+it|hold\\s+still|show\\s+me|sit\\s+(?:down|still)|of\\s+course|right\\s+away|on\\s+it|in\\s+luck|go\\s+on\\s+then)\\b/", $t) === 1;
}

function stobeRelIsPlayerSide(string $name, string $player): bool {
    if (function_exists('stobeIsPlayerSideName')) return stobeIsPlayerSideName($name, $player);
    return strcasecmp(normalizeParticipantNameToken($name), normalizeParticipantNameToken($player)) === 0;
}

/** Item 120: her in-character refusal for a free ask below the line. */
function stobeRelFavourRefusalLine(string $kind): string {
    return match ($kind) {
        'heal' => "Kits cost money. Pay me and I'll patch you up.",
        'gift' => "Nothing's free out here. Pay for it, or go without.",
        'pay_later' => "Pay first. I don't trust you to pay me later.",
        default => "Why would I do that for nothing? Pay me and we'll talk.",
    };
}

/** Item 120: an outsider patches the player up at r >= +30, or under a deal. Squadmates always. */
function stobeRelFirstAidForPlayerAllowed(string $npc, array|false $npcData, string $player): bool {
    if (!is_array($npcData)) return false;
    if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData)) return true;
    if (stobeRelValue($npcData, $player) >= STOBE_REL_FREE_FAVOUR_MIN) return true;
    try {
        if (function_exists('stobeDealOpenForNpc') && stobeDealOpenForNpc($npc) !== null) return true;
        if (function_exists('stobeNegNpcHasDealContext') && stobeNegNpcHasDealContext($npc)) return true;
    } catch (Throwable $e) {
    }
    return false;
}

/**
 * Item 120: the willingness lines on a plain chat turn (no deal recorded). A non-squad NPC who takes on the
 * player's ask for a free favour below r +30, a free item/Cats below the gift threshold, or pay-later below 0
 * refuses in character instead (her service/gift actions dropped). An agreed heal at r >= +30 becomes real
 * first aid (FIRST_AID@player) instead of a roleplay notice.
 * $ctx: decision (deal decision this turn), open_deal (bool), blocked_gift (bool), already_streamed (bool).
 */
function stobeRelFreeAskGuard(string $npc, array|false $npcData, string $player, string $message, string $reply, array $actions, array $ctx = []): array {
    $out = ['text' => $reply, 'actions' => $actions, 'rule' => '', 'kind' => '', 'r' => 0, 'added' => [], 'removed' => []];
    if (!is_array($npcData) || trim($player) === '') return $out;
    if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData)) return $out; // squadmates exempt
    if (in_array(strval($ctx['decision'] ?? ''), ['ACCEPT', 'COUNTER', 'PROPOSE'], true) || !empty($ctx['open_deal'])) return $out;
    $kind = stobeRelFreeAskKind($message);
    $gives = []; $services = [];
    foreach ($actions as $i => $a) {
        $parts = explode('@', strval($a));
        $cmd = strtoupper(trim($parts[0]));
        $target = trim(strval($parts[1] ?? ''));
        $toPlayer = $target !== '' && stobeRelIsPlayerSide($target, $player);
        if (in_array($cmd, ['GIVE_ITEM', 'GIVE_CATS'], true) && ($toPlayer || $target === '')) $gives[] = $i;
        elseif (in_array($cmd, ['FIRST_AID','BODYGUARD','GUARD_TARGET','FOLLOW','MOVE_TO_TARGET','RESCUE','PUT_IN_BED','ROLEPLAY_ACTION'], true) && $toPlayer) $services[] = $i;
        elseif (in_array($cmd, ['TASK_GOAL','WORK_GOAL','REPAIR','BUILD'], true)) $services[] = $i;
    }
    if ($kind === '' && count($gives) === 0) return $out;
    $r = stobeRelValue($npcData, $player);
    $out['r'] = $r; $out['kind'] = $kind;
    $takesOn = stobeRelReplyTakesOn($reply, $actions, $player) || ($kind === 'gift' && !empty($ctx['blocked_gift']));
    if (!$takesOn && count($gives) === 0) return $out; // her own refusal or question stands
    $pay = stobeRelFreeAskPayment($message, $r);
    $giftMin = function_exists('getSettingInt') ? max(0, min(100, intval(getSettingInt('GIFT_TRUST_THRESHOLD', 56)))) : 56;
    $rule = ''; $line = ''; $log = '';
    if ($pay['later_refused']) {
        $rule = 'pay-later needs r >= ' . STOBE_REL_PAY_LATER_MIN; $line = stobeRelFavourRefusalLine('pay_later'); $log = 'Pay-later refused by relationship (item 120)';
    } elseif (in_array($kind, ['heal', 'favour'], true) && !$pay['paid'] && $r < STOBE_REL_FREE_FAVOUR_MIN) {
        $rule = 'free favours need r >= ' . STOBE_REL_FREE_FAVOUR_MIN; $line = stobeRelFavourRefusalLine($kind); $log = 'Free favour refused by relationship (item 120)';
    } elseif (($kind === 'gift' || count($gives) > 0) && !$pay['paid'] && $r < $giftMin) {
        $rule = 'free items/Cats need r >= ' . $giftMin; $line = stobeRelFavourRefusalLine('gift'); $log = 'Free gift refused by relationship (item 120)';
    }
    if ($rule !== '') {
        $drop = array_merge($gives, $services);
        foreach ($drop as $i) $out['removed'][] = $actions[$i];
        $out['actions'] = array_values(array_diff_key($actions, array_flip($drop)));
        if (empty($ctx['already_streamed'])) $out['text'] = $line;
        $out['rule'] = $rule;
        stobeRelLog('warn', $log, ['npc' => $npc, 'player' => $player, 'r' => $r, 'kind' => $kind, 'ask' => $message,
            'reply' => $reply, 'removed' => $out['removed'], 'already_streamed' => !empty($ctx['already_streamed'])]);
        return $out;
    }
    // Agreed heal: real first aid, not just a roleplay notice.
    if ($kind === 'heal' && $takesOn && $r >= STOBE_REL_FREE_FAVOUR_MIN) {
        foreach ($actions as $a) {
            if (preg_match('/^FIRST_AID@/i', strval($a))) return $out;
        }
        $out['actions'][] = 'FIRST_AID@' . $player;
        $out['added'][] = 'FIRST_AID@' . $player;
        stobeRelLog('info', 'Agreed first aid without action: FIRST_AID added (item 120)', ['npc' => $npc, 'player' => $player, 'r' => $r, 'reply' => $reply]);
    }
    return $out;
}
'''

rel = root / 'lib/relationship_trading.php'
s = rel.read_text()
if 'function stobeRelFreeAskGuard' in s:
    print('lib/relationship_trading.php: already patched')
else:
    assert s.rstrip().endswith('    return $out;\n}'), 'relationship_trading.php: unexpected file end'
    assert 'const STOBE_REL_FREE_FAVOUR_MIN = 30;' in s and 'function stobeRelLog(' in s
    rel.write_text(s.rstrip() + '\n' + REL_FUNCS)
    print('lib/relationship_trading.php: patched')

# ---------------------------------------------------------------- processor/chat.php
patch('processor/chat.php', [
    (
        "// Handing over goods under an already agreed deal is not a gift.\nif ($negotiationOpenDeal !== null",
        "// Item 120: a free ask (favour, gift, pay-later) to an outsider: her reply is checked before she speaks it.\n"
        "$relFreeAskDefer = !$narratorMode && strcasecmp($speaker, $playerName) === 0 && is_array($npcData)\n"
        "    && !npcIsInPlayerFaction($npcData) && function_exists('stobeRelFreeAskKind') && stobeRelFreeAskKind($message) !== '';\n"
        "$GLOBALS['STOBE_BLOCKED_UNPAID_GIFT'] = false;\n"
        "// Handing over goods under an already agreed deal is not a gift.\nif ($negotiationOpenDeal !== null",
        "$relFreeAskDefer = ",
    ),
    (
        "            'defer_structured_stream' => $negotiationDefer,\n",
        "            'defer_structured_stream' => $negotiationDefer || $relFreeAskDefer, // item 120\n",
        "$negotiationDefer || $relFreeAskDefer",
    ),
    (
        "'added'=>$missingHandovers]);\n    }\n}\nif (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {\n",
        "'added'=>$missingHandovers]);\n    }\n}\n"
        "// Item 120: willingness lines on a plain chat turn (free favour < +30, free gift < gift threshold, pay-later < 0);\n"
        "// an agreed heal at >= +30 is real first aid.\n"
        "if (!$narratorMode && function_exists('stobeRelFreeAskGuard') && strcasecmp($speaker, $playerName) === 0) {\n"
        "    try {\n"
        "        $relOpenDeal = $negotiationOpenDeal ?? (function_exists('stobeDealOpenForNpc') ? stobeDealOpenForNpc($targetNpc) : null);\n"
        "        $freeAsk = stobeRelFreeAskGuard($targetNpc, $npcData, $playerName, strval($message ?? ''), strval($responseText ?? ''), $responseActions, [\n"
        "            'decision' => $dealTurnDecision, 'open_deal' => $relOpenDeal !== null,\n"
        "            'blocked_gift' => !empty($GLOBALS['STOBE_BLOCKED_UNPAID_GIFT']), 'already_streamed' => !empty($alreadyStreamed),\n"
        "        ]);\n"
        "        $responseText = $freeAsk['text'];\n"
        "        $responseActions = $freeAsk['actions'];\n"
        "    } catch (Throwable $freeAskError) {\n"
        "        stobeLogWarn('Free-ask guard failed (item 120)', ['npc'=>$targetNpc, 'error'=>$freeAskError->getMessage()]);\n"
        "    }\n"
        "}\n"
        "if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {\n",
        "stobeRelFreeAskGuard($targetNpc",
    ),
])

# ---------------------------------------------------------------- lib/chat_helper_functions.php
patch('lib/chat_helper_functions.php', [
    (
        "    if (in_array($cmd, stobeNonFactionWorkOrderCommands(), true)) {\n"
        "        return \"I don't take orders like that from you - I'm not one of yours.\";\n",
        "    // Item 120: patching the player up is a favour, not a work order: at r >= +30 or under a deal.\n"
        "    if ($cmd === 'FIRST_AID' && function_exists('stobeRelFirstAidForPlayerAllowed') && function_exists('stobeIsPlayerSideName')) {\n"
        "        $faTarget = $at === false ? '' : trim(substr($normalizedAction, $at + 1));\n"
        "        $faPlayer = strval($GLOBALS['STOBE_PLAYER_ACTOR'] ?? '');\n"
        "        if ($faPlayer === '') $faPlayer = normalizeParticipantNameToken(strval(getSetting('PLAYER_NAME', '')));\n"
        "        if ($faTarget !== '' && $faPlayer !== '' && stobeIsPlayerSideName($faTarget, $faPlayer)) {\n"
        "            return stobeRelFirstAidForPlayerAllowed($actor, $npcData, $faPlayer) ? '' : stobeRelFavourRefusalLine('heal');\n"
        "        }\n"
        "    }\n"
        "    if (in_array($cmd, stobeNonFactionWorkOrderCommands(), true)) {\n"
        "        return \"I don't take orders like that from you - I'm not one of yours.\";\n",
        "// Item 120: patching the player up is a favour",
    ),
])

# ---------------------------------------------------------------- lib/negotiation_engine.php
patch('lib/negotiation_engine.php', [
    (
        "OR COALESCE(resolved_at, updated_at) > NOW() - INTERVAL '10 minutes') LIMIT 1\",",
        "OR (status NOT IN ('CANCELLED','EXPIRED','REJECTED') -- item 120: nothing owed on these\n"
        "                        AND COALESCE(resolved_at, updated_at) > NOW() - INTERVAL '10 minutes')) LIMIT 1\",",
        "item 120: nothing owed on these",
    ),
])
# ---------------------------------------------------------------- new regression suite
t = root / 'tests/relationship_free_ask_regression.php'
src = pathlib.Path(__file__).with_name('item120_relationship_free_ask_regression.php')
if not t.exists():
    t.write_text(src.read_text())
    print('tests/relationship_free_ask_regression.php: added')
print('done')
