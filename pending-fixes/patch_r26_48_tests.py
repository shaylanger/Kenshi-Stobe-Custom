#!/usr/bin/env python3
"""Item 48 regression checks in tests/negotiation_engine_regression.php (before the item 45 block).

Usage: patch_r26_48_tests.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'tests/negotiation_engine_regression.php'
s = f.read_text(encoding='utf-8')
if 'item 48:' in s:
    print('already patched', f)
    sys.exit(0)
anchor = "// ---------------------------------------------------------------- 12i. item 45"
assert s.count(anchor) == 1, 'anchor'
block = r'''// ---------------------------------------------------------------- 12h4. item 48: knocked out or dead NPCs don't negotiate
$koEvent = static function (string $type, string $data, string $people, int $at) use ($db): void {
    $db->exec("INSERT INTO eventlog (type, ts, gamets, data, sess, localts, people, location) VALUES ($1,$2,1000,$3,'pending',$2,$4,'')",
        [$type, $at, $data, $people]);
};
$db->exec("DELETE FROM eventlog WHERE data LIKE 'NegTestKo%' OR people LIKE '%hand_4294967000%'");
fixtureNpc('NegTestKo', ['money'=>500, 'money_observed_at'=>time(), 'storage_id'=>'hand_-296', 'is_in_combat'=>true], 'Bread x1', 'A tough raider.', '20/100');
$t48 = time() - 30;
check('item 48: no events -> conscious', stobeNegNpcOutState('NegTestKo') === '');
$koEvent('knockout', 'Shay: Knocked out by a Chisa Katana from NegTestKo', '["Shay|hand_1","NegTestKo|hand_4294967000"]', $t48);
check('item 48: knocking someone else out leaves her conscious', stobeNegNpcOutState('NegTestKo') === '');
$koEvent('knockout', 'NegTestKo: was Knocked Out.', '["NegTestKo|hand_4294967000"]', $t48 + 1);
check('item 48: knockout -> unconscious', stobeNegNpcOutState('NegTestKo') === 'unconscious');
@unlink(stobeNegThrottleMarker('initiative'));
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name='NegTestKo'");
stobeNegConsiderInitiatives('major_damage', 'NegTestKo: took a major hit (health 10%)', '["NegTestKo|hand_4294967000"]', 1000);
check('item 48: no surrender offer from a knocked-out NPC',
    $db->fetchOne("SELECT COUNT(*) AS c FROM stobe_negotiation_directive WHERE npc_name='NegTestKo'")['c'] == 0);
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='NegTestKo' AND status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE')");
$propose48 = json_encode(['message'=>'Pay me.','deal_decision'=>'PROPOSE','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']])]);
$d48 = stobeDealCaptureResponse($propose48, 'NegTestKo', $player, getNpcData('NegTestKo') ?: [], '', 'combat', 'npc');
$db->exec("UPDATE stobe_social_contract SET updated_at=NOW() - INTERVAL '11 minutes' WHERE contract_id=$1", [strval($d48['id'] ?? '')]);
stobeNegTick();
check('item 48: an offer does not expire while she is knocked out',
    ($db->fetchOne("SELECT status FROM stobe_social_contract WHERE contract_id=$1", [strval($d48['id'] ?? '')])['status'] ?? '') === 'PROPOSED', $d48);
stobeNegQueueDirective('NegTestKo', 'assist', '', ['actions'=>[], 'instruction'=>'x'], false);
check('item 48: a queued directive waits while she is knocked out', stobeNegClaimDirective(['NegTestKo']) === null);
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name='NegTestKo'");
$koEvent('recovered', 'NegTestKo: regained consciousness', '["NegTestKo|hand_4294967000"]', $t48 + 2);
check('item 48: recovered -> conscious again', stobeNegNpcOutState('NegTestKo') === '');
stobeNegResumeAfterKnockout('NegTestKo: regained consciousness');
$resume = $db->fetchOne("SELECT payload FROM stobe_negotiation_directive WHERE npc_name='NegTestKo' AND kind='resume_deal' ORDER BY id DESC LIMIT 1");
check('item 48: on waking she brings the open offer up again',
    is_array($resume) && str_contains(strval($resume['payload']), '200') && str_contains(strval($resume['payload']), 'knocked out'), $resume);
check('item 48: the resumed offer is open again', (stobeDealOpenForNpc('NegTestKo')['contract_id'] ?? '') === ($d48['id'] ?? 'x'));
$claimed48 = stobeNegClaimDirective(['NegTestKo']);
check('item 48: the resume directive is claimed once she is awake', ($claimed48['kind'] ?? '') === 'resume_deal', $claimed48);
$koEvent('knockout', 'NegTestKo: was Knocked Out.', '["NegTestKo|hand_4294967000"]', $t48 + 3);
$koEvent('death', 'NegTestKo: has died', '["NegTestKo|hand_4294967000"]', $t48 + 3);
check('item 48: knockout then death in the same second -> dead', stobeNegNpcOutState('NegTestKo') === 'dead');
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='NegTestKo' AND status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE')");
$db->exec("DELETE FROM stobe_negotiation_directive WHERE npc_name='NegTestKo'");
$db->exec("DELETE FROM eventlog WHERE data LIKE 'NegTestKo%' OR people LIKE '%hand_4294967000%'");
$db->exec("DELETE FROM core_npc_master WHERE name='NegTestKo'");

'''
s = s.replace(anchor, block + anchor)
f.write_text(s, encoding='utf-8')
print('patched', f)
