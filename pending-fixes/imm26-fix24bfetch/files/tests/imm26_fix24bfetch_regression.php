<?php
// imm26 fix24bfetch (row 24-b, found by 4080-i4op17 + 5090-i3op26 after fixR2serial): stobeAreaGoalReadCurrentTrip treated fetchOne()===false as a read failure,
// but PostgresDB::fetchOne() returns false for "no row" as well as for a failed query (lib/postgresql.class.php, pg_fetch_assoc). So a pair with no earlier
// travel_agreement row (the normal first region offer) always answered "I understand the area, but I can't verify our current trip or route yet."
// The older fixture DBs returned null for no row, so no offline test ever saw it. THIS file's fixture DB is faithful to the real driver:
// plain SELECT, no row -> false; failed query -> false; always-one-row scalar-subquery -> ['data'=>NULL] when empty.
// Run: php tests/imm26_fix24bfetch_regression.php   (fixture DB, no network, no live DB; harness copied from imm26_regionroute_serial_regression.php)
require_once __DIR__.'/../lib/travel_companionship.php';
require_once __DIR__.'/../lib/area_goal_integration.php';
require_once __DIR__.'/../lib/processor_area_goal_hook.php';
if (!defined('PGSQL_TRANSACTION_IDLE')) define('PGSQL_TRANSACTION_IDLE', 0);

class AreaGoalFixtureDb {
    public array $events=[]; public array $zones=[]; public array $world=[]; public array $queries=[]; public bool $failTravelRead=false;
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
        $this->queries[]=$sql;
        // imm26 fix24bfetch: faithful to PostgresDB::fetchOne (pg_fetch_assoc): false on a failed query AND on a plain no-row SELECT;
        // an always-one-row scalar-subquery SELECT returns ['data'=>NULL] when nothing matches.
        if ($this->failTravelRead && $type==='travel_agreement') return false;
        $prefix=strval($args[0]??'');$time=intval($args[1]??PHP_INT_MAX);
        $matches=array_values(array_filter($this->events,static fn($e)=>$e['type']===$type && $e['gamets']<=$time && str_starts_with($e['data'],$prefix)));
        usort($matches,static fn($a,$b)=>[$b['gamets'],$b['seq']]<=>[$a['gamets'],$a['seq']]);
        if (preg_match('/^\s*SELECT\s*\(\s*SELECT\s+data\s+FROM\s+eventlog/i',$sql)===1) return ['data'=>$matches[0]['data']??null];
        return $matches[0]??false;
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

function fresh_pg(bool $failRead=false): void { fresh_world(); $GLOBALS['db']->failTravelRead=$failRead; }
$CANT = "I understand the area, but I can't verify our current trip or route yet.";
function travel_rows(): array { return array_values(array_filter($GLOBALS['db']->events,static fn($e)=>$e['type']==='travel_agreement')); }
$scope=['campaign_id'=>'campaign-1','actor_id'=>'5969','speaker_id'=>'2'];   // production-shaped social ids (not the live serials)

// ---- 1. ROW ABSENT (the normal first offer): the read SUCCEEDS with an empty trip (state null) and seeds the cache with null
fresh_pg();
$read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
ac(($read['read_succeeded']??false)===true && array_key_exists('state',$read) && $read['state']===null,'1: no travel_agreement row is a successful EMPTY read (driver returns no-row as false/NULL data)');
ac(array_key_exists($key,$GLOBALS['STOBE_TRAVEL_STATE']) && $GLOBALS['STOBE_TRAVEL_STATE'][$key]===null,'1: the cache is seeded with the empty trip for the normal capture path');
ac(intval($read['actor_serial'])===2543823360 && intval($read['speaker_serial'])===3454101504,'1: the proof still carries the live serials');

// ---- 2. ROW ABSENT through the whole consider turn: the region route offer, not the "can't verify" reply
fresh_pg();
$t='Fine.';$a=['TRAVEL_LOCATION@model-invented'];
$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac($h && $t!==$CANT && !str_contains($t,"can't verify") && !bad_text($t),'2: first consider turn with no prior trip row is NOT the fixed can\'t-verify reply (reply: '.substr($t,0,120).')');
$rd=plan_rows('route_ready');
ac(count($rd)===1 && ($rd[0]['endpoint_label']??'')==='Hive Village CE','2: route_ready names the nearest Vain town');
$trip=$GLOBALS['STOBE_TRAVEL_STATE'][$key]??null;
ac(is_array($trip) && $trip['status']==='PROPOSED' && $trip['destination']==='Hive Village CE' && $a===[] && str_contains($t,'Shall we set out'),'2: PROPOSED agreement + server-written offer, zero actions');

// ---- 3. REAL DB ERROR on the trip read: still FAILS CLOSED (fixed reply, nothing stored, no movement)
fresh_pg(true);
$read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
ac(($read['read_succeeded']??true)===false && array_key_exists('state',$read) && $read['state']===null,'3: a failed trip query is a read failure');
ac(!array_key_exists($key,$GLOBALS['STOBE_TRAVEL_STATE']),'3: a failed read does not seed the cache');
$t='Fine.';$a=['TRAVEL_LOCATION@model-invented'];
$before=count(travel_rows());
$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac($h && $t===$CANT && $a===[] && count(travel_rows())===$before && plan_rows('route_ready')===[],'3: DB error -> exact can\'t-verify reply, zero actions, no agreement row, no route_ready');

// ---- 4. error does not stick: after a failed read the next healthy no-row read succeeds
$GLOBALS['db']->failTravelRead=false;$GLOBALS['STOBE_TRAVEL_STATE']=[];
$read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
ac(($read['read_succeeded']??false)===true && $read['state']===null,'4: a later healthy read after an error is an empty-trip success (no sticky failure)');

// ---- 5. ROW PRESENT: an active trip is read back and still blocks the region plan
fresh_pg();
$propose=['region_plan_decision'=>'NONE','proposed_region'=>'','travel_decision'=>'PROPOSE','travel_kind'=>'same_route','travel_leader'=>'npc',
    'travel_destination'=>'local:world:2543823360:77','travel_reason'=>'','travel_player_quote'=>''];
$t='Sure.';$a=[];rr_turn("Take me to Stumble Inn.",$propose,900,$scope,$npc,$t,$a);
$GLOBALS['STOBE_TRAVEL_STATE']=[];
$read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
ac(($read['read_succeeded']??false)===true && is_array($read['state']) && $read['state']['status']==='PROPOSED','5: a stored PROPOSED trip is read back from the row');
$GLOBALS['STOBE_TRAVEL_STATE']=[];
$t='Fine.';$a=[];$h=rr_turn($consider,$none,1000,$scope,$npc,$t,$a);
ac($h && str_contains($t,'current trip is still in place') && $t!==$CANT && $a===[],'5: an active trip still blocks the region plan');

// ---- 6. another pair's row and a row from the FUTURE (gamets > read time) are not this pair's trip
fresh_pg();
$other='travel-v1:2543823360:7654321:';
$GLOBALS['db']->events[]=['type'=>'travel_agreement','time'=>0,'gamets'=>500,'data'=>$other.'{"status":"PROPOSED"}','status'=>'pending','seq'=>1];
$GLOBALS['db']->events[]=['type'=>'travel_agreement','time'=>0,'gamets'=>2000,'data'=>$key.'{"status":"PROPOSED"}','status'=>'pending','seq'=>2];
$read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
ac(($read['read_succeeded']??false)===true && $read['state']===null,'6: another pair\'s row and a future row are not this pair\'s trip (empty, success)');

// ---- 7. a PRESENT but corrupt / incoherent row still fails closed (the no-row fix must not loosen validation)
foreach ([['{not json','7a: malformed JSON'],['{"status":"BOGUS"}','7b: unknown status'],['','7c: empty payload']] as [$payload,$label]) {
    fresh_pg();
    $GLOBALS['db']->events[]=['type'=>'travel_agreement','time'=>0,'gamets'=>900,'data'=>$key.$payload,'status'=>'pending','seq'=>1];
    $read=stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
    ac(($read['read_succeeded']??true)===false,$label.' row fails closed');
}

// ---- 8. the query shape that makes this decidable: exactly one row on success, so false can only be a failure
fresh_pg();
stobeAreaGoalReadCurrentTrip('Laru','Shay',1000,$scope);
$qs=array_values(array_filter($GLOBALS['db']->queries,static fn($q)=>str_contains($q,"type='travel_agreement'")));
ac(count($qs)>=1 && preg_match('/^\s*SELECT\s*\(\s*SELECT\s+data\s+FROM\s+eventlog/i',$qs[0])===1,'8: the trip read uses the always-one-row scalar-subquery shape');

echo "RESULT IMM26-FIX24BFETCH PASS assertions=$n\n";
