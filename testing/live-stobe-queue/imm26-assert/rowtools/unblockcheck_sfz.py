#!/usr/bin/env python3
"""unblockcheck_sfz.py <ROW> <evidence-dir>   03-b verdict for the sfz recipe (imm26-sfZ). Wraps unblockcheck_d2.py (all its checks and thresholds unchanged); the only difference is the
SETUP-FAIL text when the bounded retry loop ended without a heard_from row: it names the counts (tries / chance-gated / spoken), and flags a chance gate that still rolled < 100
(= the per-NPC seam did not apply on that lane)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import unblockcheck_d2 as d2  # noqa: E402

d = d2.d
V = d2.V


def main(argv):
    if len(argv) >= 3 and d.rc.norm(argv[1]) == '03-b':
        ev = argv[2]
        ok = d.line(ev, 'gossip_ok.txt')
        b = d.line(ev, 'b.txt')
        miss = d.line(ev, 'hearsay_missing.txt')
        tags = [d.line(ev, f) for f in sorted(os.listdir(ev)) if re.fullmatch(r'gossip_g\d+\.res', f)]
        if ok.startswith('none') and not miss and b and b != 'none' and d.line(ev, 'cind_row.txt') and tags and not all(t == 'http_err' for t in tags):
            m = re.search(r'tries=(\d+) gated=(\d+) spoken=(\d+)', ok)
            tr, ga, sp = m.groups() if m else ('?', '?', '?')
            low = sorted(set(re.findall(r'chance=(\d+)', d.rd(ev, 'gossip_tries.txt') or '')) - {'100'})
            seam = ' CHANCE SEAM NOT APPLIED (gate rolled chance=%s, expected 100: check npc_chance.txt, the lane DB layer)' % ','.join(low) if low else ''
            v = V(argv[1])
            v.setup_fail('the pair Cind -> %s never produced a heard_from row: %s tries, %s chance-gated (free), %s reached the speech (the line must name Shay; the LLM is the lottery);%s '
                         'needs: recipe, rerun with --tries 48 --max-spoken 24 or a different B (--b), gossip_all.txt + gossip_tries.txt show every try' % (b, tr, ga, sp, seam))
            return v.emit(ev)
    return d2.main(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
