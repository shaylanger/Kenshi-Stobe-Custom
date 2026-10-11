#!/usr/bin/env python3
"""KenshiFP: the manual combat adapter's native-call fault is no longer permanent, and every guarded fault logs where it
happened (5090 2026-10-11 02:48 CBE4F5A8, also 22:18 and 00:44 on older builds: on the first combat tick after loading
kah-fpxbow with the crossbow in hand, "[combat] native call fault; manual ownership disabled" right after a "[cmesh] ...
no readable triangles" line; g_combat_fault then stayed 1 for the whole launch, so every later `fp_combat on` answered
"native bindings/hooks unavailable or faulted" and list 40-rangedrows failed 10 rows in setup).
Fix: (1) veh_guard logs a crash trace (module+offset per frame) for the first 16 distinct guarded fault addresses, so
the faulting native call is named next time; (2) a combat-tick fault is retried: after 2 s the fault flag clears (at most
3 times per launch, logged), so a one-off fault at load no longer disables the adapter until restart.
Usage: kfp-combat-faultretry.py <KenshiFP tree root | client dir>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]); d = root / 'client'
if not (d / 'kfp_combat_native.inc').exists(): d = root
def patch(name, pairs):
    f = d / name; s = f.read_text()
    for old, new in pairs:
        n = s.count(old); assert n == 1, f"{name}: anchor count {n}: {old[:70]!r}"; s = s.replace(old, new)
    f.write_text(s); print('kfp-combat-faultretry applied to', f)
patch('kenshifp_client.c', [(
"""        g_guard_armed = 0;
        longjmp(g_guard_jb, 1);""",
"""        g_guard_armed = 0;
        {   /* FAULTRETRY: name the faulting native call (first 16 distinct addresses) */
            static DWORD64 gseen[16]; static int ngseen; DWORD64 grip = ep->ContextRecord->Rip; int gdup = 0;
            for (int i = 0; i < ngseen; i++) if (gseen[i] == grip) { gdup = 1; break; }
            if (!gdup && ngseen < 16) { gseen[ngseen++] = grip; logline("[guard] guarded fault code=%08lX (trace follows)", (unsigned long)code); kfp_crash_trace(ep); }
        }
        longjmp(g_guard_jb, 1);""")])
patch('kfp_combat_native.inc', [
("""static int g_combat_fault, g_combat_dispatch;""",
"""static int g_combat_fault, g_combat_dispatch;
static unsigned g_combat_faults; static ULONGLONG g_combat_fault_t;   /* FAULTRETRY: tick faults, time of the last one */"""),
("""    if (!g_combat_enabled || !g_combat_native_ready || g_combat_fault || !g_fp_mode) {
        if (g_combat_rc) {""",
"""    if (g_combat_fault && g_combat_fault_t && g_combat_faults<=3 && GetTickCount64()-g_combat_fault_t>=2000) {
        g_combat_fault=0;g_combat_fault_t=0;logline("[combat] native call fault cleared after 2 s (retry %u/3)",g_combat_faults);
    }
    if (!g_combat_enabled || !g_combat_native_ready || g_combat_fault || !g_fp_mode) {
        if (g_combat_rc) {"""),
("""        g_combat_pc=NULL;g_combat_rc=NULL;g_combat_gun=NULL;
        logline("[combat] native call fault; manual ownership disabled");return;""",
"""        g_combat_pc=NULL;g_combat_rc=NULL;g_combat_gun=NULL;++g_combat_faults;g_combat_fault_t=GetTickCount64();
        logline("[combat] native call fault #%u; manual ownership disabled%s",g_combat_faults,g_combat_faults<=3?" (retry in 2 s)":"");return;"""),
])
