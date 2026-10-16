"""imm26-sfTrav: install the travel PROPOSE test seam into a server tree.
usage (WSL):  python3 apply.py <tree-root> [--check]
  - copies imm26_travel_test_inject.php into <tree>/lib/
  - adds ONE guarded call in processor/chat.php, right before the ordinary stobeTravelCapture() of a travel-consent turn
    (is_file on the lane marker; no effect unless the marker exists AND the lane gate passes)
Idempotent: a tree that already has the seam is reported and left alone. --check only reports.
Independent of the imm26-sfO activity seam (separate file, marker and anchor).
"""
import sys, os, shutil
root = sys.argv[1].rstrip('/')
check = '--check' in sys.argv
here = os.path.dirname(os.path.abspath(__file__))
chat = root + '/processor/chat.php'
dst = root + '/lib/imm26_travel_test_inject.php'
raw = open(chat, 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
ANCHOR = ("    stobeTravelCapture($imm26TravelRaw, $targetNpc, $npcData,\n"
          "        strval($speaker), strval($message), intval($gamets), $responseText, $responseActions);\n")
NEW = ("    // imm26-sfTrav TEST SEAM (isolated /tmp/stobe-*/site lanes only; inert unless <lane>/test-inject-travel.json exists and the lane gate passes).\n"
       "    if (is_file(dirname(realpath(dirname(__DIR__)) ?: dirname(__DIR__)).'/test-inject-travel.json')) {\n"
       "        require_once __DIR__ . '/../lib/imm26_travel_test_inject.php';\n"
       "        $imm26TravelRaw = stobeTravelTestInjectApply($imm26TravelRaw, $targetNpc, $npcData, strval($speaker), strval($message),\n"
       "            intval($gamets), $responseText, $responseActions, !empty($alreadyStreamed));\n"
       "    }\n") + ANCHOR
have = 'imm26-sfTrav TEST SEAM' in s
if check:
    ok = have and os.path.isfile(dst)
    print('seam present' if ok else 'seam MISSING'); sys.exit(0 if ok else 1)
if have:
    if not os.path.isfile(dst): shutil.copyfile(here + '/imm26_travel_test_inject.php', dst)
    print('already has the seam'); sys.exit(0)
assert s.count(ANCHOR) == 1, ('anchor', s.count(ANCHOR))
s2 = s.replace(ANCHOR, NEW)
if crlf: s2 = s2.replace('\n', '\r\n')
open(chat, 'wb').write(s2.encode('utf-8'))
shutil.copyfile(here + '/imm26_travel_test_inject.php', dst)
print('seam installed in', root)
