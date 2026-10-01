import sys

root = sys.argv[1].rstrip('/')


def patch(rel, pairs, count=1):
    path = root + '/' + rel
    s = open(path).read()
    for old, new in pairs:
        n = s.count(old)
        assert n == count, (rel, old[:100], n)
        s = s.replace(old, new)
    open(path, 'w').write(s)
    print('patched', rel)


# =========================================================== negotiation_phase1.php
patch('lib/negotiation_phase1.php', [
    # B: normalise names / timing words before validation.
    ("""    $terms = stobeDealNormalizeConditionalTerms(array_values(array_filter($terms, 'is_array')));""",
     """    $terms = stobeDealNormalizeConditionalTerms(array_values(array_filter($terms, 'is_array')), $npc, $player);"""),
    ("""function stobeDealNormalizeConditionalTerms(array $terms): array {
    $out = [];
    foreach ($terms as $term) {
        $condition = trim(strval($term['condition'] ?? ''));
        $when = strtolower(trim(strval($term['when'] ?? '')));""",
     """function stobeDealNormalizeConditionalTerms(array $terms, string $npc = '', string $player = ''): array {
    $out = [];
    $side = static function ($value) use ($npc, $player): string {
        $v = strtolower(trim(strval($value)));
        $base = static fn(string $n): string => strtolower(trim(preg_replace('/\\s*\\[[^\\]]*\\]\\s*/u', ' ', $n) ?? $n));
        if (in_array($v, ['player', 'you', 'the player'], true) || ($player !== '' && $v === $base($player))) return 'player';
        if (in_array($v, ['npc', 'me', 'myself', 'self', 'i'], true) || ($npc !== '' && $v === $base($npc))) return 'npc';
        return strval($value);
    };
    foreach ($terms as $term) {
        // Models often write names ("Shay", "Slant") where the ledger expects player/npc.
        foreach (['by', 'to', 'target'] as $field) {
            if (isset($term[$field])) $term[$field] = $side($term[$field]);
        }
        $condition = trim(strval($term['condition'] ?? ''));
        $when = strtolower(trim(strval($term['when'] ?? '')));
        if ($when !== '' && preg_match('/^(now|immediate(ly)?|up[_ ]?front|first|right[_ ]?(now|away)|at[_ ]once|before|today|on[_ ]the[_ ]spot)$/', $when)) {
            $when = 'now';
            $term['when'] = 'now';
        }
        // "Half now, half later": the player's later installment is due after the NPC delivers.
        if (($term['by'] ?? '') === 'player' && $condition === '' && $when !== '' && !in_array($when, ['now', 'after_npc'], true)
            && !preg_match('/\\b(if|unless|lose|lost|win|won|bet|should|in case)\\b/', str_replace('_', ' ', $when))) {
            $when = 'after_npc';
            $term['when'] = 'after_npc';
        }"""),
    ("""        if ($kind !== 'PROMISE' && $kind !== 'STOP_ATTACK' && ($condition !== '' || !in_array($when, ['', 'now', 'after_player'], true))) {""",
     """        if ($kind !== 'PROMISE' && $kind !== 'STOP_ATTACK' && ($condition !== '' || !in_array($when, ['', 'now', 'after_player', 'after_npc'], true))) {"""),
    ("""        if (isset($term['when']) && !in_array(strval($term['when']), ['now','after_player'], true)) {""",
     """        if (isset($term['when']) && strval($term['when']) === 'after_npc' && $by !== 'player') {
            return ['ok'=>false, 'error'=>'invalid_when'];
        }
        if (isset($term['when']) && !in_array(strval($term['when']), ['now','after_player','after_npc'], true)) {"""),
    (""" If the player offers to heal, bandage or patch you up,""",
     """ Always write sides as \\"player\\" and \\"npc\\" (never names). When the player pays in parts (\\"half now, half later\\"), make one GIVE_CATS term per part and add \\"when\\":\\"after_npc\\" to the part paid after you deliver; your own delivery then waits only for the first part. If the player accepts your last offer, ACCEPT exactly those terms; never raise the price after they agreed. A fight having started does not mean anyone is hurt: only mention wounds the condition data shows. If the player offers to heal, bandage or patch you up,"""),
])

# =========================================================== negotiation_engine.php
patch('lib/negotiation_engine.php', [
    # A: a payment covers installments in order; one 150 cannot satisfy two 150 terms.
    ("""    if ($kind === 'GIVE_CATS') {
        $need = intval($term['amount'] ?? 0);
        $exec = stobeNegCatsExecuted($player, $npc, $start - 3);
        $money = stobeNegMoney(stobeNegNpcRow($npc, $serial));
        $base = $baseline['npc_money'] ?? ['known'=>false];
        $delta = (!empty($base['known']) && $money['known'] && $money['observed_at'] > $start)
            ? $money['value'] - intval($base['value']) : 0;
        if ($exec['amount'] >= $need || $delta >= $need) {""",
     """    if ($kind === 'GIVE_CATS') {
        $need = intval($term['amount'] ?? 0);
        $before = max(0, intval($term['cats_before'] ?? 0)); // earlier installments take the first Cats
        $exec = stobeNegCatsExecuted($player, $npc, $start - 3);
        $money = stobeNegMoney(stobeNegNpcRow($npc, $serial));
        $base = $baseline['npc_money'] ?? ['known'=>false];
        $delta = (!empty($base['known']) && $money['known'] && $money['observed_at'] > $start)
            ? $money['value'] - intval($base['value']) : 0;
        $exec['amount'] = max(0, $exec['amount'] - $before);
        $delta = max(0, $delta - $before);
        if ($exec['amount'] >= $need || $delta >= $need) {"""),
    ("""    $betrayal = stobeNegDecode($deal['betrayal'] ?? []);
    $changed = false;
    foreach ($state as $idx => $term) {
        $before = json_encode($term);""",
     """    $betrayal = stobeNegDecode($deal['betrayal'] ?? []);
    $changed = false;
    // Installments: each player GIVE_CATS term is covered only by Cats beyond the earlier ones,
    // all measured from the first installment's start.
    $catsBefore = 0;
    $firstStart = 0;
    foreach ($state as $idx => $term) {
        if (($term['by'] ?? '') !== 'player' || ($term['kind'] ?? '') !== 'GIVE_CATS') continue;
        if ($firstStart === 0) $firstStart = intval($term['dispatched_unix'] ?? 0);
        $state[$idx]['cats_before'] = $catsBefore;
        if ($firstStart > 0) $state[$idx]['dispatched_unix'] = $firstStart;
        $catsBefore += intval($term['amount'] ?? 0);
    }
    foreach ($state as $idx => $term) {
        $before = json_encode($term);"""),
    # C: the NPC's side waits only for the part the player pays first.
    ("""    $playerTerms = array_filter($state, static fn($t) => ($t['by'] ?? '') === 'player' && ($t['kind'] ?? '') !== 'PROMISE');""",
     """    $playerTerms = array_filter($state, static fn($t) => ($t['by'] ?? '') === 'player' && ($t['kind'] ?? '') !== 'PROMISE'
        && strval($t['when'] ?? '') !== 'after_npc');"""),
    # H: refusals must lead to a decision, not more talk.
    (""". '). The deal is broken by them, not a gift and not free. React in character: you do not accept this as settled.';""",
     """. '). The deal is broken by them, not a gift and not free. Decide right now what you do about it and do it: back a demand with a real threat, take it by force (Attack), or write it off and remember it. Do not just keep talking about it.';"""),
    # Several bridge commands in a row: wait for KenshiFP to pick up the previous one.
    ("""    $temp = $path . '.tmp.' . strval(getmypid());
    $payload = strval($serial) . "\\t" . $command . "\\t" . strval(max(0, $targetSerial)) . "\\t\\n";""",
     """    $temp = $path . '.tmp.' . strval(getmypid());
    for ($i = 0; $i < 8 && file_exists($path); $i++) usleep(50000); // one-slot mailbox, polled every 50 ms
    $payload = strval($serial) . "\\t" . $command . "\\t" . strval(max(0, $targetSerial)) . "\\t\\n";"""),
    # G + D helpers.
    ("""function stobeNegTickThrottled(""",
     """/** Deal context that makes an NPC's hand-over to the player legitimate (not an unpaid gift). */
function stobeNegNpcHasDealContext(string $npc): bool {
    static $cache = [];
    $key = strtolower(trim($npc));
    if ($key === '') return false;
    if (array_key_exists($key, $cache)) return $cache[$key];
    try {
        $row = $GLOBALS['db']->fetchOne(
            "SELECT 1 AS hit FROM stobe_social_contract WHERE LOWER(npc_name)=LOWER($1)
               AND (status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE')
                    OR COALESCE(resolved_at, updated_at) > NOW() - INTERVAL '10 minutes') LIMIT 1",
            [$npc]
        );
        $hit = is_array($row);
        if (!$hit) {
            $dir = $GLOBALS['db']->fetchOne(
                "SELECT 1 AS hit FROM stobe_negotiation_directive WHERE LOWER(npc_name)=LOWER($1) AND consumed_unix=0 LIMIT 1", [$npc]);
            $hit = is_array($dir);
        }
    } catch (Throwable $e) {
        $hit = false;
    }
    if ($hit) $cache[$key] = true; // only positive answers are stable within a request
    return $hit;
}

/**
 * Personal fights: when an NPC attacks the player over a private matter (their own
 * chat decision, not a call for help), faction-mates who pile in are stood down so
 * a grudge does not turn the whole bar hostile. Toggle PERSONAL_FIGHTS (default on).
 */
function stobeNegPlayerAcceptsOfferNote(string $npc, string $message): string {
    try {
        $open = stobeDealOpenForNpc($npc);
        if (!is_array($open) || !in_array(strval($open['status'] ?? ''), ['PROPOSED','COUNTERED'], true)) return '';
        $text = function_exists('stobeNegWordsToNumbers') ? stobeNegWordsToNumbers(strtolower(trim($message))) : strtolower(trim($message));
        if ($text === '' || str_ends_with($text, '?')) return '';
        if (!preg_match("/\\b(deal|agreed|agree|accept|accepted|fine|okay|ok|yes|sure|done|you got it|you'?re on)\\b/", $text)) return '';
        if (preg_match("/\\b(no deal|not|don'?t|won'?t|never|nah|no way)\\b/", $text)) return '';
        $terms = json_decode(strval($open['terms'] ?? '[]'), true);
        $terms = is_array($terms) ? $terms : [];
        $amounts = [];
        $parts = [];
        foreach ($terms as $t) {
            if (!is_array($t)) continue;
            if (isset($t['amount'])) $amounts[] = intval($t['amount']);
            $parts[] = strval($t['by'] ?? '') . ' ' . strtolower(str_replace('_', ' ', strval($t['kind'] ?? '')))
                . (isset($t['amount']) ? ' ' . intval($t['amount']) . ' Cats' : '')
                . (!empty($t['item']) ? ' ' . strval($t['item']) : '');
        }
        if (count($parts) === 0) return '';
        preg_match_all('/\\b\\d{1,9}\\b/', $text, $nums);
        foreach ($nums[0] as $n) {
            if (!in_array(intval($n), $amounts, true)) return ''; // a different number is a counter, not acceptance
        }
        return 'The player has just accepted your current offer (' . implode('; ', $parts) . '). That is binding: answer with deal_decision ACCEPT and exactly these terms, and act on them now. Do not raise the price or add new conditions.';
    } catch (Throwable $e) {
        return '';
    }
}

function stobeNegPersonalFightsEnabled(): bool {
    return function_exists('getSettingBool') ? getSettingBool('PERSONAL_FIGHTS', true) : true;
}

function stobeNegRegisterPersonalFight(string $npc, array $npcData, string $replyText): void {
    if (!stobeNegPersonalFightsEnabled()) return;
    if (preg_match("/\\b(help me|get (him|her|them)|guards?|boys|lads|friends|everyone|all of you|grab (him|her|them))\\b/i", $replyText)) {
        stobeLogInfo('Personal fight not registered: NPC called for help', ['npc'=>$npc]);
        return;
    }
    $faction = trim(strval($npcData['faction'] ?? ''));
    $fights = json_decode(strval(getConfOpt('STOBE_PERSONAL_FIGHTS', '{}')), true);
    $fights = is_array($fights) ? $fights : [];
    foreach ($fights as $k => $f) {
        if (time() - intval($f['since'] ?? 0) > 180) unset($fights[$k]);
    }
    $fights[strtolower($npc)] = ['npc'=>$npc, 'faction'=>$faction, 'since'=>time(), 'stood_down'=>[]];
    setConfOpt('STOBE_PERSONAL_FIGHTS', json_encode($fights), true);
    stobeLogInfo('Personal fight registered', ['npc'=>$npc, 'faction'=>$faction]);
}

function stobeNegPersonalFightJoiner(string $eventData): void {
    if (!stobeNegPersonalFightsEnabled()) return;
    if (!preg_match('/^(.+?):\\s*Initiated attack\\s*\\(talking to:\\s*(.+?)\\)/', trim($eventData), $m)) return;
    $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
    $attacker = normalizeParticipantNameToken($m[1]);
    if (!stobeNegIsPlayerSide(normalizeParticipantNameToken($m[2]), $player) || stobeNegIsPlayerSide($attacker, $player)) return;
    $raw = strval(getConfOpt('STOBE_PERSONAL_FIGHTS', '{}'));
    if ($raw === '{}' || $raw === '' || $raw === '[]') return;
    $fights = json_decode($raw, true);
    if (!is_array($fights) || count($fights) === 0) return;
    $row = stobeNegNpcRow($attacker);
    $faction = trim(strval($row['faction'] ?? ''));
    $changed = false;
    foreach ($fights as $k => $f) {
        if (time() - intval($f['since'] ?? 0) > 180) { unset($fights[$k]); $changed = true; continue; }
        if (stobeNegCharMatches($attacker, strval($f['npc'] ?? ''))) return; // the grudge holder herself
        if ($faction === '' || strcasecmp($faction, strval($f['faction'] ?? '')) !== 0) continue;
        $last = intval($f['stood_down'][strtolower($attacker)] ?? 0);
        if (time() - $last < 20) continue;
        $serial = stobeNegSerialFromStorage($attacker);
        if ($serial > 0 && stobeNegQueueBridgeBySerial($serial, 'STOP_FIGHT')) {
            $fights[$k]['stood_down'][strtolower($attacker)] = time();
            $changed = true;
            stobeLogInfo('Personal fight: faction-mate stood down', ['fight'=>$f['npc'], 'joiner'=>$attacker, 'faction'=>$faction]);
        }
    }
    if ($changed) setConfOpt('STOBE_PERSONAL_FIGHTS', json_encode($fights), true);
}

function stobeNegTickThrottled("""),
    ("""    $type = strtolower(trim($eventType));
    if (in_array($type, ['combat','major_damage','knockout','combat_start'], true)) {""",
     """    $type = strtolower(trim($eventType));
    if ($type === 'combat') {
        try { stobeNegPersonalFightJoiner($eventData); } catch (Throwable $e) {}
    }
    if (in_array($type, ['combat','major_damage','knockout','combat_start'], true)) {"""),
])

# =========================================================== negotiation_voice.php (E)
patch('lib/negotiation_voice.php', [
    ("""    if (!$isHandover || ($cats <= 0 && count($items) === 0)) {
        if ($cue && ($owed > 0 || count(stobeNegPlayerOwedItems($npc)) > 0)) {
            return ['reason'=>'claimed_nothing_moved'] + $none;
        }
        return $none;
    }""",
     """    if (!$isHandover || ($cats <= 0 && count($items) === 0)) {
        // "Here's the extra one thousand" with no deal on record still must not read as paid.
        if ($cue && ($owed > 0 || count(stobeNegPlayerOwedItems($npc)) > 0
            || preg_match('/\\b(\\d{1,9}|cats?|money|payment|cash|the rest|what i owe)\\b/', $text))) {
            return ['reason'=>'claimed_nothing_moved'] + $none;
        }
        return $none;
    }"""),
])

# =========================================================== chat_helper_functions.php (D)
patch('lib/chat_helper_functions.php', [
    ("""        $config['in_player_faction'] = $isPlayerFaction;""",
     """        $config['in_player_faction'] = $isPlayerFaction;
        $config['npc_name'] = normalizeParticipantNameToken(strval($npcData['name'] ?? ''));"""),
    ("""    if (boolval($config['in_player_faction'] ?? false) || boolval($config['deal_sanctioned_give'] ?? false)) {
        return false;
    }""",
     """    if (boolval($config['in_player_faction'] ?? false) || boolval($config['deal_sanctioned_give'] ?? false)) {
        return false;
    }
    // Checked against the deal ledger itself: every code path that streams or re-validates
    // actions builds its own config, so a flag alone is not enough.
    $npcName = strval($config['npc_name'] ?? '');
    if ($npcName !== '' && function_exists('stobeNegNpcHasDealContext') && stobeNegNpcHasDealContext($npcName)) {
        return false;
    }"""),
])

# =========================================================== chat.php (F, G, I)
patch('processor/chat.php', [
    ("""$negotiationActive = !$narratorMode && strcasecmp($speaker, $playerName) === 0
    && stobeDealShouldNegotiate($targetNpc, $npcData, $message);""",
     """$negotiationActive = !$narratorMode && strcasecmp($speaker, $playerName) === 0
    && stobeDealShouldNegotiate($targetNpc, $npcData, $message);
// The player accepting the NPC's own last offer binds the NPC to it.
if ($negotiationActive && function_exists('stobeNegPlayerAcceptsOfferNote')) {
    $acceptNote = stobeNegPlayerAcceptsOfferNote($targetNpc, $message);
    if ($acceptNote !== '') {
        $messages[] = ['role' => 'user', 'content' => '[' . $acceptNote . ']'];
    }
}
// Mid-fight replies skip the model's hidden reasoning step (setting COMBAT_FAST_REPLIES).
$GLOBALS['STOBE_REASONING_OFF'] = is_array($npcData) && stobeNpcIsInCombat($npcData)
    && (function_exists('getSettingBool') ? getSettingBool('COMBAT_FAST_REPLIES', true) : true);"""),
    ("""        $responseActions = stobeNegAttachPendingForChat($targetNpc, $responseActions);
    } catch (Throwable $negAttachError) {
        stobeLogWarn('Negotiation dispatch attach failed', ['npc'=>$targetNpc, 'error'=>$negAttachError->getMessage()]);
    }
}""",
     """        $responseActions = stobeNegAttachPendingForChat($targetNpc, $responseActions);
    } catch (Throwable $negAttachError) {
        stobeLogWarn('Negotiation dispatch attach failed', ['npc'=>$targetNpc, 'error'=>$negAttachError->getMessage()]);
    }
}
// An NPC attacking the player over a private matter keeps it one-on-one.
if (!$narratorMode && function_exists('stobeNegRegisterPersonalFight') && is_array($npcData) && !npcIsInPlayerFaction($npcData)) {
    foreach ($responseActions as $responseAction) {
        if (preg_match('/^ATTACK@(.+)$/i', strval($responseAction), $attackMatch)
            && strcasecmp(normalizeParticipantNameToken($attackMatch[1]), $playerName) === 0) {
            try { stobeNegRegisterPersonalFight($targetNpc, $npcData, strval($responseText ?? '')); } catch (Throwable $e) {}
            break;
        }
    }
}"""),
])

# =========================================================== connector (I)
patch('connector/openaijson.php', [
    ("""    if ($usesReasoning) {
        $payload['reasoning'] = ['exclude' => true];
    }""",
     """    if ($usesReasoning) {
        $payload['reasoning'] = !empty($GLOBALS['STOBE_REASONING_OFF'])
            ? ['enabled' => false, 'exclude' => true]
            : ['exclude' => true];
    }"""),
], count=2)
