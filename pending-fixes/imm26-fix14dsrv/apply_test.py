#!/usr/bin/env python3
"""Add the ClearGroup boundedQuantity regression checks to imm26_wpE_activity_kinds_regression.php. usage: apply_test.py <tree-root>"""
import sys, os
p = os.path.join(sys.argv[1], 'tests/imm26_wpE_activity_kinds_regression.php')
s = open(p, encoding='utf-8').read()
if 'fix14dsrv' in s:
    print('already'); sys.exit(0)
a = "check('ClearGroup without targets rejected'"
i = s.index(a); j = s.index('\n', i) + 1
add = r"""// imm26 fix14dsrv: a model-supplied boundedQuantity must not reject a ClearGroup offer; collect kinds alias it; unknown keys still reject.
$cg = null; $cgErr = throwsMsg(function() use (&$cg, $adapter, $ctx, $base) { $cg = $adapter->propose($ctx, $base + ['kind'=>'ClearGroup','resourceId'=>'','boundedQuantity'=>5,'agreedTargets'=>[5,6,7,8,9]]); });
check('ClearGroup ignores a model-supplied count (boundedQuantity)', $cgErr === '' && count($cg['agreement']['agreedTargets']) === 5 && $cg['agreement']['quantity'] === 0, $cgErr);
$hq = null; $hqErr = throwsMsg(function() use (&$hq, $adapter, $ctx, $base) { $hq = $adapter->propose($ctx, $base + ['kind'=>'Hunt','resourceId'=>'meat','boundedQuantity'=>2]); });
check('Hunt aliases boundedQuantity to quantity', $hqErr === '' && $hq['agreement']['quantity'] === 2, $hqErr);
check('unknown activity key still rejected (whitelist closed)', str_contains(throwsMsg(fn() => $adapter->propose($ctx, $base + ['kind'=>'ClearGroup','resourceId'=>'','agreedTargets'=>[5,6],'bogusKey'=>1])), 'Unexpected activity fields'));
check('static contract no longer asks for a bounded quantity on every kind', !str_contains($messages[0]['content'], 'bounded quantity'));
"""
open(p, 'w', encoding='utf-8', newline='').write(s[:j] + add + s[j:])
print('test added')
