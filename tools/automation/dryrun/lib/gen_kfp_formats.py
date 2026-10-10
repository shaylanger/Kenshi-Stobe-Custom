#!/usr/bin/env python3
"""gen_kfp_formats.py -- regenerate kfp_formats.json (the real KenshiFP reply formats the dry-run stub renders).
Run in WSL from /root/KenshiFP after a KenshiFP change that adds reply fields, e.g.
  cd /root/KenshiFP && python3 -I /mnt/c/KenshiModding/tools/automation/dryrun/lib/gen_kfp_formats.py \\
    vm:client/kfp_viewmodel.inc:2377:2382 fpstate:client/kenshifp_client.c:2434:2437 \\
    ctlstate:client/kfp_control.inc:213:215 cam:client/kfp_view.inc:269:286 pick:client/kfp_controls.inc:357:358 \\
    combat:client/kfp_combat_native.inc:959:980 combat_shot:client/kfp_combat_native.inc:437:460 \\
    ctl:client/kfp_controls.inc:1499:1500 melee:client/kfp_melee_observe.inc:66:66 \\
    meleeapp:client/kfp_combat_melee.inc:502:502 \\
    swingall:/mnt/c/KenshiModding/pending-fixes/kfp-swing-hits-all.py:152:152 \\
    _ini:/mnt/d/Steam/steamapps/common/Kenshi/mods/KenshiFP/KenshiFP.ini:all \\
    > /mnt/c/KenshiModding/tools/automation/dryrun/lib/kfp_formats.json
(line ranges = the snprintf format literals of each reply; check them with sed -n when the source moved; swingall comes
from the pending patch until kfp-swing-hits-all is committed, then from client/kfp_combat_swingall.inc).
Each arg name:file:a:b -> JSON {name: concatenation of the C string literals on lines a..b}; name:file:all -> the whole
file verbatim (_ini: the installed KenshiFP.ini the dry-run sandbox starts with, kahstub.ensure_ini)."""
import re, sys, json
out = {}
for spec in sys.argv[1:]:
    name, p, a, b = (spec.split(':') + [''])[:4]
    if a == 'all':
        out[name] = open(p, errors='replace').read().replace('\r\n', '\n')
        continue
    L = open(p).read().splitlines()[int(a) - 1:int(b)]
    s = ''
    for l in L:
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', l):
            s += lit
    out[name] = s
print(json.dumps(out, indent=0))
