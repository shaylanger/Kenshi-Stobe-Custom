#!/usr/bin/env python3
"""Bug 130 regression check: an accept above the cap becomes a counter at the cap, and her
"Four hundred, then." is rewritten to the capped terms.

Usage: patch_r22_bug130_test.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'tests' / 'negotiation_engine_regression.php'
text = path.read_text(encoding='utf-8')
if 'bug 130' in text:
    print('already patched')
    sys.exit(0)
anchor = """check('she accepts the player counter (bug 129)', ($rc['decision'] ?? '') === 'ACCEPT' && ($rowc['status'] ?? '') === 'ACCEPTED', [$rc, $rowc['status'] ?? null]);
"""
add = """// Bug 130: rich common bandit (cap 300) accepts "make it 400": recorded as his counter at 300, words follow.
fixtureNpc('NegTestBandit130', ['money'=>10000,'money_observed_at'=>time(),'is_in_combat'=>true], 'Bread x2', 'A timid coward.', '20/100');
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='NegTestBandit130' AND status NOT IN ('COMPLETE','BREACHED_PLAYER','BREACHED_NPC','IMPOSSIBLE')");
$offer300 = json_encode(['message'=>'300 cats, let me go.','deal_decision'=>'PROPOSE','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>300],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'],['kind'=>'SPARE','by'=>'player','target'=>'npc']])]);
$r130 = stobeDealCaptureResponse($offer300, 'NegTestBandit130', $player, getNpcData('NegTestBandit130') ?: [], '', 'surrender', 'npc');
$say400 = 'Four hundred, then. Cats are yours, and I walk.';
$accept400 = json_encode(['message'=>$say400,'deal_decision'=>'ACCEPT','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>400],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'],['kind'=>'SPARE','by'=>'player','target'=>'npc']])]);
$rk = stobeDealCaptureResponse($accept400, 'NegTestBandit130', $player, getNpcData('NegTestBandit130') ?: [], "Make it 400 and we're done.", 'surrender');
$rowk = stobeNegFetchDeal(strval($r130['id'] ?? ''));
check('accept above the cap is a counter at the cap (bug 130)', ($rk['decision'] ?? '') === 'COUNTER' && ($rowk['status'] ?? '') === 'COUNTERED'
    && str_contains(strval($rowk['terms'] ?? ''), '300') && !str_contains(strval($rowk['terms'] ?? ''), '400'), [$rk, $rowk['status'] ?? null, $rowk['terms'] ?? null]);
$ak = stobeDealSpeechAmountCheck($say400, 'NegTestBandit130', $rk);
check('her "Four hundred" is rewritten to the capped terms (bug 130)', is_array($ak) && str_contains($ak['line'], '300') && !str_contains($ak['line'], '400'), $ak);
check('"Four hundred, then." is a spoken amount (bug 130)', in_array(400, stobeDealSpokenCatsAmounts($say400), true), stobeDealSpokenCatsAmounts($say400));
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='NegTestBandit130' AND status NOT IN ('COMPLETE','BREACHED_PLAYER','BREACHED_NPC','IMPOSSIBLE')");
"""
assert text.count(anchor) == 1, 'anchor'
text = text.replace(anchor, anchor + add)
# The bug 96/129 bandit carried 50 (cap 17): accepting 45 is now a counter. Give him 1000 (cap 300).
old96 = "fixtureNpc('NegTestBandit96', ['money'=>50,"
assert text.count(old96) == 1, 'fixture 96'
text = text.replace(old96, "fixtureNpc('NegTestBandit96', ['money'=>1000,")
text = text.replace("foreach ([$player, 'NegTestBandit', 'NegTestTrader'] as $n) {",
                    "foreach ([$player, 'NegTestBandit', 'NegTestTrader', 'NegTestBandit130'] as $n) {")
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
