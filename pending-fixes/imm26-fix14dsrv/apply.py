#!/usr/bin/env python3
"""imm26 fix14dsrv F1/F1b: alias/drop boundedQuantity before the closed key whitelist.
usage: python3 apply.py <tree-root> [--check]   (idempotent; asserts anchors; writes .bak-fix14dsrv)
"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
AD = os.path.join(root, 'lib/activity/ActivityAgreementAdapter.php')
PR = os.path.join(root, 'lib/activity/activity_prompt.php')
MARK = 'imm26 fix14dsrv'

ANCH = "        $this->keys($intent, ['kind', 'sourceId', 'resourceId', 'quantity', 'discoveryRef', 'agreedTargets', 'routeRef', 'campZoneRef']);\n"
INS = (
"        // imm26 fix14dsrv: the rules text said \"bounded quantity\"; the model may return it as boundedQuantity (or a count on ClearGroup).\n"
"        // Normalise before the closed whitelist: collect kinds alias it to quantity, other kinds drop the count. Unknown keys still reject.\n"
"        $shapeEarly = is_string($intent['kind'] ?? null) ? stobeActivityKindShape($intent['kind']) : '';\n"
"        if ($shapeEarly === 'collect') {\n"
"            if (array_key_exists('boundedQuantity', $intent)) {\n"
"                if (!array_key_exists('quantity', $intent)) { $intent['quantity'] = $intent['boundedQuantity']; }\n"
"                unset($intent['boundedQuantity']);\n"
"            }\n"
"        } elseif ($shapeEarly !== '') { unset($intent['boundedQuantity'], $intent['quantity']); }\n"
)
P_OLD = "exact sourceId/resourceId, bounded quantity, discoveryRef"
P_NEW = "exact sourceId/resourceId, quantity (collect kinds only; omit it for ClearGroup and place kinds, the ClearGroup size is its fixed agreedTargets), discoveryRef"

def patch(path, old, new, replace_with):
    s = open(path, encoding='utf-8').read()
    if MARK in s or new in s:
        print('already patched:', path); return
    assert s.count(old) == 1, 'anchor count %d in %s' % (s.count(old), path)
    if check: print('anchor ok:', path); return
    shutil.copy2(path, path + '.bak-fix14dsrv')
    open(path, 'w', encoding='utf-8', newline='').write(s.replace(old, replace_with))
    print('patched:', path)

patch(AD, ANCH, INS, INS + ANCH)
patch(PR, P_OLD, P_NEW, P_NEW)
