/* Only intercept game command binding dispatch, never MyGUI click injection.
 * Physical L/R buttons still reach the normal combat input sampler. */
typedef void (*combat_keydown_t)(void *,int);
typedef void *(*combat_gui_instance_t)(void);
typedef void *(*combat_gui_focus_t)(void *);
static combat_keydown_t g_combat_keydown_orig;
static combat_gui_instance_t g_combat_gui_instance;
static combat_gui_focus_t g_combat_gui_focus;
static int g_combat_mouse_ready;
static unsigned g_combat_mouse_consumed;
static int combat_world_mouse_owned(int code) {
    if ((code!=0x1000 && code!=0x2000) || !combat_owned_rc(g_combat_rc) ||
        g_ui_open || g_is_down || !game_has_focus() || g_combat_injection ||
        (GetAsyncKeyState(VK_MENU)&0x8000) || (GetAsyncKeyState(VK_CONTROL)&0x8000) ||
        (GetAsyncKeyState(VK_SHIFT)&0x8000)) return 0;
    /* Do not replace an enclosing native guard's jump target. */
    if (g_guard_armed || !g_combat_gui_instance || !g_combat_gui_focus)return 0;
    if(setjmp(g_guard_jb)) {
        g_guard_armed=0;g_combat_fault=1;
        logline("[combat] UI focus query fault; manual input ownership disabled");return 0;
    }
    guard_arm();
    void *gui=g_combat_gui_instance();
    void *widget=gui?g_combat_gui_focus(gui):NULL;
    g_guard_armed=0;
    return gui && !widget;
}
static void combat_keydown_hook(void *key,int code) {
    if(combat_world_mouse_owned(code)) {++g_combat_mouse_consumed;return;}
    g_combat_keydown_orig(key,code);
}
static int fp_combat_input_init(void) {
    HMODULE gui=GetModuleHandleA("MyGUIEngine_x64.dll");
    if(!gui)return 0;
    g_combat_gui_instance=(combat_gui_instance_t)GetProcAddress(gui,
      "?getInstance@?$Singleton@VInputManager@MyGUI@@@MyGUI@@SAAEAVInputManager@2@XZ");
    g_combat_gui_focus=(combat_gui_focus_t)GetProcAddress(gui,
      "?refreshMouseFocusWidget@InputManager@MyGUI@@QEAAPEAVWidget@2@XZ");
    uintptr_t p=combat_unique_signature("40 53 48 83 EC 30 44 8B C2 48 8B D9 83 FA 2A 74 05 83 FA 36 75 07 C6 81 D9 00 00 00 01 83 FA 1D");
    if(p && g_combat_gui_instance && g_combat_gui_focus)
        g_combat_mouse_ready=install_hook((void *)p,(void *)combat_keydown_hook,(void **)&g_combat_keydown_orig);
    logline("[combat] world mouse binding hook %s (GUI/release/modifiers pass through)",
            g_combat_mouse_ready?"installed":"unavailable");
    return g_combat_mouse_ready;
}
