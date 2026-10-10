#!/usr/bin/env python3
"""Lab game model (crossbow READY commanded->rendered miss, maintainer #11; default since 2026-10-09 by coordinator decision):
key `l1k` scales the solver's cached native upper-arm length g_vm_l1n (= |native forearm local pos| * upper-arm derived scale X).
In game that product is ~0.87 x the rendered upper arm (the game over-stretches 15%); the lab replay's skeleton has scale 1, so
without this the replay reaches targets the game overshoots. Default l1k = $AL_L1K or 0.871 (the game); --set l1k=1 = the old lab.
build.sh applies it to every build (skip with --no-l1). Sources before 484c8bc (no l1fix) are left unchanged.
Usage: l1-scale.py <client dir>"""
import sys, os
p = os.path.join(sys.argv[1], 'kfp_viewmodel.inc'); s = open(p).read()
K = os.environ.get('AL_L1K', '0.871')
a = 'g_vm_b0[i] = b[i][0]; g_vm_l1n[i] = vm_len(g_vm_fpn[i]) * k; }'
if 'g_al_l1k' in s: print('l1-scale already applied'); sys.exit(0)
if s.count(a) != 1 or s.count('static float g_vm_l1n[2];') != 1: print('l1-scale: no l1fix in this source, skipped'); sys.exit(0)
s = s.replace(a, 'g_vm_b0[i] = b[i][0]; g_vm_l1n[i] = vm_len(g_vm_fpn[i]) * k * g_al_l1k; }')
s = s.replace('static float g_vm_l1n[2];', 'static float g_al_l1k = %sf; static float g_vm_l1n[2];' % K)
a = '    else if (!strcmp(k, "nearclip"))'
assert s.count(a) == 1
s = s.replace(a, '    else if (!strcmp(k, "l1k")) { g_al_l1k = x; return 1; }\n' + a)
open(p, 'w').write(s); print('l1-scale applied (l1k %s)' % K)
