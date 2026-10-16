<?php
// imm26 fixR2serial (row 24-b, found live by 5090-i3op25): WP-R2's region route is never reached in production because the area-goal code compared the
// social-scope ids (stobeSocialPreferenceScope: DB ids such as actor_id 5969 / speaker_id 2) with the LIVE native serials (2543823360 / 3454101504).
// The fixture tests of imm26_regionroute_regression.php pass only because they set id == serial. Every scope in THIS file is production-shaped:
// the social ids are NOT the live serials. The scope ids stay the region_plan key only; the trip key, the trip read and the resolve use the live serials.
// Run: php tests/imm26_regionroute_serial_regression.php   (fixture DB, no network, no live DB; harness copied from imm26_regionroute_regression.php)
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


// PRODUCTION-SHAPED scope: social DB ids, not the live serials 2543823360 (Laru) / 3454101504 (Shay).
$scope=['campaign_id'=>'campaign-1','actor_id'=>'5969','speaker_id'=>'2'];
ac($scope['actor_id']!==strval($GLOBALS['areaSerials']['Laru']) && $scope['speaker_id']!==strval($GLOBALS['areaSerials']['Shay']),'0: the scope ids really differ from the live serials');

// ---- 1. the live-found defect: the trip read must succeed with production-shaped ids, and its proof carries the LIVE serials
fresh_world();
$read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
ac(($read['read_succeeded']??false)===true && array_key_exists('state',$read) && $read['state']===null,'1: the current-trip read succeeds (empty trip) although scope ids != live serials');
ac(intval($read['actor_serial'])===2543823360 && intval($read['speaker_serial'])===3454101504,'1: the read proof carries the LIVE serials');
ac(($read['scope']??null)===$scope,'1: the read proof keeps the social scope (region_plan key only)');
$bad=stobeAreaGoalReadCurrentTrip('Ghost','Shay',1000,$scope);
ac(($bad['read_succeeded']??true)===false,'1: an actor with no live serial still fails the read');
$bad=stobeAreaGoalReadCurrentTrip('Laru','Ghost',1000,$scope);
ac(($bad['read_succeeded']??true)===false,'1: a speaker with no live serial still fails the read');
$bad=stobeAreaGoalReadCurrentTrip('Laru','Shay',0,$scope);
ac(($bad['read_succeeded']??true)===false,'1: gamets 0 still fails the read');
$bad=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,['campaign_id'=>'campaign-1','actor_id'=>'5969']);
ac(($bad['read_succeeded']??true)===false,'1: a scope without speaker_id still fails the read');

// ---- 2. the full consider turn: route_ready + PROPOSED agreement, NOT the fixed "can't verify" reply
fresh_world();
$t='Fine.';$a=['TRAVEL_LOCATION@model-invented'];
$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac($h,'2: the region hook owns the consider turn');
ac(!str_contains($t,"can't verify") && !bad_text($t),'2: no "can\'t verify our current trip or route yet" fallback (reply: '.substr($t,0,120).')');
$rd=plan_rows('route_ready');
ac(count($rd)===1 && ($rd[0]['proposed_region']??'')==='Vain' && ($rd[0]['endpoint_label']??'')==='Hive Village CE' && ($rd[0]['movement_consent']??true)===false,'2: route_ready names the nearest Vain town');
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(is_array($trip) && $trip['status']==='PROPOSED' && $trip['destination']==='Hive Village CE','2: a PROPOSED agreement keyed by the live serials points at the town');
ac(intval($trip['regional_goal']['endpoint_actor_serial']??0)===2543823360 && ($trip['regional_goal']['region']??'')==='Vain','2: regional_goal carries the LIVE actor serial');
ac($a===[] && str_contains($t,'Hive Village CE') && str_contains($t,'Shall we set out'),'2: zero actions and the server-written offer reply');
$keys=[];
foreach ($GLOBALS['db']->events as $e) if ($e['type']==='travel_agreement') $keys[substr($e['data'],0,strpos($e['data'],'{'))]=1;
ac(array_keys($keys)===['travel-v1:2543823360:3454101504:'],'2: every travel_agreement row uses the live-serial key');

// ---- 3. next Yes is the ordinary ACCEPT
$t='Good.';$a=['TRAVEL_LOCATION@Hive Village CE'];
$h2=rr_turn("Yes, let's go.",$accept('Hive Village CE'),1010,$scope,$npc,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(!$h2 && is_array($trip) && $trip['status']==='ACCEPTED' && $a===['TRAVEL_LOCATION@Hive Village CE'],'3: Yes is the ordinary ACCEPT with one TRAVEL_LOCATION');

// ---- 4. exact consent answering the NPC's own suggestion: same-turn path (stobeTravelTakeRegionalConsent) with production-shaped ids
fresh_world();
$turn0=stobeRegionPlanBegin(true,$scope,'What rough region should we consider?',990);
$t='We could head toward Vain as a rough area.';$a=['TRAVEL_LOCATION@model-invented'];
$ok=stobeAreaGoalProcessorHook(false,false,true,'',false,false,$t,$t,$turn0,json_encode(['region_plan_decision'=>'SUGGEST','proposed_region'=>'Vain']),'Laru',$npc,'Shay',990,$a,[],'Stack');
ac($ok && $a===[],'4: setup: the NPC suggested Vain');
$t='Fine.';$a=[];$h=rr_turn("I agree to go to Vain as a general area.",$none,1000,$scope,$npc,$t,$a);
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac($h && is_array($trip) && $trip['status']==='ACCEPTED' && $trip['destination']==='Hive Village CE' && $a===['TRAVEL_LOCATION@Hive Village CE'],'4: exact consent starts the trip in the same turn (ACCEPTED + one TRAVEL_LOCATION)');
ac(($trip['regional_goal']['ordinary_order_validation']??'')==='passed' && intval($trip['regional_goal']['endpoint_actor_serial']??0)===2543823360,'4: the same-turn goal passed ordinary validation with the live serial');

// ---- 5. an existing trip still blocks (the production-shaped read sees it)
fresh_world();
$propose=['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',
    'travel_destination'=>'local:world:2543823360:77','travel_reason'=>'','travel_player_quote'=>''];
$t='Sure.';$a=[];rr_turn("Take me to Stumble Inn.",$propose,900,$scope,$npc,$t,$a);
$before=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
$t='Fine.';$a=[];$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac($h && str_contains($t,'current trip is still in place') && ($GLOBALS['STOBE_TRAVEL_STATE'][$key]??null)===$before && $a===[],'5: an active trip still blocks the region plan (not the verify-failure reply)');

// ---- 6. stobeAreaGoalResolve directly: live actor serial as the argument, social ids in the scope
fresh_world();
$regionPlan=['stage'=>'awaiting_route','conceptual_agreement'=>true,'proposed_region'=>'Vain','scope'=>stobeRegionPlanScope($scope)];
$tr=['status'=>'route_ready','region'=>'Vain','town'=>['name'=>'Hive Village CE','x'=>20000.0,'y'=>10.0,'z'=>10000.0]];
$goodRead=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,$scope,$goodRead,[],'Stack',$tr);
ac(($r['status']??'')==='route_ready' && ($r['endpoint_actor_serial']??0)===2543823360,'6: resolve (live actor serial arg) is route_ready with production-shaped scope ids');
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,$scope,$goodRead,[],'Stack',$tr,3454101504);
ac(($r['status']??'')==='route_ready','6: resolve with the explicit live speaker serial is route_ready');
// negative controls
$r=stobeAreaGoalResolve($regionPlan,[],7654321,1000,$scope,$goodRead,[],'Stack',$tr);
ac(($r['status']??'')==='scope_mismatch','6: a read made for another actor serial is a scope_mismatch');
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,$scope,$goodRead,[],'Stack',$tr,7654321);
ac(($r['status']??'')==='scope_mismatch','6: a read made for another speaker serial is a scope_mismatch');
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,['campaign_id'=>'campaign-1','actor_id'=>'9999','speaker_id'=>'2'],$goodRead,[],'Stack',$tr);
ac(($r['status']??'')==='scope_mismatch','6: a different social scope (region_plan key) than the plan/read is a scope_mismatch');
$stale=$goodRead;$stale['gamets']=999;
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,$scope,$stale,[],'Stack',$tr);
ac(($r['status']??'')==='scope_mismatch','6: a stale read is still a scope_mismatch');
$unread=$goodRead;$unread['read_succeeded']=false;
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,$scope,$unread,[],'Stack',$tr);
ac(($r['status']??'')==='scope_mismatch','6: a failed read is still a scope_mismatch');
$noserial=$goodRead;$noserial['speaker_serial']=0;
$r=stobeAreaGoalResolve($regionPlan,[],2543823360,1000,$scope,$noserial,[],'Stack',$tr);
ac(($r['status']??'')==='scope_mismatch','6: a read without a speaker serial is a scope_mismatch');
$r=stobeAreaGoalResolve($regionPlan,[],0,1000,$scope,$goodRead,[],'Stack',$tr);
ac(($r['status']??'')==='scope_mismatch','6: no live actor serial is a scope_mismatch');

// ---- 7. a regional consent marker built from production-shaped ids is accepted; tampered identity is refused
fresh_world();
$mk=static function(array $over) use ($scope){
    $rs=array_intersect_key($scope,array_flip(['campaign_id','actor_id','speaker_id']));
    return array_merge(['actor'=>'Laru','speaker'=>'Shay','gamets'=>1000,'quote'=>'q','region'=>'Vain','destination_id'=>'T','endpoint_actor_serial'=>2543823360,
        'endpoint_source'=>'world_town_region','endpoint_region_evidence'=>'world_town_region','trip_read_succeeded'=>true,'trip_read_scope'=>$rs,
        'trip_read_scope_hash'=>hash('sha256',json_encode($rs)),'trip_read_actor_serial'=>2543823360,'trip_read_speaker_serial'=>3454101504,'trip_read_gamets'=>1000,
        'prior_trip_status'=>'none'],$over);
};
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=$mk([]);
ac(is_array(stobeTravelTakeRegionalConsent('Laru','Shay',1000,'q','q','T')),'7: a marker with social scope ids + live serials is accepted');
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=$mk(['trip_read_actor_serial'=>7654321]);
ac(stobeTravelTakeRegionalConsent('Laru','Shay',1000,'q','q','T')===null,'7: a marker whose read serial is another actor is refused');
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=$mk(['trip_read_speaker_serial'=>7654321]);
ac(stobeTravelTakeRegionalConsent('Laru','Shay',1000,'q','q','T')===null,'7: a marker whose read serial is another speaker is refused');
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=$mk(['trip_read_scope_hash'=>'deadbeef']);
ac(stobeTravelTakeRegionalConsent('Laru','Shay',1000,'q','q','T')===null,'7: a marker whose scope hash does not match its scope is refused');
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=$mk(['trip_read_scope'=>['campaign_id'=>'campaign-1','actor_id'=>'5969']]);
ac(stobeTravelTakeRegionalConsent('Laru','Shay',1000,'q','q','T')===null,'7: a marker whose scope lacks speaker_id is refused');
$GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']=$mk(['prior_trip_status'=>'RUNNING']);
ac(stobeTravelTakeRegionalConsent('Laru','Shay',1000,'q','q','T')===null,'7: a marker with a prior trip is refused');
unset($GLOBALS['STOBE_TRAVEL_REGIONAL_CONSENT']);

echo "RESULT IMM26-REGIONROUTE-SERIAL PASS assertions=$n\n";
