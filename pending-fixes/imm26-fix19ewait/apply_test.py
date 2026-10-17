#!/usr/bin/env python3
"""imm26 fix19ewait: add section 9 to tests/imm26_trip_resume_regression.php (idempotent, *.bak-fix19ewait).
Every wait verdict of stobeCommitmentResumeCheck writes ONE 'Trip resume wait' INFO line (reason code + inputs); a resume turn writes none.
usage: python3 apply_test.py <tree-root> [--check]
Run: STOBE_DB_NAME=stobe_test php tests/imm26_trip_resume_regression.php   (the new 'fix19ewait' checks fail on the unpatched lib)."""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
TF = os.path.join(root, 'tests/imm26_trip_resume_regression.php')
ANCH = 'echo "imm26_trip_resume: $pass passed, $fail failed\\n";\n'
MARK = 'fix19ewait'
NEW = r'''// =====================================================================================================
// 9. fix19ewait (row 19-e): a wait verdict is never silent - one 'Trip resume wait' line with the reason code and its inputs
// =====================================================================================================
function tr_log_offset(): int { clearstatcache(); $p = stobeGetLogPath('stobeserver.log'); return is_file($p) ? intval(filesize($p)) : 0; }
/** The decoded 'Trip resume wait' context objects for $actor written after $offset. */
function tr_wait_lines(int $offset, string $actor): array {
    $p = stobeGetLogPath('stobeserver.log');
    $fh = @fopen($p, 'rb'); if (!$fh) return [];
    fseek($fh, $offset); $chunk = stream_get_contents($fh); fclose($fh);
    $out = [];
    foreach (preg_split('/\r?\n/', strval($chunk)) as $line) {
        if (strpos($line, 'Trip resume wait |') === false) continue;
        $j = json_decode(substr($line, strpos($line, '| {') + 2), true);
        if (is_array($j) && ($j['npc'] ?? '') === $actor) $out[] = $j;
    }
    return $out;
}
foreach ([
    'not_in_people'      => ['live'=>false],
    'unavailable'        => ['combat'=>true],
    'absence_unverified' => ['absent'=>false],
    'no_snapshot'        => ['__header'=>'other-receipt'],
] as $why => $opt) {
    [$W, $Ws] = tr_actor(); $seedW = tr_seed($W, $Ws);
    tr_turn($W, $Ws, 1100, ['live'=>false]);                      // enter interrupted_by_load, out of range
    $savedHeader = $_SERVER['HTTP_X_STOBE_PLAYTHROUGH'];
    if (isset($opt['__header'])) { $_SERVER['HTTP_X_STOBE_PLAYTHROUGH'] = $opt['__header']; unset($opt['__header']); }
    $off = tr_log_offset();
    $r = tr_turn($W, $Ws, 1150, $opt);
    $_SERVER['HTTP_X_STOBE_PLAYTHROUGH'] = $savedHeader;
    $lines = tr_wait_lines($off, $W);
    $l = $lines[0] ?? [];
    check("fix19ewait ($why): exactly one 'Trip resume wait' line, why=$why", count($lines) === 1 && ($l['why'] ?? '') === $why, $lines);
    check("fix19ewait ($why): the line carries the agreement id, gamets, interrupted_gamets and resume_count", ($l['agreement_id'] ?? '') === $seedW['agreement_id']
        && intval($l['gamets'] ?? 0) === 1150 && intval($l['interrupted_gamets'] ?? 0) === 1100 && array_key_exists('resume_count', $l), $l);
    check("fix19ewait ($why): logging changes nothing (still interrupted_by_load, no wire)", tr_phase($r['state']) === 'interrupted_by_load' && $r['wires'] === [], [tr_phase($r['state']), $r['wires']]);
    if ($why === 'unavailable') check('fix19ewait (unavailable): the inputs name the availability reasons', in_array('in_combat', $l['reasons'] ?? [], true), $l);
    if ($why === 'absence_unverified') check('fix19ewait (absence_unverified): the inputs show the absent flag is false', array_key_exists('absent_flag', $l) && $l['absent_flag'] === false, $l);
    if ($why === 'no_snapshot') check('fix19ewait (no_snapshot): the inputs name the failing snapshot gate', ($l['snapshot'] ?? '') === 'receipt_mismatch', $l);
    if ($why === 'not_in_people') check('fix19ewait (not_in_people): the inputs say how many people were listed', array_key_exists('people_n', $l), $l);
    // the next calm in-range turn resumes and writes no wait line
    $off = tr_log_offset();
    $r = tr_turn($W, $Ws, 1160, ['live'=>true]);
    check("fix19ewait ($why): the resume turn writes no wait line and still resumes", tr_wait_lines($off, $W) === [] && count($r['wires']) === 1, [count($r['wires']), tr_wait_lines($off, $W)]);
}

'''
s = open(TF, encoding='utf-8', newline='').read()
if MARK in s:
    print('tests already present:', TF); sys.exit(0)
assert s.count(ANCH) == 1, 'anchor count %d' % s.count(ANCH)
if check:
    print('anchor ok:', TF); sys.exit(0)
shutil.copy2(TF, TF + '.bak-fix19ewait')
open(TF, 'w', encoding='utf-8', newline='').write(s.replace(ANCH, NEW + ANCH))
print('tests added:', TF)
