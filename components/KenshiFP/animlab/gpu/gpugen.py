#!/usr/bin/env python3
"""gpugen.py -- mechanical CPU/GPU split of the animlab adapter translation unit (gpu-lab 2026-10-11).

The game source stays the single source of truth: build.sh --preprocess writes the adapter TU (kfpvm_replay.c +
the shipped kfp_viewmodel.inc, gcc -E, same -D flags). This script only re-arranges that TU, it never edits game logic:

  gpugen.py <tu.i> <outdir>
    <outdir>/cpu.c    the same TU for gcc (WSL): function-local statics hoisted to file scope (renamed, same lifetime and
                      value), malloc/calloc/realloc tracked, plus the snapshot writer/reader (al_snap_*) over every mutable
                      global. Built with the same gcc flags it must give byte-identical replay output (selftest).
    <outdir>/dev.c    the device TU for clang --target=nvptx64 (Windows): system-header items dropped (dev_prelude.h gives
                      libc/libm), every mutable global becomes a field of `struct KSt` (one per GPU thread), every use in a
                      function body is rewritten to (KST->name); constants stay shared globals.
    <outdir>/globals.tsv   index, name, kind (state|const) of every global, same order as the snapshot table.
    <outdir>/funcs.tsv     index, name of every function definition (function-pointer relocation table).

Pointers inside the state are relocated by the snapshot format (al_snap_* writes (kind, target, offset) for every
pointer word: global, function, read-only string, tracked heap block)."""
import re, sys, os

TOK = re.compile(r'''
 (?P<ws>[ \t\r\f\v]+) | (?P<nl>\n) |
 (?P<str>L?"(?:[^"\\\n]|\\.)*") | (?P<chr>L?'(?:[^'\\\n]|\\.)*') |
 (?P<num>\.?[0-9](?:[eEpP][+-]|[0-9a-zA-Z_.])*) |
 (?P<id>[A-Za-z_][A-Za-z_0-9]*) |
 (?P<p><<=|>>=|\.\.\.|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||\*=|/=|%=|\+=|-=|&=|\^=|\|=|\#\#|[\[\](){}.&*+\-~!/%<>^|?:;=,\#])
''', re.X)
KW = set('''auto break case char const continue default do double else enum extern float for goto if inline int long register
restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Bool _Complex
__attribute__ __extension__ __restrict __inline __inline__ __asm__ asm __typeof__ typeof _Alignof __alignof__ _Noreturn
__builtin_va_list _Static_assert __int128 _Float128 __signed__ __const'''.split())
SPEC = set('''const volatile static extern inline register unsigned signed int float double char short long void _Bool
__extension__ __inline __inline__ _Noreturn __restrict __signed__ __const'''.split())


class T:
    __slots__ = ('k', 's', 'f', 'l')
    def __init__(s, k, v, f, l): s.k, s.s, s.f, s.l = k, v, f, l
    def __repr__(s): return s.s


def lex(text):
    toks = []; fname = '?'; line = 1
    for raw in text.split('\n'):
        m = re.match(r'#\s*(\d+)\s+"([^"]*)"', raw)
        if m: line = int(m.group(1)); fname = m.group(2); continue
        if raw.startswith('#'):   # #pragma etc: keep as one token
            toks.append(T('pp', raw, fname, line)); line += 1; continue
        pos = 0
        while pos < len(raw):
            m = TOK.match(raw, pos)
            if not m: raise SystemExit('lex error %s:%d: %r' % (fname, line, raw[pos:pos + 40]))
            pos = m.end(); k = m.lastgroup
            if k in ('ws', 'nl'): continue
            toks.append(T(k, m.group(k), fname, line))
        line += 1
    return toks


def is_sys(f): return f.startswith('/usr/') or f.startswith('<')


class Item:
    def __init__(s, toks): s.t = toks; s.kind = None; s.names = []; s.sys = is_sys(toks[0].f)


def split_items(toks):
    items = []; cur = []; depth = 0; fdef = False
    for i, t in enumerate(toks):
        if t.k == 'pp' and depth == 0 and not cur: items.append(Item([t])); items[-1].kind = 'pp'; continue
        cur.append(t)
        if t.s in '([{':
            if t.s == '{' and depth == 0:
                prev = cur[-2].s if len(cur) > 1 else ''
                has_eq = any(x.s == '=' for x in cur[:-1])
                # function definition: `) {` or `) __attribute__((..)) {` with no `=` before
                fdef = not has_eq and (prev == ')') and not any(x.s in ('struct', 'union', 'enum') and cur.index(x) == len(cur) - 3 for x in cur)
            depth += 1
        elif t.s in ')]}':
            depth -= 1
            if t.s == '}' and depth == 0 and fdef:
                it = Item(cur); it.kind = 'func'; items.append(it); cur = []; fdef = False
        elif t.s == ';' and depth == 0:
            items.append(Item(cur)); cur = []
    if cur: raise SystemExit('trailing tokens: %r' % cur[:20])
    return items


def depth0_split(toks, sep=','):
    out = [[]]; d = 0
    for t in toks:
        if t.s in '([{': d += 1
        elif t.s in ')]}': d -= 1
        if t.s == sep and d == 0: out.append([]); continue
        out[-1].append(t)
    return out


def func_name(it):
    # name = identifier before the parameter list's '(' that precedes the body '{'
    body = next(i for i, t in enumerate(it.t) if t.s == '{')
    d = 0
    for i in range(body - 1, -1, -1):
        s = it.t[i].s
        if s == ')': d += 1
        elif s == '(':
            d -= 1
            if d == 0 and i > 0 and it.t[i - 1].k == 'id' and it.t[i - 1].s not in ('__attribute__',):
                return it.t[i - 1].s, body
    raise SystemExit('no function name at %s:%d' % (it.t[0].f, it.t[0].l))


def classify(items, typedefs):
    for it in items:
        if it.kind: continue
        ss = [t.s for t in it.t]
        if 'typedef' in ss[:ss.index('{') if '{' in ss else len(ss)] or (ss and ss[0] == 'typedef'):
            it.kind = 'type'
            # typedef name(s): last identifier of each declarator
            _, rest = split_specs([t for t in it.t if t.s != 'typedef'], typedefs)
            for dcl in depth0_split(rest):
                n = decl_name(dcl)
                if n: typedefs.add(n)
            continue
        if ss[0] in ('_Static_assert',): it.kind = 'type'; continue
        specs, rest = split_specs(it.t, typedefs)
        if not rest: it.kind = 'type'; continue          # struct X {...}; enum {...};
        decls = depth0_split(rest)
        kinds = set(); it.decls = []
        for dcl in decls:
            eq = next((i for i, t in enumerate(dcl) if t.s == '=' and depth_at(dcl, i) == 0), None)
            dd = dcl if eq is None else dcl[:eq]
            n, isfn = decl_name_fn(dd)
            if n is None: raise SystemExit('no declarator name at %s:%d %r' % (it.t[0].f, it.t[0].l, dcl[:12]))
            it.decls.append((n, dd, dcl[eq + 1:] if eq is not None else None, isfn))
            kinds.add('proto' if isfn else 'var')
        if kinds == {'proto'}: it.kind = 'proto'
        elif kinds == {'var'}: it.kind = 'var'; it.specs = specs
        else: raise SystemExit('mixed proto/var at %s:%d' % (it.t[0].f, it.t[0].l))


def depth_at(toks, idx):
    d = 0
    for t in toks[:idx]:
        if t.s in '([{': d += 1
        elif t.s in ')]}': d -= 1
    return d


def skip_braces_specs(toks):
    # for typedef items: drop everything up to and including a depth-0 {...} body
    if any(t.s == '{' for t in toks):
        d = 0; end = None
        for i, t in enumerate(toks):
            if t.s == '{': d += 1
            elif t.s == '}':
                d -= 1
                if d == 0: end = i
        return toks[end + 1:-1] if end is not None else toks[:-1]
    return toks[:-1]


def split_specs(toks, typedefs):
    """decl-specifiers (incl. struct/union/enum bodies, attributes) | init-declarator list (without the ';')"""
    i = 0; n = len(toks) - 1; seen_type = False
    while i < n:
        t = toks[i]
        if t.s in ('struct', 'union', 'enum'):
            i += 1
            if toks[i].k == 'id' and toks[i].s not in KW: i += 1
            while toks[i].s == '__attribute__': i = skip_paren(toks, i + 1)
            if toks[i].s == '{': i = skip_group(toks, i)
            seen_type = True; continue
        if t.s in ('__attribute__', '__typeof__', 'typeof', '_Alignas', '__declspec'):
            i = skip_paren(toks, i + 1); continue
        if t.s in SPEC or t.s == '__builtin_va_list':
            if t.s not in ('const', 'volatile', 'static', 'extern', 'inline', 'register', '__extension__', '__inline', '__inline__', '_Noreturn', '__restrict', '__const'):
                seen_type = True
            i += 1; continue
        if t.k == 'id' and t.s in typedefs and not seen_type:
            seen_type = True; i += 1; continue
        break
    return toks[:i], toks[i:n]


def skip_paren(toks, i):
    assert toks[i].s == '(', toks[i]
    return skip_group(toks, i)


def skip_group(toks, i):
    d = 0
    while True:
        if toks[i].s in '([{': d += 1
        elif toks[i].s in ')]}':
            d -= 1
            if d == 0: return i + 1
        i += 1


def decl_name(dcl):
    n, _ = decl_name_fn(dcl); return n


def decl_name_fn(dd):
    i = 0
    while i < len(dd):
        t = dd[i]
        if t.s == '__attribute__' or t.s == '__asm__' or t.s == 'asm':
            i = skip_paren(dd, i + 1); continue
        if t.k == 'id' and t.s not in KW:
            nxt = dd[i + 1].s if i + 1 < len(dd) else ''
            return t.s, nxt == '('
        if t.s == '[': i = skip_group(dd, i); continue
        i += 1
    return None, False


def is_const_obj(specs, dd, name):
    """the object itself is const (shared read-only on the GPU)"""
    ni = next(i for i, t in enumerate(dd) if t.s == name)
    stars = [i for i in range(ni) if dd[i].s == '*']
    if stars:
        last = stars[-1]
        return any(dd[j].s == 'const' for j in range(last + 1, ni))
    return any(t.s == 'const' for t in specs)


def text(toks, sub=None):
    out = []; line = None; f = None
    for i, t in enumerate(toks):
        s = sub(i, t) if sub else t.s
        if t.k == 'pp': out.append('\n' + s + '\n'); line = None; continue
        if (t.l, t.f) != (line, f):
            out.append('\n'); line, f = t.l, t.f
        out.append(s + ' ')
    return ''.join(out)


def hoist_local_statics(fit, fname, typedefs):
    """returns (hoisted decl token lists [(newname, toks)], body token list with renames)"""
    toks = fit.t; _, body = func_name(fit)
    hoisted = []; out = list(toks[:body]); i = body; ren = {}
    while i < len(toks):
        t = toks[i]
        prev = out[-1].s if out else ''
        if t.s == 'static' and prev in ('{', ';', '}', ')') and depth_at(toks, i) >= 1:
            j = i; d = 0
            while not (toks[j].s == ';' and d == 0):
                if toks[j].s in '([{': d += 1
                elif toks[j].s in ')]}': d -= 1
                j += 1
            decl = toks[i:j + 1]
            specs, rest = split_specs(decl, typedefs)
            newdecl = list(specs)
            for k, dcl in enumerate(depth0_split(rest)):
                n = decl_name(dcl); nn = '__ls_%s_%s' % (fname, n); ren[n] = nn
                if k: newdecl.append(T('p', ',', t.f, t.l))
                newdecl += [T('id', nn, x.f, x.l) if (x.k == 'id' and x.s == n) else x for x in dcl]
            newdecl.append(T('p', ';', t.f, t.l))
            hoisted.append(newdecl); i = j + 1; continue
        if t.k == 'id' and t.s in ren and prev not in ('.', '->'):
            out.append(T('id', ren[t.s], t.f, t.l))
        else: out.append(t)
        i += 1
    return hoisted, out


def main():
    a = sys.argv[1:]; opt = {'inject': [], 'rename-def': [], 'cpu-tail': [], 'dev-tail': []}; pos = []
    while a:
        x = a.pop(0)
        if x.startswith('--') and x[2:] in opt: opt[x[2:]].append(a.pop(0))
        else: pos.append(x)
    src, od = pos[0], pos[1]; os.makedirs(od, exist_ok=True)
    text_in = open(src).read()
    def nocomment(x): return re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', ' ', x, flags=re.S))
    for f in opt['inject']: text_in += '\n# 1 "inject:%s"\n' % os.path.basename(f) + nocomment(open(f).read())
    toks = lex(text_in)
    items = split_items(toks)
    typedefs = set(['__builtin_va_list'])
    classify(items, typedefs)
    ren = dict(r.split('=') for r in opt['rename-def'])
    for it in items:   # --rename-def NAME=NEW: the definition only (callers keep NAME: a hook defines it)
        if it.kind == 'func' and not it.sys:
            n, body = func_name(it)
            if n in ren:
                for i in range(body - 1, -1, -1):
                    if it.t[i].s == n: it.t[i] = T('id', ren[n], it.t[i].f, it.t[i].l); break
    # function-local statics -> file scope (both TUs)
    for it in items:
        if it.kind == 'func' and not it.sys:
            it.fname, _ = func_name(it)
            it.hoisted, it.t = hoist_local_statics(it, it.fname, typedefs)
    # drop functions nothing reachable calls (static helpers the plugin only uses from code the adapter leaves out, e.g.
    # vm_ini -> ini_int): gcc drops them in the normal build, but the snapshot function table would keep them alive
    fdef = {it.fname: it for it in items if it.kind == 'func' and not it.sys}
    roots = {'main'} | set(n for n, it in fdef.items() if any(t.s in ('constructor', 'destructor') for t in it.t[:func_name(it)[1]]))   # run by the C runtime
    for f in opt['inject'] + opt['cpu-tail'] + opt['dev-tail']: roots |= set(re.findall(r'[A-Za-z_][A-Za-z_0-9]*', open(f).read()))
    for it in items:
        if it.kind == 'var' and not it.sys: roots |= set(t.s for t in it.t if t.k == 'id')
    live = set(); todo = [r for r in roots if r in fdef]
    while todo:
        n = todo.pop()
        if n in live: continue
        live.add(n); it = fdef[n]
        todo += [t.s for t in it.t if t.k == 'id' and t.s in fdef and t.s not in live]
        for h in it.hoisted: todo += [t.s for t in h if t.k == 'id' and t.s in fdef and t.s not in live]
    ndead = 0
    for it in items:
        if it.kind == 'func' and not it.sys and it.fname not in live: it.kind = 'dead'; ndead += 1
    print('gpugen: %d unreachable functions dropped%s' % (ndead, (': ' + ' '.join(it.fname for it in items if it.kind == 'dead')) if os.environ.get('GPUGEN_V') else ''))
    # globals
    gl = {}; order = []
    def addvar(name, kind, dtoks, specs):
        if name not in gl: order.append(name); gl[name] = kind
        elif kind == 'state': gl[name] = 'state'
    for it in items:
        if it.sys: continue
        if it.kind == 'var':
            for (n, dd, init, _) in it.decls:
                if any(t.s == 'extern' for t in it.specs): continue
                addvar(n, 'const' if is_const_obj(it.specs, dd, n) else 'state', dd, it.specs)
        if it.kind == 'func':
            for h in it.hoisted:
                sp, rest = split_specs(h, typedefs)
                for dcl in depth0_split(rest):
                    n = decl_name(dcl); addvar(n, 'const' if is_const_obj(sp, dcl, n) else 'state', dcl, sp)
    for it in items:   # a 'const' table whose initializer points at mutable globals lives in the state too
        if it.sys or it.kind != 'var': continue
        for (n, dd, init, _) in it.decls:
            if gl.get(n) == 'const' and init and any(t.k == 'id' and gl.get(t.s) == 'state' for t in init): gl[n] = 'state'
    state = [n for n in order if gl[n] == 'state']
    funcs = [it.fname for it in items if it.kind == 'func' and not it.sys and it.fname != 'main']
    # ---------------- CPU TU ----------------
    cpu = ['/* generated by gpugen.py from %s: do not edit */\n' % os.path.basename(src)]
    for it in items:
        if it.kind == 'dead': continue
        if it.kind == 'func' and not it.sys:
            for h in it.hoisted: cpu.append(text(h))
            cpu.append(text(it.t, lambda i, t: ('al_' + t.s) if t.k == 'id' and t.s in ('malloc', 'calloc', 'realloc', 'free') and i + 1 < len(it.t) and it.t[i + 1].s == '(' else t.s))
        else:
            cpu.append(text(it.t))
    cpu.append('\n#include "snap_cpu.h"\n')
    cpu.append('static const AlGlobal al_globals[] = {\n' + ''.join('  { "%s", (void *)&%s, sizeof(%s) },\n' % (n, n, n) for n in state) + '};\n')
    cpu.append('static const AlFunc al_funcs[] = {\n' + ''.join('  { "%s", (void *)%s },\n' % (f, f) for f in funcs) + '};\n')
    cpu.append('#include "snap_cpu.c"\n')
    for f in opt['cpu-tail']: cpu.append('\n' + open(f).read())
    # function prototypes are needed before snap use: the allocator wrappers come first
    cpu.insert(1, '#include "snap_alloc.h"\n')
    open(os.path.join(od, 'cpu.c'), 'w').write(''.join(cpu))
    # ---------------- device TU ----------------
    sset = set(state)
    TYPEKW = {'int', 'float', 'double', 'char', 'unsigned', 'long', 'short', 'void', 'signed', '_Bool', 'const', 'volatile'}
    def devsub(toks):
        # locals / parameters that shadow a global keep their name: a declaration is a global's name right after a type
        # (typedef name or type keyword, possibly through '*'), or after ',' inside a declaration statement
        _, body = next(((n, b) for n, b in [func_name_safe(toks)]), (None, 0))
        keep = set(); scopes = [set()]; decl = [None]; pd = 0   # decl[-1] = paren depth of the open declaration statement
        par = set(t.s for t in toks[:body] if t.k == 'id' and t.s in sset)
        scopes[0] |= par
        for i, t in enumerate(toks):
            if i < body: continue
            if t.s == '{': scopes.append(set()); decl.append(None); continue
            if t.s == '}': scopes.pop(); decl.pop(); continue
            if t.s == '(': pd += 1; continue
            if t.s == ')': pd -= 1; continue
            if t.s == ';': decl[-1] = None; continue
            prev = toks[i - 1].s if i else ''
            if t.k == 'id' and (t.s in typedefs or t.s in TYPEKW) and prev in ('{', ';', '}', '(', ')'):
                decl[-1] = pd
            if t.k == 'id' and t.s in sset and prev not in ('.', '->'):
                j = i - 1
                while j >= 0 and toks[j].s == '*': j -= 1
                pj = toks[j] if j >= 0 else None
                isdecl = pj is not None and (pj.s in typedefs or pj.s in TYPEKW) and (j == i - 1 or True)
                if pj is not None and pj.s == ',' and decl[-1] is not None and decl[-1] == pd: isdecl = True   # ',' of the declarator list, not of a call
                if isdecl and i + 1 < len(toks) and toks[i + 1].s in ('=', ';', ',', '[', ')'):
                    scopes[-1].add(t.s)
                if any(t.s in sc for sc in scopes): keep.add(i)
        def f(i, t):
            if i >= body and t.k == 'id' and t.s in sset and i not in keep and (i == 0 or toks[i - 1].s not in ('.', '->')): return '(KST->%s)' % t.s
            return t.s
        return f
    def func_name_safe(toks):
        it = Item(toks); return func_name(it)
    head = ['/* generated by gpugen.py from %s: do not edit */\n#include "dev_prelude.h"\n' % os.path.basename(src)]
    fields = []; bodies = []
    for it in items:
        if it.sys or it.kind == 'pp': continue
        if it.kind in ('type',): head.append(text(it.t)); continue
        if it.kind == 'proto':
            head.append(text(it.t)); continue
        if it.kind == 'var':
            specs = [t for t in it.specs if t.s not in ('static', 'extern')]
            for (n, dd, init, _) in it.decls:
                if gl.get(n) == 'state':
                    if init is not None or n not in [x[0] for x in fields]:
                        dd2 = list(dd)
                        for q in range(len(dd2) - 1):
                            if dd2[q].s == '[' and dd2[q + 1].s == ']':
                                if not init or init[0].s != '{': raise SystemExit('unsized state array %s without initializer' % n)
                                cnt = len([x for x in depth0_split(init[1:-1]) if x])
                                dd2.insert(q + 1, T('num', str(cnt), dd2[q].f, dd2[q].l)); break
                        fields = [x for x in fields if x[0] != n] + [(n, text(specs) + ' ' + text(dd2))]
                elif gl.get(n) == 'const' and init is not None:
                    head.append('static ' + text(specs) + ' ' + text(dd) + ' = ' + text(init) + ';')
            continue
        if it.kind == 'func' and it.fname == 'main': continue   # host entry point: not on the device
        if it.kind == 'func':
            for h in it.hoisted:
                sp, rest = split_specs(h, typedefs)
                sp = [t for t in sp if t.s != 'static']
                for dcl in depth0_split(rest):
                    n = decl_name(dcl)
                    if gl[n] == 'state': fields.append((n, text(sp) + ' ' + text(dcl)))
                    else: raise SystemExit('const local static %s: not supported' % n)
            fn, body = func_name(it)
            head.append(text(it.t[:body]) + ';')   # prototype at the original position
            bodies.append(text(it.t, devsub(it.t)))
    ks = ['struct KSt {\n'] + ['  __attribute__((aligned(16))) %s;\n' % d for (n, d) in fields] + ['};\n']
    tail = ['\n#include "dev_tail.h"\n',
            'static const unsigned long long kst_off[] = {\n' + ''.join('  __builtin_offsetof(struct KSt, %s),\n' % n for n in state) + '};\n',
            'static const unsigned long long kst_size[] = {\n' + ''.join('  sizeof(((struct KSt *)0)->%s),\n' % n for n in state) + '};\n',
            '__attribute__((nvptx_kernel)) void kst_layout(unsigned long long *o) { o[0] = sizeof(struct KSt); o[1] = %d;\n'
            '  for (int i = 0; i < %d; i++) { o[2 + 2 * i] = kst_off[i]; o[3 + 2 * i] = kst_size[i]; } }\n' % (len(state), len(state)),
            '__attribute__((nvptx_kernel)) void kst_funcs(unsigned long long *o) {\n' + ''.join('  o[%d] = (unsigned long long)(void *)%s;\n' % (k, f) for k, f in enumerate(funcs)) + '}\n']
    assert set(n for n, _ in fields) == sset, (set(n for n, _ in fields) ^ sset)
    for f in opt['dev-tail']: tail.append('\n' + open(f).read())
    open(os.path.join(od, 'dev.c'), 'w').write(''.join(head) + '\n' + ''.join(ks) + '\n#include "dev_kst.h"\n' + ''.join(bodies) + ''.join(tail))
    with open(os.path.join(od, 'globals.tsv'), 'w') as f:
        for k, n in enumerate(state): f.write('%d\t%s\tstate\n' % (k, n))
    with open(os.path.join(od, 'funcs.tsv'), 'w') as f:
        for k, n in enumerate(funcs): f.write('%d\t%s\n' % (k, n))
    print('gpugen: %d items, %d state globals, %d consts, %d functions, %d hoisted local statics' % (
        len(items), len(state), sum(1 for n in order if gl[n] == 'const'), len(funcs), sum(len(it.hoisted) for it in items if it.kind == 'func' and not it.sys)))


if __name__ == '__main__':
    main()
