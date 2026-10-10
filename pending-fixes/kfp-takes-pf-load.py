#!/usr/bin/env python3
"""kfp-takes-pf-load.py <tree root> <script.sh>...: FP take scripts load the studio fixture by default (Speed plan 6):
the fixed 'A load kah-fpxbow + wait-world loop' becomes pf_load (take-preflight.sh: kah-fpstudio where installed, else
kah-fpxbow; PF_SAVE=<save> forces one). Asserts its anchors; idempotent."""
import io, sys
root = sys.argv[1].rstrip('/') + '/components/KenshiFP/tests/ingame/'
OLD = ('A load kah-fpxbow | cut -c1-80; sleep 8\n'
       'for i in $(seq 1 60); do sleep 3; A wait-world | grep -qE "phase=world|ready" && break; done\n')
NEW = 'pf_load   # studio fixture kah-fpstudio where installed, else kah-fpxbow (take-preflight.sh; PF_SAVE=<save> forces one)\n'
for f in sys.argv[2:]:
    p = root + f
    s = io.open(p, newline='').read()
    if NEW in s:
        print(f, 'already'); continue
    assert s.count(OLD) == 1, f + ': anchor not found once'
    assert s.index('take-preflight.sh"') < s.index(OLD) if 'take-preflight.sh"' in s else s.index('take-preflight.sh\n') < s.index(OLD) if 'take-preflight.sh\n' in s else True
    io.open(p, 'w', newline='').write(s.replace(OLD, NEW, 1))
    print(f, 'patched')
