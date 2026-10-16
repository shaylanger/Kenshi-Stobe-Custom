#!/usr/bin/env python3
"""sfr22b_keep_fake.py: offline fake lane for sfrrun_v4.sh / sfr22b_v4_selftest.sh. Runs sfrfake.py unchanged; for a sfr22b_keep.sh walk call (body has `teleport Shay` AND `uf:nend`)
it appends the scenario `nend` lines to the `where` line, which is what the real in-call grep prints. Args = sfrfake.py args (kind body)."""
import json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
r = subprocess.run([sys.executable, os.path.join(here, 'sfrfake.py')] + sys.argv[1:], capture_output=True, text=True)
sys.stdout.write(r.stdout)
body = sys.argv[2] if len(sys.argv) > 2 else ''
if sys.argv[1:2] == ['h'] and 'uf:nend' in body and 'teleport Shay' in body:
    scen = json.load(open(os.environ['FAKE_SCEN']))
    if scen.get('nend'):
        print('\n'.join(scen['nend']))
