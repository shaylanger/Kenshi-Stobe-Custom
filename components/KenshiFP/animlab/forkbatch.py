#!/usr/bin/env python3
"""forkbatch.py <jobs file|-> [-j N] [--warm mod,mod] [--check K]   (gpu-lab 2026-10-11; Shay 18:47: CPU >90% from
lab sweeps that start one python3 per variant: pasweep.py tworP_*, stroke/pose evaluators)
Drop-in for `xargs -P N -I{} -d '\\n' bash -c '{}' < jobs`: runs every `python3 <script.py> args...` job line in a child
FORKED from one warm parent that already imported numpy + the lab modules (recfmt, metrics, weapon_matrix, ...), so a
variant costs no interpreter start / imports (~0.2-0.3 s CPU each). Each job is a fresh fork: module state a script
mutates (metrics.BLADE, ARC_MID, ...) never leaks to the next job, and the script file is read at run time, so edits to
pasweep.py etc. apply to the next job like with xargs. Output: each job's whole stdout printed as one block when it ends
(completion order, like xargs); stderr passes through. Lines that are not `python3 <file>.py ...` run via bash -c.
In each child recfmt.parse(path) is memoised on (path, mtime, size) (pasweep.py parsed every replay twice: judge + own).
  -j N        parallel children (default $LABNICE_J or 6); run it under labnice.sh like xargs was:
              labnice.sh -s 6 python3 forkbatch.py jobs2.txt -j 6 > sweep2.txt 2>&1
  --cwd D     job working dir (default: current dir)
  --warm M    extra modules to import in the parent (comma list; default numpy + recfmt,metrics,weapon_matrix,labcache)
  --check K   agreement selftest: the first K jobs run both forked and as a plain `bash -c` subprocess; exit 1 on any
              output difference (replay caches make the second run of a job a cache hit, as in a rerun of a sweep)
The KenshiFP adapter replay inside a job (C viewmodel sim, ~75% elbow search, branchy per frame) stays on the CPU:
it is the shipped game code compiled for the lab; see docs/animlab USAGE "forkbatch" for the measured split.
"""
import sys, os, argparse, shlex, tempfile, subprocess, runpy, time

LAB = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'


def warm(mods):
    sys.path.insert(0, LAB)
    import importlib
    for m in mods:
        try:
            importlib.import_module(m)
        except Exception as e:
            print('forkbatch: warm import %s failed: %s' % (m, e), file=sys.stderr)
    rf = sys.modules.get('recfmt')
    if rf is not None and not getattr(rf, '_fb_memo', False):
        orig = rf.parse; memo = {}

        def parse(path):
            try:
                k = (path, os.path.getmtime(path), os.path.getsize(path))
            except OSError:
                return orig(path)
            if k not in memo:
                memo.clear(); memo[k] = orig(path)
            return memo[k]
        rf.parse = parse; rf._fb_memo = True
    mt = sys.modules.get('metrics')
    if mt is not None and hasattr(mt, 'rendered') and not getattr(mt, '_fb_memo', False):
        # rendered(F) depends on F + metrics.BLADE only; judge() + the caller recompute it 3x per replay. Cache the
        # per-frame dicts, hand out shallow copies (frame_metrics adds keys to them).
        orig_r = mt.rendered; rmemo = {}

        def rendered(F):
            k = (id(F), len(F), tuple(sorted(mt.BLADE.items())))
            if k not in rmemo:
                if len(rmemo) > 4:
                    rmemo.clear()
                rmemo[k] = (F, orig_r(F))   # F kept alive so id(F) cannot be reused while cached
            return [dict(p) for p in rmemo[k][1]]
        mt.rendered = rendered; mt._fb_memo = True


def py_job(line):
    """(script, argv) when the line is a plain `python3 x.py args` (no shell syntax), else None."""
    if any(c in line for c in '|&;<>$`(){}*?'):
        return None
    try:
        a = shlex.split(line)
    except ValueError:
        return None
    if len(a) >= 2 and os.path.basename(a[0]) in ('python3', 'python', 'python3.11') and a[1].endswith('.py'):
        return a[1], a[1:]
    return None


def child(line, cwd, outpath):
    fd = os.open(outpath, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.dup2(fd, 1); os.close(fd)
    sys.stdout = os.fdopen(1, 'w', buffering=1)
    os.chdir(cwd)
    pj = py_job(line)
    code = 0
    if pj is None:
        code = subprocess.run(['bash', '-c', line], stdout=1).returncode
    else:
        script, argv = pj
        sys.argv = argv
        sp = os.path.dirname(os.path.abspath(script))
        sys.path.insert(0, sp)
        try:
            runpy.run_path(script, run_name='__main__')
        except SystemExit as e:
            if isinstance(e.code, str):
                print(e.code, file=sys.stderr); code = 1
            else:
                code = e.code or 0
        except BaseException:
            import traceback
            traceback.print_exc(); code = 1
    try:
        sys.stdout.flush(); sys.stderr.flush()
    except Exception:
        pass
    os._exit(code if isinstance(code, int) else 1)


def run(lines, j, cwd, tmp, emit):
    live = {}; q = list(lines); rc = 0; n = 0
    while q or live:
        while q and len(live) < j:
            line = q.pop(0); n += 1
            op = os.path.join(tmp, 'j%d.out' % n)
            pid = os.fork()
            if pid == 0:
                child(line, cwd, op)
            live[pid] = (line, op)
        pid, st = os.wait()
        if pid not in live:
            continue
        line, op = live.pop(pid)
        with open(op) as f:
            emit(line, f.read())
        os.unlink(op)
        if os.waitstatus_to_exitcode(st) != 0:
            rc = 123   # like xargs: some job failed
    return rc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('jobs'); ap.add_argument('-j', type=int, default=int(os.environ.get('LABNICE_J', '6') or 6))
    ap.add_argument('--cwd', default=os.getcwd()); ap.add_argument('--warm', default='')
    ap.add_argument('--check', type=int, default=0)
    o = ap.parse_args()
    lines = [l.rstrip('\n') for l in (sys.stdin if o.jobs == '-' else open(o.jobs)) if l.strip()]
    warm(['numpy', 'recfmt', 'metrics', 'weapon_matrix', 'labcache'] + [m for m in o.warm.split(',') if m])
    tmp = tempfile.mkdtemp(prefix='forkbatch-', dir='/dev/shm' if os.path.isdir('/dev/shm') else None)
    try:
        if o.check:
            got = {}
            t0 = time.time(); run(lines[:o.check], o.j, o.cwd, tmp, lambda l, s: got.__setitem__(l, s)); tf = time.time() - t0
            bad = 0; t0 = time.time()
            for l in lines[:o.check]:
                ref = subprocess.run(['bash', '-c', l], cwd=o.cwd, capture_output=True, text=True).stdout
                if ref != got.get(l):
                    bad += 1; print('DIFF %s\n  fork: %s\n  bash: %s' % (l[:120], (got.get(l) or '')[:300], ref[:300]))
            print('forkbatch check: %d/%d identical (fork %.1fs, serial bash %.1fs)' % (o.check - bad, o.check, tf, time.time() - t0))
            sys.exit(1 if bad else 0)
        sys.exit(run(lines, max(1, o.j), o.cwd, tmp, lambda l, s: (sys.stdout.write(s), sys.stdout.flush())))
    finally:
        subprocess.run(['rm', '-rf', tmp])


if __name__ == '__main__':
    main()
