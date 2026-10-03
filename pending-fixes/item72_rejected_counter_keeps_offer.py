#!/usr/bin/env python3
"""Item 72: the player haggled up an NPC's surrender offer, the NPC refused (REJECT) and the deal went
REJECTED; "fine, 200, deal" then made a NEW combat deal with the payer flipped (the player paying).
(a) an NPC's REJECT of the player's counter leaves his own offer (proposer npc, still PROPOSED) on the
    table unless his reply ends the talks;
(b) an ACCEPT with no open deal takes a just-rejected offer of his as the table (its terms' direction
    and kind);
(c) her own words "I'll get the cats out" / "I'll pay you 200" say she pays (item 44 family).
Usage: item72_rejected_counter_keeps_offer.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text(encoding='utf-8')
    if new in s:
        print(f'{rel}: already patched'); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n} times'
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'{rel}: patched')

P = 'lib/negotiation_phase1.php'
patch(P,
'''    $open = stobeDealOpenForNpc($npc);
    if ($decision === 'REJECT' && $open !== null && in_array(strval($open['status']), ['PROPOSED','COUNTERED'], true)) {''',
'''    $open = stobeDealOpenForNpc($npc);
    if ($decision === 'REJECT' && $open !== null && strval($open['status']) === 'PROPOSED'
        && strval($open['proposer'] ?? '') === 'npc' && !stobeDealReplyEndsTalks(strval($response['message'] ?? ''))) {
        // Item 72: he turned down the player's counter; his own offer stays on the table.
        stobeDealLog('info', "Negotiation: REJECT of the player's counter, his own offer stays (item 72)",
            ['npc'=>$npc, 'contract_id'=>strval($open['contract_id'])]);
        return ['ok'=>true,'decision'=>'REJECT','id'=>strval($open['contract_id']),'offer_kept'=>true];
    }
    if ($decision === 'REJECT' && $open !== null && in_array(strval($open['status']), ['PROPOSED','COUNTERED'], true)) {''')
patch(P,
'''    $terms = stobeDealFixCatsDirectionFromTable($terms, $open, $playerMessage); // item 44''',
'''    // Item 72: no open deal, but he just offered one that got rejected: that offer is the table.
    $table = $open;
    if ($table === null && $decision === 'ACCEPT') {
        $table = stobeDealRecentRejectedNpcOffer($npc);
        if ($table !== null) {
            $kind = strval($table['kind'] ?? $kind) ?: $kind;
            $proposer = 'npc';
            stobeDealLog('info', 'Negotiation: ACCEPT takes up his just-rejected offer (item 72)', ['npc'=>$npc, 'contract_id'=>strval($table['contract_id'])]);
        }
    }
    $terms = stobeDealFixCatsDirectionFromHerWords($terms, strval($response['message'] ?? '')); // item 72
    $terms = stobeDealFixCatsDirectionFromTable($terms, $table, $playerMessage); // item 44''')
patch(P,
'''function stobeDealFixCatsDirectionFromTable(array $terms, ?array $open, string $playerMessage): array {''',
'''/** Item 72: his reply ends the talks ("no deal", "forget it", "then we fight"). */
function stobeDealReplyEndsTalks(string $message): bool {
    return preg_match("/\\b(no\\s+deal|forget\\s+it|forget\\s+the\\s+deal|deal'?s\\s+off|offer'?s\\s+(?:off|gone|withdrawn)|we\\s+fight|fight\\s+it\\s+is|to\\s+the\\s+death|then\\s+die|i\\s+take\\s+it\\s+back)\\b/i", $message) === 1;
}

/** Item 72: an NPC offer (proposer npc) he himself rejected in the last 10 minutes, or null. */
function stobeDealRecentRejectedNpcOffer(string $npc): ?array {
    try {
        $row = $GLOBALS['db']->fetchOne(
            "SELECT * FROM stobe_social_contract WHERE LOWER(npc_name)=LOWER($1) AND status='REJECTED' AND proposer='npc'
               AND COALESCE(evidence->>'rejected_by','')='npc' AND updated_at > NOW() - INTERVAL '10 minutes'
             ORDER BY updated_at DESC LIMIT 1", [$npc]);
        return is_array($row) ? $row : null;
    } catch (Throwable $e) {
        return null;
    }
}

/** Item 72: her line says she pays ("I'll get the cats out", "I'll pay you 200"): the one player-paid Cats term is hers. */
function stobeDealFixCatsDirectionFromHerWords(array $terms, string $message): array {
    $m = strtolower(str_replace(["\\u{2019}", "\\u{2018}"], "'", $message));
    if (!preg_match("/\\b(?:i'?ll|i\\s+will|let\\s+me|i'?m\\s+(?:getting|handing))\\s+(?:get|dig|fish|pull|count|hand|pay|give|getting|handing)\\b[^.?!]{0,30}\\b(?:cats|coin|coins|money|purse|\\d{2,7}|hundred|thousand)\\b/", $m)) return $terms;
    if (preg_match("/\\byou(?:'ll|\\s+will)?\\s+(?:pay|give|hand)\\b/", $m)) return $terms;
    $cats = [];
    foreach ($terms as $i => $t) {
        if (is_array($t) && strtoupper(strval($t['kind'] ?? '')) === 'GIVE_CATS') $cats[] = $i;
    }
    if (count($cats) !== 1 || ($terms[$cats[0]]['by'] ?? '') !== 'player') return $terms;
    $terms[$cats[0]]['by'] = 'npc';
    $terms[$cats[0]]['to'] = 'player';
    stobeDealLog('warn', 'Negotiation term fixed: her words say she pays (item 72)', ['amount'=>intval($terms[$cats[0]]['amount'] ?? 0)]);
    return $terms;
}

function stobeDealFixCatsDirectionFromTable(array $terms, ?array $open, string $playerMessage): array {''')

T = 'tests/negotiation_engine_regression.php'
patch(T,
'''// ---------------------------------------------------------------- 12h5. deal-offer cap tiers''',
'''// ---------------------------------------------------------------- 12h4c. item 72: his offer survives his "no" to a counter
$n72 = 'Weth72 [NegTest72 Bandit]';
fixtureNpc($n72, ['money'=>500,'money_observed_at'=>time(),'is_in_combat'=>true], 'Bread x1', 'A tough raider.', '30/100');
$db->exec("DELETE FROM stobe_social_contract WHERE npc_name=$1", [$n72]);
$offer72 = json_encode(['message'=>'Two hundred cats and I walk away.','deal_decision'=>'PROPOSE','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>200],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'],['kind'=>'SPARE','by'=>'player','target'=>'npc']])]);
$p72 = stobeDealCaptureResponse($offer72, $n72, $player, getNpcData($n72) ?: [], '', 'surrender', 'npc');
$reject72 = json_encode(['message'=>"There's no third fifty hiding anywhere. Two hundred, and I stop swinging. That's the whole offer.",'deal_decision'=>'REJECT','deal_terms'=>'']);
$r72 = stobeDealCaptureResponse($reject72, $n72, $player, getNpcData($n72) ?: [], "Weth, two hundred isn't enough. Make it 350.");
check('item 72: his REJECT of the counter keeps his offer on the table',
    ($r72['offer_kept'] ?? false) === true && ($db->fetchOne("SELECT status FROM stobe_social_contract WHERE contract_id=$1", [strval($p72['id'] ?? '')])['status'] ?? '') === 'PROPOSED', [$p72, $r72]);
$accept72 = json_encode(['message'=>"Good. Two hundred, and we both stop. I'll get the cats out.",'deal_decision'=>'ACCEPT','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']])]);
$a72 = stobeDealCaptureResponse($accept72, $n72, $player, getNpcData($n72) ?: [], 'Fine Weth, two hundred. Deal, you can walk.');
$cats72 = array_values(array_filter($a72['terms'] ?? [], static fn($t) => ($t['kind'] ?? '') === 'GIVE_CATS'));
check('item 72: "fine, two hundred, deal" accepts HIS offer (same deal, he pays)',
    ($a72['id'] ?? '') === ($p72['id'] ?? 'x') && ($a72['status'] ?? '') === 'ACCEPTED' && ($cats72[0]['by'] ?? '') === 'npc', $a72);
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name=$1 AND status NOT IN ('COMPLETE','BREACHED_PLAYER','BREACHED_NPC','IMPOSSIBLE','REJECTED')", [$n72]);
// (b) his offer was already rejected (old server): the accept takes it up, not a player-pays combat deal
$p72b = stobeDealCaptureResponse($offer72, $n72, $player, getNpcData($n72) ?: [], '', 'surrender', 'npc');
stobeDealTransition(strval($p72b['id'] ?? ''), 'PROPOSED', 'REJECTED', ['rejected_by'=>'npc']);
$accept72b = json_encode(['message'=>'Good. Two hundred, and we both stop.','deal_decision'=>'ACCEPT','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']])]);
$a72b = stobeDealCaptureResponse($accept72b, $n72, $player, getNpcData($n72) ?: [], 'Fine Weth, two hundred. Deal, you can walk.');
$cats72b = array_values(array_filter($a72b['terms'] ?? [], static fn($t) => ($t['kind'] ?? '') === 'GIVE_CATS'));
check('item 72: accepting a just-rejected offer of his: he pays, kind surrender',
    ($a72b['kind'] ?? '') === 'surrender' && ($cats72b[0]['by'] ?? '') === 'npc', $a72b);
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name=$1 AND status NOT IN ('COMPLETE','BREACHED_PLAYER','BREACHED_NPC','IMPOSSIBLE','REJECTED')", [$n72]);
// (a) a REJECT that ends the talks still kills his offer
$p72c = stobeDealCaptureResponse($offer72, $n72, $player, getNpcData($n72) ?: [], '', 'surrender', 'npc');
stobeDealCaptureResponse(json_encode(['message'=>'Forget it. No deal.','deal_decision'=>'REJECT','deal_terms'=>'']), $n72, $player, getNpcData($n72) ?: [], 'Make it 350.');
check('item 72: "Forget it. No deal." withdraws his offer',
    ($db->fetchOne("SELECT status FROM stobe_social_contract WHERE contract_id=$1", [strval($p72c['id'] ?? '')])['status'] ?? '') === 'REJECTED');
check('item 72: "I\\'ll get the cats out" flips a player-paid term to her',
    (stobeDealFixCatsDirectionFromHerWords([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200]], "I'll get the cats out.")[0]['by'] ?? '') === 'npc');
check('item 72: "you\\'ll pay me, I\\'ll count the cats" does not flip',
    (stobeDealFixCatsDirectionFromHerWords([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200]], "You'll pay me first, then I'll count the cats.")[0]['by'] ?? '') === 'player');
$db->exec("DELETE FROM stobe_social_contract WHERE npc_name=$1", [$n72]);
$db->exec("DELETE FROM core_npc_master WHERE name=$1", [$n72]);

// ---------------------------------------------------------------- 12h5. deal-offer cap tiers''')
