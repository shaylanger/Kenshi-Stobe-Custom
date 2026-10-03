#!/usr/bin/env python3
"""KenshiFP: test commands through the Kenshi Automation Harness.

Registers fp_mode / fp_click / fp_putdown / fp_state with the harness (only if
AutomationHarness.dll is loaded), so tests can drive first-person input that
otherwise needs real keys and Kenshi having focus (automated runs keep it
unfocused):
- fp_mode on|off  : the same toggle edge the Right Alt poll thread sets
- fp_click        : a captured-cursor left click (bug 79 guard); then select a
                    squad member within 1 s (as Kenshi's click would)
- fp_putdown      : a G press (bug 100 put down)
- fp_state        : fp_mode / cursor_hidden / ui_open
Injected presses skip only the focus/cursor checks; FP mode and "no UI open"
are still required. The goal panel needs no command: harness `ui StobeGoalPanel`.

Usage: patch_kenshifp_harness_bridge.py <KenshiFP root> <harness repo>   (idempotent)
"""
import shutil
import sys
from pathlib import Path

root, harness = Path(sys.argv[1]), Path(sys.argv[2])
f = root / 'client' / 'kenshifp_client.c'
s = f.read_text(encoding='utf-8')
if 'kah_bridge_tick' in s:
    print('already patched')
    sys.exit(0)


def sub(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n}x: {old[:70]!r}'
    s = s.replace(old, new)


sub('#include <windows.h>\n', '#include <windows.h>\n#include "KenshiAutomationHarness.h" /* test commands, if the harness is installed */\n')

sub('static volatile LONG g_toggle_edge;    /* FP-toggle press latched by the DI poll thread */\n',
    'static volatile LONG g_toggle_edge;    /* FP-toggle press latched by the DI poll thread */\n'
    'static volatile LONG g_kah_inject_click, g_kah_inject_putdown; /* harness-injected presses */\n'
    'static void kah_bridge_tick(void);    /* registers the harness test commands */\n')

sub('''static int game_has_focus(void);
static void fp_lookat_click_guard(void *gw)
{''', '''static int game_has_focus(void);

/* ---- Kenshi Automation Harness bridge (TEST ONLY) ----
 * fp_mode / fp_click / fp_putdown / fp_state, registered only when
 * AutomationHarness.dll is loaded (retried once a second). Handlers just latch
 * presses; the FP code consumes them on its next frame. */
static KAH_Api g_kah;
static int g_kah_connected;
static DWORD g_kah_last_try;

static int kah_fp_mode(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)u;
    if (argc < 2 || (_stricmp(argv[1], "on") && _stricmp(argv[1], "off"))) {
        r->append(r, "usage: fp_mode on|off");
        return KAH_ERROR;
    }
    int want = !_stricmp(argv[1], "on");
    if (want == (g_fp_mode != 0)) {
        r->append(r, want ? "FP mode already ON" : "FP mode already OFF");
        return KAH_OK;
    }
    InterlockedExchange(&g_toggle_edge, 1);
    r->append(r, want ? "FP mode toggling ON (next frame; log [input] FP mode toggled)"
                      : "FP mode toggling OFF (next frame)");
    return KAH_OK;
}

static int kah_fp_click(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)argc; (void)argv; (void)u;
    if (!g_fp_mode) { r->append(r, "FP mode is off (fp_mode on first)"); return KAH_ERROR; }
    InterlockedExchange(&g_kah_inject_click, 1);
    r->append(r, "left click injected: select a squad member within 1 s (bug 79 guard)");
    return KAH_OK;
}

static int kah_fp_putdown(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)argc; (void)argv; (void)u;
    if (!g_fp_mode) { r->append(r, "FP mode is off (fp_mode on first)"); return KAH_ERROR; }
    InterlockedExchange(&g_kah_inject_putdown, 1);
    r->append(r, "G injected (bug 100 put down; log [fp] put down)");
    return KAH_OK;
}

static int kah_fp_state(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)argc; (void)argv; (void)u;
    char b[160];
    snprintf(b, sizeof(b), "fp_mode=%d cursor_hidden=%d ui_open=%d", g_fp_mode ? 1 : 0,
             g_cursor_hidden ? 1 : 0, g_ui_open ? 1 : 0);
    r->append(r, b);
    return KAH_OK;
}

static void kah_bridge_tick(void)
{
    if (g_kah_connected) return;
    DWORD now = GetTickCount();
    if (now - g_kah_last_try < 1000) return;
    g_kah_last_try = now;
    if (!KAH_Connect(&g_kah)) return;
    g_kah_connected = 1;
    int n = g_kah.registerCommand("fp_mode", "fp_mode on|off", kah_fp_mode, NULL)
          + g_kah.registerCommand("fp_click", "fp_click (then select a squad member)", kah_fp_click, NULL)
          + g_kah.registerCommand("fp_putdown", "fp_putdown (G while carrying)", kah_fp_putdown, NULL)
          + g_kah.registerCommand("fp_state", "fp_state", kah_fp_state, NULL);
    g_kah.log("KenshiFP: first-person test commands registered");
    logline("[kah] connected to the automation harness: %d commands (fp_mode/fp_click/fp_putdown/fp_state)", n);
}

static void fp_lookat_click_guard(void *gw)
{''')

sub('''    int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    DWORD now = GetTickCount();
    if (lmb && !lmb_prev && g_fp_mode && g_cursor_hidden && !g_ui_open && game_has_focus()) {
        click_ms = now ? now : 1;
        keep = g_player_pc;
    }''', '''    int lmb = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    int injected = InterlockedExchange(&g_kah_inject_click, 0) != 0; /* harness fp_click */
    DWORD now = GetTickCount();
    if ((lmb && !lmb_prev && g_fp_mode && g_cursor_hidden && !g_ui_open && game_has_focus())
        || (injected && g_fp_mode && !g_ui_open)) {
        click_ms = now ? now : 1;
        keep = g_player_pc;
        if (injected) logline("[fp] look-at click (harness-injected)");
    }''')

sub('''    int k = (GetAsyncKeyState('G') & 0x8000) != 0;
    int edge = k && !prev;
    prev = k;
    if (!edge || dead || !g_fp_mode || g_ui_open || !g_cursor_hidden || !pcx || !game_has_focus()) return;''',
    '''    int k = (GetAsyncKeyState('G') & 0x8000) != 0;
    int injected = InterlockedExchange(&g_kah_inject_putdown, 0) != 0; /* harness fp_putdown */
    int edge = (k && !prev) || injected;
    prev = k;
    if (!edge || dead || !g_fp_mode || g_ui_open || !pcx) return;
    if (!injected && (!g_cursor_hidden || !game_has_focus())) return;''')

sub('''    stobe_work_goal_tick(gw);
    stobe_task_goal_tick(gw);''', '''    stobe_work_goal_tick(gw);
    stobe_task_goal_tick(gw);
    kah_bridge_tick();''')

f.write_text(s, encoding='utf-8')
shutil.copy2(harness / 'include' / 'KenshiAutomationHarness.h', root / 'client' / 'KenshiAutomationHarness.h')
print('patched KenshiFP: harness bridge (fp_mode/fp_click/fp_putdown/fp_state)')
