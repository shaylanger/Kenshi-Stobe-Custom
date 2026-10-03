#!/usr/bin/env python3
"""Item 108: list the generic (non-unique) CHARACTER template names of this load order.

stobeIsGenericNpcName() only knew a template once it had seen "X [Template]" in the DB, so an unnamed
fighter like "Berserker" (a template never seen named) got relationship entries. This writes the
lower-cased names of all non-unique character templates, minus any name a unique template also uses
(Dust King, Beep, ...), to <tree>/data/npc_generic_templates.json.
Usage (WSL): python3 gen_npc_generic_templates.py <server tree>   (uses tools/research/fcs_merge.py)
"""
import sys, json, pathlib
sys.path.insert(0, '/mnt/c/KenshiModding/tools/research')
from fcs_merge import load
db = load()
chars = [r for r in db.values() if r['type'] == 1 and r['name'].strip()]
unique = {r['name'].strip().lower() for r in chars if r.get('bools', {}).get('unique')}
# recruitables (Izumi, Ruka, ...) have no 'unique' bool at all: only an explicit False counts as generic
generic = sorted({r['name'].strip().lower() for r in chars if r.get('bools', {}).get('unique') is False} - unique)
out = pathlib.Path(sys.argv[1]) / 'data' / 'npc_generic_templates.json'
out.write_text(json.dumps(generic, indent=0))
print(f"{len(generic)} generic template names -> {out} ({len(unique)} unique names excluded)")
for n in ('berserker', 'hungry bandit', 'dust king', 'beep', 'shay', 'malzin', 'beaks', 'avarek', 'garro vex'):
    print(f"  {n}: {'generic' if n in generic else '-'}")
