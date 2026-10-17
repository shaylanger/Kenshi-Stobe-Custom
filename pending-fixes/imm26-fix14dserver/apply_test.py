#!/usr/bin/env python3
"""imm26 fix14dserver: add the 14-d regression block to tests/imm26_wpE_activity_kinds_regression.php (idempotent, *.bak-fix14dserver).
usage: python3 apply_test.py <tree-root> [--check]
Run: STOBE_DB_NAME=stobe_test php tests/imm26_wpE_activity_kinds_regression.php   (the 'prompt spells out' checks fail on the unpatched prompt)."""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
TF = os.path.join(root, 'tests/imm26_wpE_activity_kinds_regression.php')
ANCH = 'echo "RESULT IMM26-WPE-ACTIVITY-KINDS "'
MARK = 'fix14dserver'
NEW = r'''// =====================================================================================================
// fix14dserver (row 14-d): the prompt spells out the object shapes; the adapter stays strict about them
// =====================================================================================================
{
    $msgs14 = []; stobeActivityAppendStaticContract($msgs14); $rules14 = $msgs14[0]['content'];
    check('fix14dserver prompt spells out discoveryRef as an object with both keys inside', str_contains($rules14, 'discoveryRef = an OBJECT {"candidateId"') && str_contains($rules14, 'never as top-level fields and never a bare string'));
    check('fix14dserver prompt spells out routeRef and campZoneRef objects', str_contains($rules14, 'routeRef = an OBJECT') && str_contains($rules14, 'campZoneRef = an OBJECT {"candidateId"'));
    check('fix14dserver prompt carries a complete ClearGroup example', str_contains($rules14, '"kind":"ClearGroup"') && str_contains($rules14, '"agreedTargets":[<serial>,<serial>]') && str_contains($rules14, '"routeRef":{"candidateId"'));
    $camp14 = ['candidateId'=>'v1:' . str_repeat('a', 48), 'scopeDigest'=>str_repeat('b', 64)];
    $good14 = ['kind'=>'ClearGroup','sourceId'=>'src-1','discoveryRef'=>['candidateId'=>'d1','targetSerial'=>7],'routeRef'=>['candidateId'=>'route-1'],
        'campZoneRef'=>$camp14,'agreedTargets'=>[5,6,7,8,9]];
    $p14 = null; $e14 = throwsMsg(function() use (&$p14, $adapter, $ctx, $good14) { $p14 = $adapter->propose($ctx, $good14); });
    check('fix14dserver the documented example shape proposes (campZoneRef object + discoveryRef object accepted)', $e14 === '' && ($p14['agreement']['campZone'] ?? null) === $camp14 && count($p14['agreement']['agreedTargets']) === 5, $e14);
    $bad14 = $good14; $bad14['targetSerial'] = 7; $bad14['discoveryRef'] = 'activity-proposal:1:2'; unset($bad14['routeRef']);
    check('fix14dserver the req_6ad2e2f8eadf4 shape (top-level targetSerial, string discoveryRef) is still rejected', throwsMsg(fn() => $adapter->propose($ctx, $bad14)) === 'Unexpected activity fields');
    $bad14b = $good14; $bad14b['discoveryRef'] = 'activity-proposal:1:2';
    check('fix14dserver a bare-string discoveryRef is still rejected on its own', throwsMsg(fn() => $adapter->propose($ctx, $bad14b)) === 'Missing discovery reference');
    $bad14c = $good14; $bad14c['campZoneRef']['extra'] = 1;
    check('fix14dserver campZoneRef accepts only candidateId and scopeDigest', throwsMsg(fn() => $adapter->propose($ctx, $bad14c)) === 'Unexpected activity fields');
}

'''
s = open(TF, encoding='utf-8', newline='').read()
if MARK in s:
    print('tests already present:', TF); sys.exit(0)
assert s.count(ANCH) == 1, 'anchor count %d' % s.count(ANCH)
if check:
    print('anchor ok:', TF); sys.exit(0)
shutil.copy2(TF, TF + '.bak-' + MARK)
open(TF, 'w', encoding='utf-8', newline='').write(s.replace(ANCH, NEW + ANCH))
print('tests added:', TF)
