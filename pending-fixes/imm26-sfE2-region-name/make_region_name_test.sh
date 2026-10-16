#!/usr/bin/env bash
# make_region_name_test.sh <server-tree-root>: writes <root>/tests/imm26_sfE2_region_name_forward.php from the first 44 lines (fixture db/globals) of imm26_wpE_region_regression.php
# plus 4 assertions: native spatial.region_name survives stobeTravelLocalCandidates, a building-anchored candidate whose region_name matches is a valid area-goal endpoint
# WITHOUT any destination memory (known regions []), a mismatching region_name is not, and a missing region_name is not. Fails BEFORE apply_region_name_forward.py, passes after.
R="${1:?tree root}"; T="$R/tests/imm26_sfE2_region_name_forward.php"
head -44 "$R/tests/imm26_wpE_region_regression.php" > "$T"
cat >> "$T" <<'PHPEOF'
function ac(bool $ok,string $label){global $n;if(!$ok)throw new RuntimeException('FAIL '.$label);++$n;}
$n=0;
$mk=static fn(array $sp)=>['name'=>'Laru','extended_data'=>['relationships'=>['Shay'=>['aff'=>70]]],'metadata'=>['travel_destinations'=>[[
  'id'=>'local:world:2543823360:78','actor_serial'=>2543823360,'observed'=>true,'observed_unix'=>time(),'reachability'=>'path_confirmed','kind'=>'landmark',
  'label'=>'Old watchtower','x'=>100.0,'y'=>0.0,'z'=>200.0,'spatial'=>$sp]]]];
$c1=array_values(stobeTravelLocalCandidates('Laru',$mk(['anchor_type'=>'building','anchor_name'=>'Watchtower','region_name'=>'Vain'])));
ac(count($c1)===1 && ($c1[0]['spatial']['region_name']??'')==='Vain','native spatial.region_name is forwarded to the normalized candidate');
ac(stobeAreaGoalEndpointValid($c1[0],'Vain',2543823360,1000,[],'Stack'),'building-anchored candidate with matching region_name is a valid endpoint without destination memory');
ac(!stobeAreaGoalEndpointValid($c1[0],'Okran',2543823360,1000,[],'Stack'),'a different consented region does not match');
$c2=array_values(stobeTravelLocalCandidates('Laru',$mk(['anchor_type'=>'building','anchor_name'=>'Watchtower'])));
ac(count($c2)===1 && !stobeAreaGoalEndpointValid($c2[0],'Vain',2543823360,1000,[],'Stack'),'no region_name and no town memory stays invalid (never inferred)');
echo "RESULT IMM26-SFE2-REGION-NAME-FORWARD PASS assertions=$n\n";
PHPEOF
