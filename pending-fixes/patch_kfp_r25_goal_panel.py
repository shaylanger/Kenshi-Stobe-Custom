#!/usr/bin/env python3
"""Feature (Shay, 2026-10-02): goal panel above the jobs area instead of the top-centre label.

When the selected squad member has a goal ("make bread"), a small panel sits directly
above Kenshi's job list (HUD OrdersPanel -> JobsPanel), as wide as the job box, in the
same orders-box frame:
    Malzin - Make 2 Bread  1/2
    Loading 2 Flour into Stone Oven
    +1 more queued
It follows the real JobsPanel widget (absolute position summed up the parent chain),
hides with the HUD job list, keeps BLOCKED/DONE for 60 s (same rules as the old label),
and falls back to the layout fractions (Kenshi_MainPanel.layout) if the widget isn't
found. Logs: `GOAL_PANEL created at x,y wxh (jobs widget|layout fallback)`.

Usage: patch_kfp_r25_goal_panel.py <KenshiFP root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
s = f.read_text(encoding='utf-8')
if 'GOAL_PANEL created' in s:
    print('already patched'); sys.exit(0)

def sub(old, new):
    global s
    assert s.count(old) == 1, f'anchor found {s.count(old)}x: {old[:70]!r}'
    s = s.replace(old, new)

# forward declarations for helpers defined later in kenshifp_client.c
sub("static void *make_mstr_long(unsigned char *b32, const char *s);              /* kenshifp_client.c */\n",
    "static void *make_mstr_long(unsigned char *b32, const char *s);              /* kenshifp_client.c */\n"
    "static void *settings_find(void *gui, const char *target);                   /* kenshifp_client.c */\n"
    "static void *make_child(void *parent, const char *type, const char *skin, int l, int t, int w, int h, const char *name);\n"
    "static void *g_goal_panel_text;   /* the TextBox inside the panel frame */\n"
    "static void *g_goal_jobs;         /* Kenshi's JobsPanel widget */\n"
    "static int g_goal_jobs_tries;\n"
    "static int g_goal_panel_x, g_goal_panel_y;\n")

# shorter text that fits the job box width
sub("""    if(!found)return;
    if(more>0)snprintf(out,outsz,"%s - %s\\n%s\\n+%d more queued",actor,head,step,more);
    else snprintf(out,outsz,"%s - %s\\n%s",actor,head,step);""",
"""    if(!found)return;
    if(strlen(step)>58){step[55]='.';step[56]='.';step[57]='.';step[58]='\\0';} /* fits the job box */
    if(more>0)snprintf(out,outsz,"%s - %s\\n%s\\n+%d more queued",actor,head,step,more);
    else snprintf(out,outsz,"%s - %s\\n%s",actor,head,step);""")

HELPERS = r'''/* Goal panel: absolute screen rect of a MyGUI widget, summing the parent-relative
 * IntCoord (+0x20 left, +0x24 top, +0x28 width, +0x2C height) up the parent chain. */
static int goal_abs_rect(void *w,int *x,int *y,int *wd,int *ht)
{
    if(!readable(w,0x30))return 0;
    *wd=*(int *)((uintptr_t)w+0x28); *ht=*(int *)((uintptr_t)w+0x2C);
    if(*wd<=0||*wd>8192||*ht<=0||*ht>8192)return 0;
    int ax=0,ay=0; void *c=w;
    for(int i=0;i<16&&c;i++){
        if(!readable(c,0x30))return 0;
        ax+=*(int *)((uintptr_t)c+0x20); ay+=*(int *)((uintptr_t)c+0x24);
        if(!g_widget_getparent)break;
        c=g_widget_getparent(c);
    }
    if(ax<0||ay<0||ax>16384||ay>16384)return 0;
    *x=ax; *y=ay; return 1;
}

#define GOAL_PANEL_H 62
/* Where the panel goes: above the job box frame (JobsPanel's parent). 1 = from the widget. */
static int goal_panel_rect(void *gui,int *x,int *y,int *w)
{
    if(!g_goal_jobs&&g_goal_jobs_tries<40){
        g_goal_jobs_tries++;
        g_goal_jobs=settings_find(gui,"JobsPanel");
    }
    if(g_goal_jobs){
        void *frame=g_widget_getparent?g_widget_getparent(g_goal_jobs):NULL;
        int fx,fy,fw,fh;
        if(frame&&goal_abs_rect(frame,&fx,&fy,&fw,&fh)){*x=fx;*y=fy-GOAL_PANEL_H-4;*w=fw;return 1;}
    }
    /* layout fallback (Kenshi_MainPanel.layout): OrdersPanel 0.748438,0.761111 w 0.252083;
     * job box at 0.274793 / 0.0269231 of it, 0.714876 wide */
    int cx=GetSystemMetrics(SM_CXSCREEN),cy=GetSystemMetrics(SM_CYSCREEN);
    if(cx<=0)cx=1920; if(cy<=0)cy=1080;
    double pw=0.252083*cx, ph=0.240741*cy;
    *x=(int)(0.748438*cx+0.274793*pw); *w=(int)(0.714876*pw);
    *y=(int)(0.761111*cy+0.0269231*ph)-GOAL_PANEL_H-4;
    return 0;
}

'''
sub("static void stobe_goal_label_update(void *gw)\n{", HELPERS + "static void stobe_goal_label_update(void *gw)\n{")

old_create = s[s.index("    if(!g_goal_label){\n        void *gui=g_gui_getinstance();"):s.index("    char text[600];\n    goal_label_build(gw,text,sizeof(text));")]
new_create = r'''    void *gui=g_gui_getinstance();
    if(!readable(gui,8)){g_guard_armed=0;return;}
    int px=0,py=0,pw=0;
    int from_widget=goal_panel_rect(gui,&px,&py,&pw);
    if(!g_goal_label){
        if(!from_widget&&g_goal_jobs_tries<40){g_guard_armed=0;return;} /* give the HUD a moment */
        if(pw<120)pw=120;
        unsigned char ty[32],sk[32],ly[32],nm[32];
        void *f1=make_mstr_long(ty,"Widget");
        void *f2=make_mstr_long(sk,"Kenshi_OrdersTextboxSkin");
        void *f3=make_mstr_long(ly,"Middle");
        void *f4=make_mstr_long(nm,"StobeGoalPanel");
        void *w=g_gui_createwidget(gui,ty,sk,px,py,pw,GOAL_PANEL_H,0,ly,nm);
        if(f1)free(f1);if(f2)free(f2);if(f3)free(f3);if(f4)free(f4);
        if(!readable(w,8)){g_guard_armed=0;g_goal_label_dead=1;logline("[stobe] GOAL_PANEL create failed -- disabled");return;}
        void *t=make_child(w,"TextBox","Kenshi_TextboxStandardText",8,5,pw-16,GOAL_PANEL_H-10,"StobeGoalPanelText");
        if(!readable(t,8)){g_guard_armed=0;g_goal_label_dead=1;logline("[stobe] GOAL_PANEL text create failed -- disabled");return;}
        g_widget_setvisible(w,0);
        g_goal_label=w; g_goal_panel_text=t; g_goal_panel_x=px; g_goal_panel_y=py;
        g_goal_label_text[0]='\0';
        logline("[stobe] GOAL_PANEL created at %d,%d %dx%d (%s)",px,py,pw,GOAL_PANEL_H,from_widget?"jobs widget":"layout fallback");
    }
    if(from_widget&&g_widget_setpos&&(px!=g_goal_panel_x||py!=g_goal_panel_y)){
        g_widget_setpos(g_goal_label,px,py); g_goal_panel_x=px; g_goal_panel_y=py;
    }
'''
s = s.replace(old_create, new_create)

sub("""    if(!text[0]){
        if(g_goal_label_text[0]){g_widget_setvisible(g_goal_label,0);g_goal_label_text[0]='\\0';}
    }else if(strcmp(text,g_goal_label_text)){
        caption_set(g_goal_label,text,g_textbox_setcap);
        g_widget_setvisible(g_goal_label,1);
        strncpy(g_goal_label_text,text,sizeof(g_goal_label_text)-1);
    }""",
"""    /* hidden with the HUD job list (menus, map, hidden UI) */
    int hud=!g_goal_jobs||!g_widget_inhvis||g_widget_inhvis(g_goal_jobs);
    if(!text[0]||!hud){
        if(g_goal_label_text[0]){g_widget_setvisible(g_goal_label,0);g_goal_label_text[0]='\\0';}
    }else if(strcmp(text,g_goal_label_text)){
        caption_set(g_goal_panel_text,text,g_textbox_setcap);
        g_widget_setvisible(g_goal_label,1);
        strncpy(g_goal_label_text,text,sizeof(g_goal_label_text)-1);
    }""")

f.write_text(s, encoding='utf-8')
print('patched', f)
