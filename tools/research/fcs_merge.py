#!/usr/bin/env python3
"""Merge Kenshi data in load order (vanilla + this install's big mods) into one dict by sid; cached as pickle."""
import os, pickle, sys
sys.path.insert(0, os.path.dirname(__file__))
from fcs_parse import read
K = '/mnt/d/Steam/steamapps/common/Kenshi/data/'
V = '/mnt/c/Users/Shay/AppData/Roaming/Vortex/kenshi/mods/'
FILES = [K+'gamedata.base', K+'Newwworld.mod', K+'rebirth.mod',
         V+'Universal Wasteland Expansion 634 32 2026-06-27T05-22Z p5KTzCO5n/Universal Wasteland Expansion/Universal Wasteland Expansion.mod',
         V+'Unofficial Patches For Kenshi-1173-3-6-5-1775521434/Unofficial Patches for Kenshi/Unofficial Patches for Kenshi.mod']
CACHE = '/tmp/kenshi_merged.pkl'
def load():
    if os.path.exists(CACHE): return pickle.load(open(CACHE, 'rb'))
    db = {}
    for f in FILES:
        try: recs = read(f)
        except Exception as e: print('skip', f, e); continue
        for r in recs:
            cur = db.get(r['sid'])
            if cur is None: db[r['sid']] = r; continue
            if r['name']: cur['name'] = r['name']
            for k in ('bools','floats','ints','vec3','vec4','strings','files'): cur[k].update(r[k])
            for cat, lst in r['refs'].items():
                old = {x[0]: x for x in cur['refs'].get(cat, [])}
                for x in lst: old[x[0]] = x
                cur['refs'][cat] = [x for x in old.values() if not (x[1] == 2147483647 and x[2] == 2147483647)]
        print('loaded', os.path.basename(f), len(recs))
    pickle.dump(db, open(CACHE, 'wb'))
    return db
if __name__ == '__main__':
    db = load(); print(len(db))
