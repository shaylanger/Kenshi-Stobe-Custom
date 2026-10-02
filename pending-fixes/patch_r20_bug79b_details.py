#!/usr/bin/env python3
"""Bug 79, second half (run 8, test 48): the 19h guard keeps control on Shay
when a first-person click lands on Malzin, but the info shown is then Shay's.
Wanted: her details, like clicking a normal NPC.
Fix: after reverting the selection, open the clicked squad member's stats
window via the game's ForgottenGUI::showCharacterStatsWindow(hand) (static
ForgottenGUI instance at RVA 0x21337b0, as used by the UI-panel checks),
under the crash guard.
Usage: patch_r20_bug79b_details.py <KenshiFP tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("client/kenshifp_client.c", [
    ("""typedef void (*pi_selectpc_t)(void *, void *, unsigned char, unsigned char);""",
     """typedef void (*pi_selectpc_t)(void *, void *, unsigned char, unsigned char);
#define KLIB_GUI_SHOWSTATS_SYM "?showCharacterStatsWindow@ForgottenGUI@@QEAAXAEBVhand@@@Z"
#define RVA_GUI_INSTANCE 0x21337b0u /* static ForgottenGUI instance (see RVA_GUI_* above) */
typedef void (*gui_showstats_t)(void *, const void *);"""),
    ("""    guard_arm();
    fn(pi, keep, 0, 0);
    g_guard_armed = 0;
    logline("[fp] look-at click selected another squad member: kept control (bug 79)");
}""",
     """    guard_arm();
    fn(pi, keep, 0, 0);
    g_guard_armed = 0;
    logline("[fp] look-at click selected another squad member: kept control (bug 79)");
    /* Bug 79b: show the clicked member's details instead of yours. */
    static gui_showstats_t show;
    static int show_dead;
    if (show_dead) return;
    if (!show) {
        HMODULE k2 = GetModuleHandleA("KenshiLib.dll");
        if (k2) show = (gui_showstats_t)GetProcAddress(k2, KLIB_GUI_SHOWSTATS_SYM);
        if (!show) { show_dead = 1; logline("[fp] look-at details: export missing -- disabled"); return; }
    }
    void *gui = (void *)(g_base + RVA_GUI_INSTANCE);
    const void *h = (const void *)((uintptr_t)cur + CHAR_HANDLE);
    if (!readable(gui, 0x220) || !readable(h, 0x20)) return;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; show_dead = 1; logline("[fp] look-at details FAULTED -- disabled"); return; }
    guard_arm();
    show(gui, h);
    g_guard_armed = 0;
    logline("[fp] look-at click: opened the clicked member's details (bug 79)");
}"""),
])
