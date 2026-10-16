#!/usr/bin/env python3
"""unblockfake_f.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_f_selftest.sh. Answers the sfF-specific calls and delegates the rest to unblockfake_b.py.
Scenario keys (env FAKE_SCEN): term_seq (per uf_terminal call: '' | 'C' | 'F', last repeats; the COMPLETED-count query advances the index, the FAILED-count query of the same pair
reads it)  nend (lines answering the `uf:nend` stobe.log grep)  ndump (lines answering the `uf:ndump` grep)  nobs (lines for `uf:nobs`). Counter file FAKE_STATE+'.uf'."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.uf'
st = json.load(open(sp)) if os.path.isfile(sp) else {'i': -1}
here = os.path.dirname(os.path.abspath(__file__))


def cur():
    seq = scen.get('term_seq', [''])
    return seq[min(max(st['i'], 0), len(seq) - 1)]


if kind == 'sql' and 'count(*)' in body and "type='travel_agreement'" in body:
    if '"status":"COMPLETED"' in body:
        st['i'] += 1; json.dump(st, open(sp, 'w'))
        print(1 if cur() == 'C' else 0); sys.exit(0)
    if '"status":"FAILED"' in body:
        print(1 if cur() == 'F' else 0); sys.exit(0)
if kind == 'h':
    if 'uf:nend' in body:
        print('\n'.join(scen.get('nend', []))); sys.exit(0)
    if 'uf:ndump' in body or 'uf:nobs' in body:
        print('\n'.join(scen.get('ndump' if 'uf:ndump' in body else 'nobs', []))); sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(here, 'unblockfake_b.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
