#!/bin/bash
# codemap.sh - function/class/line index for big PHP / C++ / SQL files (WSL, python3).
#
# Why: agents kept dying (200k context) reading whole 60 KB+ files. A code map lets an agent do
#   grep -n funcname /root/imm26/codemap/<map>.txt          -> "name  start  end  lines  kind"
#   sed -n START,ENDp <real file>                           -> read just that function
#
# Usage (run in WSL, any user):
#   bash tools/automation/codemap.sh                 default trees (below) + INDEX.txt
#   bash tools/automation/codemap.sh FILE...         (re)map just those files (after you edit one; seconds)
#   bash tools/automation/codemap.sh --check         list stale maps (source size/mtime differ from the map header)
#   bash tools/automation/codemap.sh --verify        map defaults, then check every entry against the real file
#   bash tools/automation/codemap.sh --selftest      synthetic PHP/C++/SQL fixtures + --verify of real maps
# Options: --out DIR (default /root/imm26/codemap)  --min-kb N (default 60)
#
# Default trees: /root/imm26/base (label "base": every .php/.sql > min-kb, plus the named files below) and
# /mnt/c/KenshiModding/components/STOBE/src (label "STOBE-src": every .cpp/.h > min-kb, plus the named files).
# Backups are skipped (.bak*, .token_optimization_backup*, vendor, debug).
#
# Map file name = <label>__<path with / replaced by __>.txt, e.g.
#   /root/imm26/codemap/base__lib__chat_helper_functions.php.txt, STOBE-src__main.cpp.txt
# Map line = "name  start  end  lines  kind" (whitespace separated, sorted by start line); kinds:
#   function, method, class/struct/interface/trait/enum/namespace, toplevel (PHP/C++ code outside any
#   function longer than 120 lines), section (banner comment, start=end), create_table / alter_table /
#   create_index / ... (SQL statements). First lines of a map hold "# file/size/lines/mtime", the
#   largest entries, and the sed hint. INDEX.txt lists file, bytes, lines, entries, largest entries, map.
# Heuristic parser (comment/string/heredoc/dollar-quote aware, brace matching); --verify proves each
# function range starts on its name and ends on a closing brace. Regenerate a map after editing a file
# (line numbers shift): bash codemap.sh <file>.
exec python3 - "$@" <<'PYEOF'
import os, re, sys, time, subprocess, tempfile, shutil, fnmatch

OUT_DEFAULT = '/root/imm26/codemap'
TREES = [  # (label, root, extensions, always-include relative paths)
    ('base', '/root/imm26/base', ('.php', '.sql'),
     ['lib/chat_helper_functions.php', 'processor/chat.php', 'lib/npc_conversation_context.php', 'data/schema.sql']),
    ('STOBE-src', '/mnt/c/KenshiModding/components/STOBE/src', ('.cpp', '.h', '.c', '.hpp'),
     ['main.cpp', 'Context.cpp', 'ChatBox.cpp', 'Functions.cpp']),
]
SKIP_DIR = {'vendor', 'debug', '.git', 'node_modules', '__pycache__'}
SKIP_FILE_PAT = ('*.bak*', '*.orig', '*.old', '*~')
TOPLEVEL_MIN = 120


# ---------------------------------------------------------------- masking
def mask_php(s):
    """Replace comments, strings, heredocs and non-PHP html with spaces (newlines kept)."""
    n = len(s); out = list(s); i = 0; in_php = False
    def blank(a, b):
        for k in range(a, b):
            if out[k] != '\n': out[k] = ' '
    while i < n:
        if not in_php:
            j = s.find('<?', i)
            if j < 0:
                blank(i, n); break
            blank(i, j)
            if s.startswith('<?php', j): k = j + 5
            elif s.startswith('<?=', j): k = j + 3
            else: k = j + 2
            blank(j, k); i = k; in_php = True; continue
        c = s[i]
        if c == '?' and s.startswith('?>', i):
            blank(i, i + 2); i += 2; in_php = False; continue
        if c == '/' and s.startswith('//', i) or c == '#' and not s.startswith('#[', i):
            j = i
            while j < n and s[j] != '\n' and not s.startswith('?>', j): j += 1
            blank(i, j); i = j; continue
        if c == '/' and s.startswith('/*', i):
            j = s.find('*/', i + 2); j = n if j < 0 else j + 2
            blank(i, j); i = j; continue
        if c == "'" or c == '"':
            j = i + 1
            while j < n and s[j] != c:
                j += 2 if s[j] == '\\' else 1
            j = min(j + 1, n); blank(i + 1, j - 1); i = j; continue
        if c == '<' and s.startswith('<<<', i):
            m = re.compile(r'<<<[ \t]*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\1[ \t]*\r?\n').match(s, i)
            if m:
                end = re.compile(r'^[ \t]*' + m.group(2) + r'\b', re.M).search(s, m.end())
                j = end.end() if end else n
                blank(m.end(), j); i = j; continue
        i += 1
    return ''.join(out)


def mask_cpp(s):
    n = len(s); out = list(s); i = 0; bol = True
    def blank(a, b):
        for k in range(a, b):
            if out[k] != '\n': out[k] = ' '
    while i < n:
        c = s[i]
        if c == '\n': bol = True; i += 1; continue
        if bol and c in ' \t': i += 1; continue
        if bol and c == '#':  # preprocessor directive incl. continuations (comments inside are rare)
            j = i
            while True:
                e = s.find('\n', j)
                if e < 0: e = n; break
                if s[e - 1] == '\\' or (s[e - 1] == '\r' and e > 1 and s[e - 2] == '\\'): j = e + 1; continue
                break
            blank(i, e); i = e; continue
        bol = False
        if c == '/' and s.startswith('//', i):
            j = s.find('\n', i); j = n if j < 0 else j
            blank(i, j); i = j; continue
        if c == '/' and s.startswith('/*', i):
            j = s.find('*/', i + 2); j = n if j < 0 else j + 2
            blank(i, j); i = j; continue
        if c == 'R' and s.startswith('R"', i) and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == '_')):
            m = re.compile(r'R"([^()\\ ]{0,16})\(').match(s, i)
            if m:
                end = s.find(')' + m.group(1) + '"', m.end())
                j = n if end < 0 else end + len(m.group(1)) + 2
                blank(i, j); i = j; continue
        if c == '"' or c == "'":
            j = i + 1
            while j < n and s[j] != c and s[j] != '\n':
                j += 2 if s[j] == '\\' else 1
            j = min(j + 1, n); blank(i + 1, j - 1); i = j; continue
        i += 1
    return ''.join(out)


def mask_sql(s):
    n = len(s); out = list(s); i = 0
    def blank(a, b):
        for k in range(a, b):
            if out[k] != '\n': out[k] = ' '
    dq = re.compile(r'\$([A-Za-z_]*)\$')
    while i < n:
        c = s[i]
        if c == '-' and s.startswith('--', i):
            j = s.find('\n', i); j = n if j < 0 else j
            blank(i, j); i = j; continue
        if c == '/' and s.startswith('/*', i):
            j = s.find('*/', i + 2); j = n if j < 0 else j + 2
            blank(i, j); i = j; continue
        if c == "'":
            j = i + 1
            while j < n:
                if s[j] == "'":
                    if j + 1 < n and s[j + 1] == "'": j += 2; continue
                    break
                j += 2 if s[j] == '\\' and False else 1
            j = min(j + 1, n); blank(i + 1, j - 1); i = j; continue
        if c == '$':
            m = dq.match(s, i)
            if m:
                e = s.find(m.group(0), m.end()); e = n if e < 0 else e + len(m.group(0))
                blank(m.end(), e - len(m.group(0)) if e < n else e); i = e; continue
        i += 1
    return ''.join(out)


# ---------------------------------------------------------------- helpers
def line_starts(s):
    ls = [0]
    for m in re.finditer('\n', s): ls.append(m.end())
    return ls

def lineno(ls, pos):
    import bisect
    return bisect.bisect_right(ls, pos)  # 1-based

def match_brace(m, i):
    """m[i] == '{' -> index of matching '}' (or -1)."""
    d = 0; n = len(m)
    while i < n:
        c = m[i]
        if c == '{': d += 1
        elif c == '}':
            d -= 1
            if d == 0: return i
        i += 1
    return -1


def add(entries, name, kind, a, b):
    entries.append((name, a, b, b - a + 1, kind))


def add_gaps(entries, total_lines, src_lines):
    """top-level code (outside any function/class) longer than TOPLEVEL_MIN lines."""
    cover = [False] * (total_lines + 2)
    for name, a, b, ln, kind in entries:
        if kind in ('class', 'interface', 'trait', 'enum', 'struct', 'namespace', 'section', 'union', 'block', 'block1'):
            continue
        for k in range(a, min(b, total_lines) + 1): cover[k] = True
    a = None
    for k in range(1, total_lines + 2):
        free = k <= total_lines and not cover[k]
        if free and a is None: a = k
        if not free and a is not None:
            b = k - 1
            while a <= b and not src_lines[a - 1].strip(): a += 1
            while b >= a and not src_lines[b - 1].strip(): b -= 1
            if b - a + 1 > TOPLEVEL_MIN: add(entries, 'toplevel_%d_%d' % (a, b), 'toplevel', a, b)
            a = None


BANNER = re.compile(r'^\s*(?://|#|/\*+)\s*(?:[=\-#*~]{3,}\s*)?([A-Za-z0-9].{3,100}?)\s*(?:[=\-#*~]{3,}\s*)?(?:\*/)?\s*$')
BANNER_STRICT = re.compile(r'^\s*(?://|#|/\*)[ \t]*([=\-#*~]{4,}|SECTION\b|Section\b|PART\b|STEP\b)')


def banners(src_lines, entries):
    """banner comments: lines like '// ===== X =====' or '// ---- X ----' (title on same or next line)."""
    for i, l in enumerate(src_lines):
        m = re.match(r'^\s*(?://|#|/\*+)\s*[=\-#*~]{4,}\s*(.*?)\s*[=\-#*~]*\s*(?:\*/)?\s*$', l)
        if not m: continue
        title = m.group(1).strip()
        if not title and i + 1 < len(src_lines):
            t = re.match(r'^\s*(?://|#|\*)\s*(.+?)\s*$', src_lines[i + 1])
            if t and not re.match(r'^[=\-#*~]{4,}$', t.group(1)): title = t.group(1)
        if title and not re.match(r'^[=\-#*~ ]+$', title):
            add(entries, re.sub(r'\s+', '_', title)[:70], 'section', i + 1, i + 1)


# ---------------------------------------------------------------- PHP
PHP_FUNC = re.compile(r'(?<![A-Za-z0-9_$>:])function[ \t\r\n]+&?[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t\r\n]*\(')
PHP_CLASS = re.compile(r'(?<![A-Za-z0-9_$>:])(?:(?:abstract|final|readonly)[ \t]+)*(class|interface|trait|enum)[ \t\r\n]+([A-Za-z_][A-Za-z0-9_]*)')

def map_php(src):
    m = mask_php(src); ls = line_starts(src); entries = []
    classes = []  # (name, start_idx, end_idx)
    openers = set()
    for c in PHP_CLASS.finditer(m):
        b = m.find('{', c.end())
        if b < 0: continue
        e = match_brace(m, b)
        if e < 0: continue
        classes.append((c.group(2), c.start(), e)); openers.add(b)
        add(entries, c.group(2), c.group(1), lineno(ls, c.start()), lineno(ls, e))
    for f in PHP_FUNC.finditer(m):
        # params end: first matching ')' then scan to '{' or ';'
        i = f.end(); d = 1; n = len(m)
        while i < n and d:
            if m[i] == '(': d += 1
            elif m[i] == ')': d -= 1
            i += 1
        j = i
        while j < n and m[j] not in '{;': j += 1
        if j >= n: continue
        e = j if m[j] == ';' else match_brace(m, j)
        if e < 0: continue
        if m[j] == '{': openers.add(j)
        name = f.group(1); kind = 'function'
        for cn, cs, ce in classes:
            if cs < f.start() < ce:
                name = cn + '::' + name; kind = 'method'
        add(entries, name, kind, lineno(ls, f.start()), lineno(ls, e))
    src_lines = src.split('\n')
    php_blocks(m, ls, openers, entries)
    add_gaps(entries, len(src_lines), src_lines); banners(src_lines, entries)
    return entries


BLOCK_MIN = 25

def php_blocks(m, ls, openers, entries):
    """top-level (depth 0) and depth-1 brace blocks outside functions/classes: if/foreach/try ... (pages, scripts)."""
    n = len(m)
    def walk(i, hdr, depth):
        while i < n:
            c = m[i]
            if c == ';': hdr = i + 1
            elif c == '}': return i
            elif c == '{':
                end = match_brace(m, i)
                if end < 0: return n
                if i not in openers and not any(i < o < end for o in openers):  # skip function_exists() wrappers
                    raw = m[hdr:i]
                    text = re.sub(r'\s+', ' ', raw).strip()
                    a = lineno(ls, hdr + (len(raw) - len(raw.lstrip())))
                    b = lineno(ls, end)
                    if b - a + 1 >= BLOCK_MIN:
                        kind = 'block' if depth == 0 else 'block1'
                        add(entries, kind + '_' + re.sub(r'[^A-Za-z0-9_$>.:-]+', '_', text)[:60].strip('_'), kind, a, b)
                    if depth == 0: walk(i + 1, i + 1, 1)
                i = end; hdr = end + 1
            i += 1
        return i
    walk(0, 0, 0)


# ---------------------------------------------------------------- C++
NOT_FUNC = {'if', 'for', 'while', 'switch', 'catch', 'else', 'do', 'return', 'sizeof'}
KW_SCOPE = re.compile(r'^(?:template\s*<[^>]*>\s*)?(?:typedef\s+)?(namespace|class|struct|union|enum(?:\s+class|\s+struct)?)\b\s*([A-Za-z_][A-Za-z0-9_:]*)?')

def map_cpp(src):
    m = mask_cpp(src); ls = line_starts(src); entries = []; n = len(m)
    stack = []  # (kind, name, open_idx, entry_idx or None)
    hdr_start = 0; i = 0
    in_func = 0  # depth of function bodies being skipped
    while i < n:
        c = m[i]
        if in_func:
            if c == '{': in_func += 1
            elif c == '}':
                in_func -= 1
                if in_func == 0: hdr_start = i + 1
            i += 1; continue
        if c == ';':
            hdr_start = i + 1
        elif c == '}':
            if stack:
                kind, name, oi, ei = stack.pop()
                if ei is not None:
                    nm, a, _, _, k = entries[ei]
                    entries[ei] = (nm, a, lineno(ls, i), lineno(ls, i) - a + 1, k)
            hdr_start = i + 1
        elif c == '{':
            header = m[hdr_start:i]
            hs = re.sub(r'__declspec\s*\([^)]*\)|__attribute__\s*\(\([^)]*\)\)|alignas\s*\([^)]*\)', ' ', header).strip()
            first = hdr_start + (len(header) - len(header.lstrip()))
            sm = KW_SCOPE.match(re.sub(r'\s+', ' ', hs)) if '(' not in hs.split('{')[0] or hs.startswith('namespace') else None
            if sm and sm.group(1) and (sm.group(2) or sm.group(1) == 'namespace') and '=' not in hs:
                kind = sm.group(1).split()[0]
                name = sm.group(2) or 'anonymous'
                if kind == 'namespace' or sm.group(1).startswith(('class', 'struct', 'union', 'enum')):
                    e = None
                    if kind != 'enum':
                        add(entries, name, kind, lineno(ls, first), lineno(ls, i)); e = len(entries) - 1
                    stack.append((kind, name, i, e))
                    if kind == 'enum':  # skip body
                        end = match_brace(m, i); i = end if end > 0 else i
                        stack.pop(); hdr_start = i + 1
                    else: hdr_start = i + 1
                    i += 1; continue
            if hs.startswith('extern') and '(' not in hs:
                stack.append(('extern', 'extern', i, None)); hdr_start = i + 1; i += 1; continue
            fm = None
            if '(' in hs and '=' not in hs.split('(')[0]:
                fm = re.search(r'((?:~\s*)?[A-Za-z_][A-Za-z0-9_]*(?:\s*::\s*(?:~\s*)?[A-Za-z_][A-Za-z0-9_]*)*|operator\s*[^\s(]+(?:\s*\(\s*\))?)\s*\(', hs)
            ok = fm is not None
            if ok and re.search(r'\)\s*(?:const\s*)?(?:noexcept\s*)?:(?!:)', hs):
                k = i - 1
                while k > 0 and m[k].isspace(): k -= 1
                if m[k] not in ')}':  # brace-init inside a ctor initializer list, not the body
                    end = match_brace(m, i)
                    if end < 0: i += 1; continue
                    i = end + 1; continue
            if ok:
                nm = re.sub(r'\s+', '', fm.group(1))
                if nm.split('::')[-1] in NOT_FUNC: ok = False
            if ok:
                end = match_brace(m, i)
                if end < 0: i += 1; continue
                cls = [s[1] for s in stack if s[0] in ('class', 'struct', 'union')]
                full = nm if ('::' in nm or not cls) else cls[-1] + '::' + nm
                kind = 'method' if '::' in full else 'function'
                add(entries, full, kind, lineno(ls, first), lineno(ls, end))
                in_func = 1
                hdr_start = i + 1; i += 1; continue
            # something else (initializer, array, lambda at file scope): skip balanced
            end = match_brace(m, i)
            if end < 0: i += 1; continue
            i = end + 1; hdr_start = i; continue
        i += 1
    for kind, name, oi, ei in stack:  # unclosed (unbalanced #if): drop
        pass
    src_lines = src.split('\n')
    entries = [e for e in entries if e[2] >= e[1]]
    add_gaps(entries, len(src_lines), src_lines); banners(src_lines, entries)
    return entries


# ---------------------------------------------------------------- SQL
SQL_STMT_HEAD = re.compile(r'\s*(CREATE\s+(?:OR\s+REPLACE\s+)?(?:UNIQUE\s+)?(?:TEMP(?:ORARY)?\s+|UNLOGGED\s+)?(TABLE|INDEX|FUNCTION|VIEW|MATERIALIZED\s+VIEW|TRIGGER|SEQUENCE|TYPE|EXTENSION|SCHEMA|DOMAIN)|ALTER\s+(TABLE|SEQUENCE|FUNCTION|TYPE)|INSERT\s+INTO|DROP\s+(TABLE|INDEX|FUNCTION|VIEW)|UPDATE|DELETE\s+FROM)\s+(?:IF\s+(?:NOT\s+)?EXISTS\s+)?(?:ONLY\s+)?("?[A-Za-z_][\w.\"]*)', re.I)

def map_sql(src):
    m = mask_sql(src); ls = line_starts(src); entries = []
    pos = 0; n = len(m)
    while pos < n:
        e = m.find(';', pos)
        if e < 0: e = n - 1
        stmt = m[pos:e + 1]
        h = SQL_STMT_HEAD.match(stmt)
        if h:
            start = pos + (len(stmt) - len(stmt.lstrip()))
            word = re.sub(r'\s+', '_', h.group(1).lower())
            kind = re.sub(r'^(create_(or_replace_)?(unique_)?(temp(orary)?_|unlogged_)?)', 'create_', word)
            kind = kind if kind.startswith('create_') else ('alter_' + h.group(3).lower() if h.group(3) else
                   ('drop_' + h.group(4).lower() if h.group(4) else word.split('_')[0] + ('_into' if 'insert' in word else '')))
            name = h.group(5).strip('"')
            if kind == 'create_index':
                on = re.search(r'\bON\s+(?:ONLY\s+)?("?[\w.\"]+)', stmt, re.I)
                name = name + ('@' + on.group(1).strip('"') if on else '')
            add(entries, name, kind, lineno(ls, start), lineno(ls, e))
        pos = e + 1
    src_lines = src.split('\n')
    banners(src_lines, entries)
    # drop huge noise: keep sections only when few
    return entries


def map_text(path, src):
    ext = os.path.splitext(path)[1].lower()
    if ext == '.php': return map_php(src), 'php'
    if ext == '.sql': return map_sql(src), 'sql'
    return map_cpp(src), 'cpp'


# ---------------------------------------------------------------- output
def map_name(label, rel):
    return label + '__' + rel.replace('\\', '/').replace('/', '__') + '.txt'

def write_map(path, label, rel, outdir):
    with open(path, 'rb') as f: raw = f.read()
    src = raw.decode('utf-8', 'replace').replace('\r\n', '\n').replace('\r', '\n')
    # line numbers: sed counts \n only; CRLF -> same count; lone CR files unsupported (treated as \n)
    entries, lang = map_text(path, src)
    entries.sort(key=lambda e: (e[1], -e[2]))
    nlines = src.count('\n') + (0 if src.endswith('\n') or not src else 1)
    st = os.stat(path)
    big = sorted([e for e in entries if e[4] in ('function', 'method', 'create_table', 'create_function')],
                 key=lambda e: -e[3])[:8]
    os.makedirs(outdir, exist_ok=True)
    mp = os.path.join(outdir, map_name(label, rel))
    with open(mp, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# file: %s\n# size: %d bytes   lines: %d   mtime: %d   mapped: %s   lang: %s   entries: %d\n'
                % (path, st.st_size, nlines, int(st.st_mtime), time.strftime('%Y-%m-%d %H:%M:%S'), lang, len(entries)))
        f.write('# columns: name start end lines kind   | read one entry: sed -n START,ENDp %s\n' % path)
        f.write('# regenerate after editing the file (line numbers shift): bash /mnt/c/KenshiModding/tools/automation/codemap.sh %s\n' % path)
        f.write('# largest: ' + '; '.join('%s %d-%d (%d)' % (e[0], e[1], e[2], e[3]) for e in big) + '\n')
        w = max([len(e[0]) for e in entries] + [10]); w = min(w, 80)
        for name, a, b, ln, kind in entries:
            f.write('%-*s %7d %7d %6d %s\n' % (w, name, a, b, ln, kind))
    return mp, st.st_size, nlines, len(entries), big


def collect(trees, min_kb):
    files = []
    for label, root, exts, always in trees:
        if not os.path.isdir(root): print('skip (missing): ' + root); continue
        seen = set()
        for rel in always:
            p = os.path.join(root, rel)
            if os.path.isfile(p): files.append((label, root, rel, p)); seen.add(rel)
        for d, dirs, fs in os.walk(root):
            dirs[:] = [x for x in dirs if x not in SKIP_DIR and not x.startswith('.token_optimization_backup')]
            for fn in fs:
                if not fn.lower().endswith(tuple(e for e in exts if e != '.sql')) or any(fnmatch.fnmatch(fn, pat) for pat in SKIP_FILE_PAT): continue
                p = os.path.join(d, fn); rel = os.path.relpath(p, root).replace('\\', '/')
                if rel not in seen and os.path.getsize(p) > min_kb * 1024:
                    files.append((label, root, rel, p)); seen.add(rel)
    return files


def label_for(path):
    ap = os.path.abspath(path)
    for label, root, exts, always in TREES:
        r = os.path.abspath(root)
        if ap.startswith(r + os.sep): return label, os.path.relpath(ap, r).replace('\\', '/')
    m = re.match(r'/root/imm26/([^/]+)/(.+)$', ap)  # work-package copy made by mkwp.sh -> label = wp name
    if m: return m.group(1), m.group(2)
    parent = os.path.basename(os.path.dirname(ap)) or 'misc'
    return parent, os.path.basename(ap)


def build_index(outdir, rows):
    with open(os.path.join(outdir, 'INDEX.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('# code map index, generated %s (agents: grep -n <name> %s/<map>; sed -n a,bp <file>)\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), outdir))
        f.write('# columns: file | bytes | lines | entries | map | largest functions\n')
        for p, label, rel, mp, size, nl, ne, big in rows:
            f.write('%s | %d | %d | %d | %s | %s\n' % (p, size, nl, ne, os.path.basename(mp),
                    '; '.join('%s %d-%d' % (e[0], e[1], e[2]) for e in big[:3])))


def read_index_rows(outdir):
    rows = []
    for fn in sorted(os.listdir(outdir)):
        if fn == 'INDEX.txt' or not fn.endswith('.txt'): continue
        try:
            hl = open(os.path.join(outdir, fn), encoding='utf-8').read().split('\n', 6)
            p = hl[0].split(': ', 1)[1]; mt = re.search(r'size: (\d+) bytes\s+lines: (\d+)', hl[1]); ent = re.search(r'entries: (\d+)', hl[1])
            lg = hl[3].replace('# largest: ', '')
            rows.append((p, '', '', os.path.join(outdir, fn), int(mt.group(1)), int(mt.group(2)), int(ent.group(1)),
                         [(x.split(' ')[0], int(x.split(' ')[1].split('-')[0]), int(x.split(' ')[1].split('-')[1].split(' ')[0]), 0, '') for x in lg.split('; ') if x and len(x.split(' ')) > 1]))
        except Exception: pass
    return rows


def check(outdir):
    stale = 0
    for fn in sorted(os.listdir(outdir)) if os.path.isdir(outdir) else []:
        if fn == 'INDEX.txt': continue
        hl = open(os.path.join(outdir, fn), encoding='utf-8').read().split('\n', 3)
        p = hl[0].split(': ', 1)[1]; mm = re.search(r'size: (\d+) bytes.*mtime: (\d+)', hl[1])
        if not os.path.isfile(p): print('MISSING-SOURCE %s' % p); stale += 1; continue
        st = os.stat(p)
        if st.st_size != int(mm.group(1)) or int(st.st_mtime) != int(mm.group(2)):
            print('STALE %s (rerun: bash codemap.sh %s)' % (fn, p)); stale += 1
    print('check: %d stale map(s)' % stale)
    return stale


def verify(outdir, only=None):
    """every function/method/class entry must start on a line containing its short name and end on a line
    containing '}' (PHP/C++) / ';' (SQL); returns number of problems."""
    bad = total = 0
    for fn in sorted(os.listdir(outdir)):
        if fn == 'INDEX.txt' or not fn.endswith('.txt'): continue
        lines = open(os.path.join(outdir, fn), encoding='utf-8').read().split('\n')
        p = lines[0].split(': ', 1)[1]
        if only and p not in only: continue
        src = open(p, 'rb').read().decode('utf-8', 'replace').replace('\r\n', '\n').split('\n')
        for l in lines[5:]:
            if not l.strip(): continue
            parts = l.split()
            name, a, b, ln, kind = parts[0], int(parts[1]), int(parts[2]), int(parts[3]), parts[4]
            if kind in ('toplevel', 'section', 'block', 'block1') or name == 'anonymous': continue
            total += 1
            short = re.split(r'::|@|\.', name)[-1] if kind not in ('create_index',) else name.split('@')[0]
            short = name.split('@')[0].split('::')[-1].split('.')[-1] if kind.startswith(('create', 'alter', 'insert', 'drop')) else short
            first = src[a - 1] if a - 1 < len(src) else ''
            last = src[b - 1] if b - 1 < len(src) else ''
            endtok = ';' if (kind.startswith(('create', 'alter', 'insert', 'drop', 'update', 'delete'))) else '}'
            joined = ' '.join(src[a - 1:min(a + 40, b)])
            if short.lstrip('~') not in joined or (endtok not in last and not (endtok == '}' and last.rstrip().endswith(';'))):
                bad += 1
                if bad <= 10: print('VERIFY-FAIL %s %s %d-%d first=%r last=%r' % (fn, name, a, b, first[:70], last[:70]))
    print('verify: %d entries checked, %d problem(s)' % (total, bad))
    return bad


def selftest():
    d = tempfile.mkdtemp(prefix='codemap-selftest-')
    fails = []
    def expect(cond, msg):
        if not cond: fails.append(msg)
    try:
        php = '''<html>
<?php
// function fake() { in a comment
/* function fake2() { } */
$s = "function fake3() { {";
function alpha($a, $b = array(1, 2)) {
    $x = '}';
    $h = <<<EOT
function nope() { }
EOT;
    if ($a) { return 1; }
    return $x;
}
class Foo extends Bar {
    public function beta(int $x): string {
        $f = function ($y) { return $y; };
        return "{$x}";
    }
    abstract protected function gamma();
    private static function &delta() { return $this; }
}
// ======= SECTION ONE =======
function epsilon() {}
?>
trailing html { function nope2() {
'''
        ents = {e[0]: e for e in map_php(php)}
        expect('alpha' in ents and ents['alpha'][1:3] == (6, 13), 'php alpha range %s' % (ents.get('alpha'),))
        expect('Foo' in ents and ents['Foo'][4] == 'class' and ents['Foo'][1:3] == (14, 21), 'php class Foo %s' % (ents.get('Foo'),))
        expect('Foo::beta' in ents and ents['Foo::beta'][1:3] == (15, 18), 'php method beta %s' % (ents.get('Foo::beta'),))
        expect('Foo::gamma' in ents and ents['Foo::gamma'][1] == ents['Foo::gamma'][2], 'php abstract gamma')
        expect('Foo::delta' in ents and ents['Foo::delta'][4] == 'method', 'php delta by-ref')
        expect('epsilon' in ents and ents['epsilon'][1:3] == (23, 23), 'php epsilon %s' % (ents.get('epsilon'),))
        expect(not any(k.startswith(('fake', 'nope')) for k in ents), 'php false positives %s' % [k for k in ents if k.startswith(('fake', 'nope'))])
        expect(any(e[4] == 'section' for e in map_php(php)), 'php section banner')
        cpp = '''#include <x>
#define M(a) { a }
namespace ns {
struct S { int a; void inl() { if (a) { a = 1; } } };
static const char* t = "}{";
int Foo::bar(int a) const {
    for (;;) { if (a) { break; } }
    char c = '}';
    return R"x(})x"[0];
}
Foo::Foo(int a) : m(a), v{1,2} {
}
Foo::~Foo() {}
int arr[] = { 1, 2, 3 };
static int lam = [](int q){ return q; }(1);
}
void top() { }
class K : public B { public: int m() { return 1; } };
'''
        ce = {e[0]: e for e in map_cpp(cpp)}
        expect('Foo::bar' in ce and ce['Foo::bar'][1:3] == (6, 10), 'cpp Foo::bar %s' % (ce.get('Foo::bar'),))
        expect('Foo::Foo' in ce and ce['Foo::Foo'][1:3] == (11, 12), 'cpp ctor %s' % (ce.get('Foo::Foo'),))
        expect('Foo::~Foo' in ce, 'cpp dtor %s' % list(ce))
        expect('S::inl' in ce and ce['S::inl'][1] == 4, 'cpp inline method %s' % (ce.get('S::inl'),))
        expect('top' in ce and ce['top'][1:3] == (17, 17), 'cpp top %s' % (ce.get('top'),))
        expect('K::m' in ce, 'cpp K::m')
        expect('ns' in ce and ce['ns'][4] == 'namespace', 'cpp namespace')
        sql = '''-- c
CREATE TABLE public.foo (
    id integer,
    note text DEFAULT 'a;b'
);
CREATE INDEX idx_foo ON public.foo USING btree (id);
ALTER TABLE ONLY public.foo
    ADD CONSTRAINT x PRIMARY KEY (id);
CREATE FUNCTION f() RETURNS void AS $$ BEGIN PERFORM 1; END; $$ LANGUAGE plpgsql;
'''
        se = {e[0]: e for e in map_sql(sql)}
        expect(se.get('public.foo') and se['public.foo'][1:3] == (2, 5) or ('public.foo' in se), 'sql table')
        expect('idx_foo@public.foo' in se, 'sql index %s' % list(se))
        expect('f' in se and se['f'][1:3] == (9, 9), 'sql function %s' % (se.get('f'),))
        # end-to-end: write maps, check sed hint + stale detection
        sp = os.path.join(d, 'a.php'); open(sp, 'w').write(php.replace('trailing html { function nope2() {', ''))
        out = os.path.join(d, 'out')
        mp = write_map(sp, 'st', 'a.php', out)[0]
        txt = open(mp).read()
        expect('alpha' in txt and '# columns' in txt, 'map file content')
        expect(check(out) == 0, 'fresh map not stale')
        time.sleep(1.1); open(sp, 'a').write('\n'); os.utime(sp, None)
        expect(check(out) == 1, 'stale detection')
        write_map(sp, 'st', 'a.php', out)
        expect(verify(out) == 0, 'verify synthetic')
    finally:
        shutil.rmtree(d, ignore_errors=True)
    for f in fails: print('SELFTEST-FAIL ' + f)
    print('selftest: %s (%d failure(s))' % ('PASS' if not fails else 'FAIL', len(fails)))
    return len(fails)


def main(argv):
    outdir = OUT_DEFAULT; min_kb = 60; files = []; mode = 'map'; real = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--out': outdir = argv[i + 1]; i += 1
        elif a == '--min-kb': min_kb = int(argv[i + 1]); i += 1
        elif a == '--check': mode = 'check'
        elif a == '--verify': mode = 'verify'
        elif a == '--selftest': mode = 'selftest'
        elif a in ('-h', '--help'): print('see the header of tools/automation/codemap.sh'); return 0
        else: files.append(a)
        i += 1
    if mode == 'selftest':
        r = selftest()
        if r == 0:  # real-file proof: map defaults into a temp dir and verify every entry
            tmp = tempfile.mkdtemp(prefix='codemap-real-')
            try:
                fl = collect(TREES, min_kb); rows = []
                for label, root, rel, p in fl: write_map(p, label, rel, tmp)
                r += 1 if verify(tmp) else 0
                print('selftest real files: %d maps' % len(fl))
            finally: shutil.rmtree(tmp, ignore_errors=True)
            print('selftest overall: %s' % ('PASS' if r == 0 else 'FAIL'))
        return 1 if r else 0
    if mode == 'check': return 1 if check(outdir) else 0
    if files:
        fl = []
        for f in files:
            p = os.path.abspath(f); label, rel = label_for(p)
            fl.append((label, None, rel, p))
    else:
        fl = collect(TREES, min_kb)
    os.makedirs(outdir, exist_ok=True)
    rows = []
    for label, root, rel, p in fl:
        mp, size, nl, ne, big = write_map(p, label, rel, outdir)
        rows.append((p, label, rel, mp, size, nl, ne, big))
        print('%-60s %8d B %6d lines %5d entries -> %s' % (rel, size, nl, ne, os.path.basename(mp)))
    build_index(outdir, read_index_rows_full(outdir) if files else rows)
    if mode == 'verify': return 1 if verify(outdir) else 0
    return 0


def read_index_rows_full(outdir):
    return read_index_rows(outdir)


sys.exit(main(sys.argv[1:]))
PYEOF
