#!/usr/bin/env python3
"""Kenshi NPC wealth survey (run 12 research for the deal-offer cap tiers).

For every CHARACTER template in this install's load order (vanilla + UWE + UPK):
  cats   = 'money min'..'money max' (what the game gives them to carry)
  bounty = 'bounty amount'
  gear   = estimated value of the gear they spawn with: armour 'value' x chance,
           best weapon 'value' x its manufacturer 'price mod' (base grade, no quality mult)
Faction comes from the squad templates that use the character (leader/squad/shop).
Writes /mnt/c/KenshiModding/archive/npc-wealth-survey.tsv and prints a summary.
"""
import sys, collections, statistics
sys.path.insert(0, '/mnt/c/KenshiModding/tools/research')
from fcs_merge import load

db = load()
name = lambda sid: db[sid]['name'].strip() if sid in db else sid

# character -> factions (via squad templates)
fac = collections.defaultdict(set)
for r in db.values():
    if r['type'] != 52: continue
    fs = [name(s) for s, *_ in r['refs'].get('faction', [])]
    for cat in ('leader', 'squad', 'squad2', 'choosefrom list', 'special'):
        for s, *_ in r['refs'].get(cat, []):
            for f in fs: fac[s].add(f)
for r in db.values():
    if r['type'] == 1:
        for s, *_ in r['refs'].get('faction', []): fac[r['sid']].add(name(s))

def mfr_mult(char):
    lv = char['refs'].get('weapon level', [])
    mults = [db[s]['floats'].get('price mod', 1.0) for s, *_ in lv if s in db]
    return max(mults) if mults else 1.0

rows = []
for r in db.values():
    if r['type'] != 1: continue
    ints = r['ints']
    cmin, cmax = ints.get('money min', 0), ints.get('money max', 0)
    bounty = ints.get('bounty amount', 0) if ints.get('bounty chance', 0) > 0 else 0
    armour = 0.0
    for s, a, chance, c in r['refs'].get('clothing', []):
        if s in db and db[s]['type'] == 3:
            armour += db[s]['ints'].get('value', 0) * (chance if 0 < chance <= 100 else 100) / 100.0
    wvals = [db[s]['ints'].get('value', 0) for s, *_ in r['refs'].get('weapons', []) if s in db]
    weapon = (max(wvals) if wvals else 0) * mfr_mult(r)
    gear = int(armour + weapon)
    rows.append((r['name'].strip(), '/'.join(sorted(fac.get(r['sid'], []))) or '-', cmin, cmax, bounty, gear, int(armour), int(weapon), r['sid']))

with open('/mnt/c/KenshiModding/archive/npc-wealth-survey.tsv', 'w', encoding='utf-8') as out:
    out.write('name\tfactions\tcats_min\tcats_max\tbounty\tgear_est\tarmour\tweapon\tsid\n')
    for x in sorted(rows, key=lambda x: (-x[3], -x[5])):
        out.write('\t'.join(str(v) for v in x) + '\n')

if __name__ == '__main__':
    q = [a.lower() for a in sys.argv[1:]]
    for x in sorted(rows, key=lambda x: -(x[3] + x[5])):
        if not q or any(t in x[0].lower() or t in x[1].lower() for t in q):
            print(f"{x[0][:34]:34} {x[1][:34]:34} cats {x[2]:>6}-{x[3]:<7} bounty {x[4]:>7} gear {x[5]:>7}")
