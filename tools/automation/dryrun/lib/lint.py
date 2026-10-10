#!/usr/bin/env python3
"""lint.py -- static checks of a dry-run row's script and the scripts it runs by literal path (1 level):
  bash -n syntax                                                     FAIL
  unquoted expansion of a path variable that holds spaces on the 4080 (KDIR "/c/Program Files (x86)/...", KAH_DIR,
  PF_SHOTS, WIN_TITLE/PF_TITLE) or of a variable assigned from one     FAIL on rig 4080, NOTE on 5090
  (skyck.sh KDIR quoting, 4080 run 1)"""
import os, re, subprocess, sys

SPACEY = {'KDIR', 'KAH_DIR', 'PF_SHOTS', 'WIN_TITLE', 'PF_TITLE'}
VAR = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)')


def to_real(p):
    p = p.replace('${CR:-/mnt/c}', '/mnt/c').replace('$CR', '/mnt/c').replace('${CR}', '/mnt/c')
    if p.startswith('/c/'):
        p = '/mnt/c/' + p[3:]
    return p


def scripts_of(cmd):
    out = []
    for w in cmd.replace(';', ' ').split():
        w = w.strip('"\'')
        if w.endswith('.sh') and not re.match(r'^[A-Za-z_]\w*=', w):
            p = to_real(w)
            if not p.startswith('/'):
                p = os.path.join('/mnt/c/KenshiModding/tests/ingame/stobe', p)
            out.append(p)
    return out


def unquoted(line, tainted):
    """names of tainted vars expanded outside double quotes (not in assignments / [[ ]])"""
    hits, i, q, n = [], 0, None, len(line)
    word_start = 0
    dbl = 0
    stack, depth = [], 0   # $( ... ) opens a fresh quoting context, also inside "..." ("$(awk ... "$FR")" is quoted)
    while i < n:
        c = line[i]
        if q == "'":
            if c == "'":
                q = None
            i += 1; continue
        if c == '\\':
            i += 2; continue
        if c == '#' and q is None and (i == 0 or line[i - 1] in ' \t;'):
            break
        if line.startswith('$(', i):
            stack.append((q, depth)); q, depth = None, 0; i += 2; word_start = i; continue
        if q is None and c == '(':
            depth += 1
        if q is None and c == ')':
            if depth:
                depth -= 1
            elif stack:
                q, depth = stack.pop(); i += 1; continue
        if c == "'" and q is None:
            q = "'"; i += 1; continue
        if c == '"':
            q = None if q == '"' else '"'; i += 1; continue
        if q is None and c in ' \t;|&()':
            word_start = i + 1
        if line.startswith('[[', i) and q is None:
            dbl += 1
        if line.startswith(']]', i) and q is None:
            dbl = max(0, dbl - 1)
        if c == '$' and q is None and not dbl:
            m = VAR.match(line, i)
            if m and m.group(1) in tainted:
                w = line[word_start:i]
                if not re.match(r'^(?:local |export |declare )?[A-Za-z_]\w*\+?=', w) and not re.match(r'^[A-Za-z_]\w*\+?=', w):
                    hits.append(m.group(1))
        i += 1
    return hits


def lint_file(p, rig):
    res = []
    if not os.path.exists(p):
        return res
    r = subprocess.run(['bash', '-n', p], capture_output=True, text=True)
    if r.returncode:
        res.append(('FAIL', 'bash -n %s: %s' % (os.path.basename(p), r.stderr.strip().splitlines()[-1][:120])))
    tainted = set(SPACEY)
    lines = open(p, errors='replace').read().splitlines()
    for _ in range(2):   # propagate X=...$KDIR...
        for l in lines:
            for m in re.finditer(r'(?:^|[\s;])(?:local\s+|export\s+)?([A-Za-z_]\w*)=(\S*)', l):
                if any(v in tainted for v in VAR.findall(m.group(2))):
                    tainted.add(m.group(1))
    sev = 'FAIL' if rig == '4080' else 'NOTE'
    for k, l in enumerate(lines, 1):
        h = unquoted(l, tainted)
        if h:
            res.append((sev, '%s:%d unquoted $%s (holds spaces on the 4080: "Program Files (x86)")' % (os.path.basename(p), k, h[0])))
    return res


def lint_cmd(cmd, rig):
    out, seen = [], set()
    todo = scripts_of(cmd)
    for depth in range(2):
        nxt = []
        for p in todo:
            if p in seen:
                continue
            seen.add(p)
            out += lint_file(p, rig)
            if os.path.exists(p) and depth == 0:
                for m in re.finditer(r'(?:bash|\.|source)\s+"?([^\s";|&]+\.sh)', open(p, errors='replace').read()):
                    q = to_real(m.group(1))
                    if q.startswith('/') and '$' not in q:
                        nxt.append(q)
        todo = nxt
    return out[:6]


if __name__ == '__main__':
    for s, t in lint_cmd(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '5090'):
        print(s, t)
