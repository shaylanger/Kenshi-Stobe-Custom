"""imm26-sfO: install the activity PROPOSE test seam into a server tree.
usage (WSL):  python3 apply.py <tree-root> [--check]
  - copies ActivityTestInject.php next to ActivityChat.php
  - adds ONE guarded call in stobeActivityChatFinish() (is_file on the lane marker; no effect unless the marker exists AND the lane gate passes)
Idempotent: a tree that already has the seam is reported and left alone. --check only reports.
"""
import sys, os, shutil
root = sys.argv[1].rstrip('/')
check = '--check' in sys.argv
here = os.path.dirname(os.path.abspath(__file__))
chat = root + '/lib/activity/ActivityChat.php'
dst = root + '/lib/activity/ActivityTestInject.php'
raw = open(chat, 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
ANCHOR = "    $reply = json_decode(trim($raw),true);\n    $decision = $reply['activity_decision'] ?? 'NONE';\n"
NEW = ("    $reply = json_decode(trim($raw),true);\n"
       "    // imm26-sfO TEST SEAM (isolated /tmp/stobe-*/site lanes only; inert unless <lane>/test-inject-activity.json exists and the lane gate passes).\n"
       "    if (is_file(dirname(realpath(dirname(__DIR__,2)) ?: dirname(__DIR__,2)).'/test-inject-activity.json')) {\n"
       "        require_once __DIR__.'/ActivityTestInject.php';\n"
       "        stobeActivityTestInjectApply($turn,$reply);\n"
       "    }\n"
       "    $decision = $reply['activity_decision'] ?? 'NONE';\n")
have = 'imm26-sfO TEST SEAM' in s
if check:
    print('seam present' if have and os.path.isfile(dst) else 'seam MISSING'); sys.exit(0 if have and os.path.isfile(dst) else 1)
if have:
    print('already has the seam'); sys.exit(0)
assert s.count(ANCHOR) == 1, ('anchor', s.count(ANCHOR))
s2 = s.replace(ANCHOR, NEW)
if crlf: s2 = s2.replace('\n', '\r\n')
open(chat, 'wb').write(s2.encode('utf-8'))
shutil.copyfile(here + '/ActivityTestInject.php', dst)
print('seam installed in', root)
