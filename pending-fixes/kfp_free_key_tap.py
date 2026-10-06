#!/usr/bin/env python3
"""KenshiFP: free-cursor key toggles only on a clean tap (S04: Alt+Tab out of Kenshi flipped the toggle and froze FP
combat with why=ui_open). Usage: kfp_free_key_tap.py <KenshiFP tree root>."""
import sys, os
root = sys.argv[1].rstrip('/')
H = r'''/* Free-cursor key (default Left Alt) tap detector. Pure, offline-tested (tests/test_free_key.c).
 * The toggle fires on RELEASE, and only for a clean tap: Kenshi kept focus for the whole hold and no switch-away
 * combo key (Tab/Esc/F4/Win) was pressed meanwhile. Alt+Tab / Alt+F4 / Alt+Esc out of the game starts with Kenshi focused, so a press-edge toggle
 * flipped the cursor free and froze FP combat (why=ui_open, 5090 S04 soak). */
#ifndef KFP_FREE_KEY_H
#define KFP_FREE_KEY_H
typedef struct { int down, dirty; } KfpFreeKey;
/* One frame: key = free key held, focus = Kenshi foreground, other = a switch-away combo key held. Returns 1 = toggle now. */
static int kfp_free_key_step(KfpFreeKey *s,int key,int focus,int other) {
    if (key) {
        if (!s->down) { s->down=1; s->dirty=!focus || other; }
        else if (!focus || other) s->dirty=1;
        return 0;
    }
    if (!s->down) return 0;
    s->down=0;
    return !s->dirty && focus;
}
#endif
'''
T = r'''/* Offline: free-cursor key clean-tap detector (B19). */
#include <assert.h>
#include <stdio.h>
#include "../client/kfp_free_key.h"
static int run(const int (*f)[3],int n){KfpFreeKey s={0,0};int t=0;for(int i=0;i<n;i++)t+=kfp_free_key_step(&s,f[i][0],f[i][1],f[i][2]);return t;}
int main(void){
    const int tap[][3]={{0,1,0},{1,1,0},{1,1,0},{0,1,0}};             /* clean tap -> 1 toggle on release */
    const int alttab[][3]={{1,1,0},{1,1,1},{1,0,1},{1,0,0},{0,0,0}};   /* Alt+Tab away -> none */
    const int altkey[][3]={{1,1,0},{1,1,1},{1,1,0},{0,1,0}};           /* Alt+Esc/F4 inside the game -> none */
    const int unfocused[][3]={{1,0,0},{1,1,0},{0,1,0}};                /* pressed while another window had focus -> none */
    const int held[][3]={{1,1,0},{1,1,0},{1,1,0}};                     /* still held -> nothing yet */
    const int two[][3]={{1,1,0},{0,1,0},{1,1,0},{0,1,0}};              /* two taps -> 2 */
    assert(run(tap,4)==1); assert(run(alttab,5)==0); assert(run(altkey,4)==0);
    assert(run(unfocused,3)==0); assert(run(held,3)==0); assert(run(two,4)==2);
    puts("RESULT B19 PASS free-cursor key: toggles on a clean tap release only (Alt+Tab, Alt+key, unfocused press ignored)");
    return 0;
}
'''
open(f"{root}/client/kfp_free_key.h","w",newline="\n").write(H)
open(f"{root}/tests/test_free_key.c","w",newline="\n").write(T)
def patch(rel,pairs):
    p=f"{root}/{rel}"; s=open(p,encoding="utf-8").read()
    for o,n in pairs:
        assert s.count(o)==1, f"{rel}: anchor {o[:60]!r}"; s=s.replace(o,n)
    open(p,"w",encoding="utf-8",newline="\n").write(s)
patch("client/kenshifp_client.c",[
('#include "kfp_cmd_args.h"\n','#include "kfp_cmd_args.h"\n#include "kfp_free_key.h"\n'),
('''            static int free_was_down;
            /* GetAsyncKeyState is desktop-global: an Alt typed in another window
             * (Alt+Tab elsewhere, a terminal) flipped the toggle and froze FP
             * combat with why=ui_open (S03). Count presses only with focus. */
            int fd = g_cfg_key_free && game_has_focus()
                     && (GetAsyncKeyState(g_cfg_key_free) & 0x8000);
            if (fd && !free_was_down) g_free_toggle = !g_free_toggle;   /* press edge */
            free_was_down = fd;
''','''            static KfpFreeKey free_key;
            /* GetAsyncKeyState is desktop-global: an Alt typed in another window
             * flipped the toggle (S03), and Alt+Tab OUT of Kenshi starts with
             * focus, so it flipped it too (S04 soak). Toggle on a clean tap only:
             * release, focus kept, no switch-away combo key (Tab/Esc/F4/Win)
             * during the hold. Movement keys held while tapping still count. */
            int kd = g_cfg_key_free && (GetAsyncKeyState(g_cfg_key_free) & 0x8000);
            int other = kd && ((GetAsyncKeyState(VK_TAB) | GetAsyncKeyState(VK_ESCAPE) | GetAsyncKeyState(VK_F4)
                                | GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) & 0x8000);
            if (kfp_free_key_step(&free_key, kd, game_has_focus(), other))
                g_free_toggle = !g_free_toggle;
'''),
])
patch("tests/run_offline.py",[('"test_cmd_args.c"):','"test_cmd_args.c","test_free_key.c"):')])
print("ok")
