#!/usr/bin/env python3
"""kfpreview.py <keyframes tables file> [--stroke N] [-o DIR] [--mp4] [--pool] [--adapter BIN] [--every 2] [--label T]
Seconds-fast preview of a KenshiFP keyframe sword stroke (kf-lab 2026-10-11, keyframe player; WSL python3).

The tables file is the live-tables format the plugin reads (`kf.N...`, `kfh.N...`, `kfmask`; written by kfstroke.py
fit|make or by hand, docs components/KenshiFP/docs/KEYFRAME_FORMAT.md). The replay adapter (kf/build-kf.sh ->
/root/animlab-build/kfpvm_kf) is compiled from the SAME kfp_viewmodel.inc + pending-fixes/kfp-keyframe-stroke.py the
plugin ships, so the lab interpolation (spline hilt/tip, edge slerp, arm IK) is the plugin's code, not a copy.

Steps: replay one sword-pool recording with `--no-rec-sets --set stroke=N --tables F` (labcache result cache; the pick
of the recording with a full stroke-N swing is cached), judge that swing with every lab swing check (path dev/late,
angle SR14 diagonals, end band SR38, span/centre/fast, travel SR39/40, sweep + wind-up exit, SR41 return edge away,
arc edge lead, wrist, blade snap/seen, stroke length, churn, inline, framing) and render a labelled contact strip at
zoom 0 (tip path + outer 10% end band + crosshair drawn on every tile).
  --pool   also every swing of every pool recording (kfcheck.evaluate, the pool take rates; ~10 s) AND the game-take
           judge on corpus E6 game takes (kftake.py via kfcheck: weapon sets kept, fp-e6-strokes.sh lab commands)
  --rec R  replay game take recording R (its weapon/2H condition sets kept, as kftake.py) instead of the sword pool
           (heavy-kf 2026-10-11: heavy 2H / polearm keyframe strokes need the take's weapon class)
  --mp4    a short clip of the swing: once at full speed, once at 1/2 speed (SR37), h264_nvenc (libx264 fallback)
Prints `RESULT KFPREVIEW-s<N>[<label>] PASS|FAIL <failed checks> path=... strip=<png>` (exit 0 PASS, 1 FAIL, 2 error).
Strip: DIR/strip.png (default DIR /mnt/c/KenshiTestRuns/kf-lab/preview/<tables name>)."""
import sys, os, re, json, argparse, time, subprocess, shutil, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
AL = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
sys.path[:0] = [AL, os.path.join(AL, 'visual'), HERE]
import recfmt, metrics as M, labcache

POOL = '/mnt/c/KenshiTestRuns/corpus/pools/sword-swing'
VISUAL = os.path.join(os.path.dirname(HERE), 'visual.json')
WORK = '/root/animlab-work/kfpreview'
ADAPTER = '/root/animlab-build/kfpvm_kf'
REC = None


def pool_recs():
    return [os.path.join(POOL, l.strip()) for l in open(os.path.join(POOL, 'pool-all.list')) if l.strip() and not l.startswith('#')]


def stroke_of(tables):
    m = re.search(r'^\s*kf\.(\d)', open(tables).read(), re.M)
    return int(m.group(1)) if m else None


def ensure_adapter(adapter):
    if os.path.exists(adapter):
        return
    tag = os.path.basename(adapter)[len('kfpvm_kf'):] if os.path.basename(adapter).startswith('kfpvm_kf') else ''
    subprocess.run(['bash', os.path.join(HERE, 'build-kf.sh'), tag], check=True)


def replay(adapter, rec, out, stroke, tables, sets):
    args = ['--no-rec-sets', '--set', 'stroke=%d' % stroke, '--tables', tables]
    for kv in sets:
        args += ['--set', kv]
    rc, so, se = labcache.replay([adapter], rec, out, args)
    if rc or not os.path.exists(out):
        raise SystemExit('adapter %s failed on %s: %s' % (adapter, os.path.basename(rec), (se or so or '')[-400:]))
    return out


def judge(out, stroke):
    """-> (rec, F, P, verdict of the first full stroke-N swing, swing frame idx) or None"""
    M.STROKE_ONLY = stroke
    r = recfmt.parse(out)
    F = r.frames; P = M.frame_metrics(r)
    sw = M.swings(F, P)
    for v in M.swing_verdicts(F, P, (2,), inline=True):
        if v['full'] and v['stroke'] in (None, -1, stroke):
            return r, F, P, v, sw[v['k']]
    return None


def pick_and_judge(adapter, stroke, tables, sets, d):
    os.makedirs(WORK, exist_ok=True)
    if REC:   # --rec: one game take recording with its condition sets kept (weapon wcat/wpom/wtip, 2H class keys; kftake.replay)
        import kftake
        out, _ = kftake.replay(adapter, REC, os.path.join(d, os.path.basename(REC)), stroke, tables, sets)
        j = judge(out, stroke)
        if not j:
            raise SystemExit('%s has no full stroke-%d swing' % (REC, stroke))
        return REC, out, j
    pk = os.path.join(WORK, 'pick-s%d.txt' % stroke)
    recs = pool_recs()
    if os.path.exists(pk):
        first = open(pk).read().strip()
        recs = [x for x in recs if os.path.basename(x) == first] + [x for x in recs if os.path.basename(x) != first]
    for rec in recs:
        out = replay(adapter, rec, os.path.join(d, os.path.basename(rec)), stroke, tables, sets)
        j = judge(out, stroke)
        if j:
            open(pk, 'w').write(os.path.basename(rec))
            return rec, out, j
    raise SystemExit('no pool recording has a full stroke-%d swing' % stroke)


def checks(F, P, v, stroke):
    """-> (ok, [failed names], summary dict, detail lines)"""
    bad, det = [], []
    for k, ok in v['ok'].items():
        if not ok:
            bad.append(k)
    pt = ' '.join(v['ptxt'])
    # the swing's own path line (path_check text of swing k) + its :BAD tokens
    mine = [t for t in v['ptxt'] if t.startswith('swing%d' % v['k'])] or v['ptxt']
    for t in mine:
        for name in re.findall(r'([a-z_]+)=[^,:]*(?:/[^,:]*)?:BAD', t):
            if name not in bad:
                bad.append(name)
    fok, ftxt = M.framed_check(F, P)
    if not fok:
        bad.append('framed')
    wb_ok = v['wb_max'] <= 50.0   # SR10 swing wrist limit (vmcheck wswing)
    if not wb_ok:
        bad.append('wrist')
    num = lambda pat, s: (lambda m: m.group(1) if m else '-')(re.search(pat, s))
    mt = ' '.join(mine)
    summ = dict(ang=num(r'ang=([\d.]+)', mt), trav=num(r'trav=([\d.]+)', mt), edge=num(r'edge=([\d.]+)', mt),
                span=num(r'span=([^,]+)', mt), ctr=num(r'ctr=([\d.]+)', mt), dev=num(r'dev=([\d.]+)', mt),
                sweep=num(r'sweep=([\d.]+)', mt), wb=round(v['wb_max'], 1),
                arc='%d/%d' % (v['arc_good'], v['arc_n']))
    det += ['path ' + t for t in mine] + ['blade ' + ' '.join(v['btxt']), 'stroke ' + ' '.join(v['stxt']),
                                          'churn ' + v['ctxt'], 'inline ' + ' '.join(v.get('itxt', [])), 'framed ' + ' '.join(ftxt)]
    return not bad, bad, summ, det


def tips(F, P, idx):
    out = []
    for i in idx:
        t = M._uproj(P[i]['tip']) if P[i].get('tip') is not None else None
        out.append((i, F[i].get('swu', 0.0), t))
    return out


# ---------------- render ----------------
_RIG = None


def _init(cfg):
    global _RIG
    import render
    _RIG = render.Rig(render.load_cfg(cfg))


def _one(job):
    import render
    f, size, path = job
    img, _, _ = render.render_frame(_RIG, f, size)
    render.save(img, path)
    return path


def render_frames(rec_out, sel, size, d, jobs=8):
    import render
    from multiprocessing import Pool
    Pz = render.load_pose(rec_out)
    sel = [i for i in sel if i < len(Pz)]
    js = [(Pz[i], size, os.path.join(d, 'r%05d.png' % i)) for i in sel]
    with Pool(min(jobs, max(1, len(js))), initializer=_init, initargs=(VISUAL,)) as pool:
        pool.map(_one, js)
    return {i: os.path.join(d, 'r%05d.png' % i) for i in sel}, Pz


def draw_overlay(im, path_px, cur, scale, label, hi=False):
    from PIL import ImageDraw
    g = ImageDraw.Draw(im)
    W, H = im.size
    bw, bh = 0.10 * W, 0.10 * H   # SR38 outer 10% band
    g.rectangle([bw, bh, W - bw, H - bh], outline=(70, 70, 120))
    g.line([W / 2 - 6, H / 2, W / 2 + 6, H / 2], fill=(200, 200, 200)); g.line([W / 2, H / 2 - 6, W / 2, H / 2 + 6], fill=(200, 200, 200))
    pts = [(p[0] * scale, p[1] * scale) for p in path_px if p]
    if len(pts) > 1:
        g.line(pts, fill=(240, 200, 40), width=1)
    if cur:
        x, y = cur[0] * scale, cur[1] * scale
        g.ellipse([x - 4, y - 4, x + 4, y + 4], outline=(255, 60, 60), width=2)
    g.rectangle([0, 0, W, 14], fill=(0, 0, 0))
    g.text((3, 1), label, fill=(255, 255, 0) if hi else (255, 255, 255))


def make_strip(frames, T, F, idx, out_png, cols, title):
    from PIL import Image, ImageDraw
    tiles = []
    path_px = [t for _, _, t in T]
    tipat = {i: t for i, _, t in T}
    i0, i1 = idx[0], idx[-1]
    for i in sorted(frames):
        im = Image.open(frames[i]).convert('RGB')
        scale = im.size[0] / M.W_PX
        u = F[i].get('swu', 0.0) if i0 <= i <= i1 else None
        st = F[i].get('st') or F[i].get('state') or ''
        lab = 'f%d %s' % (i, ('u=%.2f' % u) if u is not None else ('pre' if i < i0 else 'post'))
        draw_overlay(im, path_px, tipat.get(i), scale, lab, hi=u is not None and 0.28 <= u <= 0.78)
        tiles.append(im)
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * w, rows * h + 34), (20, 20, 20))
    g = ImageDraw.Draw(sheet)
    for k, line in enumerate(title[:2]):
        g.text((4, 2 + 15 * k), line[:cols * w // 6], fill=(255, 255, 255))
    for k, im in enumerate(tiles):
        sheet.paste(im, ((k % cols) * w, 34 + (k // cols) * h))
    sheet.save(out_png)


def make_mp4(frames_full, T, F, idx, Pz, out_mp4, d):
    from PIL import Image
    tipat = {i: t for i, _, t in T}
    path_px = [t for _, _, t in T]
    seq = sorted(frames_full)
    lab_dir = os.path.join(d, 'mp4'); os.makedirs(lab_dir, exist_ok=True)
    for k, i in enumerate(seq):
        im = Image.open(frames_full[i]).convert('RGB')
        u = F[i].get('swu', 0.0) if idx[0] <= i <= idx[-1] else None
        draw_overlay(im, path_px, tipat.get(i), im.size[0] / M.W_PX, 'f%d %s' % (i, 'u=%.2f' % u if u is not None else ''))
        im.save(os.path.join(lab_dir, 'f%05d.png' % k))
    dt = max(1e-3, Pz[seq[-1]]['t'] - Pz[seq[0]]['t'])
    fps = max(1, round((len(seq) - 1) / dt))
    vf = '[0:v]split[a][b];[b]setpts=2*PTS[s];[a][s]concat=n=2:v=1:a=0,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p[o]'
    for enc in ('h264_nvenc', 'libx264'):
        r = subprocess.run(['ffmpeg', '-nostdin', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i', os.path.join(lab_dir, 'f%05d.png'),
                            '-filter_complex', vf, '-map', '[o]', '-c:v', enc, out_mp4], capture_output=True, text=True)
        if r.returncode == 0:
            return enc, fps
    return None, fps


def preview(a):
    """entry used by kfstroke.py preview too (a.stroke a.tables a.o [a.trav a.every a.adapter a.label a.pool a.mp4])"""
    t0 = time.time()
    tables = os.path.abspath(a.tables)
    stroke = a.stroke if a.stroke is not None else stroke_of(tables)
    if stroke is None:
        raise SystemExit('no kf.<stroke> line in %s (use --stroke)' % tables)
    adapter = getattr(a, 'adapter', None) or ADAPTER
    ensure_adapter(adapter)
    od = a.o or os.path.join('/mnt/c/KenshiTestRuns/kf-lab/preview', os.path.splitext(os.path.basename(tables))[0])
    os.makedirs(od, exist_ok=True)
    d = tempfile.mkdtemp(prefix='kfprev-', dir='/tmp')
    try:
        rec, out, (r, F, P, v, idx) = pick_and_judge(adapter, stroke, tables, getattr(a, 'set', []) or [], d)
        ok, bad, summ, det = checks(F, P, v, stroke)
        trav = getattr(a, 'trav', None)
        if trav:
            lo, hi = map(float, trav.split(':')) if isinstance(trav, str) else trav
            tv = float(summ['trav']) if summ['trav'] != '-' else 0.0
            if not lo <= tv <= hi:
                bad.append('trav_range'); ok = False
        t_chk = time.time() - t0
        pool_txt = ''
        if getattr(a, 'pool', False):
            import kfcheck
            pr = kfcheck.evaluate(adapter, stroke, tables, getattr(a, 'set', []) or [], None, 10)
            # kfcheck.evaluate includes the game-take judge (kftake.py, Misses kf-s0b): pool rates AND every take line
            tk = pr.get('take') or {}
            pool_txt = ' pool=%s(%s n=%s kftake=%s)' % ('PASS' if pr['ok'] else 'FAIL', 'score=%.2f' % pr['score'], pr.get('n'),
                                                       '%s,fail=%s/%s,%s' % ('PASS' if tk.get('ok') else 'FAIL', tk.get('fail'), tk.get('n'),
                                                                            tk.get('worst', '').replace(' ', ',')) if tk else 'off')
            for l in tk.get('lines', []):
                if ' FAIL' in l and '(info)' not in l:
                    det.append(l[:260])
            if not pr['ok']:
                bad.append('pool'); ok = False
        # strip: 6 frames of wind-up before the swing, the swing, 6 frames after (every N)
        ev = max(1, getattr(a, 'every', 2) or 2)
        lo_i, hi_i = max(0, idx[0] - 6 * ev), min(len(F) - 2, idx[-1] + 6 * ev)
        sel = list(range(lo_i, hi_i + 1, ev))
        T = tips(F, P, [i for i in range(idx[0], idx[-1] + 1) if 0.0 <= F[i].get('swu', 0.0) <= 1.0])
        fd = os.path.join(d, 'tiles'); os.makedirs(fd, exist_ok=True)
        frames, Pz = render_frames(out, sel, (400, 225), fd)
        label = getattr(a, 'label', '') or ''
        res = 'RESULT KFPREVIEW-s%d%s %s %s ang=%s trav=%s endband=%s span=%s ctr=%s dev=%s sweep=%s wb=%s arc=%s%s' % (
            stroke, label, 'PASS' if ok else 'FAIL', ('failed=' + ','.join(bad)) if bad else 'all-checks-ok',
            summ['ang'], summ['trav'], summ['edge'], summ['span'], summ['ctr'], summ['dev'], summ['sweep'], summ['wb'], summ['arc'], pool_txt)
        png = os.path.join(od, 'strip.png')
        make_strip(frames, T, F, idx, png, 8, [res.replace('RESULT ', ''), '%s | rec %s | %s' % (os.path.basename(tables), os.path.basename(rec), time.strftime('%H:%M'))])
        mp4 = ''
        if getattr(a, 'mp4', False):
            fd2 = os.path.join(d, 'full'); os.makedirs(fd2, exist_ok=True)
            full, Pz = render_frames(out, list(range(lo_i, hi_i + 1)), (800, 450), fd2)
            enc, fps = make_mp4(full, T, F, idx, Pz, os.path.join(od, 'clip.mp4'), d)
            mp4 = ' mp4=%s(%s,%dfps,full+half)' % (os.path.join(od, 'clip.mp4'), enc, fps) if enc else ' mp4=FAILED'
        with open(os.path.join(od, 'checks.txt'), 'w') as fh:
            fh.write(res + '\n' + '\n'.join(det) + '\n')
        shutil.copy(out, os.path.join(od, 'replay.rec.txt'))
        print('kfpreview: rec %s swing frames %d-%d, checks %.1f s, total %.1f s' % (os.path.basename(rec), idx[0], idx[-1], t_chk, time.time() - t0))
        print('%s strip=%s%s' % (res, png, mp4))
        return 0 if ok else 1
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('tables')
    ap.add_argument('--stroke', type=int)
    ap.add_argument('-o')
    ap.add_argument('--set', action='append', default=[])
    ap.add_argument('--adapter', default=ADAPTER)
    ap.add_argument('--every', type=int, default=2)
    ap.add_argument('--trav')
    ap.add_argument('--label', default='')
    ap.add_argument('--pool', action='store_true')
    ap.add_argument('--mp4', action='store_true')
    ap.add_argument('--rec', help='replay this game take recording (condition sets kept: weapon, 2H class) instead of a sword-pool rec')
    a = ap.parse_args()
    global REC
    REC = os.path.abspath(a.rec) if a.rec else None
    try:
        return preview(a)
    except SystemExit as e:
        if isinstance(e.code, str):
            print('RESULT KFPREVIEW FAIL error: %s' % e.code)
            return 2
        raise


if __name__ == '__main__':
    sys.exit(main())
