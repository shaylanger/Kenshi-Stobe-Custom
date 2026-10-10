#!/usr/bin/env python3
"""gen_spec.py -- the command spec the dry-run stub validates take-script calls against (one TSV line per command):
   name <TAB> source <TAB> min_args <TAB> subcommands (comma list, '' = any first argument) <TAB> usage
Sources: harness docs/COMMANDS.md tables + `cmd == "x"` in harness src (built-ins), registerCommand(...) in the KenshiFP
and Stobe sources (usage string + the first-argument literals their handlers compare against), kah.py client commands.
Usage: gen_spec.py <out.tsv> [--harness DIR] [--kfp DIR] [--stobe DIR]"""
import argparse, glob, os, re, sys

ap = argparse.ArgumentParser()
ap.add_argument('out')
ap.add_argument('--harness', default='/mnt/c/KenshiModding/Kenshi-Automation-Harness')
ap.add_argument('--kfp', default='/root/KenshiFP')
ap.add_argument('--stobe', default='/root/STOBE-src')
a = ap.parse_args()
spec = {}   # name -> dict


def add(name, src, usage='', subs=None, minargs=None):
    d = spec.setdefault(name, dict(src=set(), usage='', subs=None, minargs=None))
    d['src'].add(src)
    if usage and len(usage) > len(d['usage']):
        d['usage'] = usage
    if subs is not None:
        d['subs'] = (d['subs'] or set()) | set(subs)
    if minargs is not None:
        d['minargs'] = minargs if d['minargs'] is None else min(d['minargs'], minargs)


def req_args(usage_tail):
    """number of top-level <...> groups outside [...] (a|b alternatives in the first token count as one)."""
    s = re.sub(r'\[[^\]]*\]', '', usage_tail)
    s = re.sub(r'\([^)]*\)', '', s)
    alts = s.split('|')
    n = None
    for alt in alts if '<' not in s.split()[0:1] and '|' in s.split(' ')[0] else [s]:
        k = len(re.findall(r'<[^>]*>', alt))
        n = k if n is None else min(n, k)
    return n or 0


# 1. COMMANDS.md tables (first column)
md = os.path.join(a.harness, 'docs', 'COMMANDS.md')
for line in open(md, encoding='utf-8', errors='replace'):
    if not line.startswith('| `'):
        continue
    col = line.split(' | ')[0][2:]
    for seg in re.findall(r'`([^`]+)`', col):
        seg = seg.replace('\\|', '|')
        first, _, tail = seg.partition(' ')
        if not re.match(r'^[a-z_][a-z0-9_|-]*$', first):
            continue
        for nm in first.split('|'):
            add(nm, 'COMMANDS.md', seg, minargs=req_args(tail) if tail else 0)
# 2. harness source dispatch
for f in glob.glob(os.path.join(a.harness, 'src', '*.cpp')) + glob.glob(os.path.join(a.harness, 'src', '*.inc')):
    for m in re.finditer(r'\bcmd == "([a-z_][a-z0-9_-]*)"', open(f, encoding='utf-8', errors='replace').read()):
        add(m.group(1), 'harness-src')
# 3. registerCommand in mod sources
CMP = r'(?:strcmp|_stricmp|stricmp|strcasecmp|_strnicmp|strncmp)\(\s*(%s)\s*,\s*"([^"]+)"'
for root, tag in ((a.kfp, 'KenshiFP'), (a.stobe, 'Stobe')):
    files = [f for e in ('*.c', '*.cpp', '*.inc', '*.h') for f in glob.glob(os.path.join(root, '**', e), recursive=True)]
    text = {f: open(f, encoding='utf-8', errors='replace').read() for f in files}
    allsrc = '\n'.join(text.values())
    for m in re.finditer(r'registerCommand\(\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*(\w+)', allsrc):
        nm, usage, fn = m.groups()
        tail = usage[len(nm):].strip() if usage.startswith(nm) else usage
        subs = set()
        first = re.sub(r'\([^)]*\)', '', tail).strip()
        # usage alternatives: "state|take|press" or "state|press <x> [ms]|release"
        for alt in first.split('|'):
            w = alt.strip().split(' ')[0] if alt.strip() else ''
            if re.match(r'^[a-z_][a-z0-9_]*$', w):
                subs.add(w)
        # handler body: literals compared against argv[1] or a variable holding argv[1]
        b = re.search(r'\n(?:static\s+)?int\s+%s\s*\([^;{]*\)\s*\{(.*?)\n\}' % re.escape(fn), allsrc, re.S)
        open_any = True
        if b:
            body = b.group(1)
            vars_ = {r'argv\[1\]'} | {re.escape(v) for v in re.findall(r'(\w+)\s*=\s*(?:argc\s*>\s*1\s*\?\s*)?argv\[1\]', body)}
            for v in list(vars_):
                for mm in re.finditer(CMP % v, body):
                    subs.add(mm.group(2))
            # handlers that take free text / numbers as the first argument
            open_any = bool(re.search(r'ato[fi]\(\s*argv\[1\]|strto[dfl]\w*\(\s*argv\[1\]', body))
        if tail.lstrip().startswith(('<', '[')):   # "fp_move <wasd|none> [ms]": a free first argument
            open_any = True
        add(nm, tag, usage, subs=None if (open_any or not subs) else subs, minargs=0)
# 3b. pending KenshiFP patches (pending-fixes/kfp-*.py, built into the staged DLL by kfp-pipeline.sh before they are
# committed to /root/KenshiFP): a first-argument literal the patch compares argv[1] against counts for the registered
# command the patch text names it with ("fp_melee swing_all [reset]" -> fp_melee gets swing_all)
PEND = '/mnt/c/KenshiModding/pending-fixes'
for f in sorted(glob.glob(os.path.join(PEND, 'kfp-*.py'))):
    t = open(f, encoding='utf-8', errors='replace').read()
    for lit in set(re.findall(CMP % r'argv\[1\]', t)):
        for nm in set(re.findall(r'\b([a-z_][a-z0-9_]*) %s\b' % re.escape(lit[1]), t)):
            if nm in spec and 'KenshiFP' in spec[nm]['src'] and spec[nm]['subs'] is not None:
                add(nm, 'pending:' + os.path.basename(f), subs={lit[1]})
# 4. kah.py client-side commands
for nm, mn in (('on', 0), ('off', 0), ('autoload', 1), ('wait-world', 0), ('wait-game', 1), ('run', 1), ('help', 0)):
    add(nm, 'kah.py', minargs=mn)
with open(a.out, 'w') as o:
    for nm in sorted(spec):
        d = spec[nm]
        o.write('%s\t%s\t%s\t%s\t%s\n' % (nm, ','.join(sorted(d['src'])), d['minargs'] or 0,
                                          ','.join(sorted(d['subs'])) if d['subs'] else '', d['usage'].replace('\t', ' ')))
print('spec: %d commands -> %s' % (len(spec), a.out))
