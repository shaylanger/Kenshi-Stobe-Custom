#!/usr/bin/env python3
"""Relationship fix R2: the code fallback of the relationship analysis prompt had Skyrim examples.

ext/relationship_system/relationship_llm.php getAnalysisPrompt() fallback:
"Imperial -> Stormcloak -60", "Khajit -40 contempt", "Thieves Guild -> Guard". The DB
copy (prompts.rel_llm_analysis) is already generic; the fallback is used when the DB
row is missing. Now Kenshi examples.

Usage: patch_r25_rel_kenshi_examples.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'ext/relationship_system/relationship_llm.php'
s = f.read_text(encoding='utf-8')
if 'Holy Nation' in s and 'Stormcloak' not in s:
    print('already patched', f); sys.exit(0)
old_start = s.index('1. FACTION: Imperial')
old_end = s.index('\n', s.index('3. OCCUPATION:'))
new = ('1. FACTION: Holy Nation -> add "Shek Kingdom": -60 enemy and "Hivers": -50 contempt. United Cities samurai -> "Dust Bandits": -40 enemy.\n'
       '2. RACIAL: If the NPC shows racial attitudes, add the race as target (e.g. a Holy Nation paladin: "Shek": -40 contempt).\n'
       '3. OCCUPATION: Slaver -> "Anti-Slavers": -60 enemy. Bandit -> "United Cities": -30 rival.')
s = s[:old_start] + new + s[old_end:]
f.write_text(s, encoding='utf-8')
print('patched', f)
