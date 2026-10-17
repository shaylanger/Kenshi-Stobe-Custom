#!/usr/bin/env python3
"""imm26 fix02bxregex (row 02-bx rep1, principle_voiced_log 2<3): widen the voiced-principle detection.
Evidence (op32 02-bx rep1): Cind said "No. Not that - shackles, captives, that's not a thing I do." and
"But I won't put irons on him." Sentence 1 has a profile word (shackles) but the stanceSay regex did not know
"that's not a thing I do"; sentence 2 has the stance ("I won't") but "irons" was not a voice_extra word.
Change 1 (lib/imm26_c1_principles.php stanceSay): add refusal-of-principle phrases: "(that|it|this)('s| is) not (a thing|something|what) I do/would/will",
  "not (a thing|something) I do/would/will/could", "I do not", "I am/I'm not going to|doing".
Change 2 (slavery voice_extra): add binding gear: manacles, fetters, handcuffs, leg-irons, and "irons" ONLY after a put/clap/snap/lock/slap verb
  (so "I don't iron clothes" / "irons in the fire" stay unmatched). The stance-before-word clause rule from fix02bxsrv still applies.
Requires fix02bxsrv to be applied first. usage: python3 apply.py <tree-root> [--check]   (idempotent; asserts anchors; writes *.bak-fix02bxregex)
"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
PF = os.path.join(root, 'lib/imm26_c1_principles.php')
MARK = 'imm26 fix02bxregex'

A1 = r"""never)\b/iu';
    $sentences = preg_split("""
N1 = (r"never|(?:(?:that|it|this)(?:\'s| is) )?not (?:a thing|something|what) I (?:do|would|will|could)|I do not|I(?:\'m| am) not (?:going to|doing))\b/iu';"
      " // imm26 fix02bxregex: + refusal-of-principle phrasings\n    $sentences = preg_split(")
A2 = r"|cages?|(?:haul|sell|trade|buy|own)"
N2 = r"|cages?|manacles?|fetters?|handcuffs?|leg[- ]irons?|(?:put|clap|snap|lock|slap)\w*\s+(?:\w+\s+){0,3}irons|(?:haul|sell|trade|buy|own)"

s = open(PF, encoding='utf-8', newline='').read()
if MARK in s:
    print('already patched:', PF); sys.exit(0)
assert 'stobeImm26PrincipleSentenceVoices' in s, 'fix02bxsrv must be applied first'
for a in (A1, A2):
    assert s.count(a) == 1, 'anchor count %d: %r' % (s.count(a), a[:60])
if check:
    print('anchors ok:', PF); sys.exit(0)
shutil.copy2(PF, PF + '.bak-fix02bxregex')
s = s.replace(A1, N1).replace(A2, N2)
open(PF, 'w', encoding='utf-8', newline='').write(s)
print('patched:', PF)
