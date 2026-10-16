<?php
// imm26 WP-R2 (row 24-b, Shay 2026-10-16): "Let's consider <region> as a general area" -> the NPC OFFERS A FIRST LEG (PROPOSE only, server-written reply, no
// movement action) to the grounded destination (native id if in range, else the nearest known town in the region, rumoured towns allowed); the next explicit
// "Yes" is the ordinary ACCEPT -> TRAVEL_LOCATION. Harness copied from imm26_sfL_region_waypoint_regression.php (fixture DB, no network, no live DB).
// Run: php tests/imm26_regionroute_regression.php
require_once __DIR__.'/../lib/travel_companionship.php';
require_once __DIR__.'/../lib/area_goal_integration.php';
require_once __DIR__.'/../lib/processor_area_goal_hook.php';
if (!defined('PGSQL_TRANSACTION_IDLE')) define('PGSQL_TRANSACTION_IDLE', 0);

class AreaGoalFixtureDb {
    public array $events=[]; public array $zones=[]; public array $world=[];
    function transactionStatus() { return PGSQL_TRANSACTION_IDLE; }
    function exec($sql) { return true; }
    function fetchAll($sql,$args=[]) {
        if (str_contains($sql,'FROM location_zones')) return $this->zones;
        if (str_contains($sql,'FROM stobe_world_town')) {
            if (str_contains($sql,'discovered')) return array_map(static fn($w)=>['name'=>$w['zone_name'],'discovered'=>$w['discovered']],$this->world);
            return array_map(static fn($w)=>['zone_name'=>$w['zone_name'],'x'=>$w['x'],'y'=>$w['y'],'z'=>$w['z']],$this->world);
        }
        return [];
    }
    function fetchOne($sql,$args=[]) {
        if (str_contains($sql,'pg_try_advisory_lock')) return ['acquired'=>true];
        if (str_contains($sql,'pg_advisory_unlock')) return ['unlocked'=>true];
        if (str_contains($sql,'to_regclass')) return ['present'=>true];
        $type=str_contains($sql,"type='travel_agreement'")?'travel_agreement':(str_contains($sql,"type='region_plan'")?'region_plan':'');
        if ($type==='') return null;
        $prefix=strval($args[0]??'');$time=intval($args[1]??PHP_INT_MAX);
        $matches=array_values(array_filter($this->events,static fn($e)=>$e['type']===$type && $e['gamets']<=$time && str_starts_with($e['data'],$prefix)));
        usort($matches,static fn($a,$b)=>[$b['gamets'],$b['seq']]<=>[$a['gamets'],$a['seq']]);
        return $matches[0]??null;
    }
}
$GLOBALS['areaSerials']=['Laru'=>2543823360,'Shay'=>3454101504,'Other'=>7654321];
$GLOBALS['STOBE_TRAVEL_SPEAKER']='Shay';
function stobeResolveLiveParticipantSerial($name){return intval($GLOBALS['areaSerials'][$name]??0);}
function normalizeCoreNpcMetadata($metadata){return is_array($metadata)?$metadata:[];}
function normalizeParticipantNameToken($name){return trim((string)$name);}
function stobeLogWarn($m,$c=[]){ }
function stobeLogInfo($m,$c=[]){ }
function stobePlayerOrderGate($actor,$npc,$action){return '';}
function stobeNonFactionMinorOrderCommands(){return ['FOLLOW','STOP_FOLLOW','MOVE_TO','TRAVEL_LOCATION'];}
function normalizeActionTagToken($action,$config=[]){return (string)$action;}
function stobeBuildActionConfigForNpc($mode,$npc){return [];}
function stobeResolveTravelLocationFromVisitedZones($name){return false;}   // NOTHING resolves through the visited zones: only the region pin can make a town resolve
function stobeDestinationSource($source){return [];}
function stobeDestinationKnownRegions($a,$n,$t){return $GLOBALS['TEST_KNOWN_REGIONS']??[];}   // the NPC's own region memory (the only way a native candidate proves a region: the candidate normaliser drops spatial.region_name)
function normalizeNpcMetadataPayload($m){return is_array($m)?$m:[];}
function normalizeStorageIdToken($s){return trim((string)$s);}
function stobeEnsureWorldTownTable(): bool {return true;}   // data_functions.php is not loaded here; the fixture db serves stobe_world_town
function stobeSanitizeTravelLocationToken(string $v,int $m=120): string {return trim(substr(trim(preg_replace('/\s+/',' ',str_replace(['[',']','@','|',';'],'',$v)) ?? ''),0,$m));}   // chat_helper_functions.php is not loaded here
function normalizeNpcExtendedDataPayload($data){return is_array($data)?$data:[];}
function sanitizeForKenshi($s){return (string)$s;}
function stobeDestinationCatalog(){return [['regions'=>[
 ['name'=>'Vain','provenance'=>['fixture catalog']],['name'=>'The Pits','provenance'=>['fixture catalog']],['name'=>'Border Zone','provenance'=>['fixture catalog']]]]];}
function storeEvent($type,$time,$gamets,$data,$status='pending',$a='',$b='', $c=false){
 static $seq=0; $event=['type'=>$type,'time'=>$time,'gamets'=>$gamets,'data'=>$data,'status'=>$status,'seq'=>++$seq];
 $GLOBALS['db']->events[]=$event;return $event;
}
function ac(bool $ok,string $label){global $n;if(!$ok)throw new RuntimeException('FAIL '.$label);++$n;}

$n=0;
$scope=['campaign_id'=>'campaign-1','actor_id'=>'2543823360','speaker_id'=>'3454101504'];
$stumble=['id'=>'local:world:2543823360:77','actor_serial'=>2543823360,'observed'=>true,'observed_unix'=>time(),'reachability'=>'path_confirmed',
    'kind'=>'known_place','label'=>'Stumble Inn','x'=>100.0,'y'=>0.0,'z'=>200.0,'spatial'=>['anchor_type'=>'town','anchor_name'=>'Stumble Inn','town_name'=>'Stumble Inn']];
function mk_npc(int $aff,float $x,float $z,array $cands): array {
    return ['name'=>'Laru','extended_data'=>['relationships'=>['Shay'=>['aff'=>$aff]]],
        'metadata'=>['environment'=>['x'=>$x,'y'=>0.0,'z'=>$z,'town_name'=>'Stack'],'travel_destinations'=>$cands]];
}
$npc=mk_npc(70,0.0,0.0,[$stumble]);
$key=stobeTravelKey('Laru','Shay');
// tagged world: Vain towns (two never discovered), one Border Zone town, one untagged place
$TOWNS=[
 'Hive Village NE'=>['region'=>'Vain','source'=>'fixture'],'Hive Village CE'=>['region'=>'Vain','source'=>'fixture'],'Hive Village S'=>['region'=>'Vain','source'=>'fixture'],
 'The Hub'=>['region'=>'Border Zone','source'=>'fixture'],
];
function fresh_world(array $towns=null): void {
    global $TOWNS;
    $GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS']=$towns??$TOWNS;
    $db=new AreaGoalFixtureDb();
    $w=static fn($name,$x,$z,$disc)=>['zone_name'=>$name,'x'=>$x,'y'=>10.0,'z'=>$z,'discovered'=>$disc?'t':'f'];
    $db->world=[$w('Hive Village NE',40000.0,40000.0,false),$w('Hive Village CE',20000.0,10000.0,false),$w('Hive Village S',30000.0,-10000.0,true),
        $w('The Hub',5000.0,5000.0,true),$w('Stumble Inn',100.0,200.0,true)];
    $GLOBALS['db']=$db;$GLOBALS['STOBE_TRAVEL_STATE']=[];
    unset($GLOBALS['TEST_KNOWN_REGIONS'],$GLOBALS['STOBE_TRAVEL_REGION_HINT'],$GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN'],$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']);
}
/** One player turn exactly as processor/chat.php runs it: region hook first, ordinary travel capture when the hook declines. */
function rr_turn(string $quote,array $model,int $gamets,array $scope,array $npc,string &$text,array &$actions,string $town='Stack'): bool {
    $turn=stobeRegionPlanBegin(true,$scope,$quote,$gamets);
    if(!is_array($turn))throw new RuntimeException('turn setup failed');
    $raw=json_encode($model);
    $handled=stobeAreaGoalProcessorHook(false,false,true,'',false,false,$text,$text,$turn,$raw,'Laru',$npc,'Shay',$gamets,$actions,[],$town);
    if(!$handled){
        stobeTravelCapture($raw,'Laru',$npc,'Shay',$quote,$gamets,$text,$actions);
        stobeTravelValidateOrders('Laru',$npc,'Shay',$gamets,$text,$actions);
    }
    return $handled;
}
function plan_rows(string $stage=''): array {
    $out=[];
    foreach ($GLOBALS['db']->events as $e) if ($e['type']==='region_plan') {
        $j=json_decode(substr($e['data'],strpos($e['data'],'{')),true);
        if (is_array($j) && ($stage==='' || ($j['stage']??'')===$stage)) $out[]=$j;
    }
    return $out;
}
$none=['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'NONE'];
$consider="Let's consider Vain as a general area, not an exact spot.";
$accept=static fn(string $dest)=>['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'ACCEPT','travel_kind'=>'same_route','travel_leader'=>'npc',
    'travel_destination'=>$dest,'travel_reason'=>'','travel_player_quote'=>"Yes, let's go."];
function bad_text(string $t): bool { return (bool)preg_match("/current offer|clear answer|confirmed reachable point/i",$t); }

// ---- 1. consider wording -> awaiting_route, then route_ready + PROPOSED agreement with regional_goal + zero actions (undiscovered town, nothing resolves via visited zones)
fresh_world();
$t='Fine.';$a=['TRAVEL_LOCATION@model-invented'];
$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
$aw=plan_rows('awaiting_route');$rd=plan_rows('route_ready');
ac($h,'1: the region hook owns the consider turn');
ac(count($aw)===1 && ($aw[0]['proposed_region']??'')==='Vain' && ($aw[0]['offer_source']??'')==='unpaired_concept','1: the conceptual state awaiting_route is stored first (Vain, no earlier NPC suggestion)');
ac(count($rd)===1 && ($rd[0]['proposed_region']??'')==='Vain' && ($rd[0]['endpoint_label']??'')==='Hive Village CE' && ($rd[0]['movement_consent']??true)===false,
    '1: a route_ready row names the NEAREST Vain town (undiscovered Hive Village CE beats NE and S)');
ac(floatval($rd[0]['endpoint_point']['x']??-1)===20000.0 && floatval($rd[0]['endpoint_point']['z']??-1)===10000.0 && ($rd[0]['endpoint_region_evidence']??'')==='world_town_region'
    && ($rd[0]['endpoint_source']??'')==='world_town_region','1: the route_ready row carries the grounded point and the evidence value');
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(is_array($trip) && $trip['status']==='PROPOSED' && ($trip['execution']['phase']??'')==='proposed' && $trip['destination']==='Hive Village CE'
    && ($trip['destination_point']['source']??'')==='visited_location' && floatval($trip['destination_point']['x'])===20000.0,'1: the PROPOSED agreement points at the town coordinates');
ac(($trip['regional_goal']['region']??'')==='Vain' && ($trip['regional_goal']['endpoint_label']??'')==='Hive Village CE'
    && ($trip['regional_goal']['endpoint_region_evidence']??'')==='world_town_region' && ($trip['regional_goal']['endpoint_source']??'')==='world_town_region'
    && intval($trip['regional_goal']['endpoint_actor_serial']??0)===2543823360 && ($trip['regional_goal']['goal_source']??'')==='player_considers_region',
    '1: the PROPOSED agreement carries regional_goal Vain with the world-town evidence');
ac(($rd[0]['agreement_id']??'x')===($trip['agreement_id']??'y') && ($trip['agreement_id']??'')!=='','1: the route_ready row points at the same agreement id');
ac($a===[],'1: zero actions (the model-invented TRAVEL_LOCATION is purged, nothing moves)');
ac(str_contains($t,'Hive Village CE') && str_contains($t,'Vain') && str_contains($t,'Shall we set out') && !bad_text($t),'1: the server-written reply names the region and the first leg and asks; it is not the old fallback');
ac(!isset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']) && !isset($GLOBALS['STOBE_TRAVEL_REGION_HINT']),'1: no request-local pin or hint is left behind');
ac(stobeTravelResolvePlan('Laru',$npc,'Hive Village S',null)===false,'1: after the turn a rumoured town does NOT resolve again (the pin was one-shot, only the chosen town)');

// ---- 2. the next explicit Yes is the ordinary ACCEPT -> TRAVEL_LOCATION to the town xyz
$t='Good.';$a=['TRAVEL_LOCATION@Hive Village CE'];
$h2=rr_turn("Yes, let's go.",$accept('Hive Village CE'),1010,$scope,$npc,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(!$h2 && is_array($trip) && $trip['status']==='ACCEPTED' && ($trip['execution']['phase']??'')==='accepted','2: Yes is the ordinary ACCEPT (the region hook declines the turn)');
ac($a===['TRAVEL_LOCATION@Hive Village CE'],'2: ACCEPTED dispatches exactly one TRAVEL_LOCATION to the town');
ac(floatval($trip['destination_point']['x'])===20000.0 && floatval($trip['destination_point']['y'])===10.0 && floatval($trip['destination_point']['z'])===10000.0,'2: the destination point is the town xyz');
ac(($trip['regional_goal']['region']??'')==='Vain' && ($trip['regional_goal']['endpoint_region_evidence']??'')==='world_town_region','2: the ACCEPTED agreement keeps regional_goal Vain (old-state carry, unchanged)');
ac(stobeAreaGoalTripStateValid($trip,'Laru','Shay'),'2: the ACCEPTED state validates for the resume path');
// save/load: the stored row read back keeps the goal and the same agreement
$agreement=$trip['agreement_id'];$GLOBALS['STOBE_TRAVEL_STATE']=[];
$re=stobeTravelRead('Laru','Shay',1100);
ac(is_array($re) && $re['agreement_id']===$agreement && ($re['regional_goal']['endpoint_label']??'')==='Hive Village CE','2: save/load: agreement id and regional_goal survive the event log');

// ---- 3. no tagged town in the region -> cannot_route_yet, and NOT the "no current offer" text
fresh_world();
$t='Fine.';$a=[];
$h=rr_turn("Let's consider The Pits as a general area.",$none,1000,$scope,$npc,$t,$a);
ac($h && str_contains($t,'confirmed reachable point') && !str_contains($t,'current offer') && !str_contains($t,'clear answer'),'3: a region with no tagged town says it cannot route yet (honest), not "no current offer"');
ac(count(plan_rows('route_ready'))===0 && count(plan_rows('awaiting_route'))===1 && !isset($GLOBALS['STOBE_TRAVEL_STATE'][$key]) && $a===[],'3: plan stays awaiting_route, no route_ready row, no trip, no action');
fresh_world([]);   // an empty data source
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac(str_contains($t,'confirmed reachable point') && !isset($GLOBALS['STOBE_TRAVEL_STATE'][$key]),'3: an empty town table gives the same honest answer');
fresh_world();unset($GLOBALS['db']->world[1]);$GLOBALS['db']->world=array_values($GLOBALS['db']->world);   // CE not in the world
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac(($GLOBALS['STOBE_TRAVEL_STATE'][$key]['destination']??'')==='Hive Village S','3: a tagged town that the server does not know (no coordinates) is skipped; the next one is chosen');

// ---- 4. current town excluded
fresh_world();
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npc,$t,$a,'Hive Village CE');
ac(($GLOBALS['STOBE_TRAVEL_STATE'][$key]['destination']??'')==='Hive Village S' && !str_contains($t,'Hive Village CE'),'4: the town the NPC stands in is never the first leg');
// ---- 5. nearest wins: the NPC stands right next to NE
fresh_world();
$npcNE=mk_npc(70,39000.0,39000.0,[$stumble]);
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npcNE,$t,$a);
ac(($GLOBALS['STOBE_TRAVEL_STATE'][$key]['destination']??'')==='Hive Village NE','5: the nearest Vain town wins from where the NPC is');
// unit: ordering, ties, region key, no position
$zones=[['name'=>'B Town','x'=>1000.0,'y'=>0.0,'z'=>0.0,'discovered'=>false],['name'=>'A Town','x'=>-1000.0,'y'=>5.0,'z'=>0.0,'discovered'=>false],
        ['name'=>'C Town','x'=>0.0,'y'=>0.0,'z'=>1000.0,'discovered'=>true],['name'=>'Far','x'=>9000.0,'y'=>0.0,'z'=>0.0,'discovered'=>true],['name'=>'Elsewhere','x'=>1.0,'y'=>0.0,'z'=>0.0]];
$tags=['b town'=>['name'=>'B Town','region'=>'The Swamp'],'a town'=>['name'=>'A Town','region'=>'Swamp'],'c town'=>['name'=>'C Town','region'=>'the swamp'],'far'=>['name'=>'Far','region'=>'Swamp'],
       'elsewhere'=>['name'=>'Elsewhere','region'=>'Vain']];
$pos=['x'=>0.0,'y'=>0.0,'z'=>0.0];
$pick=stobeRegionRoutePick('The Swamp',$zones,$pos,'',$tags);
ac($pick['name']==='C Town','unit: equal distances -> the discovered town first');
$zones[2]['discovered']=false;
ac(stobeRegionRoutePick('Swamp',$zones,$pos,'',$tags)['name']==='A Town','unit: equal distance and discovery -> name order; "Swamp" == "The Swamp" == "the swamp"');
ac(stobeRegionRoutePick('Swamp',$zones,null,'',$tags)['name']==='Far','unit: no NPC position still picks a tagged town (discovered first, here only Far)');
ac(stobeRegionRoutePick('Swamp',$zones,$pos,'A Town',$tags)['name']==='B Town','unit: the current town is skipped');
ac(stobeRegionRoutePick('Nowhere',$zones,$pos,'',$tags)===null && stobeRegionRoutePick('',$zones,$pos,'',$tags)===null,'unit: unknown or empty region -> null');
ac(stobeRegionRoutePick('Vain',[['name'=>'Elsewhere','x'=>NAN,'y'=>0,'z'=>0]],$pos,'',$tags)===null,'unit: a town without finite coordinates is never picked');

// ---- 6. an existing trip -> blocked_by_existing_trip, untouched
fresh_world();
$propose=['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',
    'travel_destination'=>'local:world:2543823360:77','travel_reason'=>'','travel_player_quote'=>''];
$t='Sure.';$a=[];rr_turn("Take me to Stumble Inn.",$propose,900,$scope,$npc,$t,$a);
$before=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(is_array($before) && $before['status']==='PROPOSED' && $before['destination']==='Stumble Inn','6: setup: a PROPOSED trip to Stumble Inn exists');
$t='Fine.';$a=[];$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
$after=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac($h && str_contains($t,'current trip is still in place') && $after===$before && count(plan_rows('route_ready'))===0 && $a===[],'6: an active trip blocks the region plan and is left untouched');

// ---- 7. lore question -> no region_plan, no trip
fresh_world();
foreach (["What is Vain like?","What is the Vain region like?","Tell me about the area around Vain."] as $q) {
    $t='Vain is a stretch of rocky hills.';$a=[];rr_turn($q,$none,1000,$scope,$npc,$t,$a);
    ac(plan_rows()===[] && !isset($GLOBALS['STOBE_TRAVEL_STATE'][$key]) && !isset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']),'7: lore question stays a conversation (no region_plan row, no trip): '.$q);
    ac($t==='Vain is a stretch of rocky hills.' || !bad_text($t) ,'7: the NPC\'s own words are not replaced by a route fallback: '.$q);
}

// ---- 8. END
fresh_world();
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
$tripBefore=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
$t='Of course.';$a=['TRAVEL_LOCATION@x'];
$h=rr_turn("Forget this area.",['region_plan_decision'=>'END','proposed_region'=>'','travel_decision'=>'NONE'],1020,$scope,$npc,$t,$a);
$last=plan_rows();$last=end($last);
ac($h && ($last['stage']??'')==='ended' && $a===[],'8: END ends the region idea and strips movement');
ac(($GLOBALS['STOBE_TRAVEL_STATE'][$key]??null)===$tripBefore,'8: END of the idea does not touch the stored trip offer');

// ---- 9. a refused PROPOSE (low affinity) shows the ordinary refusal, no route_ready, plan stays awaiting_route
fresh_world();
$npcCold=mk_npc(-20,0.0,0.0,[$stumble]);
$t='Fine.';$a=[];$h=rr_turn($consider,$none,1000,$scope,$npcCold,$t,$a);
ac($h && str_contains($t,"don't trust you enough") && count(plan_rows('route_ready'))===0 && count(plan_rows('awaiting_route'))===1 && !isset($GLOBALS['STOBE_TRAVEL_STATE'][$key]) && $a===[],
    '9: a refusal by the ordinary travel policy is shown as is; nothing is stored beyond awaiting_route');
ac(!isset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']),'9: the pin is cleared on a refused proposal too');

// ---- 10. exact consent answering the NPC's own suggestion keeps its same-turn path and also uses a world town
fresh_world();
$turn0=stobeRegionPlanBegin(true,$scope,'What rough region should we consider?',990);
$t='We could head toward Vain as a rough area.';$a=['TRAVEL_LOCATION@model-invented'];
$ok=stobeAreaGoalProcessorHook(false,false,true,'',false,false,$t,$t,$turn0,json_encode(['region_plan_decision'=>'SUGGEST','proposed_region'=>'Vain']),'Laru',$npc,'Shay',990,$a,[],'Stack');
ac($ok && $a===[] && count(plan_rows('awaiting_route'))===0,'10: setup: the NPC suggested Vain (concept)');
$t='Fine.';$a=[];$h=rr_turn("I agree to go to Vain as a general area.",$none,1000,$scope,$npc,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac($h && is_array($trip) && $trip['status']==='ACCEPTED' && $trip['destination']==='Hive Village CE' && $a===['TRAVEL_LOCATION@Hive Village CE'],'10: the exact consent starts the trip in the same turn (ACCEPTED + one TRAVEL_LOCATION to the town)');
ac(($trip['regional_goal']['endpoint_source']??'')==='world_town_region' && ($trip['regional_goal']['endpoint_region_evidence']??'')==='world_town_region'
    && ($trip['regional_goal']['ordinary_order_validation']??'')==='passed' && ($trip['regional_goal']['region']??'')==='Vain','10: the same-turn goal uses the allowlisted world-town values');
ac(!isset($GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']) && !isset($GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']),'10: no marker or pin is left behind');
// the allowlist still rejects anything else
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=['actor'=>'Laru','speaker'=>'Shay','gamets'=>5,'quote'=>'q','region'=>'Vain','destination_id'=>'T','endpoint_actor_serial'=>2543823360,
    'endpoint_source'=>'invented','endpoint_region_evidence'=>'world_town_region','trip_read_succeeded'=>true,'prior_trip_status'=>'none'];
ac(stobeTravelTakeRegionalConsent('Laru','Shay',5,'q','q','T')===null,'10: an unknown endpoint_source is still refused');
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=['actor'=>'Laru','speaker'=>'Shay','gamets'=>5,'quote'=>'q','region'=>'Vain','destination_id'=>'T','endpoint_actor_serial'=>2543823360,
    'endpoint_source'=>'world_town_region','endpoint_region_evidence'=>'invented','trip_read_succeeded'=>true,'prior_trip_status'=>'none'];
ac(stobeTravelTakeRegionalConsent('Laru','Shay',5,'q','q','T')===null,'10: an unknown endpoint_region_evidence is still refused');

// ---- 11. the pin resolves only the chosen town and is never the current town
$GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']=['label'=>'Hive Village CE','x'=>1.0,'y'=>2.0,'z'=>3.0];
$p=stobeTravelResolvePlan('Laru',$npc,'Hive Village CE',null);
ac(is_array($p) && $p['x']===1.0 && $p['source']==='visited_location' && stobeTravelResolvePlan('Laru',$npc,'Hive Village S',null)===false,'11: the pin resolves exactly its own label');
$GLOBALS['CACHE_CITY']='Hive Village CE';
ac(stobeTravelResolvePlan('Laru',$npc,'Hive Village CE',null)===false,'11: the pin never resolves the town the NPC stands in');
unset($GLOBALS['CACHE_CITY'],$GLOBALS['STOBE_TRAVEL_REGION_ROUTE_PIN']);

// ---- 12. native candidate with region proof still wins over a town (native id if in range), and the offer is PROPOSE-only too
fresh_world();
$GLOBALS['TEST_KNOWN_REGIONS']=[['region'=>'Vain','town'=>'Stumble Inn']];$nativeVain=$stumble;
$npcNative=mk_npc(70,0.0,0.0,[$nativeVain]);
$t='Fine.';$a=[];$h=rr_turn($consider,$none,1000,$scope,$npcNative,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac($h && is_array($trip) && $trip['status']==='PROPOSED' && $trip['destination']==='Stumble Inn' && ($trip['destination_point']['id']??'')==='local:world:2543823360:77' && $a===[],
    '12: a native candidate carrying region proof is the first leg (PROPOSED, native id, zero actions)');
ac(($trip['regional_goal']['endpoint_source']??'')==='current_actor_scoped_native_candidate' && ($trip['regional_goal']['endpoint_region_evidence']??'')==='npc_known_town_region'
    && ($trip['regional_goal']['endpoint_id']??'')==='local:world:2543823360:77','12: its regional_goal keeps the native evidence values');
$rd=plan_rows('route_ready');
ac(count($rd)===1 && ($rd[0]['endpoint_label']??'')==='Stumble Inn' && ($rd[0]['endpoint_id']??'')==='local:world:2543823360:77','12: the route_ready row names the native candidate');

// ---- 13. the shipped data file
$GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS']=null;unset($GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS']);
$file=json_decode(file_get_contents(__DIR__.'/../data/kenshi_town_regions.json'),true);
ac(is_array($file) && is_array($file['towns']??null) && count($file['towns'])>=30,'13: the data file loads');
$tr=stobeRegionRouteTownRegions();
$vain=array_values(array_filter($tr,static fn($e)=>stobeRegionRouteKey($e['region'])==='vain'));
ac(count($vain)>=4 && isset($tr['hive village ne']) && isset($tr['hive village cw']),'13: Vain has verified towns (Hive Village NE/CE/CW/S/W/NW/SW from the Map of Vain item lists)');
ac(($tr['hive village e']['region']??'')==='Vain' && ($tr['hive village e']['source']??'')==='Shay decision 2026-10-16' && !isset($file['unverified_not_used']['Hive Village E']),'13: Hive Village E is tagged Vain with the source "Shay decision 2026-10-16"');
$catalog=json_decode(file_get_contents(__DIR__.'/../lib/destination_catalog.json'),true);
$names=[];foreach ($catalog['entries'] as $e) foreach (($e['regions']??[]) as $r) $names[stobeRegionRouteKey(strval($r['name']))]=true;
$badRegion=[];$noSource=[];
foreach ($file['towns'] as $name=>$e) { if (!isset($names[stobeRegionRouteKey($e['region'])])) $badRegion[]=$name.'='.$e['region']; if (trim(strval($e['source']??''))==='') $noSource[]=$name; }
ac(!$badRegion,'13: every tagged region is a catalog region: '.implode(', ',$badRegion));
ac(!$noSource,'13: every tagged town has a source');
ac(stobeRegionRouteKey('The Swamp')===stobeRegionRouteKey('Swamp') && stobeRegionRouteKey("Okran's Pride")==='okranspride','13: region keys normalise "the", case and punctuation');

// ---- 14. Hive Village E (Shay decision 2026-10-16) is a valid Vain route candidate: nearest wins, the current town is excluded
$shipped=stobeRegionRouteTownRegions();   // the shipped file (no override set)
$wz=static fn($name,$x,$z,$disc)=>['name'=>$name,'x'=>$x,'y'=>10.0,'z'=>$z,'discovered'=>$disc];
$zonesE=[$wz('Hive Village E',-50000.0,0.0,false),$wz('Hive Village CE',20000.0,10000.0,false),$wz('Hive Village S',30000.0,-10000.0,true)];
$pe=stobeRegionRoutePick('Vain',$zonesE,['x'=>-49000.0,'y'=>0.0,'z'=>0.0],'',$shipped);
ac(($pe['name']??'')==='Hive Village E' && ($pe['region_source']??'')==='Shay decision 2026-10-16','14: with the shipped table, the NPC next to Hive Village E gets E as the nearest Vain town');
ac(($pick2=stobeRegionRoutePick('Vain',$zonesE,['x'=>-50000.0,'y'=>0.0,'z'=>0.0],'Hive Village E',$shipped)) && $pick2['name']==='Hive Village CE','14: standing in Hive Village E, the pick skips E and takes the next nearest');
$fw=function(){ $GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS']=null;unset($GLOBALS['STOBE_REGION_ROUTE_TOWN_REGIONS']);
    $db=new AreaGoalFixtureDb();$w=static fn($name,$x,$z,$d)=>['zone_name'=>$name,'x'=>$x,'y'=>10.0,'z'=>$z,'discovered'=>$d?'t':'f'];
    $db->world=[$w('Hive Village E',-50000.0,0.0,false),$w('Hive Village CE',20000.0,10000.0,false)];
    $GLOBALS['db']=$db;$GLOBALS['STOBE_TRAVEL_STATE']=[];unset($GLOBALS['TEST_KNOWN_REGIONS']); };
$fw();
$npcE=mk_npc(70,-49000.0,0.0,[$stumble]);
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npcE,$t,$a);
ac(($GLOBALS['STOBE_TRAVEL_STATE'][$key]['destination']??'')==='Hive Village E' && str_contains($t,'Hive Village E') && $a===[],'14: end to end, the consider turn offers Hive Village E (PROPOSE only) from the shipped file');
$fw();
$npcInE=mk_npc(70,-50000.0,0.0,[$stumble]);
$t='Fine.';$a=[];rr_turn($consider,$none,1000,$scope,$npcInE,$t,$a,'Hive Village E');
ac(($GLOBALS['STOBE_TRAVEL_STATE'][$key]['destination']??'')==='Hive Village CE','14: end to end, standing in Hive Village E the offer is the next Vain town, never E itself');

echo "RESULT IMM26-REGIONROUTE PASS assertions=$n\n";
