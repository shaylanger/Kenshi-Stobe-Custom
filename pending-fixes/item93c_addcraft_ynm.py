#!/usr/bin/env python3
"""Item 93c (STOBE 16 v3, run m16): right after `find_producer done found=1 ... Crossbow Crafting Bench`
the goal blocked with "a native game call faulted". CraftingBuilding::_addCraft takes YesNoMaybe by value;
YesNoMaybe has a user-declared copy constructor, so MSVC x64 passes it by reference (pointer to a
caller-made copy). The planner passed the int 2, so the game read address 0x2. Before item 93b the
crafting path never ran, so the bad call never happened. Fix: pass a pointer to a MAYBE (2) value.
Usage: item93c_addcraft_ynm.py <KenshiFP root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]) / 'client'
edits = {
 'stobe_work_planner.inc': [
  ('typedef void *(*wgp_add_craft_t)(void *, void *, void *, float, int);',
   'typedef void *(*wgp_add_craft_t)(void *, void *, void *, float, const int *); /* item 93c: YesNoMaybe by reference (MSVC x64, non-trivial copy ctor) */'),
  ('        void *ci=g_wgp_add_craft(p->building,p->craft_base,p->craft_material,0.0f,2);',
   '        int ynm_maybe=2; /* item 93c: YesNoMaybe::MAYBE */\n        void *ci=g_wgp_add_craft(p->building,p->craft_base,p->craft_material,0.0f,&ynm_maybe);'),
 ],
 'stobe_goal_engine.inc': [
  ('typedef void *(*stobe_goal_addcraft_t)(void *, void *, void *, float, int);',
   'typedef void *(*stobe_goal_addcraft_t)(void *, void *, void *, float, const int *); /* item 93c */'),
  ('void *ci=g_goal_addcraft(building,n->recipe1,n->recipe2,0.0f,2);',
   'static const int ynm_maybe=2; void *ci=g_goal_addcraft(building,n->recipe1,n->recipe2,0.0f,&ynm_maybe);'),
 ],
}
for name, reps in edits.items():
    p = root / name
    s = p.read_text(encoding='utf-8', errors='surrogateescape')
    if 'item 93c' in s: sys.exit(name + ': already applied')
    for old, new in reps:
        if s.count(old) != 1: sys.exit(name + ': anchor missing: ' + old[:60])
        s = s.replace(old, new)
    p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)
