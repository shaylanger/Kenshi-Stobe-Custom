#!/usr/bin/env python3
"""Bug 74 (retest failed, run 8): the job list panel still only refreshed after
Shay clicked away and back. The r19 fix replayed only "nothing -> Malzin" and
logged nothing. Now replay both halves of the manual workaround
(Malzin -> nothing -> Malzin) and log the outcome.

Bug 79: in FP mode, looking at a squad member and left-clicking switched
control to them. Now a captured-cursor left click (FP on, cursor hidden, Kenshi
focused) that changes the selected squad member within 1 s is reverted with
PlayerInterface::_selectPlayerCharacter. Portrait clicks need the free cursor,
so they still switch.
Usage: patch_r19_bug74_79_selection.py <KenshiFP tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("client/stobe_work_planner.inc", [
    ("""    if (memcmp(sel + HAND_IDS, ah, 20) != 0) return; /* she isn't the selected one: panel shows someone else */
    unsigned char none[HAND_IDS + 20];
    memcpy(none, sel, sizeof(none));
    ((uint32_t *)(none + HAND_IDS))[0] = 0xb; /* null hand: "nothing was selected" */
    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0; g_job_ui_dead = 1;
        logline("[stobe] GOAL_JOB ui refresh faulted -- disabled for this session");
        return;
    }
    guard_arm();
    fn(pi, none, sel);
    g_guard_armed = 0;
}""",
     """    if (memcmp(sel + HAND_IDS, ah, 20) != 0) { logline("[stobe] GOAL_JOB ui refresh skipped: not the selected character"); return; }
    unsigned char cur[HAND_IDS + 20], none[HAND_IDS + 20];
    memcpy(cur, sel, sizeof(cur)); /* sel is live: keep a copy across the two calls */
    memcpy(none, sel, sizeof(none));
    ((uint32_t *)(none + HAND_IDS))[0] = 0xb; /* null hand: "nothing was selected" */
    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0; g_job_ui_dead = 1;
        logline("[stobe] GOAL_JOB ui refresh faulted -- disabled for this session");
        return;
    }
    guard_arm();
    fn(pi, cur, none); /* bug 74: click away ... */
    fn(pi, none, cur); /* ... and back, like the manual workaround */
    g_guard_armed = 0;
    logline("[stobe] GOAL_JOB ui refresh replayed selection");
}"""),
])

GUARD = r'''/* Bug 79: in FP a captured-cursor left click on a squad member made Kenshi
 * select her, and FP follows the selection. Revert such a switch so looking at
 * and clicking a squad member never takes control; portrait clicks (free
 * cursor) still switch. */
#define KLIB_PI_SELECTPC_SYM "?_selectPlayerCharacter@PlayerInterface@@QEAAXPEAVRootObject@@_N1@Z"
typedef void (*pi_selectpc_t)(void *, void *, unsigned char, unsigned char);
static int game_has_focus(void);
static void fp_lookat_click_guard(void *gw)
{
    static int lmb_prev, dead;
    static DWORD click_ms;
    static void *keep;
    static pi_selectpc_t fn;
    if (dead) return;
    int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    DWORD now = GetTickCount();
    if (lmb && !lmb_prev && g_fp_mode && g_cursor_hidden && !g_ui_open && game_has_focus()) {
        click_ms = now ? now : 1;
        keep = g_player_pc;
    }
    lmb_prev = lmb;
    if (!click_ms) return;
    if ((LONG)(now - click_ms) > 1000) { click_ms = 0; return; }
    void *cur = first_player_char(gw);
    if (!keep || !cur || cur == keep || !char_valid(keep)) return;
    click_ms = 0;
    if (!fn) {
        HMODULE k = GetModuleHandleA("KenshiLib.dll");
        if (k) fn = (pi_selectpc_t)GetProcAddress(k, KLIB_PI_SELECTPC_SYM);
        if (!fn) { dead = 1; logline("[fp] look-at click guard: export missing -- disabled"); return; }
    }
    void *pi = *(void **)((uintptr_t)gw + GW_PLAYER);
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; dead = 1; logline("[fp] look-at click guard faulted -- disabled"); return; }
    guard_arm();
    fn(pi, keep, 0, 0);
    g_guard_armed = 0;
    logline("[fp] look-at click selected another squad member: kept control (bug 79)");
}

'''

patch("client/kenshifp_client.c", [
    ("static int ui_panels_open(void);   /* forward decl (defined after the VEH guard) */\n",
     "static int ui_panels_open(void);   /* forward decl (defined after the VEH guard) */\n"
     "static void fp_lookat_click_guard(void *gw); /* bug 79, defined after game_has_focus */\n"),
    ("static int game_has_focus(void)\n",
     GUARD + "static int game_has_focus(void)\n"),
    ("""    {
        void *pcx = first_player_char(gw);
        /* Character swap (selected a different squad member): release the old""",
     """    {
        fp_lookat_click_guard(gw);   /* bug 79: before the swap below sees her */
        void *pcx = first_player_char(gw);
        /* Character swap (selected a different squad member): release the old"""),
])
