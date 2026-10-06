#!/usr/bin/env python3
"""Generate Stobe src/StobeGoals.cpp from the KenshiFP client (non-FP goal/action/voice code).
usage: gen_stobe_goals.py <kenshifp_client_dir> <out_cpp>
Asserts every anchor; rerun against a newer KenshiFP client to regenerate."""
import re, sys
cdir, out = sys.argv[1], sys.argv[2]
C = open(cdir + '/kenshifp_client.c', encoding='latin-1').read()
W = open(cdir + '/stobe_work_planner.inc', encoding='latin-1').read()
T = open(cdir + '/stobe_task_goals.inc', encoding='latin-1').read()


def rep(s, old, new, count=1):
    n = s.count(old)
    assert n == count, (n, old[:90])
    return s.replace(old, new)


def func(name):
    """extract the first top-level function definition called name"""
    m = re.search(r'^(?:static\s+)?[A-Za-z_][\w \*]*?[\s\*]' + name + r'\s*\([^;{]*?\)\s*\{', C, flags=re.M | re.S)
    assert m, name
    i = m.end(); depth = 1
    while depth:
        ch = C[i]
        if ch == '{': depth += 1
        elif ch == '}': depth -= 1
        i += 1
    return C[m.start():i] + '\n'


def define(name):
    m = re.search(r'^#define\s+' + name + r'\b.*$', C, flags=re.M)
    assert m, name
    return m.group(0) + '\n'


def typedef(name):
    m = re.search(r'^typedef[^;]*\(\*\s*' + name + r'\)[^;]*;', C, flags=re.M | re.S)
    assert m, name
    return m.group(0) + '\n'


# ---- moved region: STOBE voice-mode bridge .. just before camera_lock ----
start = C.index('/* STOBE voice-mode bridge.')
end = C.index('/* M1 camera lock.')
R = C[start:end]

# voice range lock + lifelike bridge: fixed Stobe.dll RVAs -> direct Stobe internals
a = R.index('#define STOBE_PROXIMITY_RVA')
b = R.index('#define KLIB_GETCHARS_SYM')
R = R[:a] + r'''#define STOBE_VOICE_LOCK_RANGE 500.0f
#define STOBE_VOICE_LOCK_MIN_HOLD_MS 350u
#define STOBE_VOICE_LOCK_WINDOW_MS 15000u
static int g_stobe_range_lock;
static float g_stobe_saved_range;
static DWORD g_stobe_range_restore_at;
/* Was KenshiFP writing Stobe.dll's g_proximityRadius by fixed RVA; now direct. */
static int stobe_set_voice_range_lock(int enable)
{
    float *prox = StobeGoals_ProximityRadius();
    if (!prox) return 0;
    float p = *prox;
    if (!(p >= 1.0f && p <= 5000.0f)) return 0;
    if (enable) {
        if (!g_stobe_range_lock) {
            g_stobe_saved_range = p;
            *prox = p > STOBE_VOICE_LOCK_RANGE ? p : STOBE_VOICE_LOCK_RANGE;
            g_stobe_range_lock = 1;
            logline("[stobe] voice target locked: post-STT range %.1f -> %.1f", p, *prox);
        }
    } else if (g_stobe_range_lock) {
        *prox = g_stobe_saved_range;
        logline("[stobe] voice target lock released: range restored to %.1f", g_stobe_saved_range);
        g_stobe_range_lock = 0;
        g_stobe_saved_range = 0.0f;
        g_stobe_range_restore_at = 0;
    }
    return 1;
}
static int stobe_mod_path(char *out, size_t outsz, const char *leaf);
/* lifelike_interrupt.flag (server: danger) -> Stobe's own chat/TTS preemption.
 * lifelike_initiative.flag is consumed by Stobe's UpdateLifelikeInitiativeFlag (main.cpp).
 * KenshiFP used fixed Stobe.dll RVAs here and built the path as exe dir + RE_Kenshi\...,
 * which never existed, so this signal was never consumed before. A flag older than 30 s
 * is stale and dropped unused. */
static void stobe_lifelike_signal_tick(void)
{
    static DWORD next_poll;
    DWORD now = GetTickCount();
    if (next_poll && (LONG)(now - next_poll) < 0) return;
    next_poll = now + 100;
    char path[MAX_PATH * 2] = {0};
    if (!stobe_mod_path(path, sizeof(path), "lifelike_interrupt.flag")) return;
    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!GetFileAttributesExA(path, GetFileExInfoStandard, &fa)) return;
    FILETIME ft; GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER t0, t1;
    t0.LowPart = fa.ftLastWriteTime.dwLowDateTime; t0.HighPart = fa.ftLastWriteTime.dwHighDateTime;
    t1.LowPart = ft.dwLowDateTime; t1.HighPart = ft.dwHighDateTime;
    double age_s = t1.QuadPart > t0.QuadPart ? (double)(t1.QuadPart - t0.QuadPart) / 1.0e7 : 0.0;
    DeleteFileA(path);
    if (age_s > 30.0) {
        logline("[stobe] lifelike interrupt flag stale (%.0f s) -- dropped", age_s);
        return;
    }
    long generation = StobeGoals_ChatInterrupt();
    logline("[stobe] lifelike danger preempted chat/TTS generation=%ld", generation);
}
''' + R[b:]

# bool-returning natives were typed int (only AL is defined on return)
for td in ['typedef int (*stobe_inv_hasroom_t)', 'typedef int (*stobe_inv_additem_t)',
           'typedef int (*stobe_invsect_hasitem_t)', 'typedef int (*stobe_invsect_removeitem_t)',
           'typedef int (*stobe_invsect_hasroom_t)', 'typedef int (*stobe_invsect_additem_t)',
           'typedef int (*stobe_equip_t)']:
    R = rep(R, td, td.replace('typedef int', 'typedef unsigned char'))

# ---- fault guards: setjmp/VEH -> SEH __try/__except (game thread only) ----
R = rep(R, '''    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0;
        logline("[stobe] unequip request faulted safely serial=%u item=%s", serial, tab);
        return;
    }
    guard_arm();
    void *npc''', '''    __try {
    void *npc''')
R = rep(R, '''    logline("[stobe] UNEQUIP_ITEM serial=%u query=%s matched=%s result=%s",
            serial, tab, matched[0] ? matched : "(unknown)", success ? "ok" : "failed");
}''', '''    logline("[stobe] UNEQUIP_ITEM serial=%u query=%s matched=%s result=%s",
            serial, tab, matched[0] ? matched : "(unknown)", success ? "ok" : "failed");
    } __except (STOBE_SEH_FILTER) {
        logline("[stobe] unequip request faulted safely serial=%u item=%s code=0x%08lx", serial, tab, g_seh_code);
    }
}''')
R = rep(R, '''        if (setjmp(g_guard_jb)) {
            g_guard_armed = 0;
            g_stobe_fight_truce[i].serial = 0;
            logline("[stobe] STOP_FIGHT reapply faulted safely serial=%u", serial);
            continue;
        }
        guard_arm();
        void *npc = stobe_find_character_by_serial(gw, serial);
        if (npc && stobe_resolve_fight_exports())
            stobe_disengage_character(npc);
        g_guard_armed = 0;''', '''        void *npc = NULL;
        __try {
            npc = stobe_find_character_by_serial(gw, serial);
            if (npc && stobe_resolve_fight_exports())
                stobe_disengage_character(npc);
        } __except (STOBE_SEH_FILTER) {
            g_stobe_fight_truce[i].serial = 0;
            logline("[stobe] STOP_FIGHT reapply faulted safely serial=%u code=0x%08lx", serial, g_seh_code);
            continue;
        }''')
R = rep(R, '''    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0;
        logline("[stobe] ACTION_BRIDGE faulted safely actor=%u command=%s",
                actor_serial, command);
        return;
    }
    guard_arm();
    int success = stobe_handle_general_action(
        gw, actor_serial, command, target_serial, argument);
    g_guard_armed = 0;''', '''    int success = 0;
    __try {
        success = stobe_handle_general_action(
            gw, actor_serial, command, target_serial, argument);
    } __except (STOBE_SEH_FILTER) {
        logline("[stobe] ACTION_BRIDGE faulted safely actor=%u command=%s code=0x%08lx",
                actor_serial, command, g_seh_code);
        return;
    }''')
assert 'setjmp' not in R, 'region setjmp left'
R = rep(R, '#include "stobe_work_planner.inc"\n#include "stobe_task_goals.inc"\n', '/*@@GOAL_INCLUDES@@*/\n')

# ---- work planner ----
W = rep(W, '''    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_sgt_dead = 1; logline("[stobe] GOAL_LOAD world time faulted -- save check off"); return; }
    guard_arm();
    fn(gw, &hours); /* TimeOfDay comes back through the hidden pointer: one double, hours */
    g_guard_armed = 0;''', '''    __try {
        fn(gw, &hours); /* TimeOfDay comes back through the hidden pointer: one double, hours */
    } __except (STOBE_SEH_FILTER) { g_sgt_dead = 1; logline("[stobe] GOAL_LOAD world time faulted -- save check off"); return; }''')
W = rep(W, '''    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0; g_job_ui_dead = 1;
        logline("[stobe] GOAL_JOB ui refresh faulted -- disabled for this session");
        return;
    }
    guard_arm();
    fn(pi, cur, none); /* bug 74: click away ... */
    fn(pi, none, cur); /* ... and back, like the manual workaround */
    g_guard_armed = 0;''', '''    __try {
        fn(pi, cur, none); /* bug 74: click away ... */
        fn(pi, none, cur); /* ... and back, like the manual workaround */
    } __except (STOBE_SEH_FILTER) {
        g_job_ui_dead = 1;
        logline("[stobe] GOAL_JOB ui refresh faulted -- disabled for this session");
        return;
    }''')
W = rep(W, '''    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0;
        wgp_goal_block(g, "a native game call faulted while working on this goal; stopped safely to protect the game");
        return;
    }
    guard_arm();
    wgp_goal_tick(gw, g);
    g_guard_armed = 0;''', '''    __try {
        wgp_goal_tick(gw, g);
    } __except (STOBE_SEH_FILTER) {
        logline("[stobe] WORK_GOAL tick faulted code=0x%08lx", g_seh_code);
        wgp_goal_block(g, "a native game call faulted while working on this goal; stopped safely to protect the game");
    }''')
assert 'setjmp' not in W

# ---- task goals ----
T = rep(T, '''    if(setjmp(g_guard_jb)){
        g_guard_armed=0;
        stg_finish(g,STG_STATE_BLOCKED,"a native game call faulted while working on this task; stopped safely to protect the game");
        return;
    }
    guard_arm();
    stg_tick_goal(gw,g);
    g_guard_armed=0;''', '''    __try {
        stg_tick_goal(gw,g);
    } __except (STOBE_SEH_FILTER) {
        logline("[stobe] TASK_GOAL tick faulted code=0x%08lx", g_seh_code);
        stg_finish(g,STG_STATE_BLOCKED,"a native game call faulted while working on this task; stopped safely to protect the game");
    }''')
T = rep(T, '''    if(setjmp(g_guard_jb)){g_guard_armed=0;g_sgm_dead=1;logline("[stobe] GOAL_MEAL faulted -- meals disabled for this session");return 0;}
    guard_arm();
    int r=sgm_meal_tick_body(gw,serial,name,step,stepsz);
    g_guard_armed=0;
    return r;''', '''    int r=0;
    __try { r=sgm_meal_tick_body(gw,serial,name,step,stepsz); }
    __except (STOBE_SEH_FILTER) { g_sgm_dead=1; logline("[stobe] GOAL_MEAL faulted -- meals disabled for this session"); return 0; }
    return r;''')
# goal label: the guarded part becomes its own function (body unchanged)
T = rep(T, '''    g_goal_label_next=now+250;
    if(setjmp(g_guard_jb)){
        g_guard_armed=0;g_goal_label_dead=1;
        logline("[stobe] GOAL_LABEL faulted -- disabled for this session");
        return;
    }
    guard_arm();
    void *gui=g_gui_getinstance();''', '''    g_goal_label_next=now+250;
    __try { stobe_goal_label_body(gw); }
    __except (STOBE_SEH_FILTER) {
        g_goal_label_dead=1;
        logline("[stobe] GOAL_LABEL faulted -- disabled for this session");
    }
}
static void stobe_goal_label_body(void *gw)
{
    void *gui=g_gui_getinstance();''')
T = rep(T, 'static void stobe_goal_label_update(void *gw)\n{', 'static void stobe_goal_label_body(void *gw);\nstatic void stobe_goal_label_update(void *gw)\n{')
T = rep(T, 'unsigned char shop_mem[0xE0] __attribute__((aligned(16)));', '__declspec(align(16)) unsigned char shop_mem[0xE0];', 2)
assert 'setjmp' not in T and '__attribute__' not in T

# ---- helpers copied from the client ----
helpers = ''
for n in ['in_module', 'readable', 'char_valid', 'first_player_char', 'char_position', 'char_prone_state',
          'read_mstring', 'make_mstr_long', 'caption_set', 'find_widget_suffix', 'settings_find', 'make_child']:
    helpers += func(n) + '\n'
tm = func('try_move_to_pos')
tm = rep(tm, '''    if (setjmp(g_guard_jb)) {          /* longjmp target: the call blew up */
        g_movetopos_dead = 1;
        g_guard_armed = 0;
        logline("playerMoveOrderDefault FAULTED -- disabled for this session");
        return 0;
    }
    guard_arm();
    fn(pc, NULL, NULL, tgt);          /* NULL,NULL = plain ground point */
    g_guard_armed = 0;''', '''    __try {
        fn(pc, NULL, NULL, tgt);          /* NULL,NULL = plain ground point */
    } __except (STOBE_SEH_FILTER) {
        g_movetopos_dead = 1;
        logline("playerMoveOrderDefault FAULTED -- disabled for this session");
        return 0;
    }''')
helpers += tm

macros = ''.join(define(n) for n in [
    'GW_PLAYER', 'CHAR_HANDLE', 'ITEM_GAMEDATA', 'ITEM_ROOT_DATA', 'ROOT_DISPLAY_NAME',
    'ITEM_SLOT_TYPE', 'ITEM_IS_EQUIPPED', 'GD_NAME', 'ATTACH_WEAPON', 'ATTACH_BACK', 'ATTACH_HAT', 'ATTACH_EYES',
    'ATTACH_BODY', 'ATTACH_LEGS', 'ATTACH_SHIRT', 'ATTACH_BOOTS', 'ATTACH_GLOVES', 'ATTACH_NECK', 'ATTACH_BACKPACK',
    'ATTACH_BELT', 'INV_ALLITEMS', 'GW_FRAMESPEED', 'CHAR_TASKHOLDER', 'TASK_CUR', 'TASK_DESC', 'TASKDESC_TYPE',
    'PI_PLAYERCHARS', 'PI_SELECTED_CHAR', 'HAND_IDS', 'LEK_COUNT', 'LEK_STUFF', 'GETPOS_VTABLE_SLOT',
    'CHAR_PRONE_STATE', 'CHAR_VT_PLAYERMOVE', 'PS_NORMAL', 'MYGUI_DLL',
    'MYGUI_GUI_GETINSTANCE_SYM', 'MYGUI_CREATEWIDGET_SYM', 'MYGUI_SETPOS_SYM', 'MYGUI_WIDGET_INHVIS_SYM',
    'MYGUI_WIDGET_SETVIS_SYM', 'MYGUI_WIDGET_CREATEWIDGET_SYM', 'MYGUI_GETPARENT_SYM', 'MYGUI_TEXTBOX_SETCAP_SYM',
    'MYGUI_USTRING_CTOR_SYM', 'MYGUI_USTRING_DTOR_SYM', 'MYGUI_GUI_GETENUM_SYM', 'MYGUI_WIDGET_GETENUM_SYM',
    'MYGUI_WIDGET_GETNAME_SYM'])
typedefs = ''.join(typedef(n) for n in [
    'gui_getinstance_t', 'gui_createwidget_t', 'widget_setpos_t',
    'widget_setvisible_t', 'widget_inhvis_t', 'widget_createwidget_t', 'getparent_t', 'textbox_setcap_t',
    'ustring_ctor_t', 'ustring_dtor_t', 'getenum_t', 'widget_getname_t'])

prelude = r'''/* StobeGoals.cpp -- GENERATED by KenshiModding/pending-fixes/decouple/gen_stobe_goals.py from the
 * KenshiFP client (kenshifp_client.c "STOBE voice-mode bridge" .. camera_lock, stobe_work_planner.inc,
 * stobe_task_goals.inc). Non-FP gameplay executor moved out of KenshiFP.dll into Stobe.dll: work/task
 * goals, goal panel, general actions (stobe_action.request), unequip requests, fight truce, voice
 * modifiers (U / Shift+U / Ctrl+U), lifelike interrupt. File protocol and log line texts unchanged;
 * log file: mods\Stobe\stobe_goals.log (was KenshiFP.log).
 * Fault containment: SEH __try/__except on the game thread (KenshiFP used setjmp + a VEH). */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <math.h>
#include "StobeGoals.h"
#pragma warning(disable: 4996 4244 4267 4018 4101 4102 4189 4305 4146 4800)

#if defined(_MSC_VER) && _MSC_VER < 1900
static int stobe_vsnprintf(char *b, size_t n, const char *f, va_list ap)
{
    if (!n) return _vscprintf(f, ap);
    int r = _vsnprintf(b, n, f, ap);
    if (r < 0 || (size_t)r >= n) { b[n - 1] = '\0'; if (r < 0) r = _vscprintf(f, ap); }
    return r;
}
static int stobe_snprintf(char *b, size_t n, const char *f, ...)
{
    va_list ap; va_start(ap, f); int r = stobe_vsnprintf(b, n, f, ap); va_end(ap); return r;
}
#define snprintf stobe_snprintf
#define vsnprintf stobe_vsnprintf
#define strtoull _strtoui64
#define strtoll _strtoi64
#define strtof(s, e) ((float)strtod((s), (e)))
#endif
#define strcasecmp _stricmp
#define strncasecmp _strnicmp

#define KFP_DEBUG_LOG 0
static unsigned long g_seh_code;
static int stobe_seh_filter(unsigned long code)
{
    switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: case EXCEPTION_ILLEGAL_INSTRUCTION: case EXCEPTION_PRIV_INSTRUCTION:
    case 0xE06D7363u: /* MSVC C++ throw that nothing below us caught */
    case EXCEPTION_IN_PAGE_ERROR: case EXCEPTION_INT_DIVIDE_BY_ZERO: case EXCEPTION_INT_OVERFLOW:
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: case EXCEPTION_DATATYPE_MISALIGNMENT:
        g_seh_code = code;
        return EXCEPTION_EXECUTE_HANDLER;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
#define STOBE_SEH_FILTER stobe_seh_filter(GetExceptionCode())
static volatile LONG g_guard_armed; /* leftover disarm writes from the setjmp guard; unused */

''' + macros + r'''
typedef struct { float x, y, z; } Vec3;
typedef Vec3 *(*get_position_t)(void *self, Vec3 *out);
''' + typedefs + r'''
static uintptr_t g_base;
static FILE *g_log;
static int g_log_tried;
static int g_movetopos_dead;
static gui_getinstance_t g_gui_getinstance;
static gui_createwidget_t g_gui_createwidget;
static widget_setpos_t g_widget_setpos;
static widget_setvisible_t g_widget_setvisible;
static widget_inhvis_t g_widget_inhvis;
static widget_createwidget_t g_widget_createwidget;
static getparent_t g_widget_getparent;
static textbox_setcap_t g_textbox_setcap;
static ustring_ctor_t g_ustring_ctor;
static ustring_dtor_t g_ustring_dtor;
static getenum_t g_gui_getenum, g_widget_getenum;
static widget_getname_t g_widget_getname;
static int g_find_budget;

static int stobe_mod_path(char *out, size_t outsz, const char *leaf);
static void logline(const char *fmt, ...)
{
    if (!g_log && !g_log_tried) {
        g_log_tried = 1;
        char path[MAX_PATH * 2] = {0};
        if (stobe_mod_path(path, sizeof(path), "stobe_goals.log"))
            g_log = fopen(path, "w");
    }
    if (!g_log) return;
    SYSTEMTIME st; GetLocalTime(&st);
    fprintf(g_log, "[%02u:%02u:%02u.%03u] ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_list ap; va_start(ap, fmt); vfprintf(g_log, fmt, ap); va_end(ap);
    fputc('\n', g_log); fflush(g_log);
}

''' + helpers + '\n'

epilogue = r'''
/* ---------------- Stobe entry points ---------------- */
static int g_goals_init;
static void stobe_goals_init(void)
{
    g_goals_init = 1;
    g_base = (uintptr_t)GetModuleHandleA(NULL);
    HMODULE mygui = GetModuleHandleA(MYGUI_DLL);
    if (mygui) {
        g_gui_getinstance = (gui_getinstance_t)GetProcAddress(mygui, MYGUI_GUI_GETINSTANCE_SYM);
        g_gui_createwidget = (gui_createwidget_t)GetProcAddress(mygui, MYGUI_CREATEWIDGET_SYM);
        g_widget_setpos = (widget_setpos_t)GetProcAddress(mygui, MYGUI_SETPOS_SYM);
        g_widget_setvisible = (widget_setvisible_t)GetProcAddress(mygui, MYGUI_WIDGET_SETVIS_SYM);
        g_widget_inhvis = (widget_inhvis_t)GetProcAddress(mygui, MYGUI_WIDGET_INHVIS_SYM);
        g_widget_createwidget = (widget_createwidget_t)GetProcAddress(mygui, MYGUI_WIDGET_CREATEWIDGET_SYM);
        g_widget_getparent = (getparent_t)GetProcAddress(mygui, MYGUI_GETPARENT_SYM);
        g_textbox_setcap = (textbox_setcap_t)GetProcAddress(mygui, MYGUI_TEXTBOX_SETCAP_SYM);
        g_ustring_ctor = (ustring_ctor_t)GetProcAddress(mygui, MYGUI_USTRING_CTOR_SYM);
        g_ustring_dtor = (ustring_dtor_t)GetProcAddress(mygui, MYGUI_USTRING_DTOR_SYM);
        g_gui_getenum = (getenum_t)GetProcAddress(mygui, MYGUI_GUI_GETENUM_SYM);
        g_widget_getenum = (getenum_t)GetProcAddress(mygui, MYGUI_WIDGET_GETENUM_SYM);
        g_widget_getname = (widget_getname_t)GetProcAddress(mygui, MYGUI_WIDGET_GETNAME_SYM);
    }
    logline("[stobe] goal executor running in Stobe.dll (moved from KenshiFP) mygui=%p cap=%p create=%p enum=%p",
            (void *)mygui, (void *)g_textbox_setcap, (void *)g_gui_createwidget, (void *)g_gui_getenum);
}

void StobeGoals_Tick(void *gw)
{
    if (!gw) return;
    if (!g_goals_init) stobe_goals_init();
    stobe_voice_modifier_tick();
    stobe_unequip_request_tick(gw);
    stobe_general_action_request_tick(gw);
    stobe_fight_truce_tick(gw);
    stobe_work_goal_tick(gw);
    stobe_task_goal_tick(gw);
    stobe_goal_label_update(gw);
}

void StobeGoals_HidePanel(void)
{
    if (!g_goal_label || !g_widget_setvisible || !g_goal_label_text[0]) return;
    __try { g_widget_setvisible(g_goal_label, 0); }
    __except (STOBE_SEH_FILTER) { g_goal_label = NULL; g_goal_panel_text = NULL; }
    g_goal_label_text[0] = '\0';
}

/* KenshiFP's FP combat refuses manual shots while a STOP_FIGHT truce is pending. */
extern "C" __declspec(dllexport) int StobeFightTruceActive(void)
{
    for (int i = 0; i < STOBE_FIGHT_TRUCE_SLOTS; ++i)
        if (g_stobe_fight_truce[i].serial) return 1;
    return 0;
}
'''
R = R.replace('/*@@GOAL_INCLUDES@@*/\n', '/* ==== stobe_work_planner.inc ==== */\n' + W +
              '\n/* ==== stobe_task_goals.inc ==== */\n' + T + '\n')
src = prelude + R + epilogue
open(out, 'w', encoding='latin-1', newline='\n').write(src)
print('wrote', out, src.count('\n'), 'lines')
