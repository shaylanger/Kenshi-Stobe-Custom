"""e1-mkpatch.py <e1-climb output> <out patch.py> : write a self-contained E1 candidate patch from the optimizer's last line."""
import json, sys, math
p = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1].split(' ', 4)[-1])
def n(v): l = math.sqrt(sum(x * x for x in v)); return [x / l for x in v]
keys = {}
for i in (1, 2, 3):
    keys[i] = ([round(x, 2) for x in p['p%d' % i]], [round(x, 2) for x in n(p['f%d' % i])])
src = '''#!/usr/bin/env python3
"""E1 candidate (animlab-found, Shay rule: the edge leads the arc): kfp-e1-swlead.py + kfp-e1-rollcap.py
(lead roll at most e1cap deg off the straight wrist) + re-authored strike keys sw2..sw4 (grip p, blade f) so that the
straight-wrist edge already leads the stroke. Found by a lab hill climb on C:\\KenshiTestRuns\\f14\\e0.txt
(objective: arc gate; limits: swing wb_max <= 50, elb_h_max <= 2.1, edge_mean >= 0.2, small path change).
Usage: %(me)s <KenshiFP root or client dir>  (runs the two base scripts from the same folder first)"""
import sys, os, subprocess
here = os.path.dirname(os.path.abspath(__file__)); root = sys.argv[1]
for b in ('kfp-e1-swlead.py', 'kfp-e1-rollcap.py'):
    subprocess.run([sys.executable, os.path.join(here, b), root], check=True)
f = os.path.join(root, 'kfp_viewmodel.inc')
if not os.path.exists(f): f = os.path.join(root, 'client', 'kfp_viewmodel.inc')
s = open(f).read()
if 'E1 keys' in s: print('already applied'); sys.exit(0)
def rep(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:60], c); s = s.replace(a, b)
rep('static float g_vm_e1cap = 45.0f;', 'static float g_vm_e1cap = %(cap).1ff;')
''' % dict(me=sys.argv[2].split('/')[-1], cap=p['cap'])
old = {1: "VP( 1.3f,-0.45f,4.8f,  -0.55f, 0.45f, 0.70f,", 2: "VP( 0.4f,-0.6f, 4.8f,  -0.92f, 0.02f, 0.38f,", 3: "VP(-0.6f,-0.9f, 4.6f,  -0.90f,-0.18f, 0.40f,"}
for i in (1, 2, 3):
    (px, py, pz), (fx, fy, fz) = keys[i]
    src += "rep(%r, %r)\n" % (old[i], "VP(%.2ff,%.2ff,%.2ff, %.2ff,%.2ff,%.2ff, /* E1 keys */" % (px, py, pz, fx, fy, fz))
src += "open(f, 'w').write(s)\nprint('applied', f)\n"
open(sys.argv[2], 'w').write(src)
print('cap %.1f keys %s' % (p['cap'], keys))
