#!/usr/bin/env python3
# mt.py: model comparison suite (Shay 2026-10-15). Runbook: docs/MODEL_TEST.md. Run it in WSL: python3 tools/model-test/mt.py <cmd> <suite-dir> ...
#   init <suite-dir>                     create a suite folder from the templates (suite.json, prompt1.txt, rubric.md, task.tmpl)
#   gen <suite-dir>                      write runs/<model>-<effort>-p<n>/prompt.md for every cell and order.txt
#                                        (suite.json may hold "frozen": <folder>, filled into {FROZEN} of the template, and "prompt_numbers": [2,3]
#                                        to keep the run ids p2/p3 of an older suite when only some prompts are used)
#   rec <suite-dir> <run> <agentId> [q5h_before qweek_before q5h_after qweek_after] [--dry]
#                                        save the run's report from its transcript and append its numbers to runs.tsv;
#                                        with a "frozen" key in suite.json, tool calls that touch live paths or the live database are flagged
#   extract <agentId> <outfile>          save any subagent's final message verbatim (graders, extra runs)
#   blind <suite-dir> [--prompts 2,3]    shuffle the reports per prompt into blind/P<n>/Rxx.md, write keys/ and the grader prompts
#   report <suite-dir> [--min N] [--prompts 2,3]   tables of quality, cost, time and false claims per config and prompt; --min drops configs below N on any prompt; --prompts uses only those prompt numbers
# Subagents cannot write files, so each run returns its report as its final message and `rec` pulls it out of the transcript.
import sys, os, re, json, csv, glob, random, shutil, importlib.util, datetime, statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LEDGER_DIR = '/mnt/c/KenshiTestRuns/ledger'
TRANSCRIPTS = '/mnt/c/Users/Shay/.claude/projects/*/*/subagents/agent-%s.jsonl'


def die(msg):
    sys.exit('mt.py: ' + msg)


def numeric_or_none(value):
    """Parse a reported number; blanks, n/a and status strings stay unavailable."""
    if value is None or str(value).strip() == '':
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def violation_state(value):
    """Return clear, flagged or unknown for legacy counts and Codex audit fields."""
    if value is None or str(value).strip() == '':
        return 'unknown'
    n = numeric_or_none(value)
    if n is not None:
        return 'flagged' if n > 0 else 'clear'
    status = str(value).strip().upper()
    if status in ('PASS', 'CLEAR', 'NONE', '0'):
        return 'clear'
    if status in ('UNKNOWN', 'N/A', 'NA', 'UNAVAILABLE'):
        return 'unknown'
    # FAIL and detailed recorder flags are evidence of a violation. Unknown
    # non-empty strings are conservatively counted as flagged, not as clear.
    return 'flagged'


def load_cfg(d):
    p = os.path.join(d, 'suite.json')
    if not os.path.exists(p):
        die('no suite.json in %s (run init first)' % d)
    return json.load(open(p, encoding='utf-8'))


def winpath(p):
    p = os.path.abspath(p)
    m = re.match(r'^/mnt/([a-z])/(.*)$', p)
    return (m.group(1).upper() + ':\\' + m.group(2).replace('/', '\\')) if m else p


def all_pnums(cfg):
    nums = list(cfg.get('prompt_numbers') or range(1, len(cfg['prompts']) + 1))
    if len(nums) != len(cfg['prompts']):
        die('prompt_numbers and prompts differ in length')
    return nums


def pnums(cfg, only=None):
    """prompt numbers of the suite: suite.json "prompt_numbers" (default 1..len(prompts)), optionally limited to `only`"""
    nums = all_pnums(cfg)
    if only:
        bad = [n for n in only if n not in nums]
        if bad:
            die('--prompts %s: not in this suite (prompt numbers: %s)' % (bad, nums))
        nums = [n for n in nums if n in only]
    return nums


def cells(cfg, only=None):
    """Yield (run id, model, effort, prompt number) in configured order.

    New Codex suites may provide explicit `cells` entries with unique slugs,
    allowing speed modes and restricted effort sets. Legacy suites retain the
    Cartesian product of `models` and `efforts`.
    """
    if cfg.get('cells') is not None:
        seen = set()
        for cell in cfg['cells']:
            slug = cell.get('slug')
            model = cell.get('model')
            effort = cell.get('effort')
            if not all(isinstance(v, str) and v for v in (slug, model, effort)):
                die('each explicit cell needs non-empty slug, model and effort')
            if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', slug):
                die('invalid cell slug: %s' % slug)
            if slug in seen:
                die('duplicate cell slug: %s' % slug)
            seen.add(slug)
            for n in pnums(cfg, only):
                yield '%s-p%d' % (slug, n), model, effort, n
        return
    for m in cfg['models']:
        for e in cfg['efforts']:
            for n in pnums(cfg, only):
                yield '%s-%s-p%d' % (m, e, n), m, e, n


def prompt_text(d, cfg, n):
    return open(os.path.join(d, cfg['prompts'][all_pnums(cfg).index(n)]), encoding='utf-8').read().strip()


def parse_prompts(a):
    if '--prompts' not in a:
        return None
    i = a.index('--prompts')
    if i + 1 >= len(a):
        die('--prompts needs a comma list, e.g. --prompts 2,3')
    try:
        return [int(x) for x in a[i + 1].split(',') if x.strip()]
    except ValueError:
        die('--prompts needs a comma list of numbers, e.g. --prompts 2,3')


def frozen_dir(cfg):
    """the frozen-world folder (suite.json "frozen", a Windows path), or None"""
    f = cfg.get('frozen')
    return f.rstrip('\\/') if f else None


# ---------------------------------------------------------------- init / gen
def cmd_init(d):
    os.makedirs(d, exist_ok=True)
    for f in ('suite.json', 'prompt1.txt', 'rubric.md', 'task.tmpl'):
        dst = os.path.join(d, f)
        if os.path.exists(dst):
            print('kept existing', dst)
        else:
            shutil.copy(os.path.join(HERE, 'templates', f), dst)
            print('wrote', dst)
    print('Edit suite.json, the prompt files, rubric.md and task.tmpl, then: mt.py gen', d)


def cmd_gen(d):
    cfg = load_cfg(d)
    tmpl = open(os.path.join(d, cfg.get('template', 'task.tmpl')), encoding='utf-8').read()
    order = []
    for run_index, (rid, m, e, n) in enumerate(cells(cfg), 1):
        rd = os.path.join(d, 'runs', rid)
        os.makedirs(rd, exist_ok=True)
        ticket = ('BENCH-R%03d' % run_index) if cfg.get('cells') is not None else ('BENCH-' + rid)
        text = tmpl.replace('{TICKET}', ticket).replace('{PROMPT}', prompt_text(d, cfg, n))
        if '{FROZEN}' in text:
            if not frozen_dir(cfg):
                die('the template uses {FROZEN} but suite.json has no "frozen" key')
            fw = frozen_dir(cfg)
            wm = re.match(r'^([A-Za-z]):[\\/](.*)$', fw)
            text = text.replace('{FROZEN_WSL}', ('/mnt/%s/%s' % (wm.group(1).lower(), wm.group(2).replace('\\', '/'))) if wm else fw.replace('\\', '/'))
            text = text.replace('{FROZEN}', fw)
        open(os.path.join(rd, 'prompt.md'), 'w', encoding='utf-8', newline='\n').write(text)
        order.append(rid)
    open(os.path.join(d, 'order.txt'), 'w').write('\n'.join(order) + '\n')
    print('%d run prompts written, order in order.txt' % len(order))
    if frozen_dir(cfg):
        print('frozen world: %s' % frozen_dir(cfg))
    first = next(iter(cells(cfg)), None)
    if first:
        rid, m, e, n = first
        if cfg.get('cells') is not None:
            print('Codex suite prepared; no model run started. Each prompt has an opaque BENCH-RNNN ticket.')
            print('  first run id: %s' % rid)
            print('  runtime:      model=%s effort=%s speed=%s' % (m, e, cfg['cells'][0].get('speed', 'standard')))
            print('  prompt file:  %s' % winpath(os.path.join(d, 'runs', rid, 'prompt.md')))
        else:
            print('Agent call for each run, foreground:')
            desc = '[case:bench] [ticket:BENCH-%s] [model:%s] [effort:%s] %s' % (rid, m, e, rid)
            print('  description: ' + desc)
            print('  prompt:      Read %s and follow it exactly.' % winpath(os.path.join(d, 'runs', rid, 'prompt.md')))


# ---------------------------------------------------------------- extract / rec
def extract_text(aid):
    hits = glob.glob(TRANSCRIPTS % aid)
    if not hits:
        die('transcript not found for agent ' + aid)
    cands = []
    with open(hits[0], encoding='utf-8', errors='ignore') as fh:
        for line in fh:
            try:
                o = json.loads(line)
            except ValueError:
                continue
            c = (o.get('message') or {}).get('content')
            if o.get('type') != 'assistant' or not isinstance(c, list):
                continue
            for b in c:
                if b.get('type') == 'text' and len(b.get('text', '')) > 300:
                    cands.append(b['text'])
                elif b.get('type') == 'tool_use' and 'andback' in b.get('name', ''):
                    for v in (b.get('input') or {}).values():
                        if isinstance(v, str) and len(v) > 300:
                            cands.append(v)
    if not cands:
        die('no report text found in the transcript')
    return hits[0], cands[-1].strip() + '\n'


def cmd_extract(aid, out):
    path, txt = extract_text(aid)
    open(out, 'w', encoding='utf-8', newline='\n').write(txt)
    print('saved %s (%d chars)' % (out, len(txt)))


MUT = re.compile(r'(\brm\b|\bmv\b|\bcp\b|\bchmod\b|\bchown\b|\btee\b|sed\s+-i|\bgit\s+(commit|checkout|reset|stash|add|clean|restore|push|apply)\b|'
                 r'psql[^\n]*\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|VACUUM)\b|curl[^\n]*(-X\s*(POST|PUT|DELETE)|\s-d\s|--data)|'
                 r'Invoke-(WebRequest|RestMethod)[^\n]*-Method\s*(Post|Put|Delete)|Set-Content|Out-File|Add-Content|Remove-Item|Move-Item|Copy-Item|New-Item|Rename-Item|Clear-Content|'
                 r'[^-=<0-9&>]>{1,2}\s*[\w"\'$./~\\])', re.I)


# Live system that a run on the frozen copy must not look at. Matched on the lower-cased text with backslashes turned into slashes.
LIVE_PATHS = ('var/www/html/stobeserver', 'root/stobe-work', 'root/stobe-src', 'c:/stobebuild', 'mnt/c/stobebuild',
              'steamapps/common/kenshi', 'pending-fixes')
# database "stobe" (not stobe_frozen): psql -d stobe, --dbname stobe, dbname=stobe, \c stobe
LIVE_DB = re.compile(r'''(?:-d\s*|--dbname[=\s]+|dbname=|/c\s+)["']?stobe(?![\w-])''')


def live_touch(nm, inp):
    """the text of a tool call that touches the live system, or None (only used when suite.json has a "frozen" key).
    Grep patterns are search text, not paths, and a glob starting with ! excludes a path, so neither counts."""
    for k in ('command', 'file_path', 'path', 'pattern', 'glob'):
        v = inp.get(k)
        if not isinstance(v, str) or (k == 'pattern' and nm != 'Glob') or v.startswith('!'):
            continue
        t = re.sub(r'/+', '/', v.lower().replace('\\', '/'))
        if any(p in t for p in LIVE_PATHS) or LIVE_DB.search(t):
            return v
    return None


def cmd_rec(d, rid, aid, q, dry):
    cfg = load_cfg(d)
    frozen = bool(cfg.get('frozen'))
    m = re.match(r'(\w+)-(\w+)-p(\d+)$', rid)
    if not m:
        die('run id must look like model-effort-pN')
    rd = os.path.join(d, 'runs', rid)
    os.makedirs(rd, exist_ok=True)
    if len(q) == 4:
        open(rd + '/quota-before.txt', 'w').write('5-hour limit %s%% used; Weekly all models %s%% used\n' % (q[0], q[1]))
        open(rd + '/quota-after.txt', 'w').write('5-hour limit %s%% used; Weekly all models %s%% used\n' % (q[2], q[3]))
    path, txt = extract_text(aid)
    if not dry:
        open(rd + '/report.md', 'w', encoding='utf-8', newline='\n').write(txt)
    # numbers from the transcript, priced with tools/automation/prices.json via ledger-report.py
    auto = os.path.join(REPO, 'tools', 'automation')
    spec = importlib.util.spec_from_file_location('ledger_report', auto + '/ledger-report.py')
    lr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lr)
    prices = lr.load_prices(auto + '/prices.json')
    tok, _, usd = lr.transcript_usage(path, None, prices)
    tmodels = set()
    first = last = None
    uses = 0
    viol = []
    with open(path, encoding='utf-8', errors='ignore') as fh:
        for line in fh:
            mm = re.search(r'"model":"(claude-[a-z0-9-]+)"', line)
            if mm:
                tmodels.add(mm.group(1))
            try:
                o = json.loads(line)
            except ValueError:
                continue
            t = o.get('timestamp')
            if t:
                first = first or t
                last = t
            c = (o.get('message') or {}).get('content')
            if not isinstance(c, list):
                continue
            for b in c:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    uses += 1
                    inp = b.get('input') or {}
                    nm = b.get('name', '')
                    if frozen and nm in ('Bash', 'PowerShell', 'Read', 'Glob', 'Grep'):
                        lv = live_touch(nm, inp)
                        if lv:
                            viol.append('LIVE %s: %s' % (nm, lv[:160].replace('\n', ' | ')))
                    if nm in ('Write', 'Edit', 'NotebookEdit'):
                        viol.append('%s %s' % (nm, inp.get('file_path', '')))
                    elif nm in ('Bash', 'PowerShell'):
                        cmd = inp.get('command', '')
                        for s in ('2>&1', '1>&2', '&>/dev/null', '2>/dev/null', '>/dev/null', '> /dev/null', '2> /dev/null'):
                            cmd = cmd.replace(s, ' ')
                        if MUT.search(cmd):
                            viol.append('%s: %s' % (nm, cmd[:160].replace('\n', ' | ')))
    pts = lambda t: datetime.datetime.strptime(t[:19], '%Y-%m-%dT%H:%M:%S')
    secs = (pts(last) - pts(first)).total_seconds() if first and last else 0
    size = len(txt.encode('utf-8'))
    cites = len(re.findall(r'[\w./\\-]+\.(?:php|cpp|h|py|sh|ps1|json|sql|ini|log)[:#L(\s]+\d+', txt))
    row = [rid, ','.join(sorted(tmodels)), m.group(2), m.group(3), '%.0f' % secs, uses, tok['input'], tok['output'], tok['cache_read'],
           tok['cache_create'], '%.4f' % usd, (q + ['n/a'] * 4)[0], (q + ['n/a'] * 4)[2], (q + ['n/a'] * 4)[1], (q + ['n/a'] * 4)[3], size, cites, len(viol), aid]
    head = 'run\tmodel\teffort\tprompt\twall_s\ttool_uses\tinput\toutput\tcache_read\tcache_create\ttoken_usd\tq5h_before\tq5h_after\tqweek_before\tqweek_after\treport_bytes\tcitations\tviolation_flags\tagent\n'
    print('%s  %s/%s  %.0fs tools=%d $%.4f report=%dB cites=%d violations=%d' % (rid, row[1], row[2], secs, uses, usd, size, cites, len(viol)))
    for v in [x for x in viol if x.startswith('LIVE ')][:6]:
        print('   LIVE-PATH flag: ' + v)
    for v in [x for x in viol if not x.startswith('LIVE ')][:3]:
        print('   flag: ' + v)
    if not dry:
        f = os.path.join(d, 'runs.tsv')
        new = not os.path.exists(f)
        with open(f, 'a', encoding='utf-8') as fh:
            if new:
                fh.write(head)
            fh.write('\t'.join(str(x) for x in row) + '\n')
        open(os.path.join(d, 'done.txt'), 'a').write('%s %s\n' % (rid, aid))


# ---------------------------------------------------------------- blind grading
GRADER = '''You are a blind grader. Ticket {tk}.
{grader_scope}
This is a test run, not coordinator work: do not run session-start.ps1, do not read testing\\HANDOFF.md, and do not start wakers, wait scripts, sleeps or other agents.

The request all {cnt} agents were given (verbatim):
<<<
{p}
>>>

Rubric: {rubric} (score each report 1-5 on its five criteria).
Reports: {dir}\\R01.md ... R{cnt:02d}.md. They are anonymous. Do not read any other file in the suite folders and do not try to find out who wrote them. Do not reward length, polish or confidence on their own.
{evidence_checks}

Final message, exactly this compact format and nothing else:
GRADES P{n}
Rxx | root=N evid=N fix=N comp=N hon=N | total=NN | false=K | <note of at most 12 words>   (one line per report, R01..R{cnt:02d})
RANKING: Rxx > Rxx > ... (best to worst, all {cnt})
KEY FALSE CLAIMS: up to six lines, "Rxx: claim (what is actually true)"
'''

GRADER_LEGACY_SCOPE = '''First read C:\\KenshiModding\\.claude\\agents\\kenshi-grader.md for grading discipline, but ignore its output format and use the compact format below. Do not write files.
Do not inspect other suite folders, other reports, or try to identify authors. Use the source scope specified for the original suite.'''

GRADER_FROZEN_SCOPE = '''This suite grades reports against a frozen copy only. Read-only sources are rooted at:
- Windows: {frozen_win}
- WSL: {frozen_wsl}
Only inspect files and logs under that root. For database evidence, use only the read-only `stobe_frozen` database and SELECT queries; discover schema through `information_schema`. Never inspect the live database `stobe`, live server/game/source paths, or `pending-fixes`. If a frozen source cannot verify a claim, mark it unverifiable. Do not delegate or start any other agents.'''

GRADER_LEGACY_CHECKS = '''You may read the live code, logs and database (read-only, SELECT only) to check claims. For every report, check at least three of its most load-bearing factual claims (a cited line, log value, database row or code behaviour). A false citation caps Evidence at 2.'''

GRADER_FROZEN_CHECKS = '''For every report, verify at least five of its most load-bearing factual claims against the frozen copy only (a cited source line, frozen log value or frozen database value). If the frozen copy cannot verify a claim, mark it unverifiable rather than consulting live state. A false citation caps Evidence at 2.'''


def wslpath(p):
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p)
    return ('/mnt/%s/%s' % (m.group(1).lower(), m.group(2).replace('\\', '/'))) if m else p.replace('\\', '/')


def cmd_blind(d, only=None):
    cfg = load_cfg(d)
    frozen = frozen_dir(cfg)
    if frozen:
        grader_scope = GRADER_FROZEN_SCOPE.format(frozen_win=frozen, frozen_wsl=wslpath(frozen))
        evidence_checks = GRADER_FROZEN_CHECKS
    else:
        grader_scope = GRADER_LEGACY_SCOPE
        evidence_checks = GRADER_LEGACY_CHECKS
    for n in pnums(cfg, only):
        items = []
        for rid, m, e, nn in cells(cfg, only):
            if nn == n:
                p = os.path.join(d, 'runs', rid, 'report.md')
                if os.path.exists(p):
                    items.append((rid[:-3], p))
        for name, tpl in (cfg.get('extra_reports') or {}).items():
            p = tpl.replace('{n}', str(n))
            if os.path.exists(p):
                items.append((name, p))
        random.SystemRandom().shuffle(items)
        bd = os.path.join(d, 'blind', 'P%d' % n)
        os.makedirs(bd, exist_ok=True)
        key = {}
        for i, (name, p) in enumerate(items, 1):
            rid = 'R%02d' % i
            txt = open(p, encoding='utf-8', errors='ignore').read()
            txt = re.sub(r'BENCH-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*', 'TICKET', txt)
            if cfg.get('cells') is not None:
                # Scrub explicit Codex identity metadata only in blind copies;
                # source reports remain byte-for-byte intact for later audits.
                for cell in sorted(cfg['cells'], key=lambda c: max(len(c['model']), len(c['slug'])), reverse=True):
                    for secret in (cell['slug'], cell['model']):
                        txt = re.sub(r'(?<![A-Za-z0-9._-])%s(?![A-Za-z0-9._-])' % re.escape(secret), 'CONFIG', txt, flags=re.I)
                txt = re.sub(r'(?i)(\b(?:reasoning\s+)?effort\s*[:=]\s*)(?:low|medium|high|xhigh|ultra)\b', r'\1[hidden]', txt)
                txt = re.sub(r'(?i)(\bspeed\s*[:=]\s*)(?:standard|fast)\b', r'\1[hidden]', txt)
            open(os.path.join(bd, rid + '.md'), 'w', encoding='utf-8', newline='\n').write(txt)
            key[rid] = name
        os.makedirs(os.path.join(d, 'keys'), exist_ok=True)
        json.dump(key, open(os.path.join(d, 'keys', 'P%d.json' % n), 'w'), indent=1)
        os.makedirs(os.path.join(d, 'grades'), exist_ok=True)
        for j in cfg['judges']:
            jn = '%s-%s' % (j['model'], j['effort'])
            tk = 'BENCH-grade-%s-p%d' % (jn, n)
            gp = os.path.join(d, 'grades', 'G-%s-p%d.md' % (jn, n))
            open(gp, 'w', encoding='utf-8', newline='\n').write(
                GRADER.format(tk=tk, p=prompt_text(d, cfg, n), n=n, cnt=len(items), rubric=winpath(os.path.join(d, cfg['rubric'])),
                              dir=winpath(bd), grader_scope=grader_scope, evidence_checks=evidence_checks))
        print('P%d: %d reports blinded; keys/P%d.json is the secret key' % (n, len(items), n))
    for j in cfg['judges']:
        print('judge call: description "[case:bench] [ticket:BENCH-grade-%s-%s-pN] [model:%s] [effort:%s] grade pN", prompt "Read grades\\G-%s-%s-pN.md and follow it exactly."; save its final message to grades/%s-%s-pN.txt with: mt.py extract <agentId> <file>'
              % (j['model'], j['effort'], j['model'], j['effort'], j['model'], j['effort'], j['model'], j['effort']))


# ---------------------------------------------------------------- report
def cmd_report(d, minq, only=None):
    cfg = load_cfg(d)
    runs = {}
    rp = os.path.join(d, 'runs.tsv')
    if os.path.exists(rp):
        for r in csv.DictReader(open(rp, encoding='utf-8'), delimiter='\t'):
            runs[r['run']] = r
    pn = pnums(cfg, only)
    nprompts = len(pn)
    sc = {}
    for n in pn:
        key = json.load(open(os.path.join(d, 'keys', 'P%d.json' % n)))
        for j in cfg['judges']:
            jn = '%s-%s' % (j['model'], j['effort'])
            gp = os.path.join(d, 'grades', '%s-p%d.txt' % (jn, n))
            if not os.path.exists(gp):
                continue
            for line in open(gp, encoding='utf-8', errors='ignore'):
                m = re.match(r'(R\d\d) \|.*total=(\d+) \| false=(\d+)', line)
                if m and m.group(1) in key:
                    sc.setdefault((re.sub(r'-p\d+$', '', key[m.group(1)]), n), {})[jn] = (int(m.group(2)), int(m.group(3)))
    if cfg.get('cells') is not None:
        names = [c['slug'] for c in cfg['cells']]
        configs = {c['slug']: c for c in cfg['cells']}
    else:
        names = ['%s-%s' % (m, e) for m in cfg['models'] for e in cfg['efforts']]
        configs = {name: {'model': m, 'effort': e} for name in names for m, e in [name.rsplit('-', 1)]}
    names += list((cfg.get('extra_reports') or {}).keys())
    rows = []
    for c in names:
        if not all((c, n) in sc for n in pn):
            continue
        q, f, cost, secs = [], [], [], []
        for n in pn:
            d_ = sc[(c, n)]
            q.append(st.mean(v[0] for v in d_.values()))
            f.append(st.mean(v[1] for v in d_.values()))
            r = runs.get('%s-p%d' % (c, n))
            cost.append(numeric_or_none(r.get('token_usd')) if r else None)
            secs.append(numeric_or_none(r.get('wall_s')) if r else None)
        rows.append((c, q, f, cost, secs))
    if minq is not None:
        dropped = [(r[0], min(r[1])) for r in rows if min(r[1]) < minq]
        rows = [r for r in rows if min(r[1]) >= minq]
    fm = lambda v, f='%.2f': '-' if v is None else f % v
    pcols = pn
    print('| Config | ' + ' | '.join('P%d q' % n for n in pcols) + ' | mean q | ' + ' | '.join('P%d $' % n for n in pcols) + ' | $/task | ' +
          ' | '.join('P%d s' % n for n in pcols) + ' | min/task | ' + ' | '.join('P%d false' % n for n in pcols) + ' |')
    print('|---|' + '---|' * (4 * nprompts + 3))
    for c, q, f, cost, secs in rows:
        ok = all(x is not None for x in cost)
        time_ok = all(x is not None for x in secs)
        label = c
        if c in configs and configs[c].get('speed'):
            label += ' (%s)' % configs[c]['speed']
        print('| %s | %s | %.1f | %s | %s | %s | %s | %s |' % (label, ' | '.join('%.1f' % x for x in q), sum(q) / nprompts, ' | '.join(fm(x) for x in cost),
              fm(sum(cost) / nprompts if ok else None), ' | '.join(fm(x, '%.0f') for x in secs), fm(sum(secs) / 60 / nprompts if time_ok else None, '%.1f'),
              ' | '.join('%g' % x for x in f)))
    if minq is not None:
        print('\nRemoved (below %g on some prompt): ' % minq + ', '.join('%s (%.1f)' % x for x in dropped))
    if len(cfg['judges']) == 2:
        a = [v for (c, n), dd in sc.items() for v in [dd] if len(dd) == 2]
        if a:
            xs = [list(dd.values())[0][0] for dd in a]
            ys = [list(dd.values())[1][0] for dd in a]
            mx, my = st.mean(xs), st.mean(ys)
            den = (sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)) ** .5
            if den:
                print('\njudge agreement (correlation over %d reports): %.2f' % (len(a), sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den))
    if only:
        runs = {k: r for k, r in runs.items() if int(k.rsplit('-p', 1)[-1]) in pn}
    run_rows = list(runs.values())
    known_costs = [numeric_or_none(r.get('token_usd')) for r in run_rows]
    known_costs = [v for v in known_costs if v is not None]
    known_secs = [numeric_or_none(r.get('wall_s')) for r in run_rows]
    known_secs = [v for v in known_secs if v is not None]
    flagged = sum(1 for r in run_rows if violation_state(r.get('violation_flags')) == 'flagged')
    unknown = sum(1 for r in run_rows if violation_state(r.get('violation_flags')) == 'unknown')
    if len(known_costs) == len(run_rows):
        cost_label = 'total token cost of the runs'
    else:
        cost_label = 'known token cost subtotal (%d/%d priced runs)' % (len(known_costs), len(run_rows))
    secs_label = ('total wall %.0f min' % (sum(known_secs) / 60)) if len(known_secs) == len(run_rows) else ('known wall time %.0f min (%d/%d runs)' % (sum(known_secs) / 60, len(known_secs), len(run_rows)))
    print('%s: $%.2f, %s, runs flagged for violations: %d, runs with unknown violation status: %d' % (
        cost_label, sum(known_costs), secs_label, flagged, unknown))


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a:
        die(__doc__ if __doc__ else 'usage: see the header of this file')
    c = a[0]
    if c == 'init' and len(a) == 2:
        cmd_init(a[1])
    elif c == 'gen' and len(a) == 2:
        cmd_gen(a[1])
    elif c == 'rec' and len(a) >= 4:
        rest = [x for x in a[4:] if x != '--dry']
        cmd_rec(a[1], a[2], a[3], rest, '--dry' in a)
    elif c == 'extract' and len(a) == 3:
        cmd_extract(a[1], a[2])
    elif c == 'blind' and len(a) >= 2:
        cmd_blind(a[1], parse_prompts(a))
    elif c == 'report' and len(a) >= 2:
        cmd_report(a[1], float(a[a.index('--min') + 1]) if '--min' in a else None, parse_prompts(a))
    else:
        die('bad command; see the header of tools/model-test/mt.py')
