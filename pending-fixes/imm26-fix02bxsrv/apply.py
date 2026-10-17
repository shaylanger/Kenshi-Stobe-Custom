#!/usr/bin/env python3
"""imm26 fix02bxsrv (row 02-bx): count a refusal in the captivity/slavery family as 'voiced'.
Server: lib/imm26_c1_principles.php stobeImm26PrincipleAfterReply logged IMM26_PRINCIPLE_VOICED only when
ONE reply sentence matched the topic profile regex (slav*/shackl*/bondage) AND a stance phrase. Replies such as
"I don't take captives, and I don't put rope on anybody." or "I haul cargo, I don't haul people ... the one line
I won't cross." state the principle but name no profile word. New optional topic key 'voice_extra' (slavery only):
a captivity-family word (captive/prisoner/hostage/chain/rope/bind/cage/haul|sell|trade|buy|own ... people) counts
ONLY when a stance phrase comes before it in the same clause (<= 90 chars, no sentence stop) and that stance is not
"I don't mind/care/know/see/think/have/need/want". The stance requirement and the profile path are unchanged.
usage: python3 apply.py <tree-root> [--check]   (idempotent; asserts anchors; writes *.bak-fix02bxsrv)
Tests: apply_test.py <tree-root> adds regression checks to tests/imm26_c1_db_regression.php.
"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
PF = os.path.join(root, 'lib/imm26_c1_principles.php')
MARK = 'imm26 fix02bxsrv'

A1 = "            'commands' => ['PICKUP_NPC', 'IMPRISON'],\n"
N1 = ("            // imm26 fix02bxsrv: captivity-family words that count as voicing the principle, only together with a stance phrase before them.\n"
      "            'voice_extra' => '/\\b(?:captives?|captivity|prisoners?|hostages?|chain(?:s|ed|ing)?|rope[sd]?|bind(?:s|ing)?|cages?|(?:haul|sell|trade|buy|own)\\w*\\s+(?:\\w+\\s+){0,2}(?:people|persons?|folk|men|women))\\b/iu',\n")

A2 = "/**\n * After a surviving reply: if the NPC voiced a stance on a topic it holds a principle on,\n"
N2 = ("/** imm26 fix02bxsrv: does this reply sentence voice the topic's principle? Profile word + stance (original rule), or a topic\n"
      " *  'voice_extra' word that follows a stance phrase in the same clause (<= 90 chars, no sentence stop, not \"I don't mind/care/...\"). */\n"
      "function stobeImm26PrincipleSentenceVoices(array $def, string $sentence, string $stanceSay): bool\n"
      "{\n"
      "    if (preg_match($stanceSay, $sentence) !== 1) return false;\n"
      "    if (preg_match($def['profile'], $sentence) === 1) return true;\n"
      "    $extra = strval($def['voice_extra'] ?? '');\n"
      "    if ($extra === '' || !preg_match_all($stanceSay, $sentence, $st, PREG_OFFSET_CAPTURE)) return false;\n"
      "    if (!preg_match_all($extra, $sentence, $ex, PREG_OFFSET_CAPTURE)) return false;\n"
      "    foreach ($st[0] as [$sTxt, $sPos]) {\n"
      "        $sEnd = $sPos + strlen($sTxt);\n"
      "        if (preg_match('/^\\s+(?:mind|care|know|see|think|have|need|want)\\b/iu', substr($sentence, $sEnd)) === 1) continue;\n"
      "        foreach ($ex[0] as [, $ePos]) {\n"
      "            if ($ePos >= $sEnd && $ePos - $sPos <= 90 && preg_match('/[.!?]/', substr($sentence, $sEnd, $ePos - $sEnd)) !== 1) return true;\n"
      "        }\n"
      "    }\n"
      "    return false;\n"
      "}\n\n")

A3 = "            if (preg_match($def['profile'], $sentence) !== 1 || preg_match($stanceSay, $sentence) !== 1) continue;\n"
N3 = "            if (!stobeImm26PrincipleSentenceVoices($def, $sentence, $stanceSay)) continue; // imm26 fix02bxsrv (was profile && stance)\n"

s = open(PF, encoding='utf-8', newline='').read()
if MARK in s or 'stobeImm26PrincipleSentenceVoices' in s:
    print('already patched:', PF); sys.exit(0)
for a in (A1, A2, A3):
    assert s.count(a) == 1, 'anchor count %d: %r' % (s.count(a), a[:60])
if check:
    print('anchors ok:', PF); sys.exit(0)
shutil.copy2(PF, PF + '.bak-fix02bxsrv')
s = s.replace(A1, N1 + A1).replace(A2, N2 + A2).replace(A3, N3)
open(PF, 'w', encoding='utf-8', newline='').write(s)
print('patched:', PF)
