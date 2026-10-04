#!/usr/bin/env python3
"""Item 118: a spoken offer ("I'll buy your Iron Hat. One cat, take it or leave it.") paid the NPC by voice.

Cause: lib/negotiation_voice.php judged each sentence alone; "1 cat, take it or leave it" matched the
hand-over cue "take it" and the earlier "I'll buy ..." sentence was only skipped, not held against it.
Fix:
  1. buy/sell/offer/"take it or leave it"/"in exchange" sentences are offers (never pay).
  2. A weak cue ("take it", "have it") after an offer sentence in the same message, with nothing owed
     on a deal, is part of the offer.
  3. At r <= STOBE_REL_NO_TRADE_MAX (item 103 no-trade) nothing moves by voice unless a deal says the
     player owes it (squadmates exempt).
Usage: python3 item118_voice_offer_no_payment.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / 'lib' / 'negotiation_voice.php'
s = p.read_text()
if 'item 118' in s:
    print('already patched:', p); sys.exit(0)

def rep(old, new):
    global s
    assert s.count(old) == 1, ('anchor not unique/missing', old[:80])
    s = s.replace(old, new)

rep("""    $reason = 'no_handover';
    foreach (preg_split('/(?<=[.!?;])\\s+|\\n+/', $trimmed) ?: [] as $sentence) {""",
"""    $reason = 'no_handover';
    $sawOffer = false; // item 118
    foreach (preg_split('/(?<=[.!?;])\\s+|\\n+/', $trimmed) ?: [] as $sentence) {""")

rep("""        if (preg_match("/\\b(if|unless|i'?ll|i will|i would|i'?d|i can|i could|would you|will you|want|wanna|how about|what about|maybe|later|tomorrow|once you|after you|when you)\\b/", $sentence)) { $reason = 'offer_or_future'; continue; }""",
"""        if (preg_match("/\\b(if|unless|i'?ll|i will|i would|i'?d|i can|i could|would you|will you|want|wanna|how about|what about|maybe|later|tomorrow|once you|after you|when you)\\b/", $sentence)) { $reason = 'offer_or_future'; $sawOffer = true; continue; }
        // Item 118: buying/selling proposals and ultimatums are offers, not payments.
        if (preg_match("/\\b(buy|sell|offer|offering|take it or leave it|or leave it|in exchange|trade you|best price|final price|final offer)\\b/", $sentence)) { $reason = 'offer_or_future'; $sawOffer = true; continue; }""")

rep("""    $cue = preg_match($cuePattern, $text) === 1;
""",
"""    $cue = preg_match($cuePattern, $text) === 1;
    // Item 118: "I'll buy your hat. 1 cat, take it." - a weak cue after an offer belongs to the offer.
    if ($sawOffer && !preg_match("/\\b(here'?s|here is|here are|here you go|here,|there you go|as promised|as agreed|i'?m (giving|paying|handing) you|i am (giving|paying|handing) you|i give you|i pay you|handing (you|it) over|keep the change)\\b/", $text)
        && stobeNegPlayerOwedCats($npc) <= 0 && count(stobeNegPlayerOwedItems($npc)) === 0) {
        return ['reason'=>'offer_or_future'] + $none;
    }
""")

rep("""        if ($parsed['reason'] !== 'handover') return '';
        $actions = [];""",
"""        if ($parsed['reason'] !== 'handover') return '';
        // Item 118 / 103: no trade at r <= STOBE_REL_NO_TRADE_MAX, so nothing moves by voice unless a deal says it's owed.
        if (function_exists('stobeRelValue') && defined('STOBE_REL_NO_TRADE_MAX')
            && !(function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData))
            && stobeNegPlayerOwedCats($npc) <= 0 && count(stobeNegPlayerOwedItems($npc)) === 0) {
            $rel = stobeRelValue($npcData, $player);
            if ($rel <= STOBE_REL_NO_TRADE_MAX) {
                stobeLogInfo('Voice hand-over blocked: no trade at this relationship (item 118)', ['player'=>$player, 'npc'=>$npc, 'r'=>$rel, 'message'=>$message]);
                return $player . ' talks as if handing something over, but nothing changed hands (no Cats or items were transferred): you will not trade with ' . $player . ' at all. Do not act as if you were paid.';
            }
        }
        $actions = [];""")

p.write_text(s)
print('patched', p)

t = root / 'tests' / 'negotiation_voice_regression.php'
s = t.read_text()
if 'item 118' not in s:
    old = """check('item quantity', ($p('Here are 2 bread')['items'][0]['qty'] ?? 0) === 2, $p('Here are 2 bread'));
"""
    new = old + """// Item 118: offers and ultimatums never pay; hostile NPCs (r <= -80) get nothing by voice.
$o = $p("Vel, I'll buy your Iron Hat. One cat, take it or leave it.");
check('item 118: "I\\'ll buy your Iron Hat. One cat, take it or leave it." does not pay', $o['cats'] === 0 && $o['reason'] === 'offer_or_future', $o);
check('item 118: "20 cats, take it or leave it" does not pay', $p('20 cats, take it or leave it.')['cats'] === 0, $p('20 cats, take it or leave it.'));
check('item 118: "I\\'ll buy your hat. 5 cats, take it." does not pay', $p("I'll buy your hat. 5 cats, take it.")['cats'] === 0, $p("I'll buy your hat. 5 cats, take it."));
check('item 118: "I\\'ll pay you 30 cats for it" does not pay', $p("I'll pay you 30 cats for it.")['cats'] === 0);
check('item 118: "Sell me the hat, 10 cats" does not pay', $p('Sell me the hat, 10 cats.')['cats'] === 0);
check('item 118: a gift with a clear cue still pays', $p('Here are 50 cats, friend.')['cats'] === 50, $p('Here are 50 cats, friend.'));
$db->exec("UPDATE core_npc_master SET extended_data=$1::jsonb WHERE name=$2", [json_encode(['relationships'=>[$player=>['aff'=>-80,'type'=>'enemy']]]), $npc]);
$wire = '';
ob_start(function (string $chunk) use (&$wire): string { $wire .= $chunk; return ''; });
$note = stobeNegVoiceHandover($npc, getNpcData($npc) ?: ['name'=>$npc], $player, 'Here are 50 cats', 1000);
ob_end_flush();
check('item 118: r=-80 and no deal: nothing dispatched', !str_contains($wire, 'GIVE_CATS'), $wire);
check('item 118: r=-80 note says nothing changed hands', str_contains($note, 'nothing changed hands'), $note);
$db->exec("UPDATE core_npc_master SET extended_data='{}'::jsonb WHERE name=$1", [$npc]);
"""
    assert s.count(old) == 1, 'test anchor 1'
    s = s.replace(old, new)
    old2 = """check('NPC gets a context note', str_contains($note, '200 Cats'), $note);
"""
    new2 = old2 + """$o = $p("Here are your 20 cats.");
check('item 118: "Here are your 20 cats." with an accepted deal pays', $o['cats'] === 20 && $o['reason'] === 'handover', $o);
check('item 118: offer with an accepted deal still does not pay', $p("I'll buy your hat. 1 cat, take it or leave it.")['cats'] === 0);
"""
    assert s.count(old2) == 1, 'test anchor 2'
    s = s.replace(old2, new2)
    t.write_text(s)
    print('patched', t)
