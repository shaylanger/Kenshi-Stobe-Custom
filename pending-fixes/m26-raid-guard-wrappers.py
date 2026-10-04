#!/usr/bin/env python3
# m26: Full-Base wrappers use the shared raid guard (stobe-fight-lib.sh raid_guard_start). Run in tests/ingame/stobe.
def patch(p,old,new):
    s=open(p,newline="").read()
    if new in s: print(p,"already"); return
    assert s.count(old)==1,(p,old); open(p,"w",newline="").write(s.replace(old,new)); print(p,"patched")
patch("STOBE-16-bench-shortfall-fullbase.sh",
"""# m23: a Band of Bones raid hit Avarek mid-goal (m22 batch E): knock out raiders near the squad every 30 s while it runs
( while sleep 30; do calm_raiders 1500 >/dev/null 2>&1; done ) & CALM=$!
trap 'kill $CALM 2>/dev/null; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
""",
"""# m23: a Band of Bones raid hit Avarek mid-goal (m22 batch E); m26: Kral's Chosen still reached Beaks with the 30-s
# sweep (m22 J): the shared raid guard sweeps every 10 s (filtered `chars`, 6-game-hour KOs) for the whole row
raid_guard_start
trap 'raid_guard_stop; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
""")
patch("STOBE-A8-bread-chain-fullbase.sh",
"""( while sleep 15; do calm_raiders 1500 >/dev/null 2>&1; done ) & CALM=$!
trap 'kill $CALM 2>/dev/null; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
""",
"""# m26: Band of Bones still KO'd Beaks at 50x (m22 J, 16 s after the guard): the shared raid guard sweeps every 10 s
# (filtered `chars`, 6-game-hour KOs) for the whole row; the A8 loop tolerates raid events (RAID_CALM=1, see there)
raid_guard_start
trap 'raid_guard_stop; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
""")
patch("fullbase-guard.sh","calm_raiders 400\n","calm_raiders 1500  # m26: 400 m missed the raid that hit Beaks 16 s later (m22 J A8)\n")
