#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
#define VK_MENU 18
#define VK_CONTROL 17
#define VK_SHIFT 16
typedef void *HMODULE;
static int owned=1,focused=1,widget,modifier,available=1,hook_ok=1,crash;
static int g_ui_open,g_is_down,g_combat_injection,g_combat_fault,g_guard_armed;
static void *g_combat_rc=(void *)1;
static jmp_buf g_guard_jb;
static unsigned passed;
static int combat_owned_rc(void *rc){return owned&&!g_combat_fault&&rc==g_combat_rc;}
static int game_has_focus(void){return focused;}
static int GetAsyncKeyState(int key){return key==modifier?0x8000:0;}
static void guard_arm(void){g_guard_armed=1;}
static void logline(const char *fmt,...){(void)fmt;}
static void original(void *key,int code){assert(key==(void *)2);(void)code;++passed;}
static void *instance(void){return available?(void *)3:NULL;}
static void *focus(void *gui){assert(gui==(void *)3);if(crash)longjmp(g_guard_jb,1);return widget?(void *)4:NULL;}
static HMODULE GetModuleHandleA(const char *name){assert(!strcmp(name,"MyGUIEngine_x64.dll"));return (void *)5;}
static void *GetProcAddress(HMODULE h,const char *name) {
 assert(h==(void *)5);
 if(strstr(name,"getInstance"))return (void *)instance;
 assert(strstr(name,"refreshMouseFocusWidget"));return (void *)focus;
}
static uintptr_t combat_unique_signature(const char *sig){assert(strstr(sig,"83 FA 2A"));return 99;}
static int install_hook(void *at,void *hook,void **orig) {
 assert(at==(void *)99);assert(hook);*orig=(void *)original;return hook_ok;
}
#include "../client/kfp_combat_input.inc"
static void passthrough(int code){unsigned old=passed;combat_keydown_hook((void *)2,code);assert(passed==old+1);}
int main(void) {
 assert(fp_combat_input_init());
 combat_keydown_hook((void *)2,0x1000);combat_keydown_hook((void *)2,0x2000);
 assert(g_combat_mouse_consumed==2&&passed==0&&!g_guard_armed);
 passthrough(0x3000);passthrough(30); /* Other mouse/keyboard untouched. */
 widget=1;passthrough(0x1000);widget=0;
 for(int i=0;i<3;++i){modifier=(int[]){VK_MENU,VK_CONTROL,VK_SHIFT}[i];passthrough(0x2000);}
 modifier=0;g_ui_open=1;passthrough(0x1000);g_ui_open=0;
 focused=0;passthrough(0x2000);focused=1;
 g_is_down=1;passthrough(0x2000);g_is_down=0;
 g_combat_injection=1;passthrough(0x1000);g_combat_injection=0;
 owned=0;passthrough(0x1000);owned=1;
 available=0;passthrough(0x1000);available=1;
 g_guard_armed=1;passthrough(0x2000);assert(g_guard_armed==1);g_guard_armed=0;
 crash=1;passthrough(0x1000);assert(g_combat_fault&&!g_guard_armed);crash=0;
 passthrough(0x2000); /* Faulted ownership cannot suppress ordinary input. */
 hook_ok=0;assert(!fp_combat_input_init());
 puts("RESULT B13 PASS production world mouse filtering, GUI/modifier/focus/ownership/guard/fault passthrough; native dispatch unvalidated");
 return 0;
}
