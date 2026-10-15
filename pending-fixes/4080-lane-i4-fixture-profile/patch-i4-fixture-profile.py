#!/usr/bin/env python3
"""Add the 4080-i4 provider-fixture route profile to a PRIVATE lane site copy.
Usage (WSL root on the 4080):  python3 patch-i4-fixture-profile.py /tmp/stobe-standalone4080-i4/site [--check]
Refuses any site root that is not under /tmp/stobe-standalone4080-i4 (never the live tree, never lane i3).
Changes lib/test_provider_reply_fixture.php only: new profile '4080-i4' (php 18085, db stobe_standalone4080_i4_test, pg 15435,
socket /tmp/stobe-standalone4080-i4/socket) and a per-profile 'instance_id' (default '3', i4 = '4') in the instance gate.
Idempotent. Back up: <file>.pre-i4profile."""
import sys, os, shutil
root = sys.argv[1].rstrip('/')
if not root.startswith('/tmp/stobe-standalone4080-i4/'): sys.exit('refused: not the i4 private site ' + root)
f = root + '/lib/test_provider_reply_fixture.php'
s = open(f, encoding='utf-8').read()
if "'4080-i4'" in s:
    print('already patched'); sys.exit(0)
a1 = "    return $profiles[$route] ?? null;"
a2 = "        || getenv('STOBE_TEST_INSTANCE_ID') !== '3'"
assert s.count(a1) == 1 and s.count(a2) == 1, 'anchors'
prof = """        '4080-i4' => [
            'route'=>'4080-i4',
            'instance_id'=>'4',
            'site_root'=>'/tmp/stobe-standalone4080-i4/site',
            'http_port'=>18085,
            'host'=>'127.0.0.1:18085',
            'database'=>'stobe_standalone4080_i4_test',
            'socket_dir'=>'/tmp/stobe-standalone4080-i4/socket',
            'db_port'=>15435,
        ],
    ];
"""
tail = "        ],\n    ];\n" + a1
assert s.count(tail) == 1, 'profiles tail anchor'
s = s.replace(tail, "        ],\n" + prof + a1)
s = s.replace(a2, "        || getenv('STOBE_TEST_INSTANCE_ID') !== strval($profile['instance_id'] ?? '3')")
if '--check' in sys.argv: print('would patch'); sys.exit(0)
shutil.copy2(f, f + '.pre-i4profile')
open(f, 'w', encoding='utf-8', newline='').write(s)
print('patched', f)
