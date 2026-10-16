#!/usr/bin/env python3
"""imm26-sfD (row 10-b gift leg): lib/social_property.php inDeal() kept a character "in a deal" forever once ANY contract of hers had
performance_started_unix > 0 and resolved_at NULL, whatever its status. A CANCELLED/EXPIRED/COMPLETE contract whose terminal path never set resolved_at
(the generic stobeDealTransition CANCELLED path; only negotiation_phase1.php:695 and negotiation_engine.php:404/1421/1486 set it) therefore made every later item_transfer
to or from her `deal_payment` (no gift credit).  Fix: a contract is open only while its status is ACCEPTED/AWAITING_PERFORMANCE with resolved_at NULL; a finished
contract keeps counting for the existing 10-minute grace window, measured from COALESCE(resolved_at, updated_at) (same pattern as negotiation_engine.php:1517).
Usage (WSL): python3 inDeal-terminal.py <tree-root>     (anchored, CRLF-aware, idempotent; also installs tests/imm26_sfD_indeal_regression.php)
Deploy to a lane (NOT done by this script):  bash <this dir>/deploy-indeal.sh <lane-root>...   (inside WSL; sha-checked, backs up, php -l)"""
import os
import shutil
import sys

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, 'lib', 'social_property.php')
raw = open(p, 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
TEST = 'imm26_sfD_indeal_regression.php'
NEW_TAIL = "AND performance_started_unix > 0 AND ((status IN ('ACCEPTED','AWAITING_PERFORMANCE') AND resolved_at IS NULL)"
if NEW_TAIL in s:
    print('already applied')
else:
    old = ("              AND performance_started_unix > 0 AND (resolved_at IS NULL OR resolved_at > now() - interval '10 minutes') LIMIT 1\", [$a['name'], $b['name']]);\n")
    new = ("              AND performance_started_unix > 0 AND ((status IN ('ACCEPTED','AWAITING_PERFORMANCE') AND resolved_at IS NULL)\n"
           "              OR COALESCE(resolved_at, updated_at) > now() - interval '10 minutes') LIMIT 1\", [$a['name'], $b['name']]);\n")
    assert s.count(old) == 1, 'anchor missing or not unique (inDeal SELECT)'
    s = s.replace(old, new)
    out = s.replace('\n', '\r\n') if crlf else s
    open(p, 'wb').write(out.encode('utf-8'))
    print('patched', p)
td = os.path.join(root, 'tests')
if os.path.isdir(td):
    shutil.copyfile(os.path.join(here, TEST), os.path.join(td, TEST))
    print('installed test', TEST)
