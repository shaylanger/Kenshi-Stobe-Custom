#!/usr/bin/env python3
"""Bug 106: during work goals Malzin worked ~1 s, stopped, waited, worked
again; goals crawled even at 50x. The planner re-sent the operate order +
rethink every 2 game s (mine step and machine step), interrupting her each
time. The goal's real Kenshi job keeps her working on its own.
Fix: order only when the target machine changes, or when she has been idle
(no task / NULL_TASK / IDLE) and 30+ game s have passed since the last order.
Usage: patch_r19_bug106_reorder.py <KenshiFP tree root>"""
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
    ("#define WGP_STALL_MS 1800000\n",
     "#define WGP_STALL_MS 1800000\n"
     "#define WGP_REORDER_MS 30000 /* bug 106: re-send the operate order only after 30 game s idle */\n"),
    ("/* Operate order for a goal; clears the old order first when the target building changes. */",
     """/* Bug 106: is she doing nothing right now? (no task, NULL_TASK 0 or IDLE 14) */
static int wgp_actor_idle(void *actor)
{
    void *tholder = readable((void *)((uintptr_t)actor + CHAR_TASKHOLDER), 8)
        ? *(void **)((uintptr_t)actor + CHAR_TASKHOLDER) : NULL;
    if (!readable(tholder, TASK_CUR + 8)) return 1;
    void *cur = *(void **)((uintptr_t)tholder + TASK_CUR);
    if (!cur) return 1;
    if (!readable(cur, TASK_DESC + 8)) return 0;
    void *desc = *(void **)((uintptr_t)cur + TASK_DESC);
    if (!readable(desc, TASKDESC_TYPE + 4)) return 0;
    int t = *(int *)((uintptr_t)desc + TASKDESC_TYPE);
    return t == 0 || t == 14;
}

/* Operate order for a goal; clears the old order first when the target building changes. */"""),
    ("""    if (g->rt_task_building != p.building || (LONG)(stobe_game_ms()-g->last_order_ms)>2000) {""",
     """    if (g->rt_task_building != p.building ||
        ((LONG)(stobe_game_ms()-g->last_order_ms)>WGP_REORDER_MS && wgp_actor_idle(actor))) { /* bug 106 */"""),
    ("""    if (g->rt_task_building != root.building || (LONG)(now-g->last_order_ms)>2000) {""",
     """    if (g->rt_task_building != root.building ||
        ((LONG)(now-g->last_order_ms)>WGP_REORDER_MS && wgp_actor_idle(actor))) { /* bug 106 */"""),
])
