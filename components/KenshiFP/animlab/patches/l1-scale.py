#!/usr/bin/env python3
"""Lab-only variant (crossbow READY commanded->rendered miss, maintainer #11): key `l1k` scales the solver's cached native
upper-arm length g_vm_l1n (= |native forearm local pos| * upper-arm derived scale X). In game that product can differ
from the rendered upper arm (non-uniform derived scale: only .x is used); l1k < 1 emulates a short L1n.
Usage: l1-scale.py <client dir>"""
import sys, os
p = os.path.join(sys.argv[1], 'kfp_viewmodel.inc'); s = open(p).read()
a = 'g_vm_b0[i] = b[i][0]; g_vm_l1n[i] = vm_len(g_vm_fpn[i]) * k; }'
assert s.count(a) == 1
s = s.replace(a, 'g_vm_b0[i] = b[i][0]; g_vm_l1n[i] = vm_len(g_vm_fpn[i]) * k * g_al_l1k; }')
a = 'static float g_vm_l1n[2];'
assert s.count(a) == 1
s = s.replace(a, 'static float g_al_l1k = 1.0f; static float g_vm_l1n[2];')
a = '    else if (!strcmp(k, "nearclip"))'
assert s.count(a) == 1
s = s.replace(a, '    else if (!strcmp(k, "l1k")) { g_al_l1k = x; return 1; }\n' + a)
open(p, 'w').write(s); print('l1-scale applied')
