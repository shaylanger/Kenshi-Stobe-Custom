#!/usr/bin/env python3
"""unblockcheck_e_v2.py <ROW> <evidence-dir>   (imm26-sfY) = unblockcheck_e.py with ONE fix: the end affinity is read from aff_end.txt OR haff-aff_end.txt.
rl_aff (hxdefs rl_aff -> hxd_haff) writes `haff-<tag>.txt`, so the v1 reader (aff_end.txt) always saw None and failed row 10-b with affinity_still_negative (aff=None)
although the evidence held aff=-47.  Nothing else changes (same thresholds/outputs); unblockcheck_e.py / unblockcheck_c.py are NOT edited.  `--has <ROW>` as v1."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import unblockcheck_e as e  # noqa: E402

_rd = e.rd
ALIASES = {'aff_end.txt': ('aff_end.txt', 'haff-aff_end.txt')}


def rd_v2(*parts):
    names = ALIASES.get(parts[-1], (parts[-1],))
    for n in names:
        t = _rd(*parts[:-1], n)
        if t:
            return t
    return ''


e.rd = rd_v2   # check_10b resolves rd from the module globals at call time

if __name__ == '__main__':
    sys.exit(e.main(['unblockcheck_e_v2.py'] + sys.argv[1:]))
