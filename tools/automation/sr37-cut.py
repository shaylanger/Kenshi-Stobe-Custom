#!/usr/bin/env python3
"""sr37-cut.py (WSL python3): Shay's SR37 review video from fp-weapon-sweep.sh takes, one command.
  python3 sr37-cut.py <out.mp4> <take dir>[=<caption>] [<take dir>[=<caption>] ...] [--zoom 0|25] [--no-still]
Per take (review/INDEX.txt labels, frame-stamp exact): ready stance 1.5 s, the FIRST swing at full speed, the same swing
at 1/2 speed (SR37: exactly 1 swing per stroke type, full + 1/2, nothing more), block guard (--no-still drops ready +
block). Captions burned in (weapon/caption, part, speed). h264_nvenc (libx264 fallback, /etc/kah-no-gpu), 1280x720.
Prints one line: SR37CUT <out> len=<s> parts=<n>.
"""
import os, re, subprocess, sys, tempfile

LBL = re.compile(r'^\s*([\d.]+)\s+(.*)$')
FONT = next((f for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
             if os.path.exists(f)), None)


def enc():
    if not os.path.exists('/etc/kah-no-gpu'):
        r = subprocess.run(['ffmpeg', '-hide_banner', '-encoders'], capture_output=True, text=True)
        if 'h264_nvenc' in r.stdout:
            return ['-c:v', 'h264_nvenc', '-preset', 'p5', '-cq', '21', '-b:v', '0']
    return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20']


def labels(take):
    out = []
    for ln in open(os.path.join(take, 'review', 'INDEX.txt'), encoding='utf-8', errors='replace'):
        m = LBL.match(ln)
        if m and 'label: ' in m.group(2):
            for part in m.group(2).split(' | '):
                if part.startswith('label: '):
                    out.append((float(m.group(1)), part[7:].strip()))
    return out


def segments(take, zoom, still):
    L = labels(take); zs = 'Zoom %s:' % zoom
    i0 = next(i for i, (t, s) in enumerate(L) if s.startswith(zs))
    L = L[i0:]
    nxt = lambda i: L[i + 1][0] if i + 1 < len(L) else L[i][0] + 2.0
    seg = []
    if still:
        seg.append((L[0][0], min(L[0][0] + 1.5, nxt(0)), 1.0, 'ready stance'))
    i = next(i for i, (t, s) in enumerate(L) if 'free swing 1' in s)
    a, b = L[i][0] - 0.3, min(nxt(i), L[i][0] + 2.6)
    seg += [(a, b, 1.0, 'swing (full speed)'), (a, b, 2.0, 'same swing (1/2 speed)')]
    if still:
        j = next((j for j, (t, s) in enumerate(L) if s.startswith('RMB held')), None)
        if j is not None:
            seg.append((L[j][0], min(nxt(j) + 0.3, L[j][0] + 2.0), 1.0, 'block guard (RMB)'))
    return seg


def esc(s):
    return s.replace('\\', '\\\\').replace(':', '\\:').replace("'", "’").replace('%', '\\%')


def main():
    a = sys.argv[1:]; zoom, still = '0', True
    if '--zoom' in a:
        k = a.index('--zoom'); zoom = a[k + 1]; del a[k:k + 2]
    if '--no-still' in a:
        a.remove('--no-still'); still = False
    out, takes = a[0], a[1:]
    E = enc(); tmp = tempfile.mkdtemp(prefix='sr37-'); parts = []
    for tk in takes:
        tk, cap = (tk.split('=', 1) + [None])[:2]
        cap = cap or os.path.basename(tk.rstrip('/')).split('-', 1)[-1].replace('_', ' ')
        vid = os.path.join(tk, 'take.mp4')
        for (s, e, slow, what) in segments(tk, zoom, still):
            p = os.path.join(tmp, '%03d.mp4' % len(parts))
            txt = esc('%s - zoom %s - %s' % (cap, zoom, what))
            vf = 'setpts=%.1f*PTS,scale=1280:720,fps=30' % slow
            if FONT:
                vf += ",drawtext=fontfile=%s:text='%s':x=20:y=20:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8" % (FONT, txt)
            cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '%.3f' % max(s, 0), '-t', '%.3f' % (e - s), '-i', vid,
                   '-an', '-vf', vf] + E + ['-pix_fmt', 'yuv420p', p]
            r = subprocess.run(cmd)
            if r.returncode and E[1] == 'h264_nvenc':
                E = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20']
                subprocess.run(cmd[:cmd.index('-c:v')] + E + ['-pix_fmt', 'yuv420p', p], check=True)
            parts.append(p)
    lst = os.path.join(tmp, 'list.txt')
    open(lst, 'w').write(''.join("file '%s'\n" % p for p in parts))
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', out], check=True)
    ln = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', out], capture_output=True, text=True).stdout.strip()
    print('SR37CUT %s len=%s parts=%d' % (out, ln, len(parts)))


if __name__ == '__main__':
    main()
