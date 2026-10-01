<?php
require __DIR__ . '/../lib/bootstrap.php';
$db=$GLOBALS['db']; $ok=0;$bad=0; function t($n,$c,$d=null){global $ok,$bad; if($c){$ok++;echo "PASS $n\n";}else{$bad++;echo "FAIL $n ".json_encode($d)."\n";}}
$now=time();
$db->exec("DELETE FROM eventlog WHERE type='r15test'");
$db->exec("INSERT INTO eventlog(type,data,gamets,localts,ts) VALUES('r15test','x',100500,$1,$1)",[$now]);
$term=['by'=>'player','kind'=>'GIVE_CATS','amount'=>5000,'status'=>'AWAITING_PLAYER','dispatched_unix'=>$now-90,'deadline_unix'=>$now-30];
$combat=['contract_id'=>'r15','npc_name'=>'R15Npc','npc_serial'=>0,'kind'=>'combat','deadline_gamets'=>101000,'terms'=>'[]','term_state'=>'[]'];
$r=stobeNegEvaluateTerm($term,$combat,'Shay',$now);
t('41 paused (game time not passed) -> still waiting', $r['status']==='AWAITING_PLAYER', $r['status']);
$combat['deadline_gamets']=100000;
$r=stobeNegEvaluateTerm($term,$combat,'Shay',$now);
t('41 both passed -> UNMET', $r['status']==='UNMET', $r['status']);
$combat['deadline_gamets']=101000; $term2=$term; $term2['deadline_unix']=$now+30;
$r=stobeNegEvaluateTerm($term2,$combat,'Shay',$now);
t('41 real time not passed -> waiting', $r['status']==='AWAITING_PLAYER', $r['status']);
$combat['deadline_gamets']=0;
$r=stobeNegEvaluateTerm($term,$combat,'Shay',$now);
t('41 old deal without gamets -> UNMET as before', $r['status']==='UNMET', $r['status']);
$db->exec("DELETE FROM eventlog WHERE type='r15test'");
// 35 with an open deal
$db->exec("DELETE FROM stobe_social_contract WHERE contract_id='r15deal'");
$terms=json_encode([['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>200],['kind'=>'GIVE_ITEM','by'=>'npc','item'=>'Chewing Tobacco']]);
$state=json_encode([['i'=>0,'by'=>'player','kind'=>'GIVE_CATS','amount'=>200,'status'=>'VERIFIED'],['i'=>1,'by'=>'npc','kind'=>'GIVE_ITEM','item'=>'Chewing Tobacco','status'=>'SETTLE_QUEUED']]);
$db->exec("INSERT INTO stobe_social_contract(contract_id,npc_name,player_name,status,terms,term_state,kind) VALUES('r15deal','R15Npc','Shay','AWAITING_PERFORMANCE',$1::jsonb,$2::jsonb,'social')",[$terms,$state]);
$txt="We've still got unfinished business - I owe you that tobacco. And three hundred cats just to look at my face? You'd be paying for nothing.";
$c=stobeDealProgressAmountCheck($txt,'R15Npc',"Take off your Iron Hat. Three hundred cats for it. Deal?");
t('35 echo of player offer allowed', $c===null, $c);
$c=stobeDealProgressAmountCheck($txt,'R15Npc',"Take off your hat for a bit.");
t('35 only wrong sentence dropped', is_array($c) && str_contains($c['line'],'unfinished business') && !str_contains($c['line'],'three hundred'), $c);
$c=stobeDealProgressAmountCheck("You paid me 900 cats.",'R15Npc','');
t('35 whole line wrong -> progress line', is_array($c) && !str_contains($c['line'],'900'), $c);
$db->exec("DELETE FROM stobe_social_contract WHERE contract_id='r15deal'");
echo "ok=$ok bad=$bad\n";
