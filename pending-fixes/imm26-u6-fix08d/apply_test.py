p='/root/imm26/compose/tests/imm26_wpC2_followups_comm_regression.php'
s=open(p).read()
anchor='\ncleanup();\necho "OK $checks checks\\n";'
assert s.count(anchor)==1, s[-80:]
new='''
/* ---------- imm26 08-d: finished trip is the ONLY open topic (retire must commit, not roll back) ---------- */
cleanup(); $GLOBALS['T_ATTN'] = []; $GLOBALS['T_COMM'] = ['amount' => 'normal', 'plan_notice' => 'normal']; $GLOBALS['T_PREFS'] = [];
$npcM = ['name' => 'Marta', 'metadata' => []];
$scopeM = stobeSocialPreferenceScope('Marta', $npcM, 'Shay');
$readM = fn(int $now) => stobeFollowupRead($scopeM, $now, true);
$TS = T0 + 800000;
check('single plan created (Marta)', stobeSocialFollowupsCapture('Marta', $npcM, 'Shay', "I'm heading to the Hub to find my brother.",
    ['followup_update' => ['decision' => 'NONE', 'topic_id' => '', 'kind' => 'personal_plan', 'source_quote' => '']],
    $base + ['manual_turn_id' => 'turn-single', 'stream_gamets' => $TS]) === true);
$onlyOpen = array_filter($readM($TS + 100), fn($r) => $r['status'] === 'open');
check('exactly one open topic', count($onlyOpen) === 1);
$solo = array_key_first($onlyOpen);
storeEvent('travel_agreement', time(), $TS + 5000, 'travel-v1:102:1:' . json_encode(['status' => 'COMPLETED', 'destination' => 'The Hub', 'kind' => 'same_route']));
$soloMeta = ['eligible_bored_turn' => true, 'social_optional_speech_allowed' => true, 'social_scope' => ['x' => 1], 'stream_gamets' => $TS + 6000, 'gamets' => $TS + 6000];
check('single-topic claim returns null (nothing else to ask)', stobeSocialFollowupsClaim('Marta', $npcM, 'Shay', $soloMeta) === null);
$afterSolo = $readM($TS + 6000);
check('single finished-trip topic stays retired (not rolled back)', ($afterSolo[$solo]['status'] ?? '') === 'closed' && ($afterSolo[$solo]['closed_reason'] ?? '') === 'outcome_completed');
'''
s=s.replace(anchor,new+anchor)
open(p,'w').write(s)
print('patched')
