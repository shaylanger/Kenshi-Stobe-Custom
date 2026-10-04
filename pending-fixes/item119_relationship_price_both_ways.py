#!/usr/bin/env python3
"""Item 119: the relationship price (item 104) only corrected a CHEAPER accept.

In game (run m19, Vel Harrow, Iron Hat value 16) Shay offered 1 cat; Vel countered "three hundred" at
r = 0/+10/+56/+100 and the contract recorded player GIVE_CATS 300 each time. stobeRelTradeGate only raised
the player's Cats when they were below her relationship price, so any NPC ask above it stood.
Fix (lib/relationship_trading.php, stobeRelTradeGate):
  1. Player buys known items from her for Cats only: the recorded Cats are exactly
     stobeRelBuyPrice(value, r) (anti-exploit floor kept), above and below.
  2. Player sells known items to her for Cats only: her Cats are exactly stobeRelSellPrice(value, r)
     (raised at most to her known purse), above and below.
  3. 'counter' => true only when the change goes against the player (she asks more / pays less); only then is
     an ACCEPT recorded as her COUNTER (lib/negotiation_phase1.php). A change in the player's favour keeps
     the ACCEPT. The spoken line is corrected by the existing amount check (stobeDealSpeechAmountCheck):
     an amount she says that isn't in the recorded terms is replaced by the plain terms line.
Refusals, r <= -80, hostile deals and deals without a known item value (services etc.) are untouched.
Usage: python3 item119_relationship_price_both_ways.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel
    s = p.read_text()
    if 'item 119' in s:
        print('already patched:', p); return
    for old, new in pairs:
        assert s.count(old) == 1, ('anchor not unique/missing', rel, old[:90])
        s = s.replace(old, new)
    p.write_text(s)
    print('patched:', p)

patch('lib/relationship_trading.php', [
("""    // Item 104: prices. Player buys items she sells for Cats.
    $catsFromPlayer = 0; $catsIdx = -1;
    foreach ($terms as $i => $t) {
        if (is_array($t) && ($t['kind'] ?? '') === 'GIVE_CATS' && ($t['by'] ?? '') === 'player') { $catsFromPlayer += intval($t['amount'] ?? 0); if ($catsIdx < 0) $catsIdx = $i; }
    }
    $required = 0; $known = true; $buyItems = 0;
    foreach ($npcTerms as $t) {
        if (($t['kind'] ?? '') !== 'GIVE_ITEM') continue;
        $buyItems++;
        $base = stobeRelItemBasePrice($npcData, strval($t['item'] ?? ''));
        if ($base === null) { $known = false; break; }
        $required += stobeRelBuyPrice($base * max(1, intval($t['quantity'] ?? 1)), $r);
    }
    if ($buyItems > 0 && $known && $catsIdx >= 0 && $catsFromPlayer < $required) {
        $terms[$catsIdx]['amount'] = intval($terms[$catsIdx]['amount']) + ($required - $catsFromPlayer);
        $out['terms'] = $terms; $out['priced'] = true;
        stobeRelLog('info', 'Deal price set by relationship (item 104)', ['npc' => $npc, 'player' => $player, 'r' => $r, 'side' => 'player buys', 'offered' => $catsFromPlayer, 'price' => $required]);
        return $out;
    }
""",
"""    // Item 104: prices. Player buys items she sells for Cats.
    // Item 119: the recorded Cats are her relationship price both ways (not only a cheaper offer raised), when the
    // deal is plain Cats for known items; 'counter' marks a change against the player (she asks more).
    $onlyKinds = static fn(array $ts, array $kinds): bool => count($ts) > 0 && count(array_filter($ts, static fn($t) => !in_array(strval($t['kind'] ?? ''), $kinds, true))) === 0;
    $catsFromPlayer = 0; $catsIdx = -1; $catsIdxs = [];
    foreach ($terms as $i => $t) {
        if (is_array($t) && ($t['kind'] ?? '') === 'GIVE_CATS' && ($t['by'] ?? '') === 'player') { $catsFromPlayer += intval($t['amount'] ?? 0); if ($catsIdx < 0) $catsIdx = $i; $catsIdxs[] = $i; }
    }
    $required = 0; $known = true; $buyItems = 0;
    foreach ($npcTerms as $t) {
        if (($t['kind'] ?? '') !== 'GIVE_ITEM') continue;
        $buyItems++;
        $base = stobeRelItemBasePrice($npcData, strval($t['item'] ?? ''));
        if ($base === null) { $known = false; break; }
        $required += stobeRelBuyPrice($base * max(1, intval($t['quantity'] ?? 1)), $r);
    }
    $plainBuy = $onlyKinds($playerTerms, ['GIVE_CATS']) && $onlyKinds($npcTerms, ['GIVE_ITEM']);
    if ($buyItems > 0 && $known && $catsIdx >= 0 && $required > 0
        && ($catsFromPlayer < $required || ($plainBuy && $catsFromPlayer > $required))) {
        if ($catsFromPlayer < $required) {
            $terms[$catsIdx]['amount'] = intval($terms[$catsIdx]['amount']) + ($required - $catsFromPlayer);
        } else {
            // Lower: take the excess off the later instalments first.
            $excess = $catsFromPlayer - $required;
            foreach (array_reverse($catsIdxs) as $i) {
                if ($excess <= 0) break;
                $have = intval($terms[$i]['amount'] ?? 0);
                $cut = $i === $catsIdx ? min($excess, $have - 1) : min($excess, $have);
                $terms[$i]['amount'] = $have - $cut;
                $excess -= $cut;
            }
            $terms = array_values(array_filter($terms, static fn($t) => !(is_array($t) && ($t['kind'] ?? '') === 'GIVE_CATS' && ($t['by'] ?? '') === 'player' && intval($t['amount'] ?? 0) <= 0)));
        }
        $out['terms'] = $terms; $out['priced'] = true; $out['counter'] = $catsFromPlayer < $required;
        stobeRelLog('info', 'Deal price set by relationship (item 104/119)', ['npc' => $npc, 'player' => $player, 'r' => $r, 'side' => 'player buys', 'asked' => $catsFromPlayer, 'price' => $required]);
        return $out;
    }
"""),
("""        if ($sellItems > 0 && $known && $catsFromNpc > $maxPay && $maxPay > 0) {
            $terms[$npcCatsIdx]['amount'] = max(1, intval($terms[$npcCatsIdx]['amount']) - ($catsFromNpc - $maxPay));
            $out['terms'] = $terms; $out['priced'] = true;
            stobeRelLog('info', 'Deal price set by relationship (item 104)', ['npc' => $npc, 'player' => $player, 'r' => $r, 'side' => 'player sells', 'asked' => $catsFromNpc, 'price' => $maxPay]);
        }
""",
"""        if ($sellItems > 0 && $known && $catsFromNpc > $maxPay && $maxPay > 0) {
            $terms[$npcCatsIdx]['amount'] = max(1, intval($terms[$npcCatsIdx]['amount']) - ($catsFromNpc - $maxPay));
            $out['terms'] = $terms; $out['priced'] = true; $out['counter'] = true;
            stobeRelLog('info', 'Deal price set by relationship (item 104/119)', ['npc' => $npc, 'player' => $player, 'r' => $r, 'side' => 'player sells', 'asked' => $catsFromNpc, 'price' => $maxPay]);
        } elseif ($sellItems > 0 && $known && $catsFromNpc < $maxPay && $maxPay > 0
            && $onlyKinds($npcTerms, ['GIVE_CATS']) && $onlyKinds($playerTerms, ['GIVE_ITEM'])) {
            // Item 119: she pays her relationship price, not less (up to what she's known to carry).
            $purse = function_exists('stobeDealNpcPurse') ? stobeDealNpcPurse($npc) : -1;
            $pay = $purse >= 0 ? min($maxPay, max($catsFromNpc, $purse)) : $maxPay;
            if ($pay > $catsFromNpc) {
                $terms[$npcCatsIdx]['amount'] = intval($terms[$npcCatsIdx]['amount']) + ($pay - $catsFromNpc);
                $out['terms'] = $terms; $out['priced'] = true; $out['counter'] = false;
                stobeRelLog('info', 'Deal price set by relationship (item 104/119)', ['npc' => $npc, 'player' => $player, 'r' => $r, 'side' => 'player sells', 'asked' => $catsFromNpc, 'price' => $pay, 'purse' => $purse]);
            }
        }
"""),
])

patch('lib/negotiation_phase1.php', [
("""        if (!empty($gate['priced']) && $decision === 'ACCEPT') {
            $decision = 'COUNTER'; // she asks her price instead of accepting a cheaper one""",
"""        if (!empty($gate['priced']) && !empty($gate['counter']) && $decision === 'ACCEPT') { // item 119: only a change against the player
            $decision = 'COUNTER'; // she asks her price instead of accepting a cheaper one"""),
("""        '/(?:^|[.!?]\\s+)(\\d+)(?=\\s*(?:[,.!?]|then\\b))/i',
    ];""",
"""        '/(?:^|[.!?]\\s+)(\\d+)(?=\\s*(?:[,.!?]|then\\b))/i',
        // Item 119: a price without "cats": "it's three hundred." / "I'll take 300 for it" / "price is 300".
        "/\\\\b(?:it'?s|it\\\\s+is|that'?s|that\\\\s+is|price(?:'s|\\\\s+is)?|costs?|asking|take|want|make\\\\s+it|for)\\\\s+(?:(?:just|only|a|me|you)\\\\s+)?(\\\\d+)(?=\\\\s*(?:[,.!?;]|$)|\\\\s+(?:and|or|then|for|if|no|not|flat|even)\\\\b)/i",
    ];"""),
])

patch('tests/relationship_trading_regression.php', [
("""foreach ([[-50, 1502], [-10, 524], [0, 500], [10, 489], [56, 421], [100, 350]] as [$r, $want]) {
    $g = $gate($r, $buy);
    $amount = intval($g['terms'][1]['amount'] ?? 0);
    $expect = max(500, $want); // the player offered 500: raised to her price when hers is higher, kept otherwise
    check("price r=$r: player pays " . $expect, !empty($g['ok']) && $amount === $expect && (!empty($g['priced']) === ($want > 500)), [$amount, $g['priced'] ?? null]);
}
""",
"""foreach ([[-50, 1502], [-10, 524], [0, 500], [10, 489], [56, 421], [100, 350]] as [$r, $want]) {
    $g = $gate($r, $buy);
    $amount = intval($g['terms'][1]['amount'] ?? 0);
    // Item 119: the player offered 500: the recorded price is hers, above and below.
    check("price r=$r: player pays " . $want, !empty($g['ok']) && $amount === $want && (!empty($g['priced']) === ($want !== 500)) && (!empty($g['counter']) === ($want > 500)), [$amount, $g['priced'] ?? null, $g['counter'] ?? null]);
}
// Item 119 (run m19, Vel Harrow): her counter of 300 for a 16-Cat hat is recorded at her relationship price.
$velNpc = static fn(int $r) => ['name' => 'RelTrade Npc', 'faction' => 'Test Traders', 'extended_data' => json_encode(['relationships' => [$player => ['aff' => $r]]]),
    'metadata' => '{}', 'inventory' => 'Bread x2 value 10', 'equipment' => 'Iron Hat x1 value 16'];
$velAsk = [['kind' => 'GIVE_CATS', 'by' => 'player', 'to' => 'npc', 'amount' => 300], ['kind' => 'GIVE_ITEM', 'by' => 'npc', 'to' => 'player', 'item' => 'Iron Hat', 'when' => 'after_player']];
foreach ([0 => 16, 10 => 16, 56 => 14, 100 => 12] as $r => $want) {
    $g = stobeRelTradeGate('RelTrade Npc', $velNpc($r), $player, 'social', $velAsk);
    check("item 119 r=$r: her counter of 300 for the 16-Cat hat is recorded at $want", !empty($g['ok']) && intval($g['terms'][0]['amount'] ?? 0) === $want && !empty($g['priced']) && empty($g['counter']), $g['terms'] ?? $g);
}
$g = stobeRelTradeGate('RelTrade Npc', $velNpc(-50), $player, 'social', $velAsk);
check('item 119 r=-50: 300 for the 16-Cat hat becomes 49', intval($g['terms'][0]['amount'] ?? 0) === 49, $g['terms'] ?? $g);
$split = [['kind' => 'GIVE_CATS', 'by' => 'player', 'to' => 'npc', 'amount' => 200], ['kind' => 'GIVE_CATS', 'by' => 'player', 'to' => 'npc', 'amount' => 100, 'when' => 'after_npc'], ['kind' => 'GIVE_ITEM', 'by' => 'npc', 'to' => 'player', 'item' => 'Iron Hat']];
$g = stobeRelTradeGate('RelTrade Npc', $velNpc(0), $player, 'social', $split);
$paid = array_sum(array_map(static fn($t) => ($t['kind'] ?? '') === 'GIVE_CATS' && ($t['by'] ?? '') === 'player' ? intval($t['amount']) : 0, $g['terms'] ?? []));
check('item 119: two instalments of 300 come down to 16 in total', $paid === 16, $g['terms'] ?? $g);
$barter = [['kind' => 'GIVE_CATS', 'by' => 'player', 'to' => 'npc', 'amount' => 300], ['kind' => 'GIVE_ITEM', 'by' => 'player', 'to' => 'npc', 'item' => 'Bread'], ['kind' => 'GIVE_ITEM', 'by' => 'npc', 'to' => 'player', 'item' => 'Iron Hat']];
$g = stobeRelTradeGate('RelTrade Npc', $velNpc(0), $player, 'social', $barter);
check('item 119: Cats plus an item from the player (barter) not lowered', intval($g['terms'][0]['amount'] ?? 0) === 300 && empty($g['priced']), $g['terms'] ?? $g);
$service = [['kind' => 'GIVE_CATS', 'by' => 'player', 'to' => 'npc', 'amount' => 300], ['kind' => 'FIRST_AID', 'by' => 'npc', 'target' => 'player']];
$g = stobeRelTradeGate('RelTrade Npc', $velNpc(0), $player, 'social', $service);
check('item 119: a service without an item value is untouched', intval($g['terms'][0]['amount'] ?? 0) === 300 && empty($g['priced']), $g['terms'] ?? $g);
check('item 119: still no trade at r=-80', (stobeRelTradeGate('RelTrade Npc', $velNpc(-80), $player, 'social', $velAsk)['error'] ?? '') === 'relationship_no_trade');
// Item 119: her spoken price without "cats" is caught, so the line is corrected to the recorded price.
$velTerms = [['kind' => 'GIVE_CATS', 'by' => 'player', 'to' => 'npc', 'amount' => 16], ['kind' => 'GIVE_ITEM', 'by' => 'npc', 'to' => 'player', 'item' => 'Iron Hat', 'when' => 'after_player']];
$fix = stobeDealSpeechAmountCheck("One cat for a hat that keeps swords off my skull. No. If you want it, it's three hundred. That's the price, not a joke.", 'RelTrade Nobody', ['decision' => 'COUNTER', 'terms' => $velTerms], "Vel, I'll buy your Iron Hat. One cat, take it or leave it.");
check("item 119: \\"it's three hundred\\" corrected to the 16-Cat terms line", is_array($fix) && in_array(300, $fix['wrong'] ?? [], true) && str_contains(strval($fix['line'] ?? ''), '16 Cats'), $fix);
check('item 119: "I\\'ll take 300 for it" is a spoken amount', in_array(300, stobeDealSpokenCatsAmounts("I'll take 300 for it."), true));
check('item 119: "for 2 days" is not a spoken amount', stobeDealSpokenCatsAmounts('Guard you for 2 days.') === []);
// Item 119 sell side: the player sells her a 500-Cat Iron Hat; she pays her relationship price both ways.
$playerRow = ['name' => $player, 'inventory' => 'Iron Hat x1 value 500', 'equipment' => '', 'metadata' => '{}'];
$sell = static fn(int $amount) => [['kind' => 'GIVE_ITEM', 'by' => 'player', 'to' => 'npc', 'item' => 'Iron Hat'], ['kind' => 'GIVE_CATS', 'by' => 'npc', 'to' => 'player', 'amount' => $amount]];
foreach ([0, 56, -50] as $r) {
    $want = stobeRelSellPrice(500, $r);
    $g = stobeRelTradeGate('RelTrade Npc', $npc($r), $player, 'social', $sell(5), $playerRow);
    check("item 119 sell r=$r: her offer of 5 is raised to $want", intval($g['terms'][1]['amount'] ?? 0) === $want && empty($g['counter']), $g['terms'] ?? $g);
    $g = stobeRelTradeGate('RelTrade Npc', $npc($r), $player, 'social', $sell(5000), $playerRow);
    check("item 119 sell r=$r: her offer of 5000 is lowered to $want (a counter)", intval($g['terms'][1]['amount'] ?? 0) === $want && !empty($g['counter']), $g['terms'] ?? $g);
}
"""),
])
