#!/usr/bin/env python3
"""imm26-wpL2: local-landmark (native_local) trip resume still FAILED after wpL on 4080-i4 (19-a landmark variant):
interrupted_by_load -> requested -> FAILED reason local_plan_expired_or_unknown, execution.resume_count 0, no OWNED_TRAVEL accepted.
ROOT CAUSE: wpL sends candidate_id='' only when execution.resume_count >= 1. resume_count is incremented only by the server
resume INJECTION (stobeCommitmentResumeAction). After the load the player talks to the NPC and the prompt tells the model the walk
resumes; the model emits TRAVEL_LOCATION@<landmark> itself, so stobeCommitmentResumeAction sees an action carrying movement and
returns '' (by design) before incrementing resume_count. The ordinary pipeline then builds OWNED_TRAVEL with resume_count 0 and
candidate_id=local:<sess>:<serial>:<n>; native (NativeTravelLifecycle.cpp ~667) calls LocalTravel::ValidateForDispatch, whose
per-process registry no longer has the id -> reject local_plan_expired_or_unknown -> FAILED.
FIX (server only): candidate_id is sent only for a start that has never been through a load: no resume_count, no interrupted_gamets,
no prior_request_id (all three are kept in execution once interrupted_by_load was entered). Anything after a load Start()s to the stored
x/y/z with candidate_id ''. Kill switch: STOBE_TRIP_RESUME_LOCAL_ENABLED=0 (wpL setting) still turns landmark resume off entirely.
Changes (lib/commitment_native_bridge.php, CRLF-preserving, anchored, idempotent):
  1. new helper stobeCommitmentExecutionAfterLoad(array $execution): bool
  2. stobeCommitmentWrapDispatch: candidate_id uses it instead of resume_count < 1.
Also installs tests/imm26_wpL2_model_emitted_resume_regression.php.
Requires wpL applied first. Usage (WSL): python3 apply.py <tree-root>"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))

def load(p):
    s = open(p, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    return (s.replace('\r\n', '\n') if crlf else s), crlf
def save(p, s, crlf):
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)

p = os.path.join(root, 'lib', 'commitment_native_bridge.php')
s, crlf = load(p)
if 'stobeCommitmentExecutionAfterLoad' not in s:
    edits = [
("""/** A stored native_local destination is resumable only with""",
"""/** True once this trip's execution has been through a save/load (interrupt keeps interrupted_gamets/prior_* afterwards, whoever
 * issues the next start: the resume injection or the model's own TRAVEL_LOCATION). Native candidate ids do not survive a load. */
function stobeCommitmentExecutionAfterLoad(array $execution): bool {
    return intval($execution['resume_count'] ?? 0) >= 1 || intval($execution['interrupted_gamets'] ?? 0) > 0
        || trim(strval($execution['prior_request_id'] ?? '')) !== '';
}

/** A stored native_local destination is resumable only with"""),
("""(($point['source'] ?? '') === 'native_local' && intval($state['execution']['resume_count'] ?? 0) < 1) ? strval($point['id'] ?? '') : ''];""",
"""(($point['source'] ?? '') === 'native_local' && !stobeCommitmentExecutionAfterLoad(is_array($state['execution'] ?? null) ? $state['execution'] : [])) ? strval($point['id'] ?? '') : ''];"""),
]
    for old, new in edits:
        if s.count(old) != 1:
            sys.exit('ANCHOR MISSING or not unique: ' + old[:70])
        s = s.replace(old, new)
    save(p, s, crlf)
    print('patched', p)
else:
    print('already patched', p)

dst = os.path.join(root, 'tests', 'imm26_wpL2_model_emitted_resume_regression.php')
src = os.path.join(here, 'imm26_wpL2_model_emitted_resume_regression.php')
if os.path.exists(src):
    shutil.copyfile(src, dst); print('installed', dst)
