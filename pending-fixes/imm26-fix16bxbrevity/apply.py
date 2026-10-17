#!/usr/bin/env python3
"""imm26 fix16bxbrevity (row 16-bx, Shay 2026-10-16 "3: a"): reserved/terse NPCs answer in <= 40 words.
Evidence: row 16-bx v3 FAIL 0/3 on 4080-i3 (agents/out/imm26-4080-i3op31/out-20261016-204558.md): the reserved Fond NPC went over the 40-word cap in 4 of 9
replies (45/50/44/49) because the prompt only says "Vary response length naturally" and has no trait brevity rule.
Change (lib/imm26_personality.php only): imm26TerseTemperament() detects a reserved/terse trait in the NPC's personality or speechstyle text;
imm26BrevityLine() returns ONE line for such NPCs (empty for everybody else); imm26PersonalityAnchorContext() puts it inside <personality_anchor>.
Non-terse NPCs: the prompt is byte-identical to before.
usage: python3 apply.py <tree-root> [--check]   (idempotent; asserts anchors; writes *.bak-fix16bxbrevity)"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
PF = os.path.join(root, 'lib/imm26_personality.php')
MARK = 'fix16bxbrevity'

A1 = "/** The NPC's last replies, newest first. */\n"
N1 = r'''/** imm26 fix16bxbrevity: does the profile (personality or speech style) name a reserved/terse temperament? Pure. */
function imm26TerseTemperament(array $npc): bool
{
    $text = trim(strval($npc['personality'] ?? '') . ' ' . strval($npc['speechstyle'] ?? ''));
    if ($text === '') return false;
    return preg_match('/(?<!not )(?<!never )(?<!un)\b(?:reserved|taciturn|laconic|terse|curt|stoic|reticent|tight-lipped|soft-spoken|of few words|few words|words sparingly|understatement|understated)\b/iu', $text) === 1;
}

/** imm26 fix16bxbrevity: the one brevity line for a reserved/terse NPC; '' for every other NPC. Pure. */
function imm26BrevityLine(array $npc): string
{
    if (!imm26TerseTemperament($npc)) return '';
    return 'Your temperament is reserved: you are a person of few words. Answer in at most 40 words, usually one or two short sentences, even with a close friend.';
}

'''
A2 = "    if (!$anchor && !$overused) return '';\n"
N2 = ("    $brevity = imm26BrevityLine($npc); // imm26 fix16bxbrevity: reserved/terse NPCs only\n"
      "    if (!$anchor && !$overused && $brevity === '') return '';\n")
A3 = "    if ($overused) $lines[] = 'Your last replies leaned on: \""
N3 = "    if ($brevity !== '') $lines[] = stobePromptXmlEscape($brevity);\n"

s = open(PF, encoding='utf-8', newline='').read()
if MARK in s or 'imm26BrevityLine' in s:
    print('already patched:', PF); sys.exit(0)
for a in (A1, A2, A3):
    assert s.count(a) == 1, 'anchor count %d: %r' % (s.count(a), a[:60])
if check:
    print('anchors ok:', PF); sys.exit(0)
shutil.copy2(PF, PF + '.bak-' + MARK)
s = s.replace(A1, N1 + A1).replace(A2, N2).replace(A3, N3 + A3)
open(PF, 'w', encoding='utf-8', newline='').write(s)
print('patched:', PF)
