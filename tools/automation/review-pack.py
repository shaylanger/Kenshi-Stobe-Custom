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
Frame stamp (harness `stamp on`; --stamp auto|off, default auto): when the video carries the stamp, the switches come
from it instead (harness tools/animlab/stamp.py): every ui_state / stroke / view / weapon class / loaded change at its
exact video frame (with the game frame), every label at the frame its mark first shows; --ts/--offset are not needed.
Auto-review (harness tools/animlab/autoreview.py; --autoreview auto|off, default auto; Shay 2026-10-10: judge only the
frames the checks flag): image checks on EVERY frame (oneview at switches, fragments in the zoom fade band, occluder =
arm/body across the lens, weapon complete vs references, overlay/cursor/openground) run first at nice 15 into
<out-dir>/autoreview/ (flags.tsv + crops/ prev|FLAG|next at full resolution). When it ran, the pack holds only the flagged
frames: one flag-NN-<t>-<check>.jpg sheet per flag (8 fps from t-0.25 to t+0.5) next to its crop, the switch list stays in
INDEX.txt as text; no 1 fps / switch sheets. --full (or autoreview unavailable, e.g. the 4080's Windows python) = the
complete pack as before (whole length at 1 fps + dense frames at every switch), plus the flags when there are any.
"""
import argparse, os, re, shutil, subprocess, sys

FFMPEG = '/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe'
if not os.path.exists(FFMPEG) and shutil.which('ffmpeg'):   # 4080 rig (Windows python, ffmpeg on PATH; fist4080f had no pack)
    FFMPEG = shutil.which('ffmpeg')
FFPROBE = FFMPEG.replace('ffmpeg.exe', 'ffprobe.exe') if FFMPEG.endswith('ffmpeg.exe') else (shutil.which('ffprobe') or 'ffprobe')
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


def autoreview(video, a):
    """run autoreview.py (nice 15) into <out>/autoreview; (RESULT line, [(t, check, what, crop)]) or None if it can't run."""
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Kenshi-Automation-Harness', 'tools', 'animlab',
                        'autoreview.py')
    if not os.path.exists(tool):
        return None
    out = os.path.join(a.out, 'autoreview')
    shutil.rmtree(out, ignore_errors=True)
    cmd = ([] if os.name == 'nt' else ['nice', '-n', '15']) + [sys.executable, tool, 'run', video, out, '--weapon', a.weapon]
    r = subprocess.run(cmd, capture_output=True, text=True)
    open('autoreview.log', 'w').write(r.stdout + r.stderr)
    res = [l for l in r.stdout.splitlines() if l.startswith('RESULT ')]
    if r.returncode or not res or not os.path.exists(os.path.join(out, 'flags.tsv')):
        return None
    flags = []
    for line in open(os.path.join(out, 'flags.tsv')).read().splitlines()[1:]:
        p = line.split('	')
        if len(p) >= 4:
            flags.append((float(p[1]), p[2], p[3], p[4] if len(p) > 4 else ''))
    return res[-1], flags


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('video'); ap.add_argument('out')
    ap.add_argument('--ts'); ap.add_argument('--labels'); ap.add_argument('--lab', nargs='*', default=[])
    ap.add_argument('--offset', type=float, default=0.0); ap.add_argument('--fps-switch', type=float, default=8.0)
    ap.add_argument('--pre', type=float, default=0.5); ap.add_argument('--post', type=float, default=1.0)
    ap.add_argument('--stamp', choices=('auto', 'off'), default='auto', help='switches + labels from the frame stamp')
    ap.add_argument('--autoreview', choices=('auto', 'off'), default='auto', help='per-frame image checks, sheets of flags only')
    ap.add_argument('--weapon', default='auto', help='autoreview weapon class (fists|sword|crossbow|auto from the name)')
    ap.add_argument('--full', action='store_true', help='complete pack (1 fps + switch sheets) even when autoreview ran')
    a = ap.parse_args()
    video = os.path.abspath(a.video)
    a.ts = a.ts and os.path.abspath(a.ts); a.labels = a.labels and os.path.abspath(a.labels)
    a.lab = [os.path.abspath(f) for f in a.lab]; a.out = os.path.abspath(a.out)
    os.makedirs(a.out, exist_ok=True)
    os.chdir(a.out)
    for f in os.listdir('.'):
        if re.match(r'^(whole|sw|flag)-.*\.jpg$', f):
            os.remove(f)
    if not os.path.exists('f.ttf'):
        shutil.copy('/mnt/c/Windows/Fonts/arialbd.ttf' if os.path.exists('/mnt/c/Windows') else r'C:\Windows\Fonts\arialbd.ttf', 'f.ttf')
    dur = duration(video)
    idx = [f'video {video}  length {dur:.1f} s', '']
    sheets = []
    ar = autoreview(video, a) if a.autoreview == 'auto' else None
    full = a.full or ar is None
    if ar is not None:
        res, flags = ar
        idx.append(f'autoreview: {res}')
        if not full:
            idx.append('pack = flagged frames only (judge these; --full for the 1 fps + switch sheets)')
        for k, (t, check, what, crop) in enumerate(flags, 1):
            name = f'flag-{k:02d}-{t:06.2f}-{check}.jpg'
            st = max(0.0, t - 0.25)
            if st < dur:
                sheet(video, name, st, min(0.75, dur - st), 8, 3, 2, f'FLAG {t:.2f} s {check}: {what[:90]}')
                sheets.append(name)
            idx.append(f'  {t:7.2f}  {check:10s} {what[:160]}  -> {name}  crop {os.path.relpath(crop) if crop and os.path.exists(crop) else "-"}')
        idx.append('')
    else:
        idx.append(f'autoreview: {"off" if a.autoreview == "off" else "not run (see autoreview.log)"}: complete pack')
    n = 0
    for s in (range(0, int(dur) + 1, 16) if full else ()):           # 16 frames (4x4) at 1 fps per sheet
        if s and dur - s < 1.0:                     # a tail < 1 s holds no 1 fps frame: ffmpeg writes nothing and fails the pack
            break
        n += 1
        name = f'whole-{n:02d}.jpg'
        sheet(video, name, float(s), min(16.0, dur - s), 1, 4, 4, f'1 fps  {s}-{min(s + 16, dur):.0f} s  {os.path.basename(video)}')
        sheets.append(name)
    st_ev = None
    if a.stamp == 'auto':
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                                            'Kenshi-Automation-Harness', 'tools', 'animlab'))
            import stamp as stampmod
            st_ev = stampmod.pack_events(video, a.labels)
        except Exception as e:   # no numpy/ffmpeg here (4080 Windows python), or no stamp module: old switches
            idx.append(f'stamp: not read ({type(e).__name__}: {e})')
    if st_ev:
        ev, stxt = st_ev
        idx.append(f'{stxt}  (switches + labels from the frame stamp, exact frames)')
        sw = []
        for t, what in ev:
            if sw and t - sw[-1][0] < 0.4:
                sw[-1] = (sw[-1][0], sw[-1][1] + ' | ' + what)
            else:
                sw.append((t, what))
    else:
        sw = switches(a.ts, a.labels, a.offset)
    idx.append(f'switches ({len(sw)}; sheets at {a.fps_switch:g} fps from t-{a.pre:g} to t+{a.post:g} s):')
    nframes = int(round((a.pre + a.post) * a.fps_switch))
    cols = 4; rows = max(1, -(-nframes // cols))
    for i, (t, what) in enumerate(sw, 1):
        if not full:
            idx.append(f'  {t:7.2f}  {what}'); continue
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
    # PASS-REC (takecheck.py): product checks passed, only recording checks failed; the sheets show what was recorded
    rw = sorted({w for l in idx for m in re.finditer(r'rec-warn=(\S+)', l) for w in m.group(1).strip(']').split(',') if w})
    if rw:
        idx += ['', 'recording warnings (PASS-REC: judged on what was recorded; sampler gaps / video length / sync lag): '
                + ','.join(rw)]
    idx += ['', 'sheets: ' + ' '.join(sheets)]
    open('INDEX.txt', 'w').write('\n'.join(idx) + '\n')
    flagn = len(ar[1]) if ar is not None else '-'
    print(f'RESULT REVIEWPACK PASS sheets={len(sheets)} switches={len(sw)} flags={flagn} '
          f'pack={"full" if full else "flagged"} out={a.out}/INDEX.txt')


if __name__ == '__main__':
    main()
