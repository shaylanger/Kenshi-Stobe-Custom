#!/usr/bin/env python3
"""Cap-tier regression checks in tests/negotiation_engine_regression.php (before the item 45 block).

Usage: patch_r26_cap_tiers_tests.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'tests/negotiation_engine_regression.php'
s = f.read_text(encoding='utf-8')
if 'cap tiers:' in s:
    print('already patched', f)
    sys.exit(0)
anchor = "// ---------------------------------------------------------------- 12i. item 45"
assert s.count(anchor) == 1, 'anchor'
block = r'''// ---------------------------------------------------------------- 12h5. deal-offer cap tiers
$tierOf = static fn(string $n, array $d = []) => stobeNegWealthTier($n, $d)['tier'];
check('cap tiers: Hungry Bandit is tier 0', $tierOf('Karric [Hungry Bandit]') === 0);
check('cap tiers: Dust Bandit is tier 1', $tierOf('Haze [Dust Bandit]') === 1);
check('cap tiers: Samurai is tier 2', $tierOf('Samurai') === 2);
check('cap tiers: Shop Guard stays tier 1', $tierOf('Shop Guard Abilene') === 1);
check('cap tiers: Samurai Sergeant is tier 3', $tierOf('Ryo [Samurai Sergeant]') === 3);
check('cap tiers: Dust King (35k bounty) is tier 4', $tierOf('Dust King') === 4);
check('cap tiers: a boss with a 15k bounty is tier 3', $tierOf('Boss Whip', ['bounty'=>15000]) === 3);
check('cap tiers: Holy Lord Phoenix is tier 5', $tierOf('Holy Lord Phoenix') === 5);
// Item 53 / bug "carried reads the squad purse": 10,000 in the purse, Dust Bandit template max 200.
$capRich = stobeNegOfferCap('Vorl [Dust Bandit]', ['metadata'=>['money'=>10000]]);
check('cap tiers: a Dust Bandit with a 10,000 squad purse carries 200 (template max), offers 200',
    $capRich[0] === 200 && $capRich[1] === 200 && $capRich[3] === false, $capRich);
$capPoor = stobeNegOfferCap('Vorl [Dust Bandit]', ['metadata'=>['money'=>50]]);
check('cap tiers: no 35 % rule: 50 carried -> offers 50', $capPoor[0] === 50, $capPoor);
$capHungry = stobeNegOfferCap('Karric [Hungry Bandit]', ['metadata'=>['money'=>5000]]);
check('cap tiers: tier 0 is capped at 100', $capHungry[0] === 100, $capHungry);
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='Ryo [Samurai Sergeant]'");
$capSgt = stobeNegOfferCap('Ryo [Samurai Sergeant]', ['metadata'=>['money'=>300]]);
check('cap tiers: tier 3 offers up to 10,000 with a top-up', $capSgt[0] === 10000 && $capSgt[3] === true, $capSgt);
// A tier 3 surrender offer above what he carries gets the top-up purse mode, then a cooldown.
fixtureNpc('Ryo [Samurai Sergeant]', ['money'=>300,'money_observed_at'=>time(),'is_in_combat'=>true], 'Bread x1', 'A proud soldier.', '20/100', 'United Cities');
$offerSgt = json_encode(['message'=>'Twelve thousand, spare me.','deal_decision'=>'PROPOSE','deal_terms'=>json_encode([
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>12000],['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player'],['kind'=>'SPARE','by'=>'player','target'=>'npc']])]);
$rSgt = stobeDealCaptureResponse($offerSgt, 'Ryo [Samurai Sergeant]', $player, getNpcData('Ryo [Samurai Sergeant]') ?: [], '', 'surrender', 'npc');
$rowSgt = stobeNegFetchDeal(strval($rSgt['id'] ?? ''));
check('cap tiers: tier 3 offer capped at 10,000 and marked topup',
    str_contains(strval($rowSgt['terms'] ?? ''), '10000') && str_contains(strval($rowSgt['terms'] ?? ''), 'topup'), [$rSgt, $rowSgt['terms'] ?? null]);
$tokTopup = stobeNegTermActionToken(['kind'=>'GIVE_CATS','by'=>'npc','amount'=>10000,'purse'=>'topup'], $player);
check('cap tiers: no purse suffix while NEG_CATS_PURSE_MODES is off', $tokTopup === 'GIVE_CATS@' . $player . '@10000', $tokTopup);
$db->exec("DELETE FROM general_settings WHERE id='NEG_CATS_PURSE_MODES'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('NEG_CATS_PURSE_MODES', 'true')");
$tokTopup = stobeNegTermActionToken(['kind'=>'GIVE_CATS','by'=>'npc','amount'=>10000,'purse'=>'topup'], $player);
check('cap tiers: purse suffix with NEG_CATS_PURSE_MODES on', $tokTopup === 'GIVE_CATS@' . $player . '@10000@topup', $tokTopup);
$db->exec("DELETE FROM general_settings WHERE id='NEG_CATS_PURSE_MODES'");
$normCfg = getActionRuntimeConfig('chat');
$normCfg['deal_sanctioned_give'] = true;
check('cap tiers: the action normalizer keeps @topup', normalizeActionTagToken('GIVE_CATS@' . $player . '@10000@topup', $normCfg) === 'GIVE_CATS@' . $player . '@10000@topup');
check('cap tiers: the action normalizer keeps @exact', normalizeActionTagToken('GIVE_CATS@' . $player . '@200@exact', $normCfg) === 'GIVE_CATS@' . $player . '@200@exact');
$db->exec("UPDATE stobe_social_contract SET status='COMPLETE' WHERE contract_id=$1", [strval($rSgt['id'] ?? '')]);
check('cap tiers: after a top-up deal the same NPC is on cooldown', stobeNegTopupOnCooldown('Ryo [Samurai Sergeant]') === true);
$capCool = stobeNegOfferCap('Ryo [Samurai Sergeant]', ['metadata'=>['money'=>300]]);
check('cap tiers: on cooldown he offers only what he carries', $capCool[0] === 300 && $capCool[3] === false, $capCool);
$extras = stobeNegDealPromptExtras('Vorl [Dust Bandit]', ['metadata'=>['money'=>10000]]);
check('cap tiers / item 53: her prompt names the limit and forbids "I have no money"',
    str_contains($extras, 'the most you will pay in a deal is 200') && str_contains($extras, 'do not claim you have no money'), $extras);
$db->exec("UPDATE stobe_social_contract SET status='CANCELLED' WHERE npc_name='Ryo [Samurai Sergeant]'");
$db->exec("DELETE FROM core_npc_master WHERE name='Ryo [Samurai Sergeant]'");

'''
s = s.replace(anchor, block + anchor)
f.write_text(s, encoding='utf-8')
print('patched', f)
