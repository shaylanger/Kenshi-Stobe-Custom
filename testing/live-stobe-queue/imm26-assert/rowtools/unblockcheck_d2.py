#!/usr/bin/env python3
"""unblockcheck_d2.py <ROW> <evidence-dir>   03-b verdict for the d2 recipe (imm26-sfD2). Wraps unblockcheck_d.py (all its checks and thresholds unchanged) and adds two
SETUP-FAIL causes in front: hearsay_missing.txt (the lane copy lacks stobeKnowledgeHearsayFor: deploy hint) and b.txt == none (no awake non-slave digit-serial NPC near Shay)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import unblockcheck_d as d  # noqa: E402

rc, V = d.rc, d.V


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) != '03-b':
        print('usage: unblockcheck_d2.py <ROW> <evidence-dir>   rows: 03-b', file=sys.stderr)
        return 2
    ev = argv[2]
    miss = d.line(ev, 'hearsay_missing.txt')
    if miss:
        v = V(argv[1])
        v.setup_fail(miss + ' (needs: deploy, no game action was taken)')
        return v.emit(ev)
    if d.line(ev, 'b.txt') == 'none':
        v = V(argv[1])
        v.setup_fail('no candidate B: no awake, non-slave, digit-serial NPC other than Shay/Malzin/Cind within the chars radius (chars.txt, b_candidates.txt); '
                     'needs: recipe, --b "<Full Name>" (a named NPC from `stobe-auto where`) or move Shay next to townsfolk')
        return v.emit(ev)
    return d.main(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
