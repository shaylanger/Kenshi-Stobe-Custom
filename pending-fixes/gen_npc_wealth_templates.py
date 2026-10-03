#!/usr/bin/env python3
"""Deal-offer cap tiers: NPC template wealth table for the server.

Reads archive/npc-wealth-survey.tsv (this install's merged FCS data:
name, factions, cats_min, cats_max, bounty, ...) and writes
<StobeServer tree>/data/npc_wealth_templates.json:
  {"dust bandit": [cats_min, cats_max, bounty], ...}
Names lose their "/UCNAME/"-style placeholders. Several templates with the same name:
lowest min, highest max, highest bounty.

Usage: gen_npc_wealth_templates.py <survey.tsv> <StobeServer tree>
"""
import csv
import json
import re
import sys
from pathlib import Path

survey, root = Path(sys.argv[1]), Path(sys.argv[2])
table = {}
with survey.open(encoding='utf-8') as fh:
    for row in csv.DictReader(fh, delimiter='\t'):
        name = re.sub(r'\s*/[A-Z]+NAME/\s*', ' ', row['name']).strip().lower()
        name = re.sub(r'\s+', ' ', name)
        if not name:
            continue
        try:
            lo, hi, bounty = int(row['cats_min']), int(row['cats_max']), int(row['bounty'])
        except ValueError:
            continue
        if name in table:
            a, b, c = table[name]
            table[name] = [min(a, lo), max(b, hi), max(c, bounty)]
        else:
            table[name] = [lo, hi, bounty]
out = root / 'data/npc_wealth_templates.json'
out.write_text(json.dumps(dict(sorted(table.items())), separators=(',', ':')) + '\n', encoding='utf-8')
print('wrote', out, len(table), 'templates')
