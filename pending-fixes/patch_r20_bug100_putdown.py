#!/usr/bin/env python3
"""Bug 100 (Shay, run 8): in first person, after picking up an NPC there was no
way to put them down (the put-down command needs the free cursor / right-click
menu, which FP captures).
Fix: in FP mode (cursor captured, Kenshi focused, no UI open) pressing G calls
the game's own Character::dropCarriedObject(ragdoll=true, removeOnly=false)
for the character you control, under the crash guard. Not carrying anyone ->
the game call does nothing.
Usage: patch_r20_bug100_putdown.py <KenshiFP tree root>"""
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
    ("static void manual_fire_update(void *pcx);      /* defined with the hooks below */",
     "static void manual_fire_update(void *pcx);      /* defined with the hooks below */\n"
     "static void fp_putdown_update(void *pcx);      /* bug 100: G puts down a carried NPC */"),
    ("""        if (KFP_MANUAL_AIM)
            manual_fire_update(pcx);    /* LMB -> GunClass::shoot at crosshair */
""",
     """        if (KFP_MANUAL_AIM)
            manual_fire_update(pcx);    /* LMB -> GunClass::shoot at crosshair */
        fp_putdown_update(pcx);         /* bug 100: G -> put down whoever you carry */
"""),
    ("static void manual_fire_update(void *pcx)\n{",
     """/* Bug 100: FP has no right-click menu, so a carried NPC could not be put
 * down. G (edge, FP, cursor captured, Kenshi focused) calls the game's own
 * Character::dropCarriedObject(ragdoll, removeOnly) under the crash guard. */
#define KLIB_DROPCARRIED_SYM "?dropCarriedObject@Character@@QEAAX_N0@Z"
typedef void (*chr_dropcarried_t)(void *, unsigned char, unsigned char);
static void fp_putdown_update(void *pcx)
{
    static int prev, dead;
    static chr_dropcarried_t fn;
    int k = (GetAsyncKeyState('G') & 0x8000) != 0;
    int edge = k && !prev;
    prev = k;
    if (!edge || dead || !g_fp_mode || g_ui_open || !g_cursor_hidden || !pcx || !game_has_focus()) return;
    if (!fn) {
        HMODULE kl = GetModuleHandleA("KenshiLib.dll");
        if (kl) fn = (chr_dropcarried_t)GetProcAddress(kl, KLIB_DROPCARRIED_SYM);
        if (!fn) { dead = 1; logline("[fp] put down: export missing -- disabled"); return; }
    }
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; dead = 1; logline("[fp] put down FAULTED -- disabled"); return; }
    guard_arm();
    fn(pcx, 1, 0);
    g_guard_armed = 0;
    logline("[fp] put down: dropCarriedObject called (bug 100)");
}

static void manual_fire_update(void *pcx)
{"""),
])
