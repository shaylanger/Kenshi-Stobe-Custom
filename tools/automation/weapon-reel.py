#!/usr/bin/env python3
"""weapon-reel.py (WSL python3): cut the zoom-0 part of fp-weapon-sweep.sh takes into ONE captioned review reel
(weapon-reel 2026-10-11: Shay's first look at the FP animations with every weapon class).

  python3 weapon-reel.py <out.mp4> <take dir> [<take dir> ...] [--size 1280x720] [--tail 0.4] [--end-label "R: sheathe"]

<take dir> = a sweep weapon dir (<k>-<slug>/ with take.mp4 + review/INDEX.txt, whose label lines carry VIDEO times from
the frame stamp). Per take: from its "Zoom 0:" label (-0.3 s) to the first --end-label after it (+--tail), real speed,
scaled to --size, captioned top-centre "<i>/<n>  <weapon> (<anim class>)" and below it the current label (state).
Encodes each segment with h264_nvenc (libx264 fallback when NVENC is missing or /etc/kah-no-gpu exists), joins them with
the concat demuxer (stream copy). Also writes <out>.lab (`t text` at reel time, last `end`) for review-pack.py --labels
and <out>.segments.tsv (i, weapon, class, take dir, take start, take end, reel start, reel end).
"""
import argparse, os, re, shutil, subprocess, sys, tempfile

LBL = re.compile(r'^\s+([\d.]+)\s+(.*)$')


def labels(idx):
    out = []
    for ln in open(idx, encoding='utf-8', errors='replace'):
        m = LBL.match(ln)
        if not m or 'label: ' not in m.group(2):
            continue
        t = float(m.group(1))
        for part in m.group(2).split(' | '):
            if part.startswith('label: '):
                out.append((t, part[7:].strip()))
    return out


def font():
    for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        if os.path.exists(f):
            return f
    return None


def enc_args():
    if not os.path.exists('/etc/kah-no-gpu'):
        r = subprocess.run(['ffmpeg', '-hide_banner', '-encoders'], capture_output=True, text=True)
        if 'h264_nvenc' in r.stdout:
            return ['-c:v', 'h264_nvenc', '-preset', 'p5', '-cq', '21', '-b:v', '0']
    return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('takes', nargs='+')
    ap.add_argument('--size', default='1280x720'); ap.add_argument('--tail', type=float, default=0.4)
    ap.add_argument('--end-label', default='R: sheathe')
    a = ap.parse_args()
    W, H = (int(x) for x in a.size.split('x'))
    fnt = font(); enc = enc_args()
    tmp = tempfile.mkdtemp(prefix='weapon-reel-')
    segs, lab, rows, t_reel = [], [], [], 0.0
    n = len(a.takes)
    for i, d in enumerate(a.takes, 1):
        idx, vid = os.path.join(d, 'review', 'INDEX.txt'), os.path.join(d, 'take.mp4')
        if not (os.path.exists(idx) and os.path.exists(vid)):
            print(f'SKIP {d}: no take.mp4 / review/INDEX.txt'); continue
        L = labels(idx)
        k0 = next((k for k, (_, s) in enumerate(L) if s.startswith('Zoom 0:')), None)
        if k0 is None:
            print(f'SKIP {d}: no "Zoom 0:" label'); continue
        m = re.match(r'Zoom 0: (.*) ready stance \((.*)\)', L[k0][1])
        name, cls = (m.group(1), m.group(2)) if m else (os.path.basename(d), '?')
        k1 = next((k for k in range(k0 + 1, len(L)) if L[k][1].startswith(a.end_label) or L[k][1].startswith('Zoom 25')), None)
        t0 = max(0.0, L[k0][0] - 0.3); t1 = (L[k1][0] + a.tail) if k1 is not None else L[k0][0] + 14.0
        dur = t1 - t0
        kend = k1 if k1 is not None else k0 + 1
        cap = [(0.0 if k == k0 else L[k][0] - t0, (L[k + 1][0] - t0) if k + 1 < kend else dur,
                L[k][1].replace(f'Zoom 0: {name} ', '').replace(f' ({cls})', '')) for k in range(k0, kend)]
        vf = [f'scale={W}:{H}:flags=bicubic', 'setsar=1', 'fps=30']
        if fnt:
            hf = os.path.join(tmp, f'h{i}.txt'); open(hf, 'w').write(f'{i}/{n}  {name}  ({cls})')
            vf.append(f"drawtext=fontfile={fnt}:textfile={hf}:fontsize=34:fontcolor=white:borderw=3:bordercolor=black:x=(w-tw)/2:y=14")
            for j, (ca, cb, txt) in enumerate(cap):
                cf = os.path.join(tmp, f'c{i}_{j}.txt'); open(cf, 'w').write(txt)
                vf.append(f"drawtext=fontfile={fnt}:textfile={cf}:fontsize=30:fontcolor=yellow:borderw=3:bordercolor=black:"
                          f"x=(w-tw)/2:y=60:enable='between(t,{ca:.2f},{cb:.2f})'")
        seg = os.path.join(tmp, f's{i:02d}.mp4')
        cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', f'{t0:.2f}', '-i', vid, '-t', f'{dur:.2f}', '-an',
               '-vf', ','.join(vf)] + enc + ['-pix_fmt', 'yuv420p', seg]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode and enc[1] == 'h264_nvenc':
            enc = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20']
            r = subprocess.run(cmd[:cmd.index('-c:v')] + enc + ['-pix_fmt', 'yuv420p', seg], capture_output=True, text=True)
        if r.returncode:
            print(f'FAIL {d}: ffmpeg {r.stderr.strip()[-300:]}'); sys.exit(1)
        segs.append(seg)
        for ca, _, txt in cap:
            lab.append((t_reel + ca, f'{name}: {txt}'))
        rows.append(f'{i}\t{name}\t{cls}\t{d}\t{t0:.2f}\t{t1:.2f}\t{t_reel:.2f}\t{t_reel + dur:.2f}')
        t_reel += dur
    if not segs:
        print('RESULT WEAPONREEL FAIL no usable take'); sys.exit(1)
    lst = os.path.join(tmp, 'list.txt')
    open(lst, 'w').write(''.join(f"file '{s}'\n" for s in segs))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    r = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst,
                        '-c', 'copy', '-movflags', '+faststart', a.out], capture_output=True, text=True)
    if r.returncode:
        print(f'RESULT WEAPONREEL FAIL concat: {r.stderr.strip()[-300:]}'); sys.exit(1)
    base = os.path.splitext(a.out)[0]
    with open(base + '.lab', 'w') as f:
        f.write(''.join(f'{t:.2f} {s}\n' for t, s in lab) + f'{t_reel:.2f} end\n')
    with open(base + '.segments.tsv', 'w') as f:
        f.write('i\tweapon\tclass\ttake\ttake_t0\ttake_t1\treel_t0\treel_t1\n' + '\n'.join(rows) + '\n')
    shutil.rmtree(tmp, ignore_errors=True)
    print(f'RESULT WEAPONREEL PASS segments={len(segs)}/{n} length={t_reel:.1f}s enc={enc[1]} out={a.out}')


if __name__ == '__main__':
    main()
