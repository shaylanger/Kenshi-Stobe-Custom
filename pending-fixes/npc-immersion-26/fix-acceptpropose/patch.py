#!/usr/bin/env python3
"""imm26-fix-acceptpropose: usage patch.py <compose-tree-root> [--test-only]. Anchored, idempotent, preserves line endings.
ACCEPT + complete activity_intent + no offer (record null) is read as PROPOSE in lib/activity/ActivityChat.php;
offline cases are added to tests/imm26_wpE_activity_kinds_regression.php."""
import sys, os
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
NL = chr(10); CRLF = chr(13) + chr(10)

def patch(rel, anchor, new, marker, before=False):
    p = os.path.join(root, rel); s = open(p, encoding='utf-8', newline='').read()
    eol = CRLF if CRLF in s else NL
    anchor = anchor.replace(NL, eol); new = new.replace(CRLF, NL).replace(NL, eol)
    if marker in s: print('already patched', rel); return
    assert s.count(anchor) == 1, (rel, 'anchor count', s.count(anchor))
    s = s.replace(anchor, (new + anchor) if before else (anchor + new))
    open(p, 'w', encoding='utf-8', newline='').write(s); print('patched', rel)

if '--test-only' not in sys.argv:
    chat_anchor = "    $decision = $reply['activity_decision'] ?? 'NONE';" + NL
    chat_new = ("    // imm26-fix-acceptpropose: the model sometimes answers ACCEPT with a complete activity_intent although no offer exists (inv-14c)." + NL +
                "    // Read it as the offer it is: PROPOSE runs the same validation/grounding, grants nothing, and the player must still accept the displayed offer." + NL +
                "    if ($decision === 'ACCEPT' && $turn['record'] === null && is_string($reply['activity_intent'] ?? null)) {" + NL +
                "        $impliedIntent = trim($reply['activity_intent']);" + NL +
                "        if ($impliedIntent !== '' && $impliedIntent !== '{}') $decision = 'PROPOSE';" + NL +
                "    }" + NL)
    patch('lib/activity/ActivityChat.php', chat_anchor, chat_new, 'imm26-fix-acceptpropose')

test_anchor = 'echo "RESULT IMM26-WPE-ACTIVITY-KINDS "'
patch('tests/imm26_wpE_activity_kinds_regression.php', test_anchor,
      open(os.path.join(here, 'test_addition.php'), encoding='utf-8', newline='').read(), 'imm26-fix-acceptpropose', before=True)
