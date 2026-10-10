"""e1-lead-variants.py -- animlab variant patch (build.sh --patch, AFTER pending-fixes/kfp-e1-swlead.py): runtime keys to
explore the E1 edge-lead patch. e1wfix (0..1, default 1) = how far the lead weight fades out the PT17 wfix blade roll,
e1clamp (0..1, default 1) = how far it fades out the S1 edge clamp. Defaults reproduce kfp-e1-swlead.py exactly.
Lab only (miss E1 in docs/animlab/STATUS.md)."""
import sys, os
f = os.path.join(sys.argv[1], 'kfp_viewmodel.inc'); s = open(f).read()
def rep(a, b, n=1):
    global s
    assert s.count(a) == n, (a, s.count(a)); s = s.replace(a, b)
rep('static int   g_vm_swlead = 1;', 'static float g_al_e1wfix = 1.0f, g_al_e1clamp = 1.0f;\nstatic int   g_vm_swlead = 1;')
rep('if (g_vm_swing && g_vm_swlw > 0.0f) { float k_ = 1.0f - g_vm_swlw;',
    'if (g_vm_swing && g_vm_swlw * g_al_e1wfix > 0.0f) { float k_ = 1.0f - g_vm_swlw * g_al_e1wfix;')
rep('(g_vm_swing ? 1.0f - g_vm_swlw : 1.0f);   /* E1', '(g_vm_swing ? 1.0f - g_vm_swlw * g_al_e1clamp : 1.0f);   /* E1')
rep('    else if (!strcmp(k, "swlead")) {',
    '    else if (!strcmp(k, "e1wfix")) { g_al_e1wfix = fmaxf(0.0f, fminf(1.0f, x)); return 1; }\n'
    '    else if (!strcmp(k, "e1clamp")) { g_al_e1clamp = fmaxf(0.0f, fminf(1.0f, x)); return 1; }\n'
    '    else if (!strcmp(k, "swlead")) {')
open(f, 'w').write(s)
print('applied', f)
