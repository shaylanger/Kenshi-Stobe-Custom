#!/usr/bin/env python3
"""Bug 122: cats paid up front for something refused are never refunded.

Run 9 (test 11): "Here's 500 cats, now give me your weapon." -> the 500
moved (by design), Rhuk refused ("Keep your coin, I'm keeping my weapon")
but kept the cats: no deal was recorded, and refunds only exist for
recorded deals. After a conditional voice payment ("... now/for/if/in
exchange ...") with no deal for that NPC in the last 2 minutes, queue a
refund directive; it goes out in the same turn (stobeNegAttachPendingForChat).
A plain gift ("here, have 100 cats") stays given.

Usage: patch_r21_bug122_prepay_refund.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
edits = [
    (root / 'lib' / 'negotiation_voice.php',
     "        $GLOBALS['STOBE_VOICE_HANDOVER_NPC'] = $npc; // bug 34: settle her side before this request ends\n",
     "        $GLOBALS['STOBE_VOICE_HANDOVER_NPC'] = $npc; // bug 34: settle her side before this request ends\n"
     "        $GLOBALS['STOBE_VOICE_HANDOVER_CATS'] = intval($parsed['cats']); // bug 122\n"
     "        $GLOBALS['STOBE_VOICE_HANDOVER_MESSAGE'] = $message;\n"),
    (root / 'lib' / 'negotiation_engine.php',
     "function stobeNegSettleAfterHandover(string $npc, int $maxMs = 4000): void {\n",
     r"""/** Bug 122: cats paid "for" something with no deal behind it come back. */
function stobeNegRefundUnearnedPrepayment(string $npc, string $player): void {
    $cats = intval($GLOBALS['STOBE_VOICE_HANDOVER_CATS'] ?? 0);
    $message = strtolower(strval($GLOBALS['STOBE_VOICE_HANDOVER_MESSAGE'] ?? ''));
    if ($cats <= 0 || trim($npc) === '' || trim($player) === '') return;
    // A plain gift stays given; only a payment tied to a request is refundable.
    if (!preg_match('/\b(now|for|if|so that|in exchange|in return|and you|then you)\b/', $message)) return;
    $deal = $GLOBALS['db']->fetchOne(
        "SELECT contract_id FROM stobe_social_contract
          WHERE LOWER(npc_name)=LOWER($1)
            AND status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE','COMPLETE')
            AND updated_at > NOW() - interval '120 seconds' LIMIT 1",
        [$npc]
    );
    if (is_array($deal)) return; // a deal covers it, with its own refund rules
    stobeNegQueueDirective($npc, 'refund', '', [
        'actions'=>['GIVE_CATS@' . $player . '@' . $cats],
        'instruction'=>'You did not agree to what ' . $player . ' asked, so you hand back the ' . $cats . ' Cats they just gave you. Say so in one short line.',
    ], true);
    stobeLogInfo('Prepayment refunded: no deal behind it (bug 122)', ['npc'=>$npc, 'cats'=>$cats]);
}

function stobeNegSettleAfterHandover(string $npc, int $maxMs = 4000): void {
"""),
    (root / 'processor' / 'chat.php',
     """    try { stobeNegSettleAfterHandover($targetNpc); } catch (Throwable $settleError) {
        stobeLogWarn('Settle after hand-over failed', ['npc'=>$targetNpc, 'error'=>$settleError->getMessage()]);
    }
""",
     """    try { stobeNegSettleAfterHandover($targetNpc); } catch (Throwable $settleError) {
        stobeLogWarn('Settle after hand-over failed', ['npc'=>$targetNpc, 'error'=>$settleError->getMessage()]);
    }
    if (function_exists('stobeNegRefundUnearnedPrepayment')) { // bug 122
        try { stobeNegRefundUnearnedPrepayment($targetNpc, $playerName); } catch (Throwable $refundError) {
            stobeLogWarn('Prepayment refund failed', ['npc'=>$targetNpc, 'error'=>$refundError->getMessage()]);
        }
    }
"""),
]
for path, old, new in edits:
    text = path.read_text(encoding='utf-8')
    marker = new.strip().splitlines()[0] if 'bug 122' not in old else ''
    if 'bug 122' in text and ('STOBE_VOICE_HANDOVER_CATS' in text or 'RefundUnearnedPrepayment' in text):
        print('already patched', path)
        continue
    assert text.count(old) == 1, 'anchor not found exactly once in %s' % path
    path.write_text(text.replace(old, new), encoding='utf-8', newline='')
    print('patched', path)
