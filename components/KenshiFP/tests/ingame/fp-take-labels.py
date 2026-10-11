#!/usr/bin/env python3
"""fp-take-labels.py: label helpers for labelled KenshiFP takes (both rigs; moved from C:\\KenshiTestRuns\\f36 + vidscripts/f26).
  fp-take-labels.py snap <labels.txt> <ts.txt>
      move every waitlab label (listed in <labels.txt>.snap as floor<TAB>pattern<TAB>text) to the HUD switch the take
      sampler saw: midpoint between the last hud_text sample without <pattern> and the first one with it (searching from
      floor-0.6 s). Script-side stamps ran 0.5-1.3 s early/late vs the HUD (T6 take4/take5 label lag).
  fp-take-labels.py filt <labels.txt> <offset s> <filter out> [textfile prefix, default lab]
      ffmpeg drawtext filter chain burning each label (text files <prefix><i>.txt in the cwd, font arialbd.ttf in the cwd).
"""
import sys, re


def snap(O, TS):
    S = [(float(l.split()[0]), l) for l in open(TS) if l[:1].isdigit() and 'hud_text=' in l]
    L = [l.rstrip('\n').split(' ', 1) for l in open(O) if l.strip()]
    for fl in open(O + '.snap'):
        if not fl.strip():
            continue
        floor, pat, txt = fl.rstrip('\n').split('\t')
        floor = float(floor); prev = hit = None
        for t, l in S:
            if t < floor - 0.6:
                continue
            if re.search(pat, l):
                hit = t; break
            prev = t
        if hit is None:
            print('snaplabels: no sample for', txt); continue
        nt = (prev + hit) / 2 if prev is not None else hit - 0.01
        for x in L:
            if x[1] == txt:
                print('snaplabels: %s %s -> %.2f' % (txt, x[0], nt)); x[0] = '%.2f' % nt
    open(O, 'w').write(''.join('%s %s\n' % (a, b) for a, b in L))


def filt(lab, off, outf, pre='lab'):
    rows = [l.split(' ', 1) for l in open(lab).read().strip().split('\n')]
    off = float(off); out = []
    for i in range(len(rows) - 1):
        a = float(rows[i][0]) + off; b = float(rows[i + 1][0]) + off - 0.04
        open('%s%d.txt' % (pre, i), 'w').write(rows[i][1])
        out.append("drawtext=fontfile=arialbd.ttf:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10:"
                   "x=(w-tw)/2:y=40:textfile=%s%d.txt:enable='between(t,%.2f,%.2f)'" % (pre, i, a, b))
    open(outf, 'w').write(',\n'.join(out))


if __name__ == '__main__':
    if len(sys.argv) >= 4 and sys.argv[1] == 'snap':
        snap(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == 'filt':
        filt(*sys.argv[2:6])
    else:
        sys.exit(__doc__)
