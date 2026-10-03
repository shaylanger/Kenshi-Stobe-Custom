#!/usr/bin/env python3
"""Item 93b (STOBE 16 v2, run m16): the work planner's BuildingFunction constants were off: KenshiLib's enum
(Enums.h: BF_ANY 0, BF_MINE 1, ... BF_SHOP 9, BF_CRAFTING 10, ... BF_BATTERY 23, BF_THRONE 24,
BF_SKELETON_BED 25, BF_RAIN_COLLECTOR 26, BF_MINE_NATURAL 27) and the game data ('function' 10 on every
crafting bench) put crafting at 10, natural mines at 27. With 9 the planner treated shop counters as crafting
benches and never saw a real one (WORK_DIAG: only "Shop Counter"). Usage: item93b_bf_enum.py <KenshiFP root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_work_planner.inc'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
for old, new in [('#define WGP_BF_CRAFTING 9\n', '#define WGP_BF_CRAFTING 10 /* item 93b: BF_CRAFTING (9 is BF_SHOP) */\n'),
                 ('#define WGP_BF_MINE_NATURAL 25\n', '#define WGP_BF_MINE_NATURAL 27 /* item 93b: BF_MINE_NATURAL (25 is BF_SKELETON_BED) */\n')]:
    if s.count(old) != 1: sys.exit('anchor missing: ' + old.strip())
    s = s.replace(old, new)
p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)
