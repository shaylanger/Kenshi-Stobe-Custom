<?php
// imm26-sfL (rows 24-b / 24-c): "Let's go toward <region>" through the ORDINARY travel path must leave a trip regional_goal (region = goal, offered place = waypoint) that
// survives save/load. Harness copied from imm26_wpE_region_regression.php (fixture DB, no network, no live DB).
require_once __DIR__.'/../lib/travel_companionship.php';
require_once __DIR__.'/../lib/area_goal_integration.php';
require_once __DIR__.'/../lib/processor_area_goal_hook.php';

class AreaGoalFixtureDb {
    public array $events=[]; public bool $failReads=false; public bool $failTravelReads=false; public mixed $forcedResult='unset';
    function fetchOne($sql,$args=[]) {
        if (str_contains($sql,'pg_try_advisory_lock')) return ['acquired'=>true];
        if (str_contains($sql,'pg_advisory_unlock')) return ['unlocked'=>true];
        if ($this->failTravelReads && str_contains($sql,"type='travel_agreement'")) throw new RuntimeException('fixture travel read failure');
        if ($this->failReads) throw new RuntimeException('fixture database read failure');
        if ($this->forcedResult!=='unset') return $this->forcedResult;
        $type=str_contains($sql,"type='travel_agreement'")?'travel_agreement':(str_contains($sql,"type='region_plan'")?'region_plan':'');
        if ($type==='') return null;
        $prefix=strval($args[0]??'');$time=intval($args[1]??PHP_INT_MAX);
        $matches=array_values(array_filter($this->events,static fn($e)=>$e['type']===$type && $e['gamets']<=$time && str_starts_with($e['data'],$prefix)));
        usort($matches,static fn($a,$b)=>[$b['gamets'],$b['seq']]<=>[$a['gamets'],$a['seq']]);
        return $matches[0]??null;
    }
}
$GLOBALS['db']=new AreaGoalFixtureDb(); $GLOBALS['STOBE_TRAVEL_STATE']=[];
$GLOBALS['areaSerials']=['Laru'=>2543823360,'Shay'=>3454101504,'Other'=>7654321];
$GLOBALS['STOBE_TRAVEL_SPEAKER']='Shay';
function stobeResolveLiveParticipantSerial($name){return intval($GLOBALS['areaSerials'][$name]??0);}
function normalizeCoreNpcMetadata($metadata){return is_array($metadata)?$metadata:[];}
function normalizeParticipantNameToken($name){return trim((string)$name);}
function stobeLogWarn($m,$c=[]){ }
function stobeLogInfo($m,$c=[]){ }
function stobePlayerOrderGate($actor,$npc,$action){$GLOBALS['fixtureOrderGateCalls']=intval($GLOBALS['fixtureOrderGateCalls']??0)+1;return strval($GLOBALS['fixtureOrderGateReason']??'');}
function stobeNonFactionMinorOrderCommands(){return ['FOLLOW','STOP_FOLLOW','MOVE_TO','TRAVEL_LOCATION'];}
function normalizeActionTagToken($action,$config=[]){return (string)$action;}
function stobeBuildActionConfigForNpc($mode,$npc){return [];}
function stobeResolveTravelLocationFromVisitedZones($name){return false;}
function stobeDestinationSource($source){return [];}
function normalizeNpcExtendedDataPayload($data){return is_array($data)?$data:[];}
function sanitizeForKenshi($s){return (string)$s;}
function stobeDestinationCatalog(){return [['regions'=>[
 ['name'=>'Vain','provenance'=>['fixture catalog']],['name'=>'The Pits','provenance'=>['fixture catalog']]]]];}
function storeEvent($type,$time,$gamets,$data,$status='pending',$a='',$b='', $c=false){
 static $seq=0; $event=['type'=>$type,'time'=>$time,'gamets'=>$gamets,'data'=>$data,'status'=>$status,'seq'=>++$seq];
 $GLOBALS['db']->events[]=$event;return $event;
}
function ac(bool $ok,string $label){global $n;if(!$ok)throw new RuntimeException('FAIL '.$label);++$n;}
function seedAreaRegionOffer(array $scope,array|false $npc,string $speaker,int $gamets,array $known=[]): bool {
    $turn=stobeRegionPlanBegin(true,$scope,'What rough region should we consider?',$gamets);
    $raw=json_encode(['region_plan_decision'=>'SUGGEST','proposed_region'=>'Vain']);
    $text='We could head toward Vain as a rough area.';$actions=['TRAVEL_LOCATION@model-invented'];
    $handled=stobeAreaGoalProcessorHook(false,false,true,'',false,false,$text,$text,$turn,$raw,
        strval($npc['name']??''),$npc,$speaker,$gamets,$actions,$known,'Stack');
    return $handled && $actions===[];
}

$n=0;
$scope=['campaign_id'=>'campaign-1','actor_id'=>'2543823360','speaker_id'=>'3454101504'];
$npc=['name'=>'Laru','extended_data'=>['relationships'=>['Shay'=>['aff'=>70]]], 'metadata'=>[
 'travel_destinations'=>[['id'=>'local:world:2543823360:77','actor_serial'=>2543823360,'observed'=>true,
   'observed_unix'=>time(),'reachability'=>'path_confirmed','kind'=>'known_place','label'=>'Stumble Inn',
   'x'=>100.0,'y'=>0.0,'z'=>200.0,'spatial'=>['anchor_type'=>'town','anchor_name'=>'Stumble Inn','town_name'=>'Stumble Inn']]]]];
$key=stobeTravelKey('Laru','Shay');
/** One player turn exactly as processor/chat.php runs it: region hook first, ordinary travel capture when the hook declines. */
function sfl_turn(string $quote,array $model,int $gamets,array $scope,array $npc,string &$text,array &$actions): bool {
    $turn=stobeRegionPlanBegin(true,$scope,$quote,$gamets);
    if(!is_array($turn))throw new RuntimeException('turn setup failed');
    $raw=json_encode($model);
    $handled=stobeAreaGoalProcessorHook(false,false,true,'',false,false,$text,$text,$turn,$raw,'Laru',$npc,'Shay',$gamets,$actions,[],'Stack');
    if(!$handled){
        stobeTravelCapture($raw,'Laru',$npc,'Shay',$quote,$gamets,$text,$actions);
        stobeTravelValidateOrders('Laru',$npc,'Shay',$gamets,$text,$actions);
    }
    return $handled;
}
$propose=['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',
    'travel_destination'=>'local:world:2543823360:77','travel_reason'=>'Shay wants to move toward Vain; Vain is a region, not a walkable point, so I offer a known place on the way north.',
    'travel_player_quote'=>''];

// ---- 24-c recipe: consider Vain / "Let's go toward Vain." / "Yes, let's go." / save+load
$t="Fine.";$a=[];
$h1=sfl_turn("Let's consider Vain as a general area, not an exact spot.",['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'NONE'],1000,$scope,$npc,$t,$a);
$plan=stobeRegionPlanRead($scope,1000);
ac($h1 && ($plan['stage']??'')==='awaiting_route' && ($plan['proposed_region']??'')==='Vain','step 1: the conceptual region plan is stored (awaiting_route, Vain)');
ac(!isset($GLOBALS['STOBE_TRAVEL_STATE'][$key]) && !isset($GLOBALS['STOBE_TRAVEL_REGION_HINT']),'step 1: no trip and no hint from a conceptual turn');

$t="Vain is a broad stretch. I could lead you to Stumble Inn.";$a=['TRAVEL_LOCATION@local:world:2543823360:77'];
$h2=sfl_turn("Let's go toward Vain.",$propose,1010,$scope,$npc,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(!$h2,'step 2: "Lets go toward Vain." stays an ordinary travel turn (hook declines)');
ac(is_array($trip) && $trip['status']==='PROPOSED' && ($trip['destination']??'')==='Stumble Inn','step 2: the model offer is stored PROPOSED');
ac(($trip['regional_goal']['region']??'')==='Vain' && ($trip['regional_goal']['goal_source']??'')==='player_toward_region'
    && ($trip['regional_goal']['endpoint_label']??'')==='Stumble Inn' && ($trip['regional_goal']['endpoint_id']??'')==='local:world:2543823360:77'
    && ($trip['regional_goal']['endpoint_region_evidence']??'')==='none_waypoint'
    && intval($trip['regional_goal']['endpoint_actor_serial']??0)===2543823360,
    'step 2: the PROPOSED trip carries regional_goal Vain with the honest waypoint (no region proof claimed)');
ac(!isset($GLOBALS['STOBE_TRAVEL_REGION_HINT']),'the hint is one-shot');

$t="Good.";$a=['TRAVEL_LOCATION@local:world:2543823360:77'];
$accept=['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'ACCEPT','travel_kind'=>'same_route','travel_leader'=>'npc',
    'travel_destination'=>'local:world:2543823360:77','travel_reason'=>'','travel_player_quote'=>"Yes, let's go."];
$h3=sfl_turn("Yes, let's go.",$accept,1020,$scope,$npc,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(!$h3 && is_array($trip) && $trip['status']==='ACCEPTED' && ($trip['execution']['phase']??'')==='accepted','step 3: Yes ACCEPTs the stored offer');
ac(($trip['regional_goal']['region']??'')==='Vain' && ($trip['regional_goal']['endpoint_label']??'')==='Stumble Inn','step 3: the ACCEPTED trip keeps regional_goal Vain');
$agreement=$trip['agreement_id']??'';

// save+load: reload the stored row through the event log (json round trip), pause it as the load reconcile does, read it again
$GLOBALS['STOBE_TRAVEL_STATE']=[];
$reloaded=stobeTravelRead('Laru','Shay',1100);
ac(is_array($reloaded) && ($reloaded['agreement_id']??'')===$agreement && ($reloaded['regional_goal']['region']??'')==='Vain',
    'save/load: the stored row read back from the event log keeps agreement_id and regional_goal');
$paused=$reloaded;$paused['execution']=stobeCommitmentInterruptExecution($reloaded['execution'],1100,'ev-absent-1');
ac(stobeTravelWrite('Laru','Shay',1100,$paused),'save/load: paused state written');
$GLOBALS['STOBE_TRAVEL_STATE']=[];
$after=stobeTravelRead('Laru','Shay',1110);
ac(($after['execution']['phase']??'')==='interrupted_by_load' && ($after['agreement_id']??'')===$agreement
    && ($after['regional_goal']['region']??'')==='Vain' && ($after['regional_goal']['endpoint_label']??'')==='Stumble Inn'
    && stobeAreaGoalTripStateValid($after,'Laru','Shay'),
    'save/load: interrupted_by_load (same agreement) keeps regional_goal and still validates');

// ---- negatives: nothing may attach a goal that the player did not ask for
function sfl_fresh(): void { $GLOBALS['db']=new AreaGoalFixtureDb();$GLOBALS['STOBE_TRAVEL_STATE']=[];unset($GLOBALS['STOBE_TRAVEL_REGION_HINT']); }
foreach ([
    ['plain place, no region named',"Let's go to Stumble Inn."],
    ['negated',"Let's not go toward Vain."],
    ['conditional',"Let's go toward Vain if the road is safe."],
    ['region mentioned but not as a direction',"Vain scares me, let's go to Stumble Inn."],
    ['two regions',"Let's go toward Vain or The Pits."],
] as [$label,$q]) {
    sfl_fresh();$t='ok';$a=[];
    sfl_turn($q,$propose,2000,$scope,$npc,$t,$a);
    $tr=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
    ac(!is_array($tr) || !isset($tr['regional_goal']),'no regional_goal: '.$label);
}
// hint bound to the exact actor/speaker/turn/quote
sfl_fresh();
$turnX=stobeRegionPlanBegin(true,$scope,"Let's go toward Vain.",3000);
stobeAreaGoalNoteRegionHint($turnX,"Let's go toward Vain.",'Laru','Shay',3000);
ac(is_array($GLOBALS['STOBE_TRAVEL_REGION_HINT']??null),'hint written for a clean region direction');
ac(stobeTravelTakeRegionHint('Other','Shay',3000,"Let's go toward Vain.")===null && !isset($GLOBALS['STOBE_TRAVEL_REGION_HINT']),'hint cannot cross actors and is consumed');
stobeAreaGoalNoteRegionHint($turnX,"Let's go toward Vain.",'Laru','Shay',3000);
ac(stobeTravelTakeRegionHint('Laru','Shay',3001,"Let's go toward Vain.")===null,'hint cannot cross turns (gamets)');
stobeAreaGoalNoteRegionHint($turnX,"Let's go toward Vain.",'Laru','Shay',3000);
ac(stobeTravelTakeRegionHint('Laru','Shay',3000,"something else")===null,'hint cannot cross quotes');
stobeAreaGoalNoteRegionHint($turnX,"Let's go toward Vain.",'Laru','Shay',3000);
ac(stobeTravelTakeRegionHint('Laru','shay',3000,"Let's go toward Vain.")==='Vain','hint is returned for the exact turn');
// a region equal to the offered place is a direct trip, not a regional goal
$st=['destination'=>'Vain','destination_point'=>['x'=>1,'y'=>2,'z'=>3,'label'=>'Vain']];
ac(stobeTravelRegionWaypointGoal($st,null,'PROPOSE','Vain','Laru',1)===null,'a place that IS the region gets no waypoint goal');
// the rule that rejects an endpoint equal to the town the player is in stays untouched
$cand=['source'=>'native_local','actor_serial'=>2543823360,'kind'=>'known_place','id'=>'local:world:2543823360:77','x'=>1.0,'y'=>2.0,'z'=>3.0,
    'spatial'=>['region_name'=>'Vain','anchor_name'=>'Stumble Inn','town_name'=>'Stumble Inn']];
ac(stobeAreaGoalEndpointValid($cand,'Vain',2543823360,1000,[],'')===true && stobeAreaGoalEndpointValid($cand,'Vain',2543823360,1000,[],'Stumble Inn')===false,
    'area_goal current-town rejection unchanged');

echo "RESULT IMM26-SFL-REGION-WAYPOINT PASS assertions=$n\n";
