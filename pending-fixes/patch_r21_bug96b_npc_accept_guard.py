#!/usr/bin/env python3
"""Bug 96 (again): "We are done here." accepted an NPC's surrender offer.

The round 20 fix keeps the "player has just accepted" note out of the prompt,
but the model can still answer deal_decision ACCEPT on its own. On a deal the
NPC proposed, ACCEPT means "the player took it", so it only stands when the
player's line really accepts (stobeNegLooksLikeAcceptance); otherwise NONE.

Usage: patch_r21_bug96b_npc_accept_guard.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_phase1.php'
text = path.read_text(encoding='utf-8')
old = """    if (!in_array($decision, ['ACCEPT','COUNTER','PROPOSE'], true)) return ['ok'=>false,'error'=>'invalid_decision'];
"""
new = old + """    // Bug 96: on an NPC's own offer, ACCEPT stands only if the player's line accepts it.
    if ($decision === 'ACCEPT' && $open !== null && strval($open['proposer'] ?? 'player') === 'npc'
        && function_exists('stobeNegLooksLikeAcceptance')
        && !stobeNegLooksLikeAcceptance(strtolower(trim($playerMessage)))) {
        stobeDealLog('warn', 'Negotiation: ACCEPT ignored, the player did not accept the NPC offer (bug 96)',
            ['npc'=>$npc, 'message'=>$playerMessage]);
        return ['ok'=>true,'decision'=>'NONE'];
    }
"""
if 'ACCEPT ignored, the player did not accept' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
