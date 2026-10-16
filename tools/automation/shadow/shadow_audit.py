"""Read-only audit for the live coordinator shadow run (docs/COORD_SHADOW_PLAN.md stage 2).

Detects any write made while the shadow arms ran, belt and braces next to the guard hook. It only reads: `git status`
of the repo paths, and file mtimes. Changes are printed, never judged: decide by hand which belong to other agents.

  python -I shadow_audit.py snapshot [--out FILE]
  python -I shadow_audit.py check [--snapshot FILE] [--baseline-git FILE] [--since "YYYY-MM-DD HH[:MM[:SS]]"]

snapshot: records `git status --short` of tools/ docs/ testing/ pending-fixes/ plus mtime/size of every file named by it,
          and mtime/size of every file under the runs dir (excluding shadow, agents, inflight, ledger, alerts, coordinator*).
check:    compares now against --snapshot (default RUNS/shadow/audit-pre.json) and/or --baseline-git FILE (a bare
          `git status --short -- tools docs testing pending-fixes` text taken earlier, when no mtime snapshot exists).
          With only a git baseline, --since TIME also lists dirty repo files and runs-dir files whose mtime is >= TIME
          (mtime-only; cannot prove the content differs).
Exit code: 0 = no change found, 1 = changes printed, 2 = usage/IO error.
Options for tests: --repo DIR (default C:\\KenshiModding), --runs DIR (default C:\\KenshiTestRuns), --max-files N.
Standard library only; run with python -I."""
import argparse, json, os, subprocess, sys, time

REPO = r'C:\KenshiModding'
RUNS = r'C:\KenshiTestRuns'
GIT_PATHS = ['tools', 'docs', 'testing', 'pending-fixes']
RUNS_SKIP_TOP = {'shadow', 'agents', 'inflight', 'ledger', 'alerts'}
MAX_FILES = 200000


def skip_name(name, top):
    low = name.lower()
    if low.startswith('coordinator'):
        return True
    return top and low in RUNS_SKIP_TOP


def git_status(repo):
    r = subprocess.run(['git', '--no-optional-locks', '-c', 'core.quotepath=false', '-C', repo, 'status', '--short', '--'] + GIT_PATHS,
                       capture_output=True)
    if r.returncode != 0:
        raise RuntimeError('git status failed: ' + r.stderr.decode('utf-8', 'replace').strip())
    return [x.rstrip('\r') for x in r.stdout.decode('utf-8', 'replace').split('\n') if x.strip()]


def decode_text(b):
    if b[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return b.decode('utf-16', 'replace')
    return b.decode('utf-8-sig', 'replace')


def read_git_baseline(path):
    with open(path, 'rb') as f:
        txt = decode_text(f.read())
    return [x.rstrip('\r') for x in txt.split('\n') if x.strip()]


def status_path(line):
    p = line[3:] if len(line) > 3 else line
    if ' -> ' in p:
        p = p.split(' -> ', 1)[1]
    return p.strip().strip('"')


def stat_entry(p):
    try:
        st = os.stat(p)
        return [round(st.st_mtime, 3), st.st_size]
    except OSError:
        return None


def dirty_files(repo, lines, cap):
    """{relpath: [mtime,size] or None} for every path named by git status (directories are expanded)."""
    out = {}
    for ln in lines:
        rel = status_path(ln)
        full = os.path.join(repo, rel)
        if os.path.isdir(full):
            for root, dirs, files in os.walk(full):
                dirs[:] = [d for d in dirs if d != '.git' and d != '__pycache__']
                for fn in files:
                    fp = os.path.join(root, fn)
                    out[os.path.relpath(fp, repo).replace('\\', '/')] = stat_entry(fp)
                    if len(out) >= cap:
                        return out
        else:
            out[rel.replace('\\', '/')] = stat_entry(full)
    return out


def runs_files(runs, cap):
    out = {}
    if not os.path.isdir(runs):
        return out
    for root, dirs, files in os.walk(runs):
        top = os.path.normcase(os.path.abspath(root)) == os.path.normcase(os.path.abspath(runs))
        dirs[:] = [d for d in dirs if not skip_name(d, top)]
        for fn in files:
            if skip_name(fn, False):
                continue
            fp = os.path.join(root, fn)
            e = stat_entry(fp)
            if e is not None:
                out[os.path.relpath(fp, runs).replace('\\', '/')] = e
            if len(out) >= cap:
                return out
    return out


def take(repo, runs, cap):
    lines = git_status(repo)
    return {'taken': time.strftime('%Y-%m-%d %H:%M:%S'), 'taken_ts': time.time(), 'git': lines,
            'dirty': dirty_files(repo, lines, cap), 'runs': runs_files(runs, cap)}


def parse_since(s):
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d %H', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M'):
        try:
            return time.mktime(time.strptime(s, fmt))
        except ValueError:
            pass
    raise ValueError('bad --since %r (use "YYYY-MM-DD HH:MM")' % s)


def fmt_t(ts):
    return time.strftime('%H:%M:%S', time.localtime(ts))


def diff_maps(label, before, after, out):
    for k in sorted(set(after) - set(before)):
        out.append('%s + %s  (mtime %s)' % (label, k, fmt_t(after[k][0]) if after[k] else 'gone'))
    for k in sorted(set(before) - set(after)):
        out.append('%s - %s  (no longer listed)' % (label, k))
    for k in sorted(set(before) & set(after)):
        b, a = before[k], after[k]
        if b != a:
            if b is None or a is None:
                out.append('%s ~ %s  (%s -> %s)' % (label, k, 'missing' if b is None else 'present', 'missing' if a is None else 'present'))
            else:
                out.append('%s ~ %s  (mtime %s -> %s, size %d -> %d)' % (label, k, fmt_t(b[0]), fmt_t(a[0]), b[1], a[1]))


def diff_git(before, after, out):
    for ln in sorted(set(after) - set(before)):
        out.append('GIT + ' + ln)
    for ln in sorted(set(before) - set(after)):
        out.append('GIT - ' + ln + '   (no longer in git status: committed, reverted or deleted)')


def cmd_snapshot(a):
    path = a.out or os.path.join(a.runs, 'shadow', 'audit-pre.json')
    snap = take(a.repo, a.runs, a.max_files)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(snap, f)
    print('snapshot written: %s (git lines %d, dirty files %d, runs files %d, at %s)' % (path, len(snap['git']), len(snap['dirty']), len(snap['runs']), snap['taken']))
    return 0


def cmd_check(a):
    snap_path = a.snapshot or os.path.join(a.runs, 'shadow', 'audit-pre.json')
    snap = None
    if os.path.exists(snap_path):
        with open(snap_path, 'r', encoding='utf-8') as f:
            snap = json.load(f)
    elif a.snapshot:
        print('ERROR: snapshot file not found: ' + snap_path)
        return 2
    base_git = None
    if a.baseline_git:
        if not os.path.exists(a.baseline_git):
            print('ERROR: --baseline-git file not found: ' + a.baseline_git)
            return 2
        base_git = read_git_baseline(a.baseline_git)
    elif snap is not None:
        base_git = snap['git']
    if base_git is None:
        print('ERROR: nothing to compare against: give --snapshot (or run snapshot first) or --baseline-git FILE')
        return 2
    now = take(a.repo, a.runs, a.max_files)
    out = []
    diff_git(base_git, now['git'], out)
    n_git = len(out)
    if snap is not None:
        diff_maps('FILE', snap['dirty'], now['dirty'], out)
        diff_maps('RUN ', snap['runs'], now['runs'], out)
        mode = 'snapshot %s (%s)%s' % (snap_path, snap['taken'], ' + git baseline ' + a.baseline_git if a.baseline_git else '')
    else:
        mode = 'git baseline only: ' + a.baseline_git
        if a.since:
            since = parse_since(a.since)
            for k, e in sorted(now['dirty'].items()):
                if e and e[0] >= since:
                    out.append('FILE ~ %s  (mtime %s >= since; mtime-only)' % (k, fmt_t(e[0])))
            for k, e in sorted(now['runs'].items()):
                if e[0] >= since:
                    out.append('RUN  ~ %s  (mtime %s >= since; mtime-only)' % (k, fmt_t(e[0])))
            mode += ', --since ' + a.since
        else:
            mode += ' (no mtime check: pass --since "YYYY-MM-DD HH:MM" for one)'
    print('AUDIT compared against ' + mode)
    for ln in out:
        print(ln)
    print('AUDIT result: %d change line(s) (%d git-status, %d mtime). Judge by hand which belong to other agents.' % (len(out), n_git, len(out) - n_git))
    return 1 if out else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['snapshot', 'check'])
    ap.add_argument('--repo', default=REPO)
    ap.add_argument('--runs', default=RUNS)
    ap.add_argument('--out')
    ap.add_argument('--snapshot')
    ap.add_argument('--baseline-git')
    ap.add_argument('--since')
    ap.add_argument('--max-files', type=int, default=MAX_FILES)
    a = ap.parse_args()
    try:
        return cmd_snapshot(a) if a.cmd == 'snapshot' else cmd_check(a)
    except (RuntimeError, ValueError, OSError) as e:
        print('ERROR: %s' % e)
        return 2


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    sys.exit(main())
