#!/usr/bin/env python3
"""review-pack.py (WSL python3): turn a take video into a ready-to-review pack (Shay 2026-10-10: the coordinator's
frame-by-frame review was the slowest manual step; every video now arrives with its sheets and lab results).

  python3 review-pack.py <video.mp4> <out-dir> [--ts ts.txt] [--labels labels.txt] [--lab file ...]
                         [--offset S] [--fps-switch 8] [--pre 0.5] [--post 1.0]

Makes, in <out-dir>:
  whole-NN.jpg    1 fps over the whole length, 4x4 tiles (480x270 each), every tile stamped with its video time
  sw-NN-<t>.jpg   one sheet per state switch: --fps-switch fps from t-pre to t+post, stamped, titled before -> after
  INDEX.txt       video length, switch list (time, what changed, sheet), label list, lab RESULT/FAIL lines, sheet list
Switches = changes of ui_state / hud_text / loaded / fp_ui_state on the `fp ...` lines of ts.txt, plus every label
time (labels.txt `t text`); switches closer than 0.4 s are merged. --offset is added to ts/label times (video time =
ts time + offset) when the recording started later than the sampler.
The review stays complete (whole length at 1 fps + dense frames at every switch); it just starts with no rendering pass.
"""
import argparse, os, re, shutil, subprocess, sys

FFMPEG = '/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe'
FFPROBE = FFMPEG.replace('ffmpeg.exe', 'ffprobe.exe')
KEYS = ('ui_state', 'hud_text', 'loaded', 'fp_ui_state')


def win(p):
    p = os.path.abspath(p)
    m = re.match(r'^/mnt/([a-z])/(.*)$', p)
    return f'{m.group(1).upper()}:/{m.group(2)}' if m else p


def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'ffmpeg failed: {r.stderr.strip()[-400:]}')
    return r.stdout


def duration(video):
    out = run([FFPROBE, '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', win(video)])
    return float(out.strip())


def switches(ts, labels, off):
    ev = []
    if ts and os.path.exists(ts):
        prev = None
        for line in open(ts, errors='replace'):
            m = re.match(r'^\s*([\d.]+)\s+fp\s+(.*)$', line)
            if not m:
                continue
            kv = dict(re.findall(r'(\w+)=(\S+)', m.group(2)))
            cur = {k: kv.get(k) for k in KEYS if k in kv}
            if prev is not None and cur != prev:
                diff = ', '.join(f'{k} {prev.get(k)}->{cur.get(k)}' for k in KEYS if prev.get(k) != cur.get(k))
                ev.append((float(m.group(1)) + off, diff))
            prev = cur
    if labels and os.path.exists(labels):
        for line in open(labels, errors='replace'):
            m = re.match(r'^\s*([\d.]+)\s+(.*\S)', line)
            if m:
                ev.append((float(m.group(1)) + off, 'label: ' + m.group(2)))
    ev.sort()
    merged = []
    for t, what in ev:
        if merged and t - merged[-1][0] < 0.4:
            merged[-1] = (merged[-1][0], merged[-1][1] + ' | ' + what)
        else:
            merged.append((t, what))
    return merged


def esc(s):
    return s.replace('\\', '').replace(':', '\\:').replace("'", '').replace('%', '\\%').replace(',', '\\,')[:150]


def sheet(video, out, start, length, fps, cols, rows, title):
    stamp = "drawtext=fontfile=f.ttf:fontsize=22:fontcolor=yellow:box=1:boxcolor=black@0.6:x=6:y=6:text='%{pts\\:hms}'"
    vf = (f"setpts=PTS+{start:.3f}/TB,fps={fps},scale=480:270:flags=lanczos,{stamp},"
          f"tile={cols}x{rows}:padding=4:color=black,pad=iw:ih+40:0:40:black,"
          f"drawtext=fontfile=f.ttf:fontsize=24:fontcolor=white:x=8:y=8:text='{esc(title)}'")
    run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-ss', f'{start:.3f}', '-t', f'{length:.3f}',
         '-i', win(video), '-vf', vf, '-frames:v', '1', '-q:v', '3', os.path.basename(out)])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('video'); ap.add_argument('out')
    ap.add_argument('--ts'); ap.add_argument('--labels'); ap.add_argument('--lab', nargs='*', default=[])
    ap.add_argument('--offset', type=float, default=0.0); ap.add_argument('--fps-switch', type=float, default=8.0)
    ap.add_argument('--pre', type=float, default=0.5); ap.add_argument('--post', type=float, default=1.0)
    a = ap.parse_args()
    video = os.path.abspath(a.video)
    a.ts = a.ts and os.path.abspath(a.ts); a.labels = a.labels and os.path.abspath(a.labels)
    a.lab = [os.path.abspath(f) for f in a.lab]; a.out = os.path.abspath(a.out)
    os.makedirs(a.out, exist_ok=True)
    os.chdir(a.out)
    for f in os.listdir('.'):
        if re.match(r'^(whole|sw)-.*\.jpg$', f):
            os.remove(f)
    if not os.path.exists('f.ttf'):
        shutil.copy('/mnt/c/Windows/Fonts/arialbd.ttf', 'f.ttf')
    dur = duration(video)
    idx = [f'video {video}  length {dur:.1f} s', '']
    sheets = []
    n = 0
    for s in range(0, int(dur) + 1, 16):           # 16 frames (4x4) at 1 fps per sheet
        n += 1
        name = f'whole-{n:02d}.jpg'
        sheet(video, name, float(s), min(16.0, dur - s), 1, 4, 4, f'1 fps  {s}-{min(s + 16, dur):.0f} s  {os.path.basename(video)}')
        sheets.append(name)
    sw = switches(a.ts, a.labels, a.offset)
    idx.append(f'switches ({len(sw)}; sheets at {a.fps_switch:g} fps from t-{a.pre:g} to t+{a.post:g} s):')
    nframes = int(round((a.pre + a.post) * a.fps_switch))
    cols = 4; rows = max(1, -(-nframes // cols))
    for i, (t, what) in enumerate(sw, 1):
        st = max(0.0, t - a.pre)
        if st >= dur:
            idx.append(f'  {t:7.2f}  {what}  (after the video end, no sheet)'); continue
        name = f'sw-{i:02d}-{t:06.2f}.jpg'
        sheet(video, name, st, min(a.pre + a.post, dur - st), a.fps_switch, cols, rows, f'{t:.2f} s  {what}')
        sheets.append(name)
        idx.append(f'  {t:7.2f}  {what}  -> {name}')
    idx += ['', 'lab / take checks:']
    for f in a.lab:
        if os.path.exists(f):
            for line in open(f, errors='replace'):
                if re.search(r'RESULT|FAIL|BAD|PASS', line):
                    idx.append(f'  {os.path.basename(f)}: {line.rstrip()[:220]}')
        else:
            idx.append(f'  {f}: MISSING')
    if not a.lab:
        idx.append('  none given (a pack without lab results is not ready for review)')
    idx += ['', 'sheets: ' + ' '.join(sheets)]
    open('INDEX.txt', 'w').write('\n'.join(idx) + '\n')
    print(f'RESULT REVIEWPACK PASS sheets={len(sheets)} switches={len(sw)} out={a.out}/INDEX.txt')


if __name__ == '__main__':
    main()
