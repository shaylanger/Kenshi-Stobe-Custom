#!/usr/bin/env python3
"""A named price with conditions came back as REJECT, so it was never recorded.

Runs 2 and 3: "2000 for the hat", "3000 and a helmet swap" -- she refused the
player's offer by naming her own price, the model chose REJECT, and nothing was
recorded; the player had to restate it as an offer.

- Prompt rule: refusing the offer but naming your own price/conditions is COUNTER
  with those terms; REJECT only when you want no deal at all.
- Guard: REJECT that still carries terms with a kind, while her line names a Cats
  amount, is recorded as COUNTER.

Usage: patch_r23_reject_with_price_is_counter.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
lib = root / 'lib' / 'negotiation_phase1.php'
s = lib.read_text(encoding='utf-8')
if 'REJECT that names her own price' not in s:
    old_rule = """    $rules .= " If active_deals holds a COUNTERED or PROPOSED deal and the player now agrees to it, answer ACCEPT with those terms;"""
    new_rule = """    $rules .= " If you turn the offer down but name your own price or conditions (\\"2000 for the hat\\", \\"3000 and your helmet\\"), that is COUNTER with those terms, not REJECT; REJECT only when you want no deal at all.";
    $rules .= " If active_deals holds a COUNTERED or PROPOSED deal and the player now agrees to it, answer ACCEPT with those terms;"""
    old_guard = """    $decision = strtoupper(trim(strval($response['deal_decision'] ?? 'NONE')));
    $open = stobeDealOpenForNpc($npc);"""
    new_guard = """    $decision = strtoupper(trim(strval($response['deal_decision'] ?? 'NONE')));
    if ($decision === 'REJECT' && stobeDealRejectNamesOwnPrice($response)) {
        // A REJECT that names her own price is her counter-offer.
        $decision = 'COUNTER';
        stobeDealLog('info', 'Negotiation: REJECT with her own price recorded as COUNTER', ['npc'=>$npc]);
    }
    $open = stobeDealOpenForNpc($npc);"""
    helper = """/** A REJECT that names her own price: terms with a kind, and a Cats amount in her line. */
function stobeDealRejectNamesOwnPrice(array $response): bool {
    $terms = json_decode(trim(strval($response['deal_terms'] ?? '')), true);
    if (!is_array($terms)) return false;
    $hasCats = false;
    foreach ($terms as $t) {
        if (is_array($t) && strtoupper(strval($t['kind'] ?? '')) === 'GIVE_CATS' && intval($t['amount'] ?? 0) > 0) $hasCats = true;
    }
    if (!$hasCats) return false;
    return count(stobeDealSpokenCatsAmounts(strval($response['message'] ?? ''))) > 0;
}

function stobeDealCaptureResponse("""
    for o, n in [(old_rule, new_rule), (old_guard, new_guard)]:
        assert s.count(o) == 1, 'anchor: ' + o[:60]
        s = s.replace(o, n)
    assert s.count('function stobeDealCaptureResponse(') == 1
    s = s.replace('function stobeDealCaptureResponse(', helper, 1)
    lib.write_text(s, encoding='utf-8', newline='')
    print('patched', lib)

test = root / 'tests' / 'negotiation_engine_regression.php'
t = test.read_text(encoding='utf-8')
if 'REJECT that names her own price' not in t:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    add = """// ---------------------------------------------------------------- 12f. REJECT that names her own price is a COUNTER
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='NegTestTrader' AND status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE')");
$rejPrice = json_encode(['message'=>'Not for 500. 2000 cats for the hat.','deal_decision'=>'REJECT','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>2000],['kind'=>'GIVE_ITEM','by'=>'npc','to'=>'player','item'=>'Iron Hat']])]);
$rr = stobeDealCaptureResponse($rejPrice, 'NegTestTrader', $player, getNpcData('NegTestTrader') ?: [], "I'll give you 500 cats for your hat.", 'social');
check('REJECT that names her own price is recorded as COUNTER', ($rr['decision'] ?? '') === 'COUNTER' && ($rr['status'] ?? '') === 'COUNTERED', $rr);
$rejPlain = json_encode(['message'=>'No. The hat stays.','deal_decision'=>'REJECT','deal_terms'=>'']);
check('a plain REJECT stays REJECT', (stobeDealCaptureResponse($rejPlain, 'NegTestTrader', $player, getNpcData('NegTestTrader') ?: [], 'Then 600?', 'social')['decision'] ?? '') === 'REJECT');
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='NegTestTrader' AND status IN ('PROPOSED','COUNTERED','REJECTED','ACCEPTED','AWAITING_PERFORMANCE')");

"""
    assert t.count(anchor) == 1
    t = t.replace(anchor, add + anchor)
    test.write_text(t, encoding='utf-8', newline='')
    print('patched', test)
