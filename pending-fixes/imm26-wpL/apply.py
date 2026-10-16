#!/usr/bin/env python3
"""imm26-wpL: trips to a LOCAL LANDMARK (source=native_local: "higher ground to the east", "a rise to the west") resume after
save+load, like visited_location trips (Shay 2026-10-15, memory trip-continues-after-load, row 19-a option B).
SERVER ONLY. Why no DLL change: the native OWNED_TRAVEL start only revalidates the local candidate when the wire carries a
non-empty candidate_id (NativeTravelLifecycle.cpp ~622: `if (!candidate.empty() && !LocalTravel::ValidateForDispatch(...))`);
the candidate registry is per-process/session and ids die on load. The stored destination_point already holds x/y/z + label, so
on a RESUMED start (execution.resume_count > 0) the server sends the stored coordinates with candidate_id='' and native Start()s to them.
Changes in lib/commitment_native_bridge.php (CRLF-preserving, anchored, idempotent):
  1. stobeCommitmentResumeSettings: + local_enabled (STOBE_TRIP_RESUME_LOCAL_ENABLED, default 1; 0 = old behaviour for landmarks).
  2. stobeCommitmentResumeEntryReason: native_local accepted when id/actor_serial/label are valid (plan_hash check still applies).
  3. stobeCommitmentResumeCheck: destination_gone zone test only for visited_location; native_local needs valid id + actor serial.
  4. stobeCommitmentWrapDispatch: candidate_id is '' on a resumed start.
Also rewrites row 5f of tests/imm26_trip_resume_regression.php (it asserted the old "native_local -> FAILED") and installs
tests/imm26_wpL_landmark_resume_regression.php.
Usage (WSL): python3 apply.py <tree-root>"""
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
if 'STOBE_TRIP_RESUME_LOCAL_ENABLED' not in s:
    edits = [
("""        'max_count'=>max(1,min(10,intval($get('STOBE_TRIP_RESUME_MAX_COUNT','3')))),
""",
"""        'max_count'=>max(1,min(10,intval($get('STOBE_TRIP_RESUME_MAX_COUNT','3')))),
        'local_enabled'=>in_array(strtolower(trim($get('STOBE_TRIP_RESUME_LOCAL_ENABLED','1'))),['1','true','yes','on'],true),
"""),
("""    if (!is_array($point) || ($point['source'] ?? '') !== 'visited_location') return 'destination_not_resumable';
    foreach (['x','y','z'] as $axis) {
        if (!is_numeric($point[$axis] ?? null) || !is_finite(floatval($point[$axis]))
            || abs(floatval($point[$axis])) > 10000000) return 'destination_not_resumable';
    }
""",
"""    $source = is_array($point) ? strval($point['source'] ?? '') : '';
    if ($source !== 'visited_location' && !($source === 'native_local' && $settings['local_enabled'])) return 'destination_not_resumable';
    foreach (['x','y','z'] as $axis) {
        if (!is_numeric($point[$axis] ?? null) || !is_finite(floatval($point[$axis]))
            || abs(floatval($point[$axis])) > 10000000) return 'destination_not_resumable';
    }
    // A local landmark is resumed from its stored x/y/z (the native candidate id dies on load): it must still be bound to this actor.
    if ($source === 'native_local' && !stobeCommitmentLocalPointValid($actor,$point)) return 'destination_not_resumable';
"""),
("""/** '' when an ACCEPTED visited-town trip may pause""",
"""/** A stored native_local destination is resumable only with a well-formed id, a label and this actor's serial. */
function stobeCommitmentLocalPointValid(string $actor, array $point): bool {
    return preg_match('/^[A-Za-z0-9_.:-]{1,96}$/D',strval($point['id'] ?? '')) === 1
        && trim(strval($point['label'] ?? '')) !== ''
        && function_exists('stobeTravelActorSerial')
        && intval($point['actor_serial'] ?? 0) > 0
        && intval($point['actor_serial']) === stobeTravelActorSerial($actor);
}

/** '' when an ACCEPTED visited-town trip may pause"""),
("""    if (!is_array($state['destination_point'] ?? null) || ($state['destination_point']['source'] ?? '') !== 'visited_location'
        || $destination === '' || ($zoneNames !== [] && !in_array(mb_strtolower($destination),$zoneNames,true))) {
""",
"""    $dpoint = is_array($state['destination_point'] ?? null) ? $state['destination_point'] : null;
    $dsource = $dpoint === null ? '' : strval($dpoint['source'] ?? '');
    $gone = $dpoint === null || $destination === '';
    if (!$gone && $dsource === 'visited_location') $gone = ($zoneNames !== [] && !in_array(mb_strtolower($destination),$zoneNames,true));
    elseif (!$gone && $dsource === 'native_local') $gone = !$settings['local_enabled'] || !stobeCommitmentLocalPointValid($actor,$dpoint);
    elseif (!$gone) $gone = true;
    if ($gone) {
"""),
("""        'candidate_id'=>($point['source'] ?? '') === 'native_local' ? strval($point['id'] ?? '') : ''];""",
"""        // A resumed start (after a load) uses the stored x/y/z only: the native candidate registry does not survive a load.
        'candidate_id'=>(($point['source'] ?? '') === 'native_local' && intval($state['execution']['resume_count'] ?? 0) < 1) ? strval($point['id'] ?? '') : ''];"""),
    ]
    for a, b in edits:
        assert s.count(a) == 1, 'anchor missing/duplicated: ' + a[:70]
        s = s.replace(a, b)
    save(p, s, crlf)
    print('bridge patched')
else:
    print('bridge already applied')

# old 5f row asserted the pre-wpL behaviour
t = os.path.join(root, 'tests', 'imm26_trip_resume_regression.php')
ts, tcrlf = load(t)
old5f = """// 5f native_local destination (candidate ids die on load): FAILED as today
[$I, $Is] = tr_actor();
tr_seed($I, $Is, ['point'=>['source'=>'native_local', 'label'=>'Old Gate', 'x'=>100.0, 'y'=>2.0, 'z'=>300.0]]);
$r = tr_turn($I, $Is, 1100, ['live'=>true]);
tr_expect_failed('native_local destination', $r);
"""
new5f = """// 5f native_local destinations now resume from their stored x/y/z (imm26-wpL: tests/imm26_wpL_landmark_resume_regression.php)
"""
if old5f in ts:
    save(t, ts.replace(old5f, new5f), tcrlf); print('5f row replaced')
else:
    assert new5f in ts, '5f anchor missing'; print('5f already replaced')
shutil.copy(os.path.join(here, 'imm26_wpL_landmark_resume_regression.php'), os.path.join(root, 'tests', 'imm26_wpL_landmark_resume_regression.php'))
print('applied')
