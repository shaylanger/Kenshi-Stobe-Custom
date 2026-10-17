#!/usr/bin/env python3
"""imm26 fix16bxbrevity: add checks to tests/imm26_wpA_personality_claims_regression.php (idempotent, *.bak-fix16bxbrevity).
usage: python3 apply_test.py <tree-root> [--check]
Run: php tests/imm26_wpA_personality_claims_regression.php   (the new 'fix16bxbrevity' checks fail on the unpatched lib)."""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
TF = os.path.join(root, 'tests/imm26_wpA_personality_claims_regression.php')
ANCH = "// ---------- item 17: claims vs native state ----------\n"
MARK = 'fix16bxbrevity'
NEW = r'''// ---------- fix16bxbrevity (row 16-bx): reserved/terse NPCs get ONE brevity line, nobody else ----------
$cind = ['personality' => 'Lighthearted without being careless, finds small pleasures in food.', 'speechstyle' => 'Tends toward understatement and dry humor. Gets quieter and more direct when serious.'];
ok(imm26TerseTemperament($cind) && str_contains(imm26BrevityLine($cind), '40 words'), 'fix16bxbrevity: understatement speech style -> brevity line (Cind)', imm26BrevityLine($cind));
ok(imm26TerseTemperament(['personality' => 'Reserved and watchful, loyal to friends']), 'fix16bxbrevity: "Reserved" personality -> terse');
ok(imm26TerseTemperament(['personality' => 'A man of few words.']) && imm26TerseTemperament(['speechstyle' => 'Terse, speaks sparingly']), 'fix16bxbrevity: few words / terse -> terse');
ok(!imm26TerseTemperament($npc) && imm26BrevityLine($npc) === '', 'fix16bxbrevity: blunt/clipped NPC without a reserved trait word gets no line', imm26BrevityLine($npc));
ok(!imm26TerseTemperament(['personality' => 'Outgoing and talkative, unreserved, never reserved with strangers.']), 'fix16bxbrevity: unreserved / never reserved is not terse');
ok(imm26BrevityLine([]) === '' && imm26BrevityLine(['personality' => '', 'speechstyle' => '']) === '', 'fix16bxbrevity: empty profile -> no line');
ok(substr_count(imm26BrevityLine($cind), "\n") === 0 && str_word_count(imm26BrevityLine($cind)) <= 40, 'fix16bxbrevity: the line is one short line');
$ctxT = imm26PersonalityAnchorContext('Brevity Test Cind', $cind + ['name' => 'Brevity Test Cind'], 'Shay');
ok(str_contains($ctxT, 'at most 40 words') && str_contains($ctxT, '<personality_anchor>') && str_contains($ctxT, '</personality_anchor>'), 'fix16bxbrevity: the line rides inside <personality_anchor> for a terse NPC', $ctxT);
$ctxN = imm26PersonalityAnchorContext('Brevity Test Blunt', $npc + ['name' => 'Brevity Test Blunt'], 'Shay');
ok(!str_contains($ctxN, 'at most 40 words') && !str_contains($ctxN, 'few words'), 'fix16bxbrevity: a non-terse NPC prompt carries no brevity line', $ctxN);

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
