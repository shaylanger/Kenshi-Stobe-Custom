#!/usr/bin/env python3
"""imm26-fix-19f: usage patch.py <tree-root> [--test-only]. Anchored, idempotent, preserves line endings. Root may hold lib/ directly (compose)
or <root>/site/lib (lane trees). Counts execution.resume_count in stobeCommitmentNoteTravelRequest (the one place an injected and a
model-emitted resume both pass), drops the early increment in stobeCommitmentResumeAction, and writes the honest resume_failure when
the load-time entry gate refuses with 'resume_count'. Default cap (3) unchanged."""
import sys, os
root = sys.argv[1]
if os.path.isdir(os.path.join(root, 'site', 'lib')): root = os.path.join(root, 'site')
here = os.path.dirname(os.path.abspath(__file__))
NL = chr(10); CRLF = chr(13) + chr(10)

def patch(rel, anchor, new, marker, before=False, replace=False):
    p = os.path.join(root, rel); s = open(p, encoding='utf-8', newline='').read()
    eol = CRLF if CRLF in s else NL
    anchor = anchor.replace(CRLF, NL).replace(NL, eol); new = new.replace(CRLF, NL).replace(NL, eol)
    if marker in s: print('already patched', rel, marker); return
    assert s.count(anchor) == 1, (rel, 'anchor count', s.count(anchor), anchor[:60])
    s = s.replace(anchor, new if replace else ((new + anchor) if before else (anchor + new)))
    open(p, 'w', encoding='utf-8', newline='').write(s); print('patched', rel)

if '--test-only' not in sys.argv:
    # (a) count the resume where the request is noted
    patch('lib/commitment_lifecycle.php',
"""    $state['execution'] = array_replace($execution,[
        'phase'=>'requested', 'changed_gamets'=>$gamets,
        'request_id'=>hash('sha256',strval($state['agreement_id'] ?? '').'|'.$gamets.'|'.$action),
        'requested_action'=>$action,
    ]);
""",
"""    // imm26-fix-19f: a resume request after a load (injected OR model-emitted) is counted here, once, so the cap cannot be bypassed.
    $resumed = ($execution['phase'] ?? '') === 'interrupted_by_load'
        ? ['resume_count'=>intval($execution['resume_count'] ?? 0) + 1, 'resume_gamets'=>$gamets] : [];
    $state['execution'] = array_replace($execution,[
        'phase'=>'requested', 'changed_gamets'=>$gamets,
        'request_id'=>hash('sha256',strval($state['agreement_id'] ?? '').'|'.$gamets.'|'.$action),
        'requested_action'=>$action,
    ] + $resumed);
""", 'imm26-fix-19f', replace=True)
    # (b) drop the early increment + pre-write in the injection
    patch('lib/commitment_native_bridge.php',
"""        $state['execution']['resume_count'] = intval($state['execution']['resume_count'] ?? 0) + 1;
        $state['execution']['resume_gamets'] = $gamets;
        if (!stobeTravelWrite($actor,$speaker,$gamets,$state)) return '';
        $GLOBALS['STOBE_TRIP_RESUME_DONE'][$actor] = $gamets;
        stobeLogInfo('Trip resume injected',['npc'=>$actor,'action'=>$action,'resume_count'=>$state['execution']['resume_count']]);
""",
"""        // imm26-fix-19f: resume_count/resume_gamets are written by stobeCommitmentNoteTravelRequest when this action is processed.
        $GLOBALS['STOBE_TRIP_RESUME_DONE'][$actor] = $gamets;
        stobeLogInfo('Trip resume injected',['npc'=>$actor,'action'=>$action,'resume_count'=>intval($state['execution']['resume_count'] ?? 0) + 1]);
""", 'imm26-fix-19f', replace=True)
    # (c) honest resume_failure at the capped load
    patch('lib/commitment_native_bridge.php',
"""            if (stobeCommitmentResumeEntryReason($actor,$speaker,$state,$gamets) === '') {
                $state['execution'] = stobeCommitmentInterruptExecution($state['execution'],$gamets,$absenceId);
                stobeTravelWrite($actor,$speaker,$gamets,$state);
                return;
            }
""",
"""            $entryReason = stobeCommitmentResumeEntryReason($actor,$speaker,$state,$gamets);
            if ($entryReason === '') {
                $state['execution'] = stobeCommitmentInterruptExecution($state['execution'],$gamets,$absenceId);
                stobeTravelWrite($actor,$speaker,$gamets,$state);
                return;
            }
            // imm26-fix-19f: the resume cap ends the trip with the honest resume_failure, not the generic post-load row.
            if ($entryReason === 'resume_count') {
                stobeCommitmentResumeFail($actor,$speaker,$gamets,$state,"I could not get our interrupted journey moving again, so we'll need a fresh plan.",'resume_count');
                return;
            }
""", 'imm26-fix-19f: the resume cap', replace=True)

T = 'tests/imm26_wpL2_model_emitted_resume_regression.php'
patch(T, "$ev = tr_receipt($s, $A, $As, 'world-new-bbbbbbbb', 2, 'running', 'wl2-ev-running');" + NL,
      "check('model-emitted post-load start: resume_count is 1 with resume_gamets (imm26-fix-19f)', intval($s['execution']['resume_count'] ?? 0) === 1 && intval($s['execution']['resume_gamets'] ?? 0) === 1200, $s['execution'] ?? null);" + NL,
      'resume_gamets (imm26-fix-19f)', before=True)
patch(T, 'echo "imm26_wpL2_model_emitted_resume: ',
      open(os.path.join(here, 'test_addition.php'), encoding='utf-8', newline='').read(), 'imm26-fix-19f: resume_count is counted', before=True)
