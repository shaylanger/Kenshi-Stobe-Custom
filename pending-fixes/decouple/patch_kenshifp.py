#!/usr/bin/env python3
"""Remove the non-FP Stobe executor from a KenshiFP tree (it now lives in Stobe.dll, StobeGoals.cpp).
usage: patch_kenshifp.py <KenshiFP root>
Keeps: camera/FP input/cursor/targeting/combat and the FP harness bridge. The FP combat truce
check now asks Stobe.dll through its named export StobeFightTruceActive (no fixed RVAs)."""
import sys
root = sys.argv[1]


def rep(s, old, new, count=1):
    n = s.count(old)
    assert n == count, (n, old[:80])
    return s.replace(old, new)


p = root + '/client/kenshifp_client.c'
s = open(p, encoding='latin-1', newline='').read()
assert 'StobeFightTruceActive' not in s, 'already patched'
a = s.index('/* STOBE voice-mode bridge.')
b = s.index('/* M1 camera lock.')
s = s[:a] + '''/* Stobe bridge. Work/task goals, the goal panel, stobe_action.request / unequip_item.request,
 * the STOP_FIGHT truce, U/Shift+U/Ctrl+U voice markers and lifelike signals run inside
 * Stobe.dll (StobeGoals.cpp) since 2026-10-06. FP combat only asks whether a truce is pending,
 * through Stobe's named export (absent Stobe or older build: no truce). */
typedef int (*stobe_truce_active_t)(void);
static int stobe_fight_truce_active(void)
{
    static stobe_truce_active_t fn;
    static DWORD next_try;
    if (!fn) {
        DWORD now = GetTickCount();
        if (next_try && (LONG)(now - next_try) < 0) return 0;
        next_try = now + 5000;
        HMODULE mod = GetModuleHandleA("Stobe.dll");
        if (mod) fn = (stobe_truce_active_t)(void *)GetProcAddress(mod, "StobeFightTruceActive");
        if (!fn) return 0;
    }
    return fn() != 0;
}

''' + s[b:]
s = rep(s, '''    stobe_voice_modifier_tick();
    stobe_unequip_request_tick(gw);
    stobe_general_action_request_tick(gw);
    stobe_fight_truce_tick(gw);
    stobe_work_goal_tick(gw);
    stobe_task_goal_tick(gw);
    kah_bridge_tick();''', '''    kah_bridge_tick();''')
s = rep(s, '''    if (gw) stobe_goal_label_update(gw);  /* selected squad member's goal (round 18d) */
''', '')
open(p, 'w', encoding='latin-1', newline='').write(s)

p = root + '/client/kfp_combat_native.inc'
s = open(p, encoding='latin-1', newline='').read()
s = rep(s, '''    for(int i=0;i<STOBE_FIGHT_TRUCE_SLOTS;++i)
        if(g_stobe_fight_truce[i].serial)return 1;
    return 0;''', '''    return stobe_fight_truce_active();''')
open(p, 'w', encoding='latin-1', newline='').write(s)
print('patched', root)
