// imm26-fix-19f: resume_count is counted where the resume REQUEST is noted, so an injected and a model-emitted resume count the same,
// and the default cap (3) bites on the 4th load with the honest resume_failure=resume_count (not the generic post-load FAILED row).
[$F, $Fs] = tr_actor(); $seedF = tr_seed($F, $Fs);
$rcSeen = []; $lastState = null;
for ($load = 1; $load <= 3; $load++) {
    $world = 'world-f' . $load . '-ffffffff'; $gen = $load + 1; $g0 = 1000 + $load * 400;
    tr_turn($F, $Fs, $g0, ['world'=>$world, 'gen'=>$gen, 'live'=>false]);
    $r = tr_turn($F, $Fs, $g0 + 50, ['world'=>$world, 'gen'=>$gen, 'live'=>true, 'actions'=>['TRAVEL_LOCATION@Squin']]);
    $lastState = $r['state'];
    $rcSeen[] = intval($lastState['execution']['resume_count'] ?? 0);
    $evF = tr_receipt($lastState, $F, $Fs, $world, $gen, 'running', 'f19-ev-run-' . $load);
    $r = tr_turn($F, $Fs, $g0 + 60, ['world'=>$world, 'gen'=>$gen, 'live'=>true, 'receipts'=>[$evF]]);
}
check('model-emitted resumes count 1,2,3 (one per load)', $rcSeen === [1, 2, 3], $rcSeen);
check('model-emitted loop keeps one agreement id', ($r['state']['agreement_id'] ?? '') === $seedF['agreement_id'], $r['state']['agreement_id'] ?? null);
$r = tr_turn($F, $Fs, 2800, ['world'=>'world-f4-ffffffff', 'gen'=>5, 'live'=>false]);
$s = $r['state'];
check('4th load with default cap 3: FAILED with resume_failure=resume_count (honest)', ($s['status'] ?? '') === 'FAILED' && tr_phase($s) === 'failed'
    && ($s['execution']['resume_failure'] ?? '') === 'resume_count' && trim(strval($s['execution']['reason'] ?? '')) !== '', [$s['status'] ?? null, tr_phase($s), $s['execution']['resume_failure'] ?? null]);
$r = tr_turn($F, $Fs, 2850, ['world'=>'world-f4-ffffffff', 'gen'=>5, 'live'=>true, 'actions'=>['TRAVEL_LOCATION@Squin']]);
check('4th load: no OWNED_TRAVEL wire', $r['wires'] === [], $r['wires']);

