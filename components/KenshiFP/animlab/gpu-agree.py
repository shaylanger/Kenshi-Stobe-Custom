#!/usr/bin/env python3
"""gpu-agree.py -- GPU-vs-CPU agreement + speed report for lab evaluation (gpu-wire 2026-10-11, Shay's order: move lab
evaluation to the GPU and compare GPU vs CPU, speed + CPU offload). WSL python3 (root).

Agreement set (C:\\KenshiTestRuns\\gpu-wire\\agree-set, built once from what the CPU ALREADY evaluated):
  manifest.jsonl  one variant per line: id, group, weapon, tip, rec, adapter (snapshots in bin/ recs/), sets, cpu_line
                  (pasweep judge text without rp= paths), cpu_score / cpu_hard (score.py formula), jobs [{id, label, args,
                  cpu_out (cpu/<job>.txt.gz = the CPU adapter's replay)}]
  jobs.jsonl      every replay as a GPU job {"id","adapter","rec","args","out"} (gpueval.py contract), out -> <outdir>/<id>.txt

  gpu-agree.py build [--n-pa 120]          collect the set (pa-work sweeps 1-7 Naginata stratified by score, plus
                                           Buster Sword/Fragment Axe 2H sets from wc-work and sword stroke sets from
                                           strokefix opt logs: those fills are the only fresh CPU replays)
  gpu-agree.py jobs <outdir> [jobs.jsonl]  (re)write jobs.jsonl with outs under <outdir>
  gpu-agree.py <results.jsonl> [--set D] [--raw-tol 0.02] [--score-tol 0.05] [--rho 0.99] [--bench bench.json]
                                           compare: per job raw replay diff vs the CPU replay (max abs, p99, bad frames,
                                           state mismatches); per variant the judge rerun on the GPU replays vs cpu_line
                                           (every number, every ok/FAIL token), score diff, hard-gate flips; Spearman rank
                                           of scores; one `AGREE PASS|FAIL ...` line (exit 0|1); report -> <results>.agree.txt
  gpu-agree.py bench <label> <results.jsonl> -- <command...>
                                           run the evaluator command and record wall, CPU-s of the command's process tree
                                           (rusage), WSL machine CPU% (/proc/stat), Windows CPU% (typeperf) and GPU util/mem
                                           (nvidia-smi.exe, 0.5 s samples) -> <results>.bench.json; compare prints it
  gpu-agree.py cpu-ref <outdir> [-j N]     CPU baseline in the same protocol: bench 'cpu' of gpueval.py cpu-batch (no cache)
  gpu-agree.py selftest                    fake 'GPU' results: exact copies PASS, noise within tol PASS, a corrupted
                                           replay / flipped state / reordered scores FAIL
"""
import sys, os, json, re, gzip, shutil, subprocess, tempfile, time, random, shlex, threading
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gpueval as G

SET = '/mnt/c/KenshiTestRuns/gpu-wire/agree-set'
PA = '/root/pa-work'
NAG_REC = '/mnt/c/KenshiTestRuns/wc-v1-i2-2/wcv1/003-Naginata/take.vmrec.txt'
WC_RECS = {'Buster Sword': '/mnt/c/KenshiTestRuns/wc-v2/wcv2/001-Buster_Sword/take.vmrec.txt',
           'Fragment Axe': '/mnt/c/KenshiTestRuns/wc-v2/wcv2/002-Fragment_Axe/take.vmrec.txt'}
SWORD_REC = '/mnt/c/KenshiTestRuns/corpus/pools/sword-swing/e6-anim-b2.txt'
RP = re.compile(r' \| rp=\S+')


# ---------------------------------------------------------------- score (= /root/pa-work/score.py, polearm-fix)
def score(l):
    g = lambda k, d=0.0: (lambda m: float(m.group(1)) if m else d)(re.search(k + r'=([\d.]+)', l))
    fr, fb = g('framed_ready'), g('framed_block')
    fs = g('framed_swing', None)
    fs = g('framed_swing_cross') if fs is None else fs   # judge since 19:12 (SR17): swing framed at the mid-stroke crossing
    ok = lambda k: (k + '=ok') in l
    wb = g('wb_max', 99)
    trav = [float(x) for x in re.findall(r'trav=([\d.]+)', l)]
    ctr = [float(x) for x in re.findall(r'ctr=([\d.]+)', l)]
    hard = fr >= .8 and fb >= .8 and fs >= .5 and ok('near') and ok('vis')
    s = min(fs, .8) * 3 + min(fr, fb) + (wb <= 50) * 1 + ok('seen') + ok('twosp') + ('path=ok' in l) * 2 \
        + (min(trav or [0]) >= .52) * .5 + (max(ctr or [1]) <= .12) * .5 - 0.2 * max(0, (wb - 50) / 10)
    return bool(hard), round(s, 4)


TOK = re.compile(r'([A-Za-z_][A-Za-z_0-9]*)=(-?[\d.]+|ok|FAIL|BAD|-)')


def tokens(line):
    """ordered (key#n, value) pairs of a judge line; numbers as float, verdict words as str; plus ':BAD' markers."""
    seen, out = {}, []
    for m in TOK.finditer(line.replace(':BAD', ' bad=BAD')):
        k = m.group(1); n = seen.get(k, 0); seen[k] = n + 1
        v = m.group(2)
        try:
            v = float(v)
        except ValueError:
            pass
        out.append(('%s#%d' % (k, n), v))
    return out


def spearman(a, b):
    def rank(v):
        o = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0] * len(v); i = 0
        while i < len(o):
            j = i
            while j + 1 < len(o) and v[o[j + 1]] == v[o[i]]:
                j += 1
            for k in range(i, j + 1):
                r[o[k]] = (i + j) / 2.0
            i = j + 1
        return r
    ra, rb = rank(a), rank(b); n = len(a)
    if n < 2:
        return 1.0
    ma, mb = sum(ra) / n, sum(rb) / n
    cov = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    va = sum((x - ma) ** 2 for x in ra) ** .5; vb = sum((y - mb) ** 2 for y in rb) ** .5
    return cov / (va * vb) if va and vb else 1.0


def rj(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def wj(p, rows):
    with open(p + '.tmp', 'w') as f:
        for r in rows:
            f.write(json.dumps(r) + '\n')
    os.replace(p + '.tmp', p)


def gzcopy(src, dst):
    with open(src, 'rb') as a, gzip.open(dst, 'wb', 6) as b:
        shutil.copyfileobj(a, b)


# ---------------------------------------------------------------- build
def snap(path, sub, d):
    os.makedirs(os.path.join(d, sub), exist_ok=True)
    dst = os.path.join(d, sub, os.path.basename(path))
    if not os.path.exists(dst):
        shutil.copy2(path, dst)
        if os.path.isdir(path + '.d') and not os.path.exists(dst + '.d'):
            shutil.copytree(path + '.d', dst + '.d')
    return dst


def build(argv):
    n_pa = int(argv[argv.index('--n-pa') + 1]) if '--n-pa' in argv else 120
    d = SET; os.makedirs(os.path.join(d, 'cpu'), exist_ok=True)
    b17 = snap('/root/animlab-build/kfpvm_b17', 'bin', d)
    sjl = snap('/root/animlab-build/sjl_v', 'bin', d)
    recs = {k: snap(v, 'recs/' + k.replace(' ', '_'), d) for k, v in list(WC_RECS.items()) + [('Naginata', NAG_REC), ('sword', SWORD_REC)]}
    import weapon_matrix as WM
    rows = []
    # 1) pa-work sweeps (already CPU-evaluated by pasweep.py on kfpvm_b17 = the snapshot)
    cand, seen = [], set()
    for k in range(1, 8):
        p = os.path.join(PA, 'sweep%d.txt' % k)
        for l in open(p):
            if not l.startswith('PA [') or 'framed_ready=' not in l:
                continue
            sets = l[4:l.index('] ')]
            rps = re.findall(r'rp=(\S+)', l)
            if sets in seen or len(rps) != 2 or not all(os.path.exists(x) for x in rps):
                continue
            seen.add(sets); hard, s = score(l)
            cand.append((s, hard, sets, RP.sub('', l.rstrip('\n')), rps, k))
    cand.sort(key=lambda c: c[0])
    soft = [c for c in cand if not c[1]]; hardc = [c for c in cand if c[1]]
    pick = soft[:: max(1, len(soft) // 30)][:30] if soft else []
    rest = n_pa - len(pick) - 15
    pick += hardc[:: max(1, len(hardc) // rest)][:rest] + hardc[-15:]
    uniq = []
    for c in pick:
        if c not in uniq:
            uniq.append(c)
    w = G.weapon('Naginata'); pom, tip = WM.two_dims(w)
    for i, (s, hard, sets, line, rps, k) in enumerate(sorted(uniq, key=lambda c: -c[0])):
        vid = 'pa%03d' % i
        _, _, jobs = G.pa_jobs('Naginata', recs['Naginata'], sets.split(), b17, '/x', '2', vid)
        js = []
        for j, rp in zip(jobs, rps):
            co = os.path.join(d, 'cpu', j['id'] + '.txt.gz'); gzcopy(rp, co)
            js.append({'id': j['id'], 'label': j['label'], 'args': j['args'], 'cpu_out': co})
        rows.append({'id': vid, 'group': 'pa-naginata(sweep%d)' % k, 'weapon': 'Naginata', 'tip': tip, 'rec': recs['Naginata'],
                     'adapter': b17, 'sets': sets.split(), 'cpu_line': line.split('] ', 1)[1], 'cpu_score': s, 'cpu_hard': hard,
                     'jobs': js, 'src': 'stored pasweep %s' % os.path.join(PA, 'sweep%d.txt' % k)})
    print('pa: %d variants (soft %d, hard %d of %d candidates)' % (len(rows), sum(not r['cpu_hard'] for r in rows), sum(r['cpu_hard'] for r in rows), len(cand)))
    # 2) fills: fresh CPU replays (Buster / Axe 2H sets from wc-work, sword stroke sets from strokefix opt logs)
    fills = []
    rnd = random.Random(11)
    for wn in WC_RECS:
        sets = []
        for f in sorted(os.listdir('/root/wc-work')):
            if f.startswith('jobs-') and f.endswith('.txt'):
                for l in open(os.path.join('/root/wc-work', f)):
                    a = shlex.split(l)
                    if len(a) > 3 and a[2] == wn:
                        sets.append(tuple(a[i + 1] for i in range(len(a)) if a[i] == '--set'))
        sets = sorted(set(sets)); rnd.shuffle(sets)
        for s in sets[:15]:
            fills.append(('wc-' + wn.split()[0].lower(), wn, recs[wn], b17, list(s), '2'))
    for lg, st in (('/root/strokefix/opt-s2a.log', 2), ('/root/strokefix/opt-s0a.log', 0)):
        for l in open(lg):
            if l.startswith('BEST '):
                kv = re.findall(r'(\w+)=(-?[\d.]+)', l.split(' score=')[0])
                fills.append(('sword-s%d' % st, 'Katana', recs['sword'], sjl, ['t.sline.s%d.%s=%s' % ((st,) + kv_) for kv_ in kv], str(st)))
    ev = G.Evaluator('cpu', cache=False)
    tmp = tempfile.mkdtemp(prefix='agree-build-', dir='/root')
    alljobs, meta = [], []
    for n, (grp, wn, rec, adp, sets, st) in enumerate(fills):
        vid = '%s%02d' % (grp.split('-')[0] + grp.split('-')[1][:3], n)
        if grp.startswith('sword'):
            w = G.weapon(wn); tip = 8.0
            args = ['--no-rec-sets', '--set', 'stroke=%s' % st] + sum([['--set', s] for s in sets], []) + ['--quiet']
            jobs = [{'id': vid + '-s%s' % st, 'adapter': adp, 'rec': rec, 'args': args, 'out': os.path.join(tmp, vid + '.txt'), 'label': ''}]
        else:
            w, tip, jobs = G.pa_jobs(wn, rec, sets, adp, tmp, st, vid)
        alljobs += jobs; meta.append((vid, grp, wn, w, tip, rec, adp, sets, jobs))
    t0 = time.time(); res = {r['id']: r for r in ev.replay_batch(alljobs)}
    print('fills: %d variants, %d fresh CPU replays %.1fs' % (len(meta), len(alljobs), time.time() - t0))
    for vid, grp, wn, w, tip, rec, adp, sets, jobs in meta:
        if any(res[j['id']]['rc'] != 0 for j in jobs):
            print('skip %s: replay rc' % vid); continue
        line = G.pa_text(w, tip, jobs, [j['out'] for j in jobs])
        hard, s = score(line)
        js = []
        for j in jobs:
            co = os.path.join(d, 'cpu', j['id'] + '.txt.gz'); gzcopy(j['out'], co)
            js.append({'id': j['id'], 'label': j['label'], 'args': j['args'], 'cpu_out': co})
        rows.append({'id': vid, 'group': grp, 'weapon': wn, 'tip': tip, 'rec': rec, 'adapter': adp, 'sets': sets,
                     'cpu_line': line, 'cpu_score': s, 'cpu_hard': hard, 'jobs': js, 'src': 'fresh CPU replay (gpu-agree build)'})
    shutil.rmtree(tmp)
    # CPU reference line = the CURRENT judge code on the stored CPU replays (the judge changed since some sweeps ran:
    # framed_swing -> framed_swing_cross 19:12, SR41 rec= 19:45); the replay is what the GPU replaces, the judge stays
    from concurrent.futures import ProcessPoolExecutor
    import multiprocessing as mp, labcache
    with ProcessPoolExecutor(int(os.environ.get('LABNICE_J') or 6), mp_context=mp.get_context('fork')) as ex:
        lines = list(ex.map(_rejudge_cpu, rows))
    changed = 0
    for r, l in zip(rows, lines):
        changed += l != r['cpu_line']
        r['cpu_line_stored'] = r['cpu_line']; r['cpu_line'] = l
        r['cpu_hard'], r['cpu_score'] = score(l)
        r['judge_code'] = labcache.code_hash()
    print('judge: %d/%d stored lines differ from the current judge code (cpu_line re-derived, stored kept)' % (changed, len(rows)))
    wj(os.path.join(d, 'manifest.jsonl'), rows)
    write_jobs(os.path.join(d, 'out-gpu'), os.path.join(d, 'jobs.jsonl'))
    # verify: judge on the stored CPU replays reproduces cpu_line (all), and K fresh replays reproduce stored replays
    bad = verify(rows, k=8)
    print('BUILD %s variants=%d jobs=%d groups=%s verify_bad=%d' % (SET, len(rows), sum(len(r['jobs']) for r in rows),
          ','.join('%s:%d' % (g, sum(r['group'].startswith(g) for r in rows)) for g in ('pa', 'wc-buster', 'wc-fragment', 'sword')), bad))
    return 1 if bad else 0


def _gunzip_tmp(p, d):
    o = os.path.join(d, os.path.basename(p)[:-3])
    with gzip.open(p, 'rb') as a, open(o, 'wb') as b:
        shutil.copyfileobj(a, b)
    return o


def verify(rows, k=6):
    from concurrent.futures import ProcessPoolExecutor
    import multiprocessing as mp
    bad = 0
    with ProcessPoolExecutor(int(os.environ.get('LABNICE_J') or 6), mp_context=mp.get_context('fork')) as ex:
        lines = list(ex.map(_rejudge_cpu, rows))
    for r, l in zip(rows, lines):
        if l != r['cpu_line']:
            bad += 1; print('VERIFY judge mismatch %s\n  stored: %s\n  rejudge: %s' % (r['id'], r['cpu_line'][:200], l[:200]))
    d = tempfile.mkdtemp(prefix='agree-verify-', dir='/root')
    for r in random.Random(3).sample(rows, min(k, len(rows))):
        j = r['jobs'][0]
        o = os.path.join(d, j['id'] + '.txt')
        subprocess.run([r['adapter'], r['rec'], o] + j['args'], stdout=subprocess.DEVNULL, check=True)
        rd = G.rawdiff(j['cpu_out'], o, tol=0.0)
        if rd['n_diff'] or rd['state_mismatch'] or rd['n_cpu'] != rd['n_other']:
            bad += 1; print('VERIFY replay not reproducible %s %s' % (j['id'], rd))
    shutil.rmtree(d)
    print('verify: %d judge lines re-derived, %d replays re-run, %d bad' % (len(rows), min(k, len(rows)), bad))
    return bad


def _rejudge_cpu(r):
    d = tempfile.mkdtemp(prefix='agree-rj-', dir='/dev/shm')
    try:
        outs = [_gunzip_tmp(j['cpu_out'], d) for j in r['jobs']]
        return rejudge(r, outs)
    finally:
        shutil.rmtree(d)


def rejudge(r, outs):
    w = G.weapon(r['weapon'])
    return G.pa_text(w, r['tip'], r['jobs'], outs)


def write_jobs(outdir, path=None):
    rows = rj(os.path.join(SET, 'manifest.jsonl'))
    jobs = [{'id': j['id'], 'adapter': r['adapter'], 'rec': r['rec'], 'args': j['args'], 'out': os.path.join(outdir, j['id'] + '.txt')}
            for r in rows for j in r['jobs']]
    wj(path or os.path.join(SET, 'jobs.jsonl'), jobs)
    print('jobs: %d -> %s (outs under %s)' % (len(jobs), path or os.path.join(SET, 'jobs.jsonl'), outdir))
    return jobs


# ---------------------------------------------------------------- compare
def _cmp_variant(a):
    r, outs, raw_tol, num_tol = a
    out = {'id': r['id'], 'group': r['group'], 'raw': [], 'err': None}
    if any(o is None or not os.path.exists(o) for o in outs):
        out['err'] = 'missing output'; return out
    for j, o in zip(r['jobs'], outs):
        out['raw'].append(dict(G.rawdiff(j['cpu_out'], o, raw_tol), job=j['id']))
    try:
        line = rejudge(r, outs)
    except Exception as e:
        out['err'] = 'judge: %s' % e; return out
    hard, s = score(line)
    # reference = the CURRENT judge on the stored CPU replays (the manifest's cpu_line is from the sweep's judge
    # version; the judge keeps changing, e.g. 458d22c blade seen); stale_ref = manifest line differs (info)
    try:
        ref = _rejudge_cpu(r)
    except Exception as e:
        out['err'] = 'cpu rejudge: %s' % e; return out
    ch, cs = score(ref)
    out.update(cpu_line=ref, cpu_score=cs, cpu_hard=ch, stale_ref=ref != r['cpu_line'])
    ta, tb = tokens(ref), tokens(line)
    flips, numd, worst = [], 0.0, None
    if [k for k, _ in ta] != [k for k, _ in tb]:
        flips.append('token layout differs')
    for (k, va), (_, vb) in zip(ta, tb):
        if isinstance(va, float) and isinstance(vb, float):
            dd = abs(va - vb) / max(1.0, abs(va))
            if dd > numd:
                numd, worst = dd, '%s %s->%s' % (k, va, vb)
        elif va != vb:
            flips.append('%s %s->%s' % (k, va, vb))
    out.update(line=line, score=s, hard=hard, flips=flips, num_rel=numd, num_worst=worst)
    return out


def compare(argv):
    res_p = argv[0]
    o = {'--set': SET, '--raw-tol': '0.02', '--score-tol': '0.05', '--rho': '0.99', '--num-tol': '0.02', '--bench': None}
    k = 1
    while k < len(argv):
        o[argv[k]] = argv[k + 1]; k += 2
    rows = rj(os.path.join(o['--set'], 'manifest.jsonl'))
    res = {x['id']: x for x in rj(res_p)}
    raw_tol, st, rho_min, num_tol = float(o['--raw-tol']), float(o['--score-tol']), float(o['--rho']), float(o['--num-tol'])
    todo = [(r, [res[j['id']]['out'] if j['id'] in res and res[j['id']].get('rc', 0) == 0 else None for j in r['jobs']], raw_tol, num_tol)
            for r in rows]
    from concurrent.futures import ProcessPoolExecutor
    import multiprocessing as mp
    with ProcessPoolExecutor(int(os.environ.get('LABNICE_J') or 6), mp_context=mp.get_context('fork')) as ex:
        cs = list(ex.map(_cmp_variant, todo))
    rep, fails = [], []
    sc_cpu, sc_gpu, maxraw, rawbad, smis, hflip, nflip, sdmax = [], [], 0.0, 0, 0, 0, 0, 0.0
    for r, c in zip(rows, cs):
        if c['err']:
            fails.append('%s %s' % (r['id'], c['err'])); rep.append('%s ERROR %s' % (r['id'], c['err'])); continue
        mr = max(x['max_abs'] for x in c['raw']); maxraw = max(maxraw, mr)
        rb = sum(x['bad_frames'] for x in c['raw']); rawbad += rb
        sm = sum(x['state_mismatch'] for x in c['raw']) + sum(x['n_cpu'] != x['n_other'] for x in c['raw']); smis += sm
        sd = abs(c['score'] - c['cpu_score']); sdmax = max(sdmax, sd)
        hf = c['hard'] != c['cpu_hard']; hflip += hf; nflip += bool(c['flips'])
        sc_cpu.append(c['cpu_score']); sc_gpu.append(c['score'])
        bad = rb or sm or sd > st or hf or c['num_rel'] > num_tol
        if bad:
            fails.append(r['id'])
        rep.append('%s %s %s raw_max=%.4g bad_frames=%d state_mis=%d score cpu=%.3f gpu=%.3f d=%.3f hard %s->%s num_rel=%.3g%s flips=%s' % (
            r['id'], 'FAIL' if bad else 'ok', r['group'], mr, rb, sm, c['cpu_score'], c['score'], sd, c['cpu_hard'], c['hard'],
            c['num_rel'], (' (%s)' % c['num_worst']) if c['num_worst'] and c['num_rel'] > 0 else '', ';'.join(c['flips'][:4]) or '-'))
    rho = spearman(sc_cpu, sc_gpu)
    top_cpu = max(range(len(sc_cpu)), key=lambda i: sc_cpu[i]) if sc_cpu else None
    top_gpu = max(range(len(sc_gpu)), key=lambda i: sc_gpu[i]) if sc_gpu else None
    ok = not fails and rho >= rho_min
    bench = o['--bench'] or (res_p + '.bench.json')
    btxt = bench_text(bench) if os.path.exists(bench) else 'bench: none (%s)' % bench
    cpu_b = os.path.join(o['--set'], 'cpu-ref.results.jsonl.bench.json')
    if os.path.exists(cpu_b) and os.path.abspath(cpu_b) != os.path.abspath(bench):
        btxt += '\n' + bench_text(cpu_b)
    head = ('AGREE %s variants=%d jobs=%d fail=%d rho=%.4f(min %.2f) score_dmax=%.3f(tol %.2f) hard_flips=%d verdict_token_flips=%d '
            'raw_max=%.4g(tol %.3g) raw_bad_frames=%d state_mismatch=%d same_winner=%s ref=current-judge(stale_manifest_lines=%d)' % (
                'PASS' if ok else 'FAIL', len(rows), sum(len(r['jobs']) for r in rows), len(fails), rho, rho_min, sdmax, st, hflip,
                nflip, maxraw, raw_tol, rawbad, smis, top_cpu == top_gpu, sum(bool(c.get('stale_ref')) for c in cs)))
    txt = head + '\n' + btxt + '\n' + '\n'.join(rep) + '\n'
    open(res_p + '.agree.txt', 'w').write(txt)
    print(head); print(btxt); print('report: %s.agree.txt' % res_p)
    if fails:
        print('first fails: %s' % ', '.join(fails[:10]))
    return 0 if ok else 1


# ---------------------------------------------------------------- bench
NVSMI = next((p for p in ('/usr/lib/wsl/lib/nvidia-smi', '/mnt/c/Windows/System32/nvidia-smi.exe') if os.path.exists(p)), 'nvidia-smi')


def _stat_cpu():
    a = open('/proc/stat').readline().split()[1:]; a = list(map(int, a))
    return sum(a), a[3] + a[4]


def bench(label, res_p, cmd):
    samples, stop = {'gpu': [], 'mem': [], 'win': []}, threading.Event()

    def gpu_loop():
        p = subprocess.Popen([NVSMI, '--query-gpu=utilization.gpu,memory.used', '--format=csv,noheader,nounits', '-lms', '500'],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True)
        for l in p.stdout:
            if stop.is_set():
                break
            try:
                u, m = [float(x) for x in l.split(',')[:2]]; samples['gpu'].append(u); samples['mem'].append(m)
            except ValueError:
                pass
        p.kill()

    def win_loop():
        p = subprocess.Popen(['/mnt/c/Windows/System32/typeperf.exe', r'\Processor(_Total)\% Processor Time', '-si', '1'],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True)
        for l in p.stdout:
            if stop.is_set():
                break
            m = re.match(r'^"[^"]+","([\d.]+)"', l.strip())
            if m:
                samples['win'].append(float(m.group(1)))
        p.kill()
    ths = [threading.Thread(target=gpu_loop, daemon=True), threading.Thread(target=win_loop, daemon=True)]
    for t in ths:
        t.start()
    time.sleep(1.5)
    r0 = os.times(); s0 = _stat_cpu(); t0 = time.time()
    p = subprocess.run(cmd)
    wall = time.time() - t0; r1 = os.times(); s1 = _stat_cpu()
    stop.set(); time.sleep(1.2)
    cpu_s = (r1.children_user - r0.children_user) + (r1.children_system - r0.children_system)
    tot, idle = s1[0] - s0[0], s1[1] - s0[1]
    n = sum(1 for l in open(res_p) if l.strip()) if os.path.exists(res_p) else 0
    avg = lambda v: round(sum(v) / len(v), 1) if v else None
    b = {'label': label, 'cmd': cmd, 'rc': p.returncode, 'jobs': n, 'wall_s': round(wall, 2), 'cpu_s': round(cpu_s, 2),
         'cpu_s_per_job': round(cpu_s / max(n, 1), 3), 'jobs_per_s': round(n / max(wall, 1e-9), 2),
         'wsl_cpu_pct': round(100.0 * (tot - idle) / max(tot, 1), 1), 'win_cpu_pct_avg': avg(samples['win']),
         'gpu_util_avg': avg(samples['gpu']), 'gpu_util_max': max(samples['gpu']) if samples['gpu'] else None,
         'gpu_mem_max_mb': max(samples['mem']) if samples['mem'] else None, 'nproc': os.cpu_count(),
         'note': 'cpu_s = rusage of the command process tree (WSL); a Windows-side GPU process is not in it: see win_cpu_pct'}
    json.dump(b, open(res_p + '.bench.json', 'w'), indent=1)
    print(bench_text(res_p + '.bench.json'))
    return p.returncode


def bench_text(p):
    b = json.load(open(p))
    return ('BENCH %(label)s jobs=%(jobs)d wall=%(wall_s).1fs cpu=%(cpu_s).1fs (%(cpu_s_per_job).3f CPU-s/job, %(jobs_per_s).2f jobs/s) '
            'wsl_cpu=%(wsl_cpu_pct)s%% win_cpu=%(win_cpu_pct_avg)s%% gpu_util avg/max=%(gpu_util_avg)s/%(gpu_util_max)s%% '
            'gpu_mem_max=%(gpu_mem_max_mb)sMB' % b)


def cpu_ref(argv):
    outdir = argv[0]; j = argv[argv.index('-j') + 1] if '-j' in argv else os.environ.get('LABNICE_J', '6')
    os.makedirs(outdir, exist_ok=True)
    jf = os.path.join(outdir, 'jobs.jsonl'); write_jobs(outdir, jf)
    rp = os.path.join(SET, 'cpu-ref.results.jsonl')
    # no result cache: the CPU adapter really runs (that is what the GPU replaces)
    code = 'import sys; sys.path.insert(0,%r); import gpueval as G, json\n' \
           'jobs=G._read_jsonl(sys.argv[1])\n' \
           'res=G.Evaluator("cpu",workers=int(sys.argv[3]),cache=False).replay_batch(jobs)\n' \
           'open(sys.argv[2],"w").write("".join(json.dumps(r)+"\\n" for r in res))' % HERE
    return bench('cpu (kfpvm adapter, %s workers, no cache)' % j, rp, [sys.executable, '-c', code, jf, rp, str(j)])


# ---------------------------------------------------------------- selftest
def selftest():
    global SET
    d = tempfile.mkdtemp(prefix='gpu-agree-st-', dir='/root')
    real = SET
    try:
        rows = rj(os.path.join(real, 'manifest.jsonl'))
        sub = [r for r in rows if r['group'].startswith('pa')][:4] + [r for r in rows if r['group'].startswith('wc')][:2]
        SET = d; wj(os.path.join(d, 'manifest.jsonl'), sub)
        jobs = {j['id']: j for r in sub for j in r['jobs']}

        def fake(name, mut=None):
            od = os.path.join(d, name); os.makedirs(od)
            res = []
            for jid, j in jobs.items():
                o = os.path.join(od, jid + '.txt'); _gunzip_tmp(j['cpu_out'], od); os.replace(os.path.join(od, jid + '.txt'), o)
                if mut:
                    mut(jid, o)
                res.append({'id': jid, 'out': o, 'rc': 0, 'ms': 1.0})
            wj(os.path.join(od, 'results.jsonl'), res)
            return os.path.join(od, 'results.jsonl')

        def noise(jid, o):   # +-0.0001 on every 7th number: float noise within tolerance
            t = open(o).read().split('\n'); out = []
            for l in t:
                if l.startswith('#') or not l:
                    out.append(l); continue
                n = [0]

                def bump(m):
                    n[0] += 1
                    return ('%.4f' % (float(m.group(0)) + 0.0001)) if n[0] % 7 == 0 else m.group(0)
                out.append(re.sub(r'-?\d+\.\d{4}\b', bump, l))
            open(o, 'w').write('\n'.join(out))

        def corrupt(jid, o):  # one job: hand positions off by 0.5 over a stretch of frames + a state flip
            if jid != sub[1]['jobs'][0]['id']:
                return
            t = open(o).read().split('\n'); k = 0
            for i, l in enumerate(t):
                if l and not l.startswith('#'):
                    k += 1
                    if 200 <= k < 400:
                        t[i] = re.sub(r'\| (-?[\d.]+),', lambda m: '| %.4f,' % (float(m.group(1)) + 0.5), l, 1)
                    if k == 300:   # flip the state word (4th field) whatever it is
                        f = t[i].split(' ')
                        f[3] = 'blocking' if f[3] != 'blocking' else 'ready'
                        t[i] = ' '.join(f)
            open(o, 'w').write('\n'.join(t))
        exp = [('exact', None, 0), ('noise', noise, 0), ('corrupt', corrupt, 1)]
        got = []
        for name, mut, want in exp:
            rc = compare([fake(name, mut), '--set', d])
            got.append(rc == want); print('selftest %s rc=%d want=%d %s' % (name, rc, want, 'ok' if rc == want else 'WRONG'))
        assert abs(spearman([1, 2, 3, 4], [10, 20, 30, 40]) - 1.0) < 1e-9 and abs(spearman([1, 2, 3, 4], [4, 3, 2, 1]) + 1.0) < 1e-9
        assert tokens('a=1 b=ok a=2.5 c=FAIL x=0.3/0.5:BAD') == [('a#0', 1.0), ('b#0', 'ok'), ('a#1', 2.5), ('c#0', 'FAIL'), ('x#0', 0.3), ('bad#0', 'BAD')]
        ok = all(got)
        print('gpu-agree selftest %s' % ('PASS' if ok else 'FAIL'))
        return 0 if ok else 1
    finally:
        SET = real
        shutil.rmtree(d, ignore_errors=True)


def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__); return 2
    c = argv[0]
    if c == 'build':
        return build(argv[1:])
    if c == 'jobs':
        write_jobs(argv[1], argv[2] if len(argv) > 2 else None); return 0
    if c == 'bench':
        i = argv.index('--'); return bench(argv[1], argv[2], argv[i + 1:])
    if c == 'cpu-ref':
        return cpu_ref(argv[1:])
    if c == 'selftest':
        return selftest()
    return compare(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
